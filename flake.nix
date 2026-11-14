{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    claude-desktop = { url = "github:aaddrick/claude-desktop-debian"; inputs.nixpkgs.follows = "nixpkgs"; };
    dms-quick-capture = { url = "github:hthienloc/dms-quick-capture"; flake = false; }; # DMS plugin, bumped by update.yml
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;
      # One config per folder in hosts/, so adding a machine never touches this file
      mkHost = name: lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [ ./modules ./hosts/${name} { networking.hostName = name; } ];
      };
    in {
      nixosConfigurations = lib.genAttrs (builtins.attrNames (builtins.readDir ./hosts)) mkHost // {
        iso = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./modules/iso.nix ];
        };
      };

      # What install.py offers on its Options screen: every on/off my.* option, labelled with its mkEnableOption text
      installer.options =
        let my = (lib.nixosSystem { system = "x86_64-linux"; specialArgs = { inherit inputs; }; modules = [ ./modules ]; }).options.my;
        in lib.mapAttrs (_: o: lib.removeSuffix "." (lib.removePrefix "Whether to enable " o.description))
          (lib.filterAttrs (_: o: o.type.name == "bool") my);
    };
}
