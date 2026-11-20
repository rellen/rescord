# A NixOS test of the module of Rescord (ADR 0044): a machine with the
# module, a local PostgreSQL and the files on disk. The service runs its
# migrations, starts, answers its health check, and has its directory of
# files, and `rescord-bootstrap-root` makes the first root user and no
# second one. `rescord-check` passes each check with the Postfix of the
# machine, and its test email arrives (ADR 0049).
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
    for line in ["ok    database", "ok    migrations", "ok    store", "ok    mail", "ok    email", "Rescord is ready."]:
        assert line in report, f"{line!r} is not in the report:\n{report}"
    machine.wait_until_succeeds("grep -rl 'Rescord can send mail' /var/spool/mail /var/lib/postfix 2>/dev/null", timeout=120)
  '';
}
