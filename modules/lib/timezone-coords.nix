# Coordinates used for local sunrise/sunset computation. Mirrors
# host/personal/configuration.nix's time.timeZone and its two commented-out
# travel alternates. Consumed by modules/home-manager/darkman.nix and by
# pkgs/greetd-proxy (via modules/nixosconf/greetd.nix).
{
  coords = {
    "Europe/Paris" = { lat = "48.8566"; lng = "2.3522"; };
    "America/Monterrey" = { lat = "25.6866"; lng = "-100.3161"; };
    "America/Mazatlan" = { lat = "23.2494"; lng = "-106.4111"; };
  };

  # Paris is the fallback for an unrecognized or missing timezone.
  fallback = { lat = "48.8566"; lng = "2.3522"; };
}
