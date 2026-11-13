# Per-host data, as declared options.
#
# This replaces host/profiles.nix and the `cfg` attrset that was threaded into
# all six configurations through specialArgs. The same declarations are
# registered on both the NixOS and the Home Manager side, so `ogama.identity.user`
# means the same thing in either evaluation and a module reads it off `config`
# rather than from a function argument.
{ ... }:
let
  constants = import ../../../lib/constants.nix;

  sharedOptions =
    { config, lib, ... }:
    let
      inherit (lib) mkOption types;
      identity = config.ogama.identity;
      server = config.ogama.server;

      # The storage tree, derived from the three roots.
      #
      # Shape and every leaf string are reproduced from the old
      # profiles.nix `cfg-server.path` exactly, because the personal profile's
      # backup and share modules compare against these paths and a single
      # changed character moves data somewhere else.
      #
      # `serverUser` rather than `identity.user`: the personal profile reads
      # this tree too (it used to embed the whole server record as
      # `cfg-perso.server`), and these paths must stay the server's regardless
      # of which host is evaluating.
      mkPath =
        let
          ssdRoot = server.paths.ssd;
          hddRoot = server.paths.hdd;
          backupRoot = server.paths.backup;
          serverHome = "/home/${server.user}";
        in
        rec {
          HDD_path = hddRoot;
          SSD_path = ssdRoot;
          HDD_app = "${HDD_path}/appdata";
          SSD_app = "${SSD_path}/appdata";

          ssd = {
            app.jellyfin = "${SSD_app}/jellyfin";
            share.swapsev_path = "${serverHome}/swapsev";
          };

          hdd = {
            app = {
              jellyfin = "${HDD_app}/jellyfin";
              immich = "${HDD_app}/immich";
              qbittorrent = "${HDD_app}/qbittorrent";
            };
            document = "${HDD_path}/document";
            photo = "${HDD_path}/photo";
            photo_1 = "${HDD_path}/photo-1";
            share = rec {
              path = "${HDD_path}/share";
              public_HDD_path = "${path}/public";
              Apple_save_HDD_path = "${path}/timemachine";
            };
          };

          backup = rec {
            path = backupRoot;
            laptop = rec {
              path = "${backupRoot}/laptop";
              document = "${path}/document";
            };
            HDD_path = "${path}/hdd-backup";
            SSD_path = "${path}/ssd-backup";
            HDD_app = "${HDD_path}/appdata";
            SSD_app = "${SSD_path}/appdata";
            ssd = {
              app.jellyfin = "${SSD_app}/jellyfin";
              share.swapsev_path = "${serverHome}/swapsev";
            };
            hdd = {
              app = {
                jellyfin = "${HDD_app}/jellyfin";
                immich = "${HDD_app}/immich";
              };
              document = "${HDD_path}/document";
              photo = "${HDD_path}/photo";
              photo_1 = "${HDD_path}/photo-1";
              share = rec {
                path = "${HDD_path}/share";
                public_HDD_path = "${path}/public";
                # Yes, "public" — not "timemachine" as the non-backup tree
                # uses. Reproduced from profiles.nix verbatim; it looks like a
                # copy-paste slip there, but changing it here would change
                # where the Apple backups are compared against, which is not
                # this migration's business.
                Apple_save_HDD_path = "${path}/public";
              };
            };
          };
        };
    in
    {
      options.ogama = {
        identity = {
          realName = mkOption {
            type = types.str;
            default = "Oscar Cornut";
            description = "Full name recorded as the author of git commits.";
          };

          user = mkOption {
            type = types.str;
            example = "ogama";
            description = ''
              Unix account name for this host. Each host sets it; there is no
              default, because getting it wrong silently writes another user's
              files.
            '';
          };

          mail = mkOption {
            type = types.str;
            default = "oscar.cornut@gmail.com";
            description = "Email recorded as the author of git commits.";
          };

          homePath = mkOption {
            type = types.str;
            default = "/home/${identity.user}";
            defaultText = ''"/home/''${config.ogama.identity.user}"'';
            description = "This account's home directory.";
          };

          sshPubkey = mkOption {
            type = types.str;
            default = "";
            description = ''
              The public half of this host's SSH key, as the bare base64 body
              without the `ssh-ed25519` prefix — that is the form the
              authorized_keys and samba modules interpolate it into. Empty on
              hosts that are never an SSH target.
            '';
          };

          sshKeyPath = {
            priv = mkOption {
              type = types.str;
              default = "${identity.homePath}/.ssh/id_ed25519";
              defaultText = ''"''${config.ogama.identity.homePath}/.ssh/id_ed25519"'';
              description = "Private key this host authenticates with.";
            };
            pub = mkOption {
              type = types.str;
              default = "${identity.sshKeyPath.priv}.pub";
              defaultText = ''"''${config.ogama.identity.sshKeyPath.priv}.pub"'';
              description = "Public key file sitting next to the private one.";
            };
          };

          isEpita = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether this is the school machine. Changes shell behaviour that
              has to cope with AFS home directories.
            '';
          };

          login = mkOption {
            type = types.str;
            default = "";
            description = "School login, where it differs from the Unix account name.";
          };
        };

        server = {
          domain = mkOption {
            type = types.str;
            default = constants.domain;
            description = ''
              Domain the server's services are published under. Read by the
              personal profile too, which points at the server for backups and
              shares.
            '';
          };

          user = mkOption {
            type = types.str;
            default = "ogama_serv";
            description = ''
              The server's Unix account. Declared separately from
              `ogama.identity.user` because the derived storage tree below is
              read by the personal profile as well, where `identity.user` is
              somebody else.
            '';
          };

          ipv6Host = mkOption {
            type = types.str;
            default = "ipv6.${server.domain}";
            defaultText = ''"ipv6.''${config.ogama.server.domain}"'';
            description = "Hostname the IPv6-only caddy vhosts are served on.";
          };

          paths = {
            ssd = mkOption {
              type = types.str;
              default = constants.paths.ssd;
              description = "Mount point of the server's SSD.";
            };
            hdd = mkOption {
              type = types.str;
              default = constants.paths.hdd;
              description = "Mount point of the server's spinning disk.";
            };
            backup = mkOption {
              type = types.str;
              default = constants.paths.backup;
              description = "Mount point of the backup target.";
            };
          };

          path = mkOption {
            type = types.raw;
            readOnly = true;
            default = mkPath;
            description = ''
              The server's storage tree, derived from `ogama.server.paths` and
              `ogama.server.user`. Read-only: the roots are the knobs, the tree
              is a consequence. Shape and leaf names are inherited from the old
              profiles.nix so call sites did not have to be rethought.
            '';
          };
        };

        share = {
          path = mkOption {
            type = types.str;
            default = "${identity.homePath}/Server/share";
            defaultText = ''"''${config.ogama.identity.homePath}/Server/share"'';
            description = "Where this host mounts the server's share.";
          };
          swapsevPath = mkOption {
            type = types.str;
            default = "${config.ogama.share.path}/swapsev";
            defaultText = ''"''${config.ogama.share.path}/swapsev"'';
            description = "Scratch directory inside the mounted share.";
          };
        };
      };
    };
in
{
  flake.featureModules.nixos.sharedOptions = sharedOptions;
  flake.featureModules.home.sharedOptions = sharedOptions;
}
