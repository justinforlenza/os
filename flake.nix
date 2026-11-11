{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
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
      nixosConfigurations = lib.genAttrs (builtins.attrNames (builtins.readDir ./hosts)) mkHost;
    };
}
