rec {
  paths = {
    SSD = "/mnt/ssd";
    HDD = "/mnt/hdd-tmp";
    BACKUP = "/mnt/backup";
  };

  mkProfile = { user, mail, ssh_pubkey, is-epita ? false, extra ? (_: { }) }:
    let
      base = rec {
        inherit user mail is-epita;
        home_path = "/home/${user}";
        ssh = {
          path = rec {
            priv = "${home_path}/.ssh/id_ed25519";
            pub = "${priv}.pub";
          };
          pubkey = ssh_pubkey;
        };
      };

    in base // (extra base);

  # ---------- config serv ---------- #
  cfg-server = let inherit (paths) SSD HDD BACKUP;
  in mkProfile {
    user = "ogama_serv";
    mail = "oscar.cornut@gmail.com";

    ssh_pubkey =
      "AAAAC3NzaC1lZDI1NTE5AAAAIHBd3Ol/Z20sasLURoDV4pHsXZ4yqmbacAYv1Uv+iyG6";

    extra = base: rec {
      path = rec {

        HDD_path = HDD;
        SSD_path = SSD;
        HDD_app = "${HDD_path}/appdata";
        SSD_app = "${SSD_path}/appdata";
        ssd = {
          app = { jellyfin = "${SSD_app}/jellyfin"; };
          share = { swapsev_path = "${base.home_path}/swapsev"; };
        };
        hdd = {
          app = {
            jellyfin = "${HDD_app}/jellyfin";
            immich = "${HDD_app}/immich";
            qbittorrent = "${HDD_app}/qbittorrent";
          };
          document = "${HDD_path}/document";

          share = rec {
            path = "${HDD_path}/share";
            public_HDD_path = "${path}/public";
            Apple_save_HDD_path = "${path}/public";
          };
        };

        backup = rec {
          path = BACKUP;
          laptop = rec {
            path = "${BACKUP}/laptop";
            document = "${path}/document";
          };
          HDD_path = "${path}/hdd-backup";
          SSD_path = "${path}/ssd-backup";
          HDD_app = "${HDD_path}/appdata";
          SSD_app = "${SSD_path}/appdata";
          ssd = {
            app = { jellyfin = "${SSD_app}/jellyfin"; };
            share = { swapsev_path = "${base.home_path}/swapsev"; };
          };
          hdd = {
            app = {
              jellyfin = "${HDD_app}/jellyfin";
              immich = "${HDD_app}/immich";
            };
            document = "${HDD_path}/document";

            share = rec {
              path = "${HDD_path}/share";
              public_HDD_path = "${path}/public";
              Apple_save_HDD_path = "${path}/public";
            };
          };

        };
      };
      server = { domain = "ogama.me"; };
    };
  };

  # ---------- config perso ---------- #
  cfg-perso = mkProfile {
    user = "ogama";
    mail = "oscar.cornut@gmail.com";
    ssh_pubkey =
      "AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id";

    extra = base: rec {
      bg_path = "${base.home_path}/nixos-configuration/assets/background";
      share = rec {
        path = "${base.home_path}/Server/share";
        swapsev_path = "${path}/swapsev";
      };
      server = cfg-server;
    };
  };

  # ---------- config epita ---------- #
  cfg-epita = mkProfile {
    user = "oscar.cornut";
    mail = "oscar.cornut@gmail.com";
    ssh_pubkey = "";
    is-epita = true;
    extra = base: { login = "oscar.cornut"; };
  };
}
