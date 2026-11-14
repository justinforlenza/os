{ config, lib, ... }: {
  # Sets in wallpapers/, sorted by aspect ratio: triple (≥ 4.5, three monitors), ultrawide (≥ 2.2),
  # single (anything narrower: one normal monitor).
  options.my.wallpapers = lib.mkOption {
    type = lib.types.enum [ "single" "triple" "ultrawide" ];
    default = "single";
    description = "Wallpaper set linked to ~/.wallpapers";
  };

  config = {
    home-manager.users.${config.my.user}.home.file.".wallpapers".source = ../../wallpapers/${config.my.wallpapers};
  };
}
