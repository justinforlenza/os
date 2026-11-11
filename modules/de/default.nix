{ lib, ... }: {
  imports = [ ./kde.nix ./niri.nix ];
  options.my.desktop = lib.mkOption { type = lib.types.enum [ "kde" "niri" ]; };
}
