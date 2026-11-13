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
    ssh.enable = true;
    sh.enable = true;
    git.enable = true;
  };

  ogama.system = {
    avahi.enable = true;
    docker.enable = true;
    samba.enable = true;
    tailscale.enable = true;
  };

  ogama.dev = {
    helix.enable = true;
  };

  ogama.server = {
    joplinServer.enable = true;
    caddy.enable = true;
    calendarSyncer.enable = true;
    calino.enable = true;
    immich.enable = true;
    jellyfin.enable = true;
    laSceneInterieure.enable = true;
    rustical.enable = true;
    statusPage.enable = true;
    wakapi.server.enable = true;
    wakapi.client.enable = true;
  };
}
