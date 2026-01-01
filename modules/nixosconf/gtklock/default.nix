{ pkgs, ... }:

{
  programs.gtklock = {
    enable = true;

    config = {
      main = {
        idle-hide = true;
        idle-timeout = 10;

        modules = [
          "${pkgs.gtklock-userinfo-module}/lib/gtklock/userinfo-module.so"
          "${pkgs.gtklock-playerctl-module}/lib/gtklock/playerctl-module.so"
          "${pkgs.gtklock-powerbar-module}/lib/gtklock/powerbar-module.so"
        ];
      };
      playerctl = {
        art-size = 64;
        position = "top-center";
      };
    };

    modules = with pkgs; [
      gtklock-userinfo-module
      gtklock-playerctl-module
      gtklock-powerbar-module
    ];

    style = builtins.readFile ./style.css;
  };

  environment.etc."xdg/gtklock/layout.xml".source = ./layout.xml;
}

