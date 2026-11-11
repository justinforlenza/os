{ config, lib, pkgs, inputs, ... }:
let
  # Default niri config that `dms setup` writes (niri.kdl includes dms/*.kdl), from the installed DMS version
  tpl = "${config.programs.dux-shell.package.src}/core/internal/config/embedded";
  binds = pkgs.writeText "niri-binds.kdl"
    (builtins.replaceStrings [ "{{TERMINAL_COMMAND}}" ] [ "ghostty" ] (builtins.readFile "${tpl}/niri-binds.kdl"));
in lib.mkIf (config.my.desktop == "niri") {
  programs.niri.enable = true;
  programs.dux-shell = { enable = true; systemd.enable = true; };
  services.displayManager.dux-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/${config.my.user}"; # greeter uses the user's DMS theme
  };
  environment.systemPackages = [ pkgs.ghostty ];

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
