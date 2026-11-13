{ ... }:
let
  # Keep ConnectionSpeed and MaxConnections low: the home router wedges under high NAT churn.
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.qbittorrent.enable = lib.mkEnableOption "the qBittorrent daemon";
    };
in
{
  flake.featureModules.nixos.qbittorrent =
    { config, pkgs, lib, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.qbittorrent.enable (
        let
          profile_dir = "/var/lib/qBittorrent";
          conf_file = "${profile_dir}/qBittorrent/config/qBittorrent.conf";

          qb_path = config.ogama.server.path.hdd.app.qbittorrent;
          incomplete_path = "${qb_path}/incomplete";
          torrent_file_path = "${qb_path}/torrents";

          # Downloads land straight inside the Jellyfin libraries. incomplete_path is on
          # the same filesystem (/mnt/hdd-tmp) as these, so the move on completion is a
          # rename, not a copy — and Jellyfin's realtime monitor picks the file up as
          # soon as it appears.
          jelly = config.ogama.server.path.hdd.app.jellyfin;
          categories = {
            films.save_path = "${jelly}/FILM";
            series.save_path = "${jelly}/SHOWS";
            musique.save_path = "${jelly}/audio/Musique";
            "livres-audio".save_path = "${jelly}/audio/Books/Audiobooks";
          };
          categories_file = pkgs.writeText "categories.json" (builtins.toJSON categories);

          # services.qbittorrent rewrites qBittorrent.conf from the store on every
          # start, so the WebUI password hash has to be part of the declarative config —
          # and it is a crackable PBKDF2 hash, so it cannot sit in a public repo. The
          # generated file carries a placeholder that this script swaps for the sops
          # secret before qbittorrent reads it.
          password_token = "@WEBUI_PASSWORD_PBKDF2@";
          inject_password = pkgs.writeShellScript "qbittorrent-inject-password" ''
            set -euo pipefail
            pass=$(cat ${config.sops.secrets."qbittorrent_webui_password_pbkdf2".path})
            ${pkgs.gnused}/bin/sed -i "s|${password_token}|$pass|" ${conf_file}
          '';
        in
        {
          sops.secrets."qbittorrent_webui_password_pbkdf2" = {
            sopsFile = ../../../sops/oserv.yaml;
            owner = config.services.qbittorrent.user;
          };

          services.qbittorrent = {
            enable = true;
            # openFirewall = true;
            profileDir = profile_dir;

            # files are written as qbittorrent:users with mode 664/775 so that Jellyfin
            # and Samba (both ogama_serv:users) can rename and delete them afterwards.
            group = "users";

            serverConfig = {
              LegalNotice.Accepted = true;
              Meta.MigrationVersion = 8;
              Core.AutoDeleteAddedTorrentFile = "Never";

              Application = {
                FileLogger = {
                  Enabled = true;
                  Path = "${profile_dir}/qBittorrent/data/logs";
                  Age = 1;
                  AgeType = 1;
                  Backup = true;
                  DeleteOld = true;
                  MaxSizeBytes = 66560;
                };
              };

              BitTorrent.Session = {
                BTProtocol = "TCP";
                Port = 46301;
                "SSL\\Port" = 56296;

                # incomplete downloads stay out of the libraries, finished ones move in
                DefaultSavePath = categories.films.save_path;
                TempPathEnabled = true;
                TempPath = incomplete_path;
                TorrentExportDirectory = torrent_file_path;

                # category => save path, applied on add and on every later change
                UseCategoryPathsInManualMode = true;
                DisableAutoTMMByDefault = false;
                DisableAutoTMMTriggers = {
                  CategoryChanged = false;
                  CategorySavePathChanged = false;
                  DefaultSavePathChanged = false;
                };

                # The house sits behind a consumer ISP router that cannot cope with
                # qBittorrent's connection churn. Measured on 2026-10-21/22 (8400+
                # samples, 5s interval): with MaxConnections = 60 and ConnectionSpeed
                # = 5 the router ran clean for 4h, started dropping packets at 18:08
                # and wedged completely at 18:28 until it was power-cycled 16h later.
                #
                # The failure mode: it keeps answering ARP, so it looks alive on the
                # LAN, but ICMP to its *own* LAN IP is 100% lost and nothing gets out.
                # IPv4 and IPv6 die together, so this is the router's forwarding and
                # control plane giving up, not just an IPv4 NAT table filling. Cached
                # DNS answers keep resolving throughout, which makes naive health
                # checks look fine during a total outage.
                #
                # What drives it is the *rate of new connection attempts*, not traffic:
                # during that run qBittorrent transferred 0 bytes (seederless torrents)
                # while holding 20-57 concurrent SYN_SENT sockets, and the router died
                # anyway. So the speed limits below are irrelevant to this failure, and
                # MaxConnections does not help either — it caps only *established*
                # peers. ConnectionSpeed is the only knob that bounds half-open
                # attempts, hence 2/s. The damage is cumulative rather than a
                # threshold (SYN_SENT peaked at 67 early on with no effect), which
                # suggests router state that leaks and is never reclaimed.
                MaxConnections = 60;
                MaxConnectionsPerTorrent = 20;
                ConnectionSpeed = 2;
                MaxUploads = 10;

                # UPnP is on by default and keeps asking the router's MiniUPnPd for a
                # mapping, competing for its few slots with Tailscale, which needs one
                # to keep direct (non-DERP) paths working. Port 46301 is not forwarded
                # anyway, so the mapping buys nothing.
                UseUPnP = false;

                # Bound how many torrents chase peers at once. Without queueing every
                # torrent in the list hunts peers simultaneously, so the per-torrent
                # limit stops bounding the real total.
                QueueingSystemEnabled = true;
                MaxActiveTorrents = 5;
                MaxActiveDownloads = 3;
                MaxActiveUploads = 3;

                GlobalUPSpeedLimit = 10;
                UseAlternativeGlobalSpeedLimit = false;
              };

              Preferences = {
                General.Locale = "en";
                WebUI = {
                  Username = "ogama";
                  Password_PBKDF2 = password_token;
                };
              };

              RSS.AutoDownloader.DownloadRepacks = true;
            };
          };

          systemd.services.qbittorrent = {
            after = [ "sops-install-secrets.service" ];

            serviceConfig = {
              UMask = "0002";
              # mkAfter: these run once the upstream module has installed its generated
              # qBittorrent.conf, which they amend.
              ExecStartPre = lib.mkAfter [
                "${pkgs.coreutils}/bin/install -Dm664 ${categories_file} ${profile_dir}/qBittorrent/config/categories.json"
                "${inject_password}"
              ];
            };
          };

          services.caddy.virtualHosts."http://qbittorrent.${config.ogama.server.ipv6Host}" = {
            extraConfig = ''
              reverse_proxy http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}
            '';
          };

          systemd.tmpfiles.rules = [
            "d ${qb_path}             0775 qbittorrent users -"
            "d ${incomplete_path}     0775 qbittorrent users -"
            "d ${torrent_file_path}   0775 qbittorrent users -"
          ];
        }
      );
    };

  flake.featureModules.home.qbittorrent = sharedOptions;
}
