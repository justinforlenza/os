{ config, lib, pkgs, ... }:
let
  # From the old dotfiles: spreads a random image from ~/.wallpapers (my.wallpapers) across all monitors
  change-wallpaper = pkgs.writeShellApplication {
    name = "change-wallpaper";
    runtimeInputs = with pkgs; [ imagemagick kdePackages.libkscreen kdePackages.qttools coreutils findutils gawk gnugrep gnused ];
    text = builtins.readFile ./change-wallpaper.sh;
    excludeShellChecks = [ "SC2004" ]; # style only (`WIDTHS[$i]`); the script is kept as it was
  };
in lib.mkIf (config.my.desktop == "kde") {
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = { enable = true; wayland.enable = true; };

  environment.systemPackages = [ change-wallpaper ];
  my.justfiles = [ ./kde.just ]; # ojust wallpaper
  # A new wallpaper every hour, while a Plasma session is running
  systemd.user.services.change-wallpaper = {
    description = "Change wallpaper";
    serviceConfig = { Type = "oneshot"; ExecStart = lib.getExe change-wallpaper; };
  };
  systemd.user.timers.change-wallpaper = {
    description = "Change wallpaper every hour";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    timerConfig.OnCalendar = "hourly";
  };
}
