{ pkgs, config, cfg, ... }:

let
  immichHost =
    "immich.${cfg.server.domain}"; # TODO: put your immich domain name here

  immichRoot =
    "${cfg.HDD_app}/immich"; # TODO: Tweak these to your desired storage locations

in {
  systemd.tmpfiles.rules = [
    "d ${immichRoot}                0755 immich immich -"
    "d ${immichRoot}/upload         0755 immich immich -"
    "d ${immichRoot}/encoded-video  0755 immich immich -"
    "d ${immichRoot}/thumbs         0755 immich immich -"
    "d ${immichRoot}/library        0755 immich immich -"
    "d ${immichRoot}/profile        0755 immich immich -"
    "d ${immichRoot}/backups        0755 immich immich -"
  ];

  services.immich = {
    enable = true;
    port = 2283;
    mediaLocation = "${immichRoot}";

    database = {
      enable = true;
      createDB = true;
    };
    machine-learning.enable = true;

    redis = {
      enable = true;
      port = 2281;
    };
    settings.server.externalDomain = "https://${immichHost}";

    openFirewall = true;
  };
}
