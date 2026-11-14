# Enroll this machine in a MeshCentral group from the group's "Add Agent -> Linux" install command.
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

# Arg is for testing; normally the command is pasted
cmd=${1:-$(gum input --char-limit 0 --width 0 --placeholder "Paste the MeshCentral Add Agent -> Linux command")}
re="meshinstall\.sh (https://[^ ]+) '([^']+)'"
if [[ ! $cmd =~ $re ]]; then
  gum log -l error "No 'meshinstall.sh https://<server> '<group id>'' found in that command"
  exit 1
fi
server=${BASH_REMATCH[1]} id=${BASH_REMATCH[2]}

umask 077
# printf keeps the $ in the group id literal (no shell expansion of the value)
printf "MESH_SERVER=%s\nMESH_ID='%s'\n" "$server" "$id" > /etc/meshagent.env
systemctl stop meshagent 2>/dev/null || true
rm -rf /var/lib/meshagent/*
systemctl restart --no-block meshagent # it retries on its own until the server is reachable
gum log -l info "Enrolling with $server. Check progress: systemctl status meshagent"
