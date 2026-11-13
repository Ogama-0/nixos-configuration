# What this host runs.
#
# Imported by BOTH this host's NixOS and Home Manager entry modules, so a
# feature is switched on in one place regardless of which side implements it.
# That only works for options declared on both sides, which is why this file
# carries `enable` flags and nothing else — anything side-specific (a port, a
# subdomain, a quota) is set in that side's entry module, where it is declared.
#
# _-prefixed: it is a plain attrset of option values, not a flake-parts module,
# so import-tree must not pick it up.
{
  ogama.core = {
    nh.system.enable = true;
    utilities.enable = true;
    sh.enable = true;
    git.enable = true;
    keyboard.enable = true;
    nixGc.enable = true;
  };

  ogama.system = {
    docker.enable = true;
    earlyoom.enable = true;
    geoclue.enable = true;
    gns3Root.enable = true;
    kdeconnect.enable = true;
    localsend.enable = true;
    mounting.enable = true;
    nvidia.enable = true;
    printer.enable = true;
    sambaCli.enable = true;
    steam.enable = true;
    stream.enable = true;
    tailscale.enable = true;
    vm.enable = true;
  };

  ogama.dev = {
    zellij.enable = true;
    gns3.enable = true;
    helix.enable = true;
    vim.enable = true;
    zed.enable = true;
  };

  ogama.server = {
    calendarSync.enable = true;
    wakapi.client.enable = true;
  };

  ogama.desktop = {
    # The compositor. Turning it on brings the whole rig with it: sway-effects,
    # sway-idle, laserbar, gammastep, vicinae and swaylock each default to this
    # flag, so dropping any one of them is one `false` rather than an edit to an
    # imports list.
    sway.enable = true;

    alacritty.enable = true;
    darkman.enable = true;
    firefox.enable = true;
    font.enable = true;
    gtk.enable = true;
    thunderbird.enable = true;
  };
}
