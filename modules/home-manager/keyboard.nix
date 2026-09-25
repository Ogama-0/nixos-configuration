{ ... }: {
  # home.keyboard = {
  #   layout = "fr";
  #   options = [ "caps:escape" ];
  # };

  wayland.windowManager.sway = {
    config = {
      input = {
        "type:keyboard" = {
          xkb_options = "caps:escape";
        };
      };
    };
  };

}
