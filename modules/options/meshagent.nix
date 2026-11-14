# MeshCentral remote-management agent. Idle until /etc/meshagent.env exists; `sudo meshagent-enroll` writes it.
{ config, lib, pkgs, ... }:
let
  enroll = pkgs.writeShellApplication {
    name = "meshagent-enroll";
    runtimeInputs = [ pkgs.gum ];
    text = builtins.readFile ./meshagent-enroll.sh;
  };
in {
  options.my.meshagent = lib.mkEnableOption "MeshCentral agent";

  config = lib.mkIf config.my.meshagent {
    environment.systemPackages = [ enroll ];
    programs.nix-ld.enable = true; # the downloaded agent is a generic Linux binary
    systemd.services.meshagent = {
      description = "MeshCentral agent";
      wants = [ "network-online.target" ]; after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/etc/meshagent.env";
      path = [ pkgs.curl pkgs.coreutils ];
      serviceConfig = {
        EnvironmentFile = "/etc/meshagent.env";
        StateDirectory = "meshagent";
        WorkingDirectory = "/var/lib/meshagent";
        # A script file, so bash (not systemd) expands the variables; temp file + mv never keeps a failed download
        ExecStartPre = pkgs.writeShellScript "meshagent-fetch" ''
          test -x meshagent || { curl -fsSL -o meshagent.tmp "$MESH_SERVER/meshagents?id=6" && chmod +x meshagent.tmp && mv meshagent.tmp meshagent; }
          test -s meshagent.msh || { curl -fsSL -o msh.tmp "$MESH_SERVER/meshsettings?id=$MESH_ID" && mv msh.tmp meshagent.msh; }
        '';
        ExecStart = "/var/lib/meshagent/meshagent";
        Restart = "always"; RestartSec = 30;
      };
    };
    # The agent only notices a new desktop session after a restart; logind rewrites this file on login/logout/user switch
    systemd.paths.meshagent-session = { wantedBy = [ "multi-user.target" ]; pathConfig.PathChanged = "/run/systemd/seats/seat0"; };
    systemd.services.meshagent-session.serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.systemd}/bin/systemctl try-restart meshagent.service"; };
  };
}
