{ config, lib, ... }: lib.mkIf (config.my.desktop == "kde") {
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = { enable = true; wayland.enable = true; };
}
