{ pkgs, ... }: {
  users.users.mrnossiom = {
    isNormalUser = true;

    extraGroups = [ "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJdt7atyPTOfaBIsgDYYb0DG1yid2u78abaCDji6Uxgi"
    ];
    shell = pkgs.fish;
  };
  programs.fish.enable = true;
  nix.settings.allowed-users = [ "mrnossiom" ];

}
