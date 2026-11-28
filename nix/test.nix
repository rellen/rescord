# A NixOS test of the module of Rescord (ADR 0044): a machine with the
# module, a local PostgreSQL and the files on disk. The service runs its
# migrations, starts, answers its health check, and has its directory of
# files, and `rescord-bootstrap-root` makes the first root user and no
# second one. `rescord-check` passes each check with the Postfix of the
# machine, and its test email arrives (ADR 0049). The backup service backs
# up a root user and a file; with the database and the file gone,
# `rescord-restore` puts both back (ADR 0050).
self:
{ ... }:
{
  name = "rescord";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.default ];
      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];
      # A mail server on the machine, which takes mail from localhost.
      services.postfix.enable = true;

      services.rescord = {
        enable = true;
        host = "rescord.test";
        # Secrets of a test machine, which nobody reaches.
        environmentFile = pkgs.writeText "rescord.env" ''
          SECRET_KEY_BASE=${builtins.concatStringsSep "" (builtins.genList (_: "s") 64)}
          TOKEN_SIGNING_SECRET=${builtins.concatStringsSep "" (builtins.genList (_: "t") 64)}
          RESCORD_KEY_SECRET=${builtins.concatStringsSep "" (builtins.genList (_: "k") 32)}
        '';
        settings = {
          RESCORD_SMTP_HOST = "localhost";
          RESCORD_SMTP_PORT = "25";
          RESCORD_SMTP_TLS = "none";
          RESCORD_MAIL_FROM = "rescord@rescord.test";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("rescord.service")
    # Generous for a machine with no KVM, where the VM is emulated.
    machine.wait_until_succeeds("curl -fsS http://localhost:4000/health | grep -x ok", timeout=900)
    machine.succeed("test -d /var/lib/rescord/files")
    machine.succeed("rescord-bootstrap-root first@rescord.test | grep 'is the first root user'")
    machine.fail("rescord-bootstrap-root second@rescord.test")

    machine.wait_for_unit("postfix.service")
    report = machine.succeed("rescord-check root@localhost")
    for line in ["ok    database", "ok    migrations", "ok    store", "ok    mail", "ok    vault", "note  assistant", "ok    email", "Rescord is ready."]:
        assert line in report, f"{line!r} is not in the report:\n{report}"

    # The change of the secret of the keys (ADR 0068): with no previous
    # secret, the command reads each value and changes none.
    rotated = machine.succeed("rescord-rotate-vault")
    assert "0 open with neither secret" in rotated, f"the command printed:\n{rotated}"
    machine.wait_until_succeeds("grep -rl 'Rescord can send mail' /var/spool/mail /var/lib/postfix 2>/dev/null", timeout=120)

    # The rehearsal of an upgrade (ADR 0081): each migration has run, so
    # there is none to rehearse. An option that it does not know is refused.
    rehearsed = machine.succeed("rescord-migrate --rehearse")
    assert "No upgrade to rehearse." in rehearsed, f"the command printed:\n{rehearsed}"
    machine.fail("rescord-migrate --other")

    machine.succeed("echo 'a file of the store' > /var/lib/rescord/files/probe.txt")

    # The comparison of the store with the database (ADR 0091): no record
    # names a file yet, and the file that Rescord did not put there is
    # counted apart. An option that it does not know is refused.
    compared = machine.succeed("rescord-check-files")
    for line in ["other     1 that Rescord did not put there: probe.txt", "The store has each file that a record names.", "Nothing was changed."]:
        assert line in compared, f"{line!r} is not in the report:\n{compared}"
    machine.fail("rescord-check-files --other")

    machine.succeed("systemctl start rescord-backup.service")
    machine.succeed("ls /var/lib/rescord-backup/database/rescord-*.dump")
    machine.succeed("test -f /var/lib/rescord-backup/files/probe.txt")

    # The server loses its database and its file.
    machine.succeed("systemctl stop rescord.service")
    machine.succeed("runuser -u postgres -- dropdb rescord")
    machine.succeed("runuser -u postgres -- createdb --owner rescord rescord")
    machine.succeed("rm /var/lib/rescord/files/probe.txt")

    machine.succeed("rescord-restore /var/lib/rescord-backup")
    machine.succeed("systemctl start rescord.service")
    machine.wait_until_succeeds("curl -fsS http://localhost:4000/health | grep -x ok", timeout=900)
    status, output = machine.execute("rescord-bootstrap-root third@rescord.test")
    assert status == 1 and "has a root user already" in output, output
    machine.succeed("grep -x 'a file of the store' /var/lib/rescord/files/probe.txt")
  '';
}
