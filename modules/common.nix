{ config, lib, pkgs, inputs, ... }: {
  imports = [ inputs.home-manager.nixosModules.home-manager inputs.disko.nixosModules.disko ];

  options.my.user = lib.mkOption { type = lib.types.str; default = "justin"; };

  config = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 14d"; };
    nix.optimise.automatic = true;
    nixpkgs.config.allowUnfree = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    hardware.enableRedistributableFirmware = true;
    zramSwap.enable = true;

    users.users.${config.my.user} = {
      isNormalUser = true;
      uid = 1000; # fixed so install.sh can chown from outside the chroot
      extraGroups = [ "wheel" "networkmanager" ];
      initialPassword = "changeme";
    };

    environment.systemPackages = with pkgs; [ git gh nextcloud-client proton-vpn distrobox ];
    virtualisation.podman.enable = true;

    system.autoUpgrade = { enable = true; flake = "github:justinforlenza/os"; dates = "daily"; operation = "boot"; };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${config.my.user} = import ../home;
    };
  };
}
