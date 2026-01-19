rec {
  paths = {
    ssd = "/mnt/ssd";
    hdd = "/mnt/hdd";
    backup = "/mnt/backup";
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
  cfg-server = let inherit (paths) ssd hdd backup;
  in mkProfile {
    user = "ogama_serv";
    mail = "oscar.cornut@gmail.com";

    ssh_pubkey =
      "AAAAC3NzaC1lZDI1NTE5AAAAIHBd3Ol/Z20sasLURoDV4pHsXZ4yqmbacAYv1Uv+iyG6";

    extra = base: rec {
      SSD_path = ssd;
      SSD_app = "${SSD_path}/appdata";

      HDD_path = hdd;
      HDD_app = "${HDD_path}/appdata";

      backup_path = backup;

      server = {
        domain = "ogama.me";

        share = rec {
          path = "${HDD_path}/share";
          swapsev_path = "${base.home_path}/swapsev";
          public_HDD_path = "${path}/public";
          Apple_save_HDD_path = "${path}/public";
        };
      };
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
