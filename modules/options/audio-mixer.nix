{ config, lib, pkgs, ... }:
let
  outputs = config.my.audioMixerOutputs;
  # `change-mixer-output <name>`: sends the Main Mix to one of the outputs above (was a hardcoded dotfiles script)
  change-mixer-output = pkgs.writeShellApplication {
    name = "change-mixer-output";
    runtimeInputs = [ pkgs.pipewire ];
    text = ''
      declare -A outputs=(${lib.concatStrings (lib.mapAttrsToList (name: node:
        " [${lib.escapeShellArg name}]=${lib.escapeShellArg node}") outputs)} )
      target=''${1:-}
      if [ -z "$target" ] || [ -z "''${outputs[$target]:-}" ]; then
        echo "Usage: change-mixer-output {${lib.concatStringsSep "|" (lib.attrNames outputs)}}" >&2
        echo "Outputs are set in my.audioMixerOutputs; find device names with: wpctl status -n" >&2
        exit 1
      fi
      for node in "''${outputs[@]}"; do # unlink the Main Mix from every output first
        for ch in FL FR; do pw-link -d "mixer_main:monitor_$ch" "$node:playback_$ch" 2>/dev/null || true; done
      done
      for ch in FL FR; do pw-link "mixer_main:monitor_$ch" "''${outputs[$target]}:playback_$ch"; done
      echo "Switched to $target"
    '';
  };
in {
  options.my = {
    audioMixer = lib.mkEnableOption "Audio mixer (virtual sinks: system, browser, music, voice chat)";
    audioMixerOutputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Outputs `change-mixer-output <name>` can send the Main Mix to: name → PipeWire node name.";
      example = {
        headphones = "alsa_output.usb-Elgato_Systems_Elgato_Wave_XLR_DS22K1A01343-00.analog-stereo";
        speakers = "alsa_output.usb-Creative_Technology_Ltd_Creative_Stage_Air_V2_Creative_Lab-01.analog-stereo";
      };
    };
  };

  config = lib.mkIf config.my.audioMixer {
    environment.systemPackages = [ change-mixer-output ];
    my.justfiles = [ ./audio-mixer.just ]; # ojust audio, ojust mixer-output
    # Virtual sinks + loopbacks into the Main Mix, from the old dotfiles
    home-manager.users.${config.my.user}.xdg.configFile = {
      "pipewire/pipewire.conf.d/10-virtual-mixer.conf".source = ../../home/files/pipewire/10-virtual-mixer.conf;
      "pipewire/pipewire.conf.d/11-mixer-loopbacks.conf".source = ../../home/files/pipewire/11-mixer-loopbacks.conf;
    };
  };
}
