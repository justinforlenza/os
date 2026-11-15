{
  imports = [ ./hardware-configuration.nix ];
  disko.devices = (import ../../disko.nix { device = "/dev/disk/by-id/nvme-WDS100T3X0C-00SJG0_21172P802594"; }).disko.devices;

  my.desktop = "niri";
  my.wallpapers = "single";
  my.fingerprint = true;
  my.gaming = false;
  my.meshagent = true;
  services.upower.enable = true; # laptop battery in DMS (niri doesn't turn UPower on)

  system.stateVersion = "26.11"; # release this machine was installed with; never change it
}
