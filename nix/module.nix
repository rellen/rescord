# The NixOS module of Rescord (ADR 0044):
#
#   services.rescord = {
#     enable = true;
#     host = "rescord.example.org";
#     environmentFile = "/run/secrets/rescord.env";
#     settings = {
#       RESCORD_SMTP_HOST = "smtp.example.org";
#       RESCORD_MAIL_FROM = "rescord@example.org";
#     };
#   };
#
# The module runs the migrations before each start, keeps the files in
# /var/lib/rescord/files, and makes a local PostgreSQL database with a peer
# login unless `database.createLocally` is false. The secrets go in
# `environmentFile`, which only root reads, and never in the store.
# `docs/self-hosting.md` lists each setting. A reverse proxy in front of
# Rescord gives HTTPS: the module can set one up with nginx.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.rescord;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  environment = {
    PHX_HOST = cfg.host;
    PORT = toString cfg.port;
    RESCORD_LISTEN_ADDRESS = cfg.listenAddress;
    RESCORD_STORAGE = "disk";
    RESCORD_FILES_DIR = "/var/lib/rescord/files";
    # No distributed Erlang: nothing listens but the web server.
    RELEASE_DISTRIBUTION = "none";
    RELEASE_COOKIE = "unused";
    LANG = "C.UTF-8";
  }
  // lib.optionalAttrs cfg.database.createLocally {
    DATABASE_URL = "ecto://rescord@localhost/rescord?socket_dir=/run/postgresql";
  }
  // cfg.settings;
  # The client of PostgreSQL for a backup: the one of the server on this
  # machine, or PostgreSQL 18 for a database elsewhere.
  postgresql =
    if cfg.database.createLocally then config.services.postgresql.package else pkgs.postgresql_18;
  backupDirectory = "/var/lib/rescord-backup";

  # A command of the release, run as root with the user and the environment of
  # the service: `rescord-bootstrap-root you@example.org` makes the first root
  # user, `rescord-check [you@example.org]` checks the server (ADR 0049),
  # `rescord-restore /var/lib/rescord-backup` puts a backup back (ADR 0050),
  # and `rescord-move-storage disk s3` copies the files into the other
  # store (ADR 0059).
  releaseCommand =
    commandName: command:
    pkgs.writeShellScriptBin commandName ''
      exec ${config.systemd.package}/bin/systemd-run --quiet --pipe --wait --collect \
        --property=DynamicUser=yes --property=User=rescord --property=Group=rescord \
        --property=StateDirectory="rescord rescord/files rescord-backup" \
        --setenv=PATH=${
          lib.makeBinPath [
            postgresql
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
          ]
        } \
        ${
          lib.optionalString (cfg.environmentFile != null) "--property=EnvironmentFile=${cfg.environmentFile}"
        } \
        ${
          lib.concatMapStringsSep " " (
            name: "--setenv=${lib.escapeShellArg "${name}=${environment.${name}}"}"
          ) (lib.attrNames environment)
        } \
        ${cfg.package}/bin/${command} "$@"
    '';
  bootstrapRoot = releaseCommand "rescord-bootstrap-root" "bootstrap-root";
  check = releaseCommand "rescord-check" "check";
  restore = releaseCommand "rescord-restore" "restore";
  moveStorage = releaseCommand "rescord-move-storage" "move-storage";
