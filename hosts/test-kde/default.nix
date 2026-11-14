# Throwaway VM test host; delete once real hosts exist
{
  my.desktop = "kde";
  my.gaming = true;
  my.audioMixer = true; # like xanathar
  my.audioMixerOutputs = { # xanathar's devices (absent in the VM)
    headphones = "alsa_output.usb-Elgato_Systems_Elgato_Wave_XLR_DS22K1A01343-00.analog-stereo";
    speakers = "alsa_output.usb-Creative_Technology_Ltd_Creative_Stage_Air_V2_Creative_Lab-01.analog-stereo";
  };
  # No hardware-configuration.nix here, so stub the root fs (build-vm replaces it anyway)
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  virtualisation.vmVariant.virtualisation = { memorySize = 4096; cores = 4; diskSize = 8192; };

  users.users.justin.initialPassword = "changeme";

  system.stateVersion = "26.11";
}
