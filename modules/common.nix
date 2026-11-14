{ config, lib, pkgs, inputs, ... }:
let
  protonvpn = pkgs.callPackage ../pkgs/proton-vpn { }; # official .deb build: has Smart and Stealth
in {
  imports = [ inputs.home-manager.nixosModules.home-manager inputs.disko.nixosModules.disko inputs.nix-flatpak.nixosModules.nix-flatpak ];

  options.my.user = lib.mkOption { type = lib.types.str; default = "justin"; };

  config = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 14d"; };
    nix.optimise.automatic = true;
    nixpkgs.config.allowUnfree = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    networking.networkmanager = {
      enable = true;
      # protun: the tunnel behind Proton VPN's Smart and Stealth protocols; OpenVPN: its OpenVPN protocols
      plugins = [ protonvpn.core pkgs.networkmanager-openvpn ];
    };
    hardware.bluetooth.enable = true;
    hardware.enableRedistributableFirmware = true;
    zramSwap.enable = true;
    time.timeZone = lib.mkDefault "America/New_York"; # a host file can override it

    users.users.${config.my.user} = {
      isNormalUser = true;
      uid = 1000; # fixed so install.sh can chown from outside the chroot
      extraGroups = [ "wheel" "networkmanager" "docker" ];
      initialPassword = "changeme";
    };

    environment.systemPackages = with pkgs; [
      git gh nextcloud-client protonvpn distrobox
      (writeShellApplication { name = "os"; runtimeInputs = [ git jq gnused gnugrep util-linux pipewire ]; text = builtins.readFile ./os.sh; })
      vscode zed-editor claude-code (callPackage ../pkgs/helium.nix { })
      pear-desktop protonmail-bridge-gui beeper proton-pass proton-pass-cli
      inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-fhs # FHS build, so MCP servers run via npx/uvx work
    ];
    # Apps from Flatpak repos (nix-flatpak leaves hand-installed Flatpaks alone)
    services.flatpak = {
      enable = true;
      remotes = [ # replaces the default list, so Flathub is listed too
        { name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }
        { name = "yaabsa"; location = "https://vito0912.github.io/yaabsa/de.vito0912.yaabsa.flatpakrepo"; } # developer's own repo
      ];
      packages = [
        "app.zen_browser.zen" "eu.betterbird.Betterbird"
        "io.github.kolunmi.Bazaar" # app store
        "it.mijorus.gearlever" # AppImage manager
        "com.rustdesk.RustDesk" # the nixpkgs build is broken (Nov 2026)
        { appId = "de.vito0912.yaabsa"; origin = "yaabsa"; } # Audiobookshelf client
      ];
      update.auto.enable = true; # weekly
    };
    # Runs AppImages (Gear Lever's, or double-clicked) through an FHS wrapper; plain NixOS can't run them
    programs.appimage = { enable = true; binfmt = true; };
    # mise downloads generic Linux binaries (Python, Node); they need a /lib64 loader NixOS lacks
    programs.nix-ld.enable = true;
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
