{ pkgs, config, ... }:
let
  colors = import ../../../lib/theme-colors.nix;
in
{
  services.mako = {
    enable = true;
    settings = {

      max-visible = 3;
      default-timeout = 7000;

      # Literal because the font no longer comes from a global theming
      # module; these are the values it used to supply (sans-serif name and
      # the popup size). display/font.nix installs Inter.
      font = "Inter 14";

      background-color = "#${colors.dark.base00}";
      text-color = "#${colors.dark.base05}";
      border-color = "#${colors.dark.base0D}";

      border-radius = 15;
      border-size = 0;

      sort = "-priority";
      height = 350;
      max-icon-size = 55;
      padding = "10";

      "mode=dnd" = { invisible = 1; };

      "mode=light" = {
        background-color = "#${colors.light.base00}";
        text-color = "#${colors.light.base05}";
        border-color = "#${colors.light.base0D}";
      };

      "mode=normal" = { };
      "mode=critical" = {
        background-color = "#${colors.dark.base08}";
        text-color = "#${colors.dark.base00}";
      };
      "mode=low" = { };
    };

    # rules = [
    #   {
    #     urgency = "critical";
    #     mode = "critical";
    #   }
    #   {
    #     urgency = "low";
    #     mode = "low";
    #   }
    #   {
    #     urgency = "normal";
    #     mode = "normal";
    #   }
    # ];

  };

}
