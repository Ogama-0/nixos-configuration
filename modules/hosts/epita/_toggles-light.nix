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
    nh.user.enable = true;
    sh.enable = true;
    git.enable = true;
  };
}
