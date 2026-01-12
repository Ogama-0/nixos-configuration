rec {
  paths = {
    ssd = "/mnt/ssd";
    hdd = "/mnt/hdd";
    backup = "/mnt/backup";
  };

  mkProfile = { user, mail, is-epita ? false, extra ? (_: { }) }:
    let
      base = rec {
        inherit user mail is-epita;
        home_path = "/home/${user}";
      };

    in base // (extra base);

  # ---------- config serv ---------- #
  cfg-server = let inherit (paths) ssd hdd backup;
  in mkProfile {
    user = "ogama_serv";
    mail = "oscar.cornut@gmail.com";

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
    is-epita = true;
    extra = base: { login = "oscar.cornut"; };
  };
}
