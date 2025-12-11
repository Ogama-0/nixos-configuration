{ ... }:

{
  services.mako = {
    enable = true;
    settings = {

      max-visible = 3;
      default-timeout = 7000;

      background-color = "#a2d5c6";
      text-color = "#000000";
      border-color = "#d72631";

      border-radius = 15;
      border-size = 0;

      sort = "-priority";
      height = 350;
      max-icon-size = 55;
      padding = "10";

      "mode=dnd" = { invisible = 1; };

      "mode=normal" = {
        background-color = "#a2d5c6";
        text-color = "#000000";
      };
      "mode=critical" = {
        background-color = "#d72631"; # Rouge vif
        text-color = "#ffffff";
      };
      "mode=low" = {
        background-color = "#f5f5dc"; # Beige clair
        text-color = "#333333";
      };
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
