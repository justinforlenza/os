# Spread a wallpaper across all monitors: pick one from ~/.wallpapers, or pass an image path or "random"
[group('desktop')]
wallpaper image="":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$OJUST_LIB"
    image=$1
    if [ -z "$image" ]; then
      [ -t 0 ] || die "Pass an image path or random (no terminal to ask on)."
      image=$( { echo random; find -L ~/.wallpapers -type f -printf '%P\n' | sort; } |
        gum filter --placeholder "Pick a wallpaper")
      [ "$image" = random ] || image=~/.wallpapers/$image
    fi
    if [ "$image" = random ]; then change-wallpaper; else change-wallpaper "$image"; fi
