{ config, lib, ... }: {
  options.my.fingerprint = lib.mkEnableOption "Fingerprint reader (fprintd)";

  # Fingerprint for sudo and the lock screen through PAM. Enroll with `fprintd-enroll`.
  config = lib.mkIf config.my.fingerprint {
    services.fprintd.enable = true;
    # Not at login (greetd substacks login): a fingerprint gives no password, so gnome-keyring stays locked
    security.pam.services.login.fprintAuth = false;
  };
}
