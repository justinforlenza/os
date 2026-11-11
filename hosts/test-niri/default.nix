# Throwaway VM test host; delete once real hosts exist
{
  my.desktop = "niri";

  # No hardware-configuration.nix here, so stub the root fs (build-vm replaces it anyway)
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  virtualisation.vmVariant.virtualisation = { memorySize = 4096; cores = 4; };

  system.stateVersion = "26.11";
}
