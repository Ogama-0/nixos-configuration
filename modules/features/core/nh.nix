# nh, the nix helper that wraps rebuild and gc.
#
# One concern, one file — but two switches, because the two halves are not the
# same thing and the hosts genuinely differ. personal installs nh system-wide
# (it has a NixOS side and rebuilds the system); epita has no NixOS side at all
# and installs it into the user environment. A single flag would have switched
# on both halves for personal and added nh to its home closure as well.
#
# The rule that falls out, used by every both-sides feature after this one: if
# the two halves always travel together, give them one flag; if a host can
# sensibly want one without the other, give them `.system` and `.user`.
{ ... }:
let
  # Both declared on both sides so a host's _toggles.nix can set either.
  sharedOptions =
    { lib, ... }:
    {
      options.ogama.core.nh = {
        system.enable = lib.mkEnableOption "nh system-wide, for hosts that rebuild NixOS";
        user.enable = lib.mkEnableOption "nh in the user environment, for Home-Manager-only hosts";
      };
    };

  # Identical on both sides, which is why this was two byte-identical files.
  nhConfig = config: {
    programs.nh = {
      enable = true;
      flake = "${config.ogama.identity.homePath}/nixos-configuration";
    };
  };
in
{
  flake.featureModules.nixos.nh =
    { config, lib, ... }:
    {
      imports = [ sharedOptions ];
      config = lib.mkIf config.ogama.core.nh.system.enable (nhConfig config);
    };

  flake.featureModules.home.nh =
    { config, lib, ... }:
    {
      imports = [ sharedOptions ];
      config = lib.mkIf config.ogama.core.nh.user.enable (nhConfig config);
    };
}
