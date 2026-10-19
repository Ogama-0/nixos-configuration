{ ... }:
{
  # Location for the things that follow the laptop around: the panel's
  # weather and gammastep's sunrise/sunset.
  #
  # Not for darkman - that one deliberately sets `usegeoclue: false` and
  # syncs from the timezone instead (modules/home-manager/darkman.nix).
  services.geoclue2 = {
    enable = true;
    # Wifi trilateration rather than IP, which is the whole point on a
    # machine that moves.
    enableWifi = true;

    # geoclue refuses any client not listed here, silently, by never
    # returning a fix. A missing entry looks exactly like "no signal".
    appConfig = {
      gammastep = {
        isAllowed = true;
        isSystem = false;
      };
      "where-am-i" = {
        isAllowed = true;
        isSystem = false;
      };
    };
  };
}
