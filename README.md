# ForlenzaOS

My personal NixOS config: one flake for all my machines.

## Install

1. Download the latest `forlenza-os-installer-*.iso` from [Releases](https://github.com/justinforlenza/os/releases).
2. Boot it. The installer starts on its own (run `os-install` to restart it).
3. Answer the questions (hostname, disk, desktop, options). It then wipes the disk and installs.

## After install

Run `ojust` to pick a command from a list, or `ojust --list` to see them all.

- `ojust update` pulls the latest config and applies it
- `ojust enable` / `ojust disable` turns optional features on or off
- `ojust desktop` switches between KDE and niri
- `ojust wallpapers` changes the wallpaper set

Changes made with `ojust` are committed and pushed back to this repo.

## Layout

- `hosts/` one folder per machine
- `modules/` shared config, desktops and optional features
- `home/` home-manager config and dotfiles
- `pkgs/` packages not in nixpkgs
- `scripts/` build the ISO, run a host in a VM, update packages
- `install.py` the installer shipped on the ISO

## Testing without Nix

`scripts/nix` runs nix in podman. `scripts/vm <host>` boots a host as a VM, and `scripts/iso-vm --iso` tests the installer. View either over VNC at localhost:5900.
