# ojust: this OS's helper commands as just recipes (like ublue's ujust). Modules add their recipes to my.justfiles
# only when enabled, so `ojust --list` shows what works on this machine. Recipes ask (gum) for any argument not given.
{ config, lib, pkgs, ... }:
let
  justfile = pkgs.writeText "ojust.just" ''
    set positional-arguments
    set shell := ["bash", "-euo", "pipefail", "-c"]
    ${lib.concatMapStrings (f: "import '${f}'\n") config.my.justfiles}
  '';
  lib-sh = ./lib.sh;
  ojust = pkgs.writeShellApplication {
    name = "ojust";
    runtimeInputs = with pkgs; [ just gum git jq gnused gnugrep util-linux coreutils pipewire ];
    text = ''
      export OJUST_LIB=${lib-sh}
      export JUST_CHOOSER="gum filter --placeholder 'Pick a command'"
      [ $# -gt 0 ] || set -- --choose # bare `ojust`: pick a recipe from a list
      exec just --justfile ${justfile} --working-directory "$PWD" "$@"
    '';
  };
  # Fails the system build on a justfile syntax error or a shellcheck finding in lib.sh or any recipe body
  check = pkgs.runCommand "ojust-check" { nativeBuildInputs = [ pkgs.just pkgs.shellcheck ]; } ''
    shellcheck -s bash ${lib-sh}
    # SC1090/1091: `source "$OJUST_LIB"`; SC2154: variables lib.sh defines
    for r in $(just --justfile ${justfile} --summary); do
      just --justfile ${justfile} --show "$r" | sed -n 's/^    //p' | shellcheck -s bash -e SC1090,SC1091,SC2154 - \
        || { echo "in recipe $r"; exit 1; }
    done
    touch $out
  '';
in {
  options.my.justfiles = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = "Just files whose recipes `ojust` offers.";
  };

  config = {
    my.justfiles = [ ./system.just ];
    environment.systemPackages = [ ojust ];
    system.checks = [ check ];
  };
}
