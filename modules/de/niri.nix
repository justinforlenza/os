{ config, lib, pkgs, inputs, ... }:
let
  # Default niri config that `dms setup` writes (niri.kdl includes dms/*.kdl), from the installed DMS version
  tpl = "${config.programs.dux-shell.package.src}/core/internal/config/embedded";
  binds = pkgs.writeText "niri-binds.kdl"
    (builtins.replaceStrings [ "{{TERMINAL_COMMAND}}" ] [ "ghostty" ] (builtins.readFile "${tpl}/niri-binds.kdl"));
in lib.mkIf (config.my.desktop == "niri") {
  programs.niri.enable = true;
  programs.dux-shell = {
    enable = true;
    systemd.enable = true;
    plugins.quickCapture.src = inputs.dms-quick-capture; # screenshot annotation + screen recording
  };
  programs.dux-search.enable = true;
  programs.dux-files = {
    enable = true;
    systemd.enable = true; # kept running in the background, so it opens instantly
    portal.enable = true;
  };
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
    adw-gtk3 # GTK3 theme DMS's dynamic colours apply to
    ddcutil
    ffmpeg imagemagick img2pdf zbar (tesseract.override { enableLanguages = [ "eng" ]; }) # Quick Capture
  ];
  # Optional DMS features: power profile switching, and printers (CUPS brings cups-pk-helper with it)
  services.power-profiles-daemon.enable = true;
  services.printing.enable = true;

  # Copied once, not symlinked: DMS rewrites these at runtime (theme colors, keybind editor)
  home-manager.users.${config.my.user}.home.activation.niriDmsConfig =
    inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      d=$HOME/.config/niri
      mkdir -p $d/dms
      cp() { [ -e "$2" ] || { command cp "$1" "$2" && chmod u+w "$2"; }; }
      cp ${tpl}/niri.kdl $d/config.kdl
      cp ${binds} $d/dms/binds.kdl
      for f in colors layout alttab input; do cp ${tpl}/niri-$f.kdl $d/dms/$f.kdl; done
    '';
}
