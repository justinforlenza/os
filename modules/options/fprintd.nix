{ config, lib, ... }: {
  options.my.fingerprint = lib.mkEnableOption "Fingerprint reader (fprintd)";

  # Also turns on fingerprint login and sudo through PAM. Enroll with `fprintd-enroll`.
  config = lib.mkIf config.my.fingerprint { services.fprintd.enable = true; };
}
