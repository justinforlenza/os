# Binary cache that cache.yml fills with what cache.nixos.org lacks (unfree apps, pkgs/, flake-input apps),
# so machines and the installer download those instead of building them
{
  nix.settings = {
    extra-substituters = [ "https://justinforlenza-os.cachix.org" ];
    extra-trusted-public-keys = [ "justinforlenza-os.cachix.org-1:jNXa+cOM83qD7nsLxEXT4WSR8SHg7QNdAJ4JTbIXcq0=" ];
  };
}
