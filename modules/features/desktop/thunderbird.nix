{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.desktop.thunderbird.enable = lib.mkEnableOption "the Thunderbird mail client";
    };
in
{
  flake.featureModules.nixos.thunderbird = sharedOptions;

  flake.featureModules.home.thunderbird =
    { lib, config, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.desktop.thunderbird.enable (
        {
          # Home-manager's Thunderbird module fully owns and regenerates
          # profiles.ini/user.js for every profile it manages, so this declares a
          # fresh "default" profile rather than adopting the one created by hand in
          # the app. Mail accounts are redeclared below for that reason, and each
          # will need a one-time OAuth2 re-auth the first time it connects under
          # this profile.
          accounts.email.accounts = {
            gmail-primary = {
              address = config.ogama.identity.mail;
              flavor = "gmail.com";
              realName = "Oscar Cornut";
              primary = true;
              thunderbird.enable = true;
            };

            gmail-secondary = {
              address = "oscar.cornut9@gmail.com";
              flavor = "gmail.com";
              realName = "Oscar Cornut";
              thunderbird.enable = true;
            };

            epita = {
              address = "oscar.cornut@epita.fr";
              flavor = "outlook.office365.com";
              realName = "Oscar Cornut";
              thunderbird.enable = true;
            };
          };

          # RustiCal (rustical.ogama.me) CalDAV calendars, principal "ogama". The
          # password/app-token is out of Nix's control either way — the Thunderbird
          # module never reads remote.passwordCommand — so it's entered once into
          # Thunderbird's own password manager after the switch.
          accounts.calendar.accounts = {
            sortie = {
              remote = {
                type = "caldav";
                url = "https://rustical.ogama.me/caldav/principal/ogama/66c1d450-3e6c-4214-b8db-e73cde1db139/";
                userName = "ogama";
              };
              thunderbird = {
                enable = true;
                color = "#333399";
              };
            };

            work = {
              remote = {
                type = "caldav";
                url = "https://rustical.ogama.me/caldav/principal/ogama/55a2e12d-5cd1-4d0b-bbea-d81de5fc7d9d/";
                userName = "ogama";
              };
              thunderbird = {
                enable = true;
                color = "#33FFFF";
              };
            };

            anniversaire = {
              primary = true; # was the manual main/default calendar
              remote = {
                type = "caldav";
                url = "https://rustical.ogama.me/caldav/principal/ogama/fd073ac7-f0f8-4684-9510-9b84845ef262/";
                userName = "ogama";
              };
              thunderbird = {
                enable = true;
                color = "#33CC00";
              };
            };
          };

          # No CardDAV address book exists on RustiCal yet — it has to be created
          # server-side first (RustiCal mints the collection UUID on creation, same
          # as it did for the calendars above). Once it exists, fill in its
          # collection URL here, uncomment, and re-switch:
          #
          # accounts.contact.accounts.rustical = {
          #   remote = {
          #     type = "carddav";
          #     url = "https://rustical.ogama.me/carddav/principal/ogama/<uuid>/";
          #     userName = "ogama";
          #   };
          #   thunderbird.enable = true;
          # };

          programs.thunderbird = {
            enable = true;
            # Plain `thunderbird` (the module's default) tracks the latest release,
            # which hydra hasn't cached and this machine can't build locally (OOMs
            # on the LTO link with 12 clang jobs, 13G and no swap) - same reason
            # tool.nix pins the bare package to thunderbird-esr. Keep both in sync
            # or buildEnv sees two different thunderbird derivations and conflicts.
            package = pkgs.thunderbird-esr;
            profiles.default = {
              isDefault = true;
              settings = {
                # "Always perform this check when starting Thunderbird" in the
                # System Integration dialog - off, since it shows the dialog on
                # every launch regardless of actual default-client state. Which
                # MIME types/schemes Thunderbird is default for is set for real via
                # xdg.mimeApps in default-app.nix (confirmed with `xdg-mime query
                # default`), this pref only controls the startup nag.
                "mail.shell.checkDefaultClient" = false;
              };
            };
          };
        }
      );
    };
}
