# Enroll this machine in a MeshCentral group: paste the group's "Add Agent -> Linux" command when asked
[group('system')]
enroll-meshagent command="":
    #!/usr/bin/env bash
    set -euo pipefail
    sudo meshagent-enroll "$@"
