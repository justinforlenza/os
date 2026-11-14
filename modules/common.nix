{ config, lib, pkgs, inputs, ... }: {
  imports = [ inputs.home-manager.nixosModules.home-manager inputs.disko.nixosModules.disko inputs.nix-flatpak.nixosModules.nix-flatpak ];

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
      extraGroups = [ "wheel" "networkmanager" "docker" ];
      initialPassword = "changeme";
    };

    environment.systemPackages = with pkgs; [
      git gh nextcloud-client proton-vpn distrobox
      vscode zed-editor claude-code (callPackage ../pkgs/helium.nix { })
      inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-fhs # FHS build, so MCP servers run via npx/uvx work
    ];
    # Apps not in nixpkgs, from Flathub (nix-flatpak leaves hand-installed Flatpaks alone)
    services.flatpak = {
      enable = true;
      packages = [ "app.zen_browser.zen" "eu.betterbird.Betterbird" ];
      update.auto.enable = true; # weekly
    };
    virtualisation.podman.enable = true;
    virtualisation.docker.enable = true;

    system.autoUpgrade = { enable = true; flake = "github:justinforlenza/os"; dates = "daily"; operation = "boot"; };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${config.my.user} = import ../home;
    };
  };
}
