# Sourced by ojust recipes. Edits to hosts/$host are committed and pushed, because the daily autoUpgrade
# builds from GitHub and would undo local-only edits.
# shellcheck disable=SC2034 # repo/host/file are used by the recipes that source this
repo=/etc/nixos
host=$(hostname)
file=$repo/hosts/$host/default.nix

die() { echo "$*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "Run ojust as your user, not root (it uses sudo when needed)."

# pick <what> [gum choose flags/options...]: ask with gum; without a terminal, say which argument to pass instead
pick() {
  local what=$1; shift
  [ -t 0 ] || die "Pass the $what as an argument (no terminal to ask on)."
  gum choose --header "Pick $what" "$@"
}

need_host() { [ -f "$file" ] || die "No $file: this machine's config isn't in $repo."; }
# my [name]: this machine's config.my (or config.my.<name>) as JSON
my() { need_host; nix eval --json "$repo#nixosConfigurations.$host.config.my${1:+.$1}"; }
rebuild() { sudo nixos-rebuild "${1:-switch}" --flake "$repo#$host"; }
pull() { need_host; git -C "$repo" pull --rebase --autostash; }

# set_my <name> <nix value>: set my.<name> in $file, adding it after my.desktop if missing (an option added
# after this machine was installed)
set_my() {
  if grep -q "^ *my\.$1 = " "$file"; then
    sed -i "s/^\( *my\.$1 = \).*;/\1$2;/" "$file"
  else
    sed -i "/^ *my\.desktop = /a\\  my.$1 = $2;" "$file"
  fi
}

# After editing $file: show the change, rebuild ($2: switch or boot; undoing the edit if that fails),
# then commit and push it
apply() {
  git -C "$repo" --no-pager diff -- "$file"
  if git -C "$repo" diff --quiet -- "$file"; then echo "Nothing to change."; exit 0; fi
  rebuild "${2:-switch}" || { git -C "$repo" checkout -- "$file"; die "Build failed; change undone."; }
  git -C "$repo" commit -q -m "$host: $1" -- "$file"
  git -C "$repo" push -q ||
    echo "Applied, but the push failed: push /etc/nixos yourself, or the daily update will undo it." >&2
}

# Boolean my.* options as JSON: name → label (what the installer's Options screen shows)
option_labels() { nix eval --json "$repo#installer.options"; }

# set_options <true|false> [name...]: turn options on/off (asking which, if none given), apply, commit, push
set_options() {
  local value=$1 labels state picked name
  shift
  labels=$(option_labels)
  if [ $# -eq 0 ]; then
    state=$(my)
    mapfile -t cands < <(jq -rn --argjson l "$labels" --argjson s "$state" --argjson v "$value" \
      '$l | keys[] | select(($s[.] // false) != $v)')
    [ ${#cands[@]} -gt 0 ] || die "Every option is already $value."
    picked=$(pick "options to set to $value (tab toggles)" --no-limit "${cands[@]}")
    [ -n "$picked" ] || exit 0
    mapfile -t names <<<"$picked"
    set -- "${names[@]}"
  fi
  for name in "$@"; do
    jq -e --arg n "$name" 'has($n)' <<<"$labels" >/dev/null || die "Unknown option '$name'. See: ojust options"
  done
  pull
  for name in "$@"; do set_my "$name" "$value"; done
  apply "$(IFS=,; echo "$*") = $value"
}

# set_enum <opt> [value]: set a my.* setting that has a fixed list of values (asking which, if not given),
# leaving the choice in $value; the caller applies
set_enum() {
  local opt=$1 current choices
  value=${2:-}
  current=$(my "$opt" | jq -r .)
  choices=$(nix eval --json "$repo#nixosConfigurations.$host.options.my.$opt.type.functor.payload.values")
  if [ -z "$value" ]; then
    mapfile -t list < <(jq -r '.[]' <<<"$choices")
    value=$(pick "$opt (now: $current)" --selected="$current" "${list[@]}")
  fi
  jq -e --arg d "$value" 'index($d)' <<<"$choices" >/dev/null ||
    die "Unknown $opt '$value'. Choices: $(jq -r 'join(", ")' <<<"$choices")"
  pull
  set_my "$opt" "\"$value\""
}
