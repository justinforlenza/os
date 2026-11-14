# Throwaway VM test host; delete once real hosts exist
{
  my.desktop = "niri";
  my.meshagent = true;

  # No hardware-configuration.nix here, so stub the root fs (build-vm replaces it anyway)
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  virtualisation.vmVariant.virtualisation = { memorySize = 4096; cores = 4; };

  users.users.justin.initialPassword = "changeme";

  system.stateVersion = "26.11";
}
