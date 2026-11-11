{ config, lib, pkgs, ... }: {
  options.my.gaming = lib.mkEnableOption "Steam and game launchers";

  config = lib.mkIf config.my.gaming {
    programs.steam = { enable = true; extraCompatPackages = [ pkgs.proton-ge-bin ]; };
    programs.gamescope.enable = true;
    programs.gamemode.enable = true;
    environment.systemPackages = with pkgs; [ heroic lutris mangohud protonup-qt ];
  };
}
