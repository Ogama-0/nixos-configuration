{ ... }: {
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "7:30";
          identity = true;
        }
        {
          time = "21:00";
          temperature = 5000;
          gamma = 0.8;
        }
      ];
    };
  };
  wayland.windowManager.hyprland.settings.exec-once = [ "hyprsunset" ];
}
