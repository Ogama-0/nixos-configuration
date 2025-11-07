{ pkgs, ... }: {
  services.printing = {
    enable = true;
    drivers = [ pkgs.brlaser ];
  };
  # hardware.printers = {
  #   ensureprinters = {

  #   };
  # };
}
