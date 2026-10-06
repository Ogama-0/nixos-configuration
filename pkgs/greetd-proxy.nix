{ writers, writeShellApplication, lib }:

# stdio <-> greetd IPC bridge and dark/light variant picker for the Quickshell
# greeter (see modules/nixosconf/greetd.nix). The timezone table is baked in at
# build time rather than read from a config file at runtime, because the
# greeter must not depend on a path it could fail to find - a greeter that
# cannot pick a variant is a machine you cannot log into.

let
  tzTable = import ../modules/lib/timezone-coords.nix;

  rawProxy = writers.writePython3Bin "greetd-proxy-unwrapped"
    {
      # The script is stdlib-only by design; these are formatting opinions
      # flake8 holds about code that is already readable.
      flakeIgnore = [ "E501" "E203" "W503" ];
    }
    (builtins.readFile ./greetd-proxy/proxy.py);
in
writeShellApplication {
  name = "greetd-proxy";
  runtimeInputs = [ rawProxy ];
  text = ''
    exec greetd-proxy-unwrapped --coords ${lib.escapeShellArg (builtins.toJSON tzTable)} "$@"
  '';

  meta = {
    description = "greetd IPC bridge and sunrise/sunset variant picker for the Quickshell greeter";
    platforms = lib.platforms.linux;
  };
}
