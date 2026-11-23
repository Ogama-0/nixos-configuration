{ ... }:
let
  # Declared on both sides so a host's _toggles.nix can set it from either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.server.contactsSync.enable =
        lib.mkEnableOption "the user-side contacts sync against rustical's CardDAV address book";
    };
in
{
  flake.featureModules.nixos.contactsSync = sharedOptions;

  flake.featureModules.home.contactsSync =
    { config, lib, pkgs, ... }:
    {
      imports = [ sharedOptions ];

      config = lib.mkIf config.ogama.server.contactsSync.enable (
        let
          contactsDir = "${config.home.homeDirectory}/.local/share/contacts/rustical";
          statusDir = "${config.home.homeDirectory}/.local/state/vdirsyncer-contacts";
          # Its own config file, deliberately never calendar-sync.nix's: both
          # write their vdirsyncer config wholesale from a `home.activation`
          # script, and two scripts doing that against the same file would
          # mean whichever runs second erases the other's pair.
          vdirsyncerConfig = "${config.home.homeDirectory}/.config/vdirsyncer/contacts-config";
        in
        {
          sops.secrets.rustical_contacts_app_token.sopsFile = ../../../sops/calendars.yaml;

          home.packages = [ pkgs.vdirsyncer ];

          # Must run after sops-nix has decrypted secrets to disk - otherwise
          # the `cat` below reads a nonexistent file and vdirsyncer syncs with
          # an empty password.
          home.activation.contactsSync = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
            run mkdir -p "${statusDir}" "${contactsDir}" "$(dirname ${vdirsyncerConfig})"

            run cat > "${vdirsyncerConfig}" <<EOF
          [general]
          status_path = "${statusDir}"

          # "from b", not null: RustiCal names its address book by a UUID
          # vdirsyncer has to discover, not one this file can hardcode.
          # That nests the synced cards in a subfolder under contactsDir
          # named after that UUID - ContactsModel.loadFrom reads the whole
          # tree, not just the top level, because of exactly this.
          [pair contacts]
          a = "contacts_local"
          b = "contacts_remote"
          collections = ["from b"]

          [storage contacts_local]
          type = "filesystem"
          path = "${contactsDir}"
          fileext = ".vcf"

          [storage contacts_remote]
          type = "carddav"
          url = "https://rustical.${config.ogama.server.domain}/carddav/"
          username = "ogama"
          password = "$(cat ${config.sops.secrets.rustical_contacts_app_token.path})"
          read_only = true
          EOF

            # discover asks, interactively, before it creates the local
            # subfolder a newly-seen remote collection needs - "yes |" is the
            # whole fix, since activation has no tty to answer from. Only
            # the very first run ever asks; every one after finds the
            # subfolder already cached in status_path and says nothing.
            run bash -c "yes | ${pkgs.vdirsyncer}/bin/vdirsyncer --config '${vdirsyncerConfig}' discover contacts || true"
          '';
        }
      );
    };
}
