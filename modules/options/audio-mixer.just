# device: a number from the list this prints, a PipeWire node name, or none (removes <name>)
# Set which sound device `ojust mixer-output <name>` sends the Main Mix to (asks for anything not given)
[group('audio')]
audio name="" device="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    role=$1 device=$2
    current=$(my audioMixerOutputs)
    echo "Mixer outputs:"
    jq -r 'if length == 0 then "  none set" else to_entries[] | "  \(.key) -> \(.value)" end' <<<"$current"
    # Sound outputs PipeWire sees right now, as "description<TAB>node name" (same list as the installer's)
    mapfile -t devices < <(pw-dump | jq -r '.[] | .info.props? // empty
      | select(."media.class" == "Audio/Sink" and (."node.name" // "" | startswith("alsa_output.")))
      | "\(."node.description" // ."node.name")\t\(."node.name")"' | sort)
    echo "Sound outputs connected now:"
    for i in "${!devices[@]}"; do
      printf '  %d) %s\n     %s\n' $((i + 1)) "${devices[i]%%$'\t'*}" "${devices[i]#*$'\t'}"
    done
    [ ${#devices[@]} -gt 0 ] || echo "  none found"
    if [ -z "$role" ]; then
      mapfile -t roles < <(jq -r '(keys + ["headphones", "speakers"]) | unique[]' <<<"$current")
      role=$(pick "output name" "${roles[@]}" "new name…")
      [ "$role" != "new name…" ] || role=$(gum input --placeholder "name, e.g. desk")
    fi
    [[ $role =~ ^[a-z][a-zA-Z0-9]*$ ]] || die "Names start with a lowercase letter, then letters/digits: '$role'."
    [ -n "$device" ] || device=$(pick "device for $role" --label-delimiter=$'\t' "${devices[@]}" $'none (remove)\tnone')
    node=""
    if [[ $device =~ ^[0-9]+$ ]]; then
      [ "$device" -ge 1 ] && [ "$device" -le ${#devices[@]} ] || die "No device $device in the list."
      node=${devices[device - 1]#*$'\t'}
    elif [ "$device" != none ]; then
      [[ $device =~ ^[A-Za-z0-9_.:-]+$ ]] || die "'$device' isn't a number, node name or none."
      node=$device
    fi
    pull
    block='/^  my\.audioMixerOutputs = {/,/^  };/' # the block the installer writes
    sed -i "$block{/^    $role = /d}" "$file"
    if [ -n "$node" ]; then
      grep -q '^  my\.audioMixerOutputs = {' "$file" ||
        sed -i '/^ *my\.desktop = /a\  my.audioMixerOutputs = {\n  };' "$file"
      sed -i -e "$block{/^  };/i\\    $role = \"$node\";" -e '}' "$file"
    fi
    apply "audio $role = ${node:-none}"
    [ "$(my audioMixer)" = true ] || echo "The mixer itself is off; turn it on with: ojust enable audioMixer"

# Send the Main Mix to one of the outputs set with `ojust audio` (asks which, if not given)
[group('audio')]
mixer-output name="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    name=$1
    if [ -z "$name" ]; then
      mapfile -t names < <(my audioMixerOutputs | jq -r 'keys[]')
      [ ${#names[@]} -gt 0 ] || die "No outputs set yet; add one with: ojust audio"
      name=$(pick "output" "${names[@]}")
    fi
    change-mixer-output "$name"
