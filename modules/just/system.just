# Pull the latest config from GitHub and apply it now (switch) or at next boot (boot)
[group('system')]
update mode="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    mode=${1:-$(pick "when to apply the update" switch boot)}
    [[ $mode = switch || $mode = boot ]] || die "Mode is switch or boot, not '$mode'."
    pull
    rebuild "$mode"

# List optional features; in a terminal, pick which ones this machine has (applied, committed, pushed)
[group('system')]
options:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    labels=$(option_labels)
    state=$(my)
    jq -rn --argjson l "$labels" --argjson s "$state" \
      '$l | to_entries[] | "\(if $s[.key] then "[on] " else "[off]" end) \(.key)\t\(.value)"' | column -t -s $'\t'
    [ -t 0 ] || exit 0
    mapfile -t names < <(jq -r 'keys[]' <<<"$labels")
    on=$(jq -rn --argjson l "$labels" --argjson s "$state" '[$l | keys[] | select($s[.])] | join(",")')
    picked=$(gum choose --no-limit --header "Options to have on (tab toggles, enter applies)" --selected="$on" "${names[@]}")
    changes=()
    for n in "${names[@]}"; do
      want=false
      if grep -qxF "$n" <<<"$picked"; then want=true; fi
      [ "$want" = "$(jq -r --arg n "$n" '.[$n] // false' <<<"$state")" ] || changes+=("$n=$want")
    done
    [ ${#changes[@]} -gt 0 ] || { echo "Nothing to change."; exit 0; }
    pull
    for c in "${changes[@]}"; do set_my "${c%=*}" "${c#*=}"; done
    apply "$(IFS=,; echo "${changes[*]}")"

# Turn features on (asks which, if none given), apply, then commit and push
[group('system')]
enable *names:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    set_options true "$@"

# Turn features off (asks which, if none given), apply, then commit and push
[group('system')]
disable *names:
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    set_options false "$@"

# Change the desktop (asks which, if not given); applied at next boot, committed and pushed
[group('desktop')]
desktop name="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    set_enum desktop "$1"
    apply "desktop = $value" boot # the login screen changes too; switching it live would end this session
    echo "Reboot to use $value."

# Change the wallpaper set (asks which, if not given); applied now, committed and pushed
[group('desktop')]
wallpapers set="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    set_enum wallpapers "$1"
    apply "wallpapers = $value"
