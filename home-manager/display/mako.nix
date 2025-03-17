{ ... }:

{
  services.mako = {
    enable = true;

    maxVisible = 3;

    defaultTimeout = 7000;
    backgroundColor = "#a2d5c6";
    textColor = "#000000";

    borderRadius = 15;
    borderSize = 0;
    borderColor = "#d72631";

    sort = "-priority";
    height = 350;
    maxIconSize = 55;
    padding = "10";

    extraConfig = ''

      [mode="do not disturb"]
      invisible=1

      [mode="test"]
      background-color=#a2d5c6

    '';
  };

}
