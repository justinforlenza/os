{ config, lib, pkgs, ... }:
let
  # Sets are the folders in github:justinforlenza/wallpapers, sorted by aspect ratio: triple (≥ 4.5, three
  # monitors), ultrawide (≥ 2.2), single (anything narrower: one normal monitor). Pinned by scripts/update-wallpapers.
  sources = lib.importJSON ../../wallpapers/sources.json;
  set = config.my.wallpapers;
  # Sparse checkout: a machine downloads only its own set
  src = pkgs.fetchFromGitHub {
    owner = "justinforlenza"; repo = "wallpapers";
    inherit (sources) rev;
    hash = sources.hashes.${set};
    sparseCheckout = [ set ];
  };
in {
  options.my.wallpapers = lib.mkOption {
    type = lib.types.enum (lib.attrNames sources.hashes);
    default = "single";
    description = "Wallpaper set linked to ~/.wallpapers";
  };

  config = {
    home-manager.users.${config.my.user}.home.file.".wallpapers".source = "${src}/${set}";
  };
}
