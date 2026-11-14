{ lib, pkgs, osConfig, ... }: {
  home.stateVersion = osConfig.system.stateVersion;
  home.packages = with pkgs; [ eza fzf bat zoxide mise starship ];

  programs.bash = {
    enable = true;
    initExtra = builtins.readFile ./files/01-alias.sh + "\n" + builtins.readFile ./files/99-init.sh;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;
  xdg.configFile."mise/config.toml".source = ./files/mise-config.toml;
  # Included from DMS's config.kdl (see dms-setup in modules/de/niri.nix)
  xdg.configFile."niri/custom.kdl" = lib.mkIf (osConfig.my.desktop == "niri") { source = ./files/niri/custom.kdl; };
  home.file.".gitconfig".source = ./files/gitconfig;
}
