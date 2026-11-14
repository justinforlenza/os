# Installer ISO: build with scripts/build-iso
{ lib, pkgs, modulesPath, inputs, ... }: {
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ./cache.nix ];

  # The repo as of the build (tracked files, including uncommitted changes) and the commit it was built on.
  # os-install starts from this and offers GitHub's latest if it differs.
  environment.etc."os-repo".source = inputs.self;
  environment.etc."os-repo-rev".text = inputs.self.rev or inputs.self.dirtyRev or "unknown";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # NetworkManager so `nmtui` works for Wi-Fi. It runs wpa_supplicant itself; forcing networking.wireless off breaks Wi-Fi.
  networking.networkmanager.enable = true;

  # kmscon instead of the kernel console: real fonts, Unicode and 256 colours, so the Textual installer renders
  # properly (the plain Linux console turns its borders into '#')
  services.kmscon = {
    enable = true;
    config.font-name = "Fira Code, DejaVu Sans Mono"; # DejaVu fills in symbols Fira Code lacks
  };
  fonts.packages = [ pkgs.fira-code pkgs.dejavu_fonts ];
  fonts.fontconfig.enable = lib.mkForce true; # the minimal ISO profile turns it off; kmscon needs it for fonts
  # Keep the screen on: a long download blanked it, which looks like a hang
  boot.kernelParams = [ "consoleblank=0" ];

  # Start the installer once per boot, in the first (auto-login) shell; later shells and ttys stay plain.
  # mkdir is the "only once" check: under kmscon the shell's tty is a pty, not /dev/tty1.
  programs.bash.loginShellInit = ''
    if [ -t 0 ] && mkdir /tmp/.os-install-autostarted 2>/dev/null; then
      os-install || echo "Installer stopped. Run os-install to start it again."
    fi
  '';

  environment.systemPackages = with pkgs; [
    git gh disko
    (writeShellApplication {
      name = "os-install"; # not `install`: that would shadow coreutils' install, which nixos-install uses
      runtimeInputs = [ (python3.withPackages (p: [ p.textual ])) git gh disko curl networkmanager rsync openssh ];
      text = ''
        [ "$(id -u)" -eq 0 ] || exec sudo --preserve-env=REPO "$0" "$@"
        exec python3 ${../install.py} "$@"
      '';
    })
  ];
}
