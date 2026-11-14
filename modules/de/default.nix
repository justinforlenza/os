{ lib, inputs, ... }: {
  # Registry: lets niri.nix turn DMS plugins on by ID (here, not in niri.nix: imports can't depend on config)
  imports = [ ./kde.nix ./niri.nix inputs.dms-plugin-registry.nixosModules.default ];
  options.my.desktop = lib.mkOption { type = lib.types.enum [ "kde" "niri" ]; };
}