in
{
  options.services.rescord = {
    enable = mkEnableOption "Rescord, a management system for animal rescues and refuges";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.rescord;
      defaultText = lib.literalExpression "rescord.packages.\${system}.rescord";
      description = "The package of Rescord.";
    };

    host = mkOption {
      type = types.str;
      example = "rescord.example.org";
      description = "The name of the host in each link that Rescord sends (`PHX_HOST`).";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "The port of the web server of Rescord, behind the reverse proxy.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        The address that the web server listens on: this machine alone by
        default, for a reverse proxy on it. `"0.0.0.0"` for each address of
        IPv4, and `"::"` for each address of IPv6 and IPv4.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/rescord.env";
      description = ''
        A file of `NAME=value` lines with the secrets: `SECRET_KEY_BASE`,
        `TOKEN_SIGNING_SECRET`, `RESCORD_KEY_SECRET`, and
        `RESCORD_SMTP_PASSWORD` or the keys of S3 when there are some. It is
        read when the service starts, and never copied into the store.
      '';
    };

    settings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        RESCORD_SMTP_HOST = "smtp.example.org";
        RESCORD_MAIL_FROM = "rescord@example.org";
      };
      description = ''
        The other settings of `docs/self-hosting.md`, which are not secret.
        They override the settings that the module gives.
      '';
    };

    database.createLocally = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to make a PostgreSQL database and user `rescord` on this
        machine, with a peer login over the local socket. When false, give
        `DATABASE_URL` in `environmentFile`.
      '';
    };

    backup = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to back up the database and the files into
          `/var/lib/rescord-backup` (ADR 0050). Copy that directory to another
          place too, with `environmentFile`: the backup does not hold the
          secrets. `rescord-restore /var/lib/rescord-backup` puts a backup back.
        '';
      };

      startAt = mkOption {
        type = types.str;
        default = "daily";
        example = "*-*-* 02:30:00";
        description = "When the backup runs, as a calendar event of systemd.";
      };

      keepDays = mkOption {
        type = types.ints.positive;
        default = 14;
        description = "The number of days that a dump of the database is kept.";
      };
    };

    nginx.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to put nginx in front of Rescord for `host`, with a
        certificate of Let's Encrypt (`security.acme` must be set up).
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !cfg.database.createLocally || lib.versionAtLeast config.services.postgresql.package.version "18";
        message = "services.rescord needs PostgreSQL 18 or later in services.postgresql.package.";
      }
    ];

    environment.systemPackages = [
      bootstrapRoot
      check
      restore
      moveStorage
    ];

    services.postgresql = mkIf cfg.database.createLocally {
      enable = true;
      # Above the default of the PostgreSQL module, and below a choice of the
      # machine: Rescord needs PostgreSQL 18 or later.
      package = lib.mkOverride 999 pkgs.postgresql_18;
      ensureDatabases = [ "rescord" ];
      ensureUsers = [
        {
          name = "rescord";
          ensureDBOwnership = true;
        }
      ];
    };

    # The owner of the database creates the extensions of the migrations:
    # citext and btree_gist are trusted extensions of PostgreSQL.
    systemd.services.rescord = {
      description = "Rescord";
      after = [ "network-online.target" ] ++ lib.optional cfg.database.createLocally "postgresql.service";
      wants = [ "network-online.target" ];
      requires = lib.optional cfg.database.createLocally "postgresql.service";
      wantedBy = [ "multi-user.target" ];
      inherit environment;

      serviceConfig = {
        Type = "exec";
        User = "rescord";
        Group = "rescord";
        DynamicUser = true;
        StateDirectory = "rescord rescord/files";
        WorkingDirectory = "/var/lib/rescord";
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        # Each start runs the migrations that have not run.
        ExecStartPre = "${cfg.package}/bin/migrate";
        ExecStart = "${cfg.package}/bin/server";
        Restart = "on-failure";
        RestartSec = 5;

        # The service reads its package and writes its state, and nothing else.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
        UMask = "0077";
      };
    };

    systemd.services.rescord-backup = mkIf cfg.backup.enable {
      description = "Back up Rescord";
      after = lib.optional cfg.database.createLocally "postgresql.service";
      startAt = cfg.backup.startAt;
      path = [ postgresql ];
      environment = environment // {
        RESCORD_BACKUP_KEEP_DAYS = toString cfg.backup.keepDays;
      };

      serviceConfig = {
        Type = "oneshot";
        User = "rescord";
        Group = "rescord";
        DynamicUser = true;
        StateDirectory = "rescord rescord/files rescord-backup";
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/backup ${backupDirectory}";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        UMask = "0077";
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts.${cfg.host} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
