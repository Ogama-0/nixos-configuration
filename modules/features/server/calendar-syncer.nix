{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.calendarSyncer.enable = lib.mkEnableOption "the job that feeds external calendars into rustical";
    };
in
{
  flake.featureModules.nixos.calendarSyncer =
    { lib, config, inputs, ... }:
    {
      # The extra entries instruct the module system and cannot live inside
      # mkIf, so they apply whether or not the feature is enabled. What they
      # pull in only declares options and gates its own behaviour.
      imports = [
        sharedOptions
        inputs.calendar-syncer.nixosModules.default
      ];

      config = lib.mkIf config.ogama.server.calendarSyncer.enable (
        let
          host = "calsync.tail.${config.ogama.server.domain}";
        in
        {
          # calendar_syncer (github.com/pixilie/calendar_syncer, private) mirrors ICS
          # subscriptions into a CalDAV calendar and keeps CalDAV calendars in sync
          # with each other. Here it writes into rustical.nix.
          #
          # It overlaps with modules/home-manager/calendar-sync.nix, which pulls the
          # same kind of ICS feeds straight onto the laptop with vdirsyncer for khal
          # and the Calendar.qml widget. Both are left in place on purpose: this one
          # is server-side and feeds every device through rustical, the other is a
          # local read-only copy that works with the server down. Nothing stops them
          # from mirroring the same feed, and if both do, khal shows each event twice.

          # Without CALSYNC_WEB_PASSWORD the service runs with *no* authentication at
          # all (see the `guard` middleware in its src/web.rs), and its UI holds the
          # CalDAV credentials of every account it syncs.
          sops.secrets."calsync_web_password" = {
            sopsFile = ../../../sops/oserv.yaml;
          };

          # restartUnits belongs on the template, not the secret: the unit's
          # EnvironmentFile is the rendered template, so that is the file whose
          # content changing has to pick the service up.
          sops.templates."calendar-syncer.env" = {
            content = ''
              CALSYNC_WEB_PASSWORD=${config.sops.placeholder.calsync_web_password}
            '';
            restartUnits = [ "calendar-syncer.service" ];
          };

          services.calendar-syncer = {
            enable = true;
            listen = "127.0.0.1:8020";
            publicUrl = "http://${host}";
            environmentFile = config.sops.templates."calendar-syncer.env".path;
          };

          systemd.services.calendar-syncer = {
            environment.CALSYNC_WEB_USER = config.ogama.identity.user;

            # Ordering only — `wants` does not make a failed rustical fail this unit,
            # and a sync pass that finds rustical down just errors and retries at its
            # own interval.
            after = [ "rustical.service" ];
            wants = [ "rustical.service" ];
          };

          # Google sync is deliberately not wired up. It is OAuth2-only, and Google
          # refuses to register a redirect URI that is not https:// (localhost
          # excepted), so GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET would be dead weight
          # while publicUrl is plain HTTP on the tailnet. ICS mirroring and
          # CalDAV<->CalDAV sync, which is what this server is for, need none of it.
          # To add it later: real TLS on *.tail.${config.ogama.server.domain} (ACME DNS-01,
          # see caddy.nix), then two more sops keys appended to the env template
          # above.

          services.caddy.virtualHosts."http://${host}" = {
            extraConfig = ''
              encode zstd gzip
              reverse_proxy http://${config.services.calendar-syncer.listen}
            '';
          };
        }
      );
    };

  flake.featureModules.home.calendarSyncer = sharedOptions;
}
