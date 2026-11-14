# Disk layout, a function of the device path. A separate /home lets a future reinstall keep your files.
{ device, ... }:
let opts = [ "compress=zstd" "noatime" ];
in {
  disko.devices.disk.main = {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; mountOptions = [ "umask=0077" ]; };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "/root" = { mountpoint = "/"; mountOptions = opts; };
              "/home" = { mountpoint = "/home"; mountOptions = opts; };
              "/nix" = { mountpoint = "/nix"; mountOptions = opts; };
            };
          };
        };
      };
    };
  };
}
