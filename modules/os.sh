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

  desktop)
    choices=$(nix eval --json "$repo#nixosConfigurations.$host.options.my.desktop.type.functor.payload.values")
    current=$(nix eval --raw "$repo#nixosConfigurations.$host.config.my.desktop")
    if [ -z "${2:-}" ]; then
      echo "Desktop: $current (choices: $(jq -r 'join(", ")' <<<"$choices"))"; exit 0
    fi
    jq -e --arg d "$2" 'index($d)' <<<"$choices" >/dev/null ||
      { echo "Unknown desktop '$2'. Choices: $(jq -r 'join(", ")' <<<"$choices")" >&2; exit 1; }
    pull
    sed -i "s/^\( *my\.desktop = \).*;/\1\"$2\";/" "$file"
    apply "desktop = $2" boot # the login screen changes too; switching it live would end this session
    echo "Reboot to use $2."
    ;;

  *) usage; [ -n "${1:-}" ] && exit 1 ;;
esac
