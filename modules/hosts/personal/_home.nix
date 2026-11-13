{ config, pkgs, ... }:
{
  imports = [
    ./_toggles.nix
    ./_home-manager/tool.nix
    ./_home-manager/default-app.nix
    # ../../home-manager/joplin-desktop.nix
    # "${inputs.home-manager}/modules/programs/xcompose.nix"
  ];

  # Per-host identity. These were entries in host/profiles.nix, reached through
  # a `cfg` attrset in specialArgs; they are declared options now
  # (modules/features/core/shared-options.nix) and set here, by the host they
  # describe.
  ogama.identity = {
    user = "ogama";
    sshPubkey = "AAAAC3NzaC1lZDI1NTE5AAAAILaKjKo1kaGVYdA5U6kvrjhDj1T3tp04CmiZE3YmA7id";
  };

  sops.age.keyFile = "${config.ogama.identity.homePath}/.config/sops/age/keys.txt";

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  home = {
    pointerCursor = {
      gtk.enable = true;
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
    };

    username = "ogama";
    homeDirectory = "/home/ogama";
    sessionVariables.swp = "${config.ogama.share.swapsevPath}";

    stateVersion = "24.11";
  };

  services.poweralertd.enable = true;

  programs.home-manager.enable = true;
}
