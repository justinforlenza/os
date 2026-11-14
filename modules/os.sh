# os: manage this machine through its config checkout in /etc/nixos.
# Changes are committed and pushed, because the daily autoUpgrade builds from GitHub and would undo local-only edits.
repo=/etc/nixos
host=$(hostname)
file=$repo/hosts/$host/default.nix

usage() {
  cat <<EOF
Usage: os <command>
  update [boot]           pull the latest config from GitHub and apply it now (or at next boot)
  options                 list optional features and whether this machine has them
  enable <option>...      turn features on, apply, then commit and push hosts/$host
  disable <option>...     turn features off, same
  desktop [<name>]        show the desktop, or change it (applied at next boot; committed and pushed)
  wallpapers [<set>]      show the wallpaper set, or change it (applied now; committed and pushed)
  audio                   show the mixer's outputs and the sound devices connected now
  audio <name> <n|none>   send \`change-mixer-output <name>\` to device n from that list (or remove it)
EOF
}

[ "$(id -u)" -ne 0 ] || { echo "Run os as your user, not root (it uses sudo when needed)." >&2; exit 1; }
[ -f "$file" ] || { echo "No $file: this machine's config isn't in $repo." >&2; exit 1; }

rebuild() { sudo nixos-rebuild "${1:-switch}" --flake "$repo#$host"; }
pull() { git -C "$repo" pull --rebase --autostash; }

# After editing $file: show the change, rebuild ($2: switch or boot; undoing the edit if that fails),
# then commit and push it
apply() {
  git -C "$repo" --no-pager diff -- "$file"
  if git -C "$repo" diff --quiet -- "$file"; then echo "Nothing to change."; exit 0; fi
  rebuild "${2:-switch}" || { git -C "$repo" checkout -- "$file"; echo "Build failed; change undone." >&2; exit 1; }
  git -C "$repo" commit -q -m "$host: $1" -- "$file"
  git -C "$repo" push -q ||
    echo "Applied, but the push failed: push /etc/nixos yourself, or the daily update will undo it." >&2
}

case "${1:-}" in
  update)
    [ "${2:-switch}" = switch ] || [ "${2:-}" = boot ] || { usage >&2; exit 1; }
    pull
    rebuild "${2:-switch}"
    ;;

  options)
    labels=$(nix eval --json "$repo#installer.options")
    state=$(nix eval --json "$repo#nixosConfigurations.$host.config.my")
    jq -rn --argjson l "$labels" --argjson s "$state" \
      '$l | to_entries[] | "\(if $s[.key] then "[on] " else "[off]" end) \(.key)\t\(.value)"' | column -t -s $'\t'
    ;;

  enable | disable)
    [ $# -ge 2 ] || { usage >&2; exit 1; }
    value=$([ "$1" = enable ] && echo true || echo false)
    shift
    pull
    labels=$(nix eval --json "$repo#installer.options")
    for name in "$@"; do
      jq -e --arg n "$name" 'has($n)' <<<"$labels" >/dev/null ||
        { echo "Unknown option '$name'. See: os options" >&2; exit 1; }
      if grep -q "^ *my\.$name = " "$file"; then
        sed -i "s/^\( *my\.$name = \).*;/\1$value;/" "$file"
      else # an option added after this machine was installed
        sed -i "/^ *my\.desktop = /a\\  my.$name = $value;" "$file"
      fi
    done
    apply "$(tr ' ' , <<<"$*") = $value"
    ;;

  desktop | wallpapers) # a my.* setting with a fixed list of values
    opt=$1
    choices=$(nix eval --json "$repo#nixosConfigurations.$host.options.my.$opt.type.functor.payload.values")
    current=$(nix eval --raw "$repo#nixosConfigurations.$host.config.my.$opt")
    if [ -z "${2:-}" ]; then
      echo "$opt: $current (choices: $(jq -r 'join(", ")' <<<"$choices"))"; exit 0
    fi
    jq -e --arg d "$2" 'index($d)' <<<"$choices" >/dev/null ||
      { echo "Unknown $opt '$2'. Choices: $(jq -r 'join(", ")' <<<"$choices")" >&2; exit 1; }
    pull
    if grep -q "^ *my\.$opt = " "$file"; then
      sed -i "s/^\( *my\.$opt = \).*;/\1\"$2\";/" "$file"
    else # a setting added after this machine was installed
      sed -i "/^ *my\.desktop = /a\\  my.$opt = \"$2\";" "$file"
    fi
    if [ "$opt" = desktop ]; then
      apply "desktop = $2" boot # the login screen changes too; switching it live would end this session
      echo "Reboot to use $2."
    else
      apply "$opt = $2"
    fi
    ;;

  audio) # my.audioMixerOutputs: the device each `change-mixer-output <name>` sends the Main Mix to
    # Sound outputs PipeWire sees right now, as "node name<TAB>description" (same list as the installer's)
    mapfile -t devices < <(pw-dump | jq -r '.[] | .info.props? // empty
      | select(."media.class" == "Audio/Sink" and (."node.name" // "" | startswith("alsa_output.")))
      | "\(."node.name")\t\(."node.description" // ."node.name")"' | sort)
    if [ -z "${2:-}" ]; then
      echo "Mixer outputs (change-mixer-output <name>):"
      nix eval --json "$repo#nixosConfigurations.$host.config.my.audioMixerOutputs" |
        jq -r 'if length == 0 then "  none set" else to_entries[] | "  \(.key) -> \(.value)" end'
      echo "Sound outputs connected now:"
      for i in "${!devices[@]}"; do
        printf '  %d) %s\n     %s\n' $((i + 1)) "${devices[i]#*$'\t'}" "${devices[i]%%$'\t'*}"
      done
      [ ${#devices[@]} -gt 0 ] || echo "  none found"
      echo "Set one with: os audio <name> <number|none>   e.g. os audio headphones 1"
      exit 0
    fi
    role=$2 pick=${3:-}
    [[ $role =~ ^[a-z][a-zA-Z0-9]*$ ]] && [ -n "$pick" ] || { usage >&2; exit 1; }
    if [ "$pick" = none ]; then
      node=""
    elif [[ $pick =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#devices[@]} ]; then
      node=${devices[pick - 1]%%$'\t'*}
    else
      echo "Pick a number from the list in 'os audio', or none." >&2; exit 1
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
    [ "$(nix eval "$repo#nixosConfigurations.$host.config.my.audioMixer")" = true ] ||
      echo "The mixer itself is off; turn it on with: os enable audioMixer"
    ;;

  *) usage; [ -n "${1:-}" ] && exit 1 ;;
esac
