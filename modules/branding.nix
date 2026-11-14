# ForlenzaOS name and logo; shared by installed systems and the installer ISO
{ pkgs, ... }:
let logo = pkgs.callPackage ../branding { };
in {
  # os-release NAME/ID: boot menu entries, nixos-version, and every fetch tool's "OS" line
  system.nixos.distroName = "ForlenzaOS";
  system.nixos.distroId = "forlenza-os";
  system.nixos.extraOSReleaseArgs = {
    ID_LIKE = "nixos"; # tools that special-case NixOS (and fetches' logo fallback) still treat it as NixOS
    LOGO = "forlenza-os"; # icon name, resolved from the logo package below
    HOME_URL = "https://github.com/justinforlenza/os";
  };

  environment.systemPackages = [ logo pkgs.fastfetch ];
  # fastfetch's system default (a user's ~/.config/fastfetch wins). Image via kitty graphics in Ghostty/Konsole,
  # chafa-rendered characters in other terminals.
  environment.etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
    "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
    logo = { type = "auto"; source = "${logo}/share/icons/hicolor/256x256/apps/forlenza-os.png"; height = 12; };
    # fastfetch's own default list; a config without one prints only the logo
    modules = [ "title" "separator" "os" "host" "kernel" "uptime" "packages" "shell" "display" "de" "wm" "wmtheme"
      "theme" "icons" "font" "cursor" "terminal" "terminalfont" "cpu" "gpu" "memory" "swap" "disk" "localip"
      "battery" "poweradapter" "locale" "break" "colors" ];
  };
}
