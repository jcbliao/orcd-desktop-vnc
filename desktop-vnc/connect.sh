#!/usr/bin/env bash
# Copy this file to your own computer and run it there (requires Bash and SSH).
set -euo pipefail
# Set ORCD_USER when your local username differs from your ORCD username.
username=${ORCD_USER:-${USER:-}}
if [[ ! "$username" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]]; then
    echo 'Set ORCD_USER to your ORCD username.' >&2
    exit 1
fi
if [[ ${1:-} == --ssh-config ]]; then
    cat <<EOF
Host orcd orcd-login.mit.edu
    HostName orcd-login.mit.edu
    User $username
    ServerAliveInterval 60
    ServerAliveCountMax 3

Match originalhost orcd-desktop exec "bash ~/connect-desktop.sh --prepare-ssh"
    Include ~/.ssh/orcd-desktop-session.conf

Host orcd-desktop
    User $username
    ServerAliveInterval 60
    ExitOnForwardFailure yes

Host node*.inband
    User $username
    ProxyJump orcd
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    exit 0
fi
mode=vnc
if [[ ${1:-} == --ssh || ${1:-} == --prepare-ssh ]]; then
    mode=${1#--}
    shift
fi
selector=${1:-engaging-desktop-vnc}
if [[ ! "$selector" =~ ^[a-zA-Z0-9_./:-]+$ ]]; then
    echo 'Use a job name or numeric job ID.' >&2
    exit 1
fi
login="$username@orcd-login.mit.edu"
if [[ $mode == prepare-ssh ]]; then
    login=orcd
fi
local_port=${VNC_LOCAL_PORT:-15901}
if [[ ! "$local_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$local_port < 1 || 10#$local_port > 65535 )); then
    echo 'VNC_LOCAL_PORT must be an integer from 1 to 65535.' >&2
    exit 1
fi
lookup_option=--password
if [[ $mode == prepare-ssh ]]; then
    lookup_option=
fi
if [[ $mode == ssh ]]; then
    lookup_option=--host
fi
if [[ $mode == prepare-ssh ]]; then
    details=$(ssh -T "$login" 'python3 ~/desktop-vnc/ensure-session.py')
else
    details=$(ssh -T "$login" "python3 ~/desktop-vnc/find-session.py '$selector' $lookup_option")
fi
IFS=$'\t' read -r job host port password_file password <<< "$details"
if [[ ! "$job" =~ ^[0-9]+$ || ! "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
    echo 'Could not parse desktop lookup response.' >&2
    exit 1
fi
if [[ $mode == ssh ]]; then
    printf 'Found job %s on %s\n' "$job" "$host"
    exec ssh -t -J "$login" "$username@$host"
fi
if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    echo 'Could not parse desktop VNC port.' >&2
    exit 1
fi
if [[ $mode == prepare-ssh ]]; then
    # Included by the local SSH config after this lookup succeeds.
    umask 077
    mkdir -p "$HOME/.ssh"
    config=$(mktemp "$HOME/.ssh/orcd-desktop-session.XXXXXXXX")
    printf 'HostName %s\nProxyJump orcd\nLocalForward 127.0.0.1:%s 127.0.0.1:%s\n' \
        "$host" "$local_port" "$port" > "$config"
    mv -f "$config" "$HOME/.ssh/orcd-desktop-session.conf"
    printf 'Opening shell and VNC tunnel. Connect TurboVNC to 127.0.0.1::%s once SSH connects.\n' "$local_port" >&2
    exit 0
fi
printf 'Found job %s on %s, VNC port %s\n' "$job" "$host" "$port"
printf 'Connect TurboVNC Viewer to 127.0.0.1::%s\n' "$local_port"
printf 'VNC password: %s\n' "$password"
printf 'Leave this terminal open. Press Ctrl-C to close the tunnel.\n'
exec ssh -N -T -o ExitOnForwardFailure=yes -J "$login" \
    -L "127.0.0.1:$local_port:127.0.0.1:$port" "$username@$host"
