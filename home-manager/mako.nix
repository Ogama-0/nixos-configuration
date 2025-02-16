{ ... }:

{
  services.mako = {
    enable = true;

    maxVisible = 3;

    defaultTimeout = 5000;
    backgroundColor = "#a2d5c6";
    textColor = "#000000";

    borderRadius = 15;
    borderSize = 0;
    borderColor = "#d72631";

    height = 350;
    maxIconSize = 55;
    padding = "10";

    # extraConfig = ''
    # [urgency=low]
    # background-color=#a2d5c6
    # text-color=#FFFFFF
    # [urgency=medium]                                                                                                                                                                     
    #   background-color=#077b8a

    #   [urgency=high]                                                                                                                                                                     
    #   background-color=#5c3c92
    # '';
  };

}
