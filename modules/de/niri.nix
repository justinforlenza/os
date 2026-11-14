{ config, lib, pkgs, inputs, ... }:
lib.mkIf (config.my.desktop == "niri") {
  programs.niri.enable = true;
  programs.dux-shell = {
    enable = true;
    systemd.enable = true;
    # From the plugin registry, by ID. Installed plugins start switched off: turn them on in Settings > Plugins.
    plugins = {
      quickCapture.enable = true; # screenshot annotation + screen recording
      dankLauncherKeys.enable = true; # search keyboard shortcuts from the launcher
      calculator.enable = true; # evaluate maths in the launcher
      emojiLauncher.enable = true; # emoji & unicode characters in the launcher
    };
  };
  programs.dux-search.enable = true;
  programs.dux-files = {
    enable = true;
    systemd.enable = true; # kept running in the background, so it opens instantly
    portal.enable = true;
  };
  # App icons: DMS (a Qt app) finds the icon theme through Qt's platform theme, and NixOS sets none, so most
  # launcher icons were missing. gtk3 reads the GTK settings, which DMS's Settings > Icons also writes.
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "gtk3";
  # System-wide default icon theme; a user's ~/.config/gtk-3.0/settings.ini (DMS writes one) overrides it
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-icon-theme-name=Adwaita
  '';

  # Default apps: Dux Files for folders and trash, Loupe for images, Celluloid for videos
  xdg.mime.defaultApplications =
    { "inode/directory" = "dev.duxlabs.files.desktop"; "x-scheme-handler/trash" = "dev.duxlabs.files.desktop"; } //
    lib.genAttrs (map (t: "image/${t}") [ "png" "jpeg" "gif" "webp" "avif" "heic" "jxl" "bmp" "tiff" "svg+xml" ])
      (_: "org.gnome.Loupe.desktop")
    // lib.genAttrs (map (t: "video/${t}") [ "mp4" "x-matroska" "webm" "quicktime" "x-msvideo" "mpeg" "ogg" "x-flv" ])
      (_: "io.github.celluloid_player.Celluloid.desktop");

  # Dux Files: drives and USB sticks (mount/eject), network shares and trash
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  # Open/save dialogs use Dux Files (the rest of niri's portal config comes from the niri module)
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = "dfiles";
  # Quick Capture's tools: recording, thumbnails, exports, OCR, QR scanning
  programs.gpu-screen-recorder.enable = true;
  # DDC/CI: DMS sets external monitors' brightness over I²C (dux-shell turns hardware.i2c on)
  users.users.${config.my.user}.extraGroups = [ config.hardware.i2c.group ];
  services.displayManager.dux-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/${config.my.user}"; # greeter uses the user's DMS theme
  };
  environment.systemPackages = with pkgs; [
    ghostty
    loupe celluloid # image viewer, video player (mpv-based, so most formats play without extra codecs)
    adw-gtk3 # GTK3 theme DMS's dynamic colours apply to
    adwaita-icon-theme hicolor-icon-theme # hicolor: where most apps install their own icons
    ddcutil
    ffmpeg imagemagick img2pdf zbar (tesseract.override { enableLanguages = [ "eng" ]; }) # Quick Capture
  ];
  # Optional DMS features: power profile switching, and printers (CUPS brings cups-pk-helper with it)
  services.power-profiles-daemon.enable = true;
  services.printing.enable = true;

  # First login: DMS's own `dms setup` writes ~/.config/niri (config.kdl + dms/*.kdl), as on any distro.
  # A user service before niri, not home-manager activation: setup needs the user's systemd (it registers
  # dms.service with niri.service), which doesn't exist yet when activation runs at boot.
  systemd.user.services.dms-setup = {
    description = "DMS first-run niri setup";
    wantedBy = [ "niri.service" ];
    before = [ "niri.service" ];
    path = [ config.systemd.package ]; # setup calls `systemctl --user`
    unitConfig.ConditionPathExists = "!%h/.config/niri/config.kdl"; # never touch an existing config
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.programs.dux-shell.package}/bin/dms setup headless --compositor niri --skip-existing";
    };
  };
}
