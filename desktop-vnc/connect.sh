#!/usr/bin/env bash
# Run on your own computer. SSH alias 'orcd' supplies your cluster username.
set -euo pipefail
if [[ ${1:-} == --ssh-config ]]; then
    cat <<'SSH_CONFIG'
# Merge into ~/.ssh/config on YOUR COMPUTER; do not replace existing entries.
# Replace YOUR_MIT_USERNAME. If you already have Host orcd, edit that entry.
Host orcd
    HostName orcd-login.mit.edu
    User YOUR_MIT_USERNAME
    ServerAliveInterval 60
    ServerAliveCountMax 3
    # Optional: uncomment and set your own key path if needed.
    # IdentityFile ~/.ssh/id_ed25519

# Optional shortcut: requires ~/connect-desktop.sh on your computer.
# Put this section before any broad Host * defaults that set User/HostName.
Match originalhost orcd-desktop exec "bash ~/connect-desktop.sh --prepare-ssh"
    Include ~/.ssh/orcd-desktop-session.conf

Host orcd-desktop
    ServerAliveInterval 60
    ExitOnForwardFailure yes
    # If you use a non-default key, specify it here too.
    # IdentityFile ~/.ssh/id_ed25519

# Needed for custom compute-node key settings, not for choosing a fixed node.
Host node*.inband
    User YOUR_MIT_USERNAME
    ProxyJump orcd
    ServerAliveInterval 60
    # IdentityFile ~/.ssh/id_ed25519

# Reset the scope before any further SSH configuration.
Host *
SSH_CONFIG
    exit 0
fi
mode=vnc
case ${1:-} in
    --prepare-ssh|--ssh) mode=${1#--}; shift ;;
    --help|-h)
        echo 'Usage: connect-desktop.sh [--ssh] [JOB_ID_OR_NAME]'
        echo 'No selector starts or reuses your desktop. --ssh opens a shell instead of VNC.'
        echo 'Set VNC_LOCAL_PORT to change the local port (default 15901).'
        exit 0 ;;
esac
selector=${1:-}
if (( $# > 1 )) || [[ -n "$selector" && ! "$selector" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
    echo 'Provide one job name or numeric job ID.' >&2
    exit 1
fi
local_port=${VNC_LOCAL_PORT:-15901}
if [[ ! "$local_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$local_port < 1 || 10#$local_port > 65535 )); then
    echo 'VNC_LOCAL_PORT must be an integer from 1 to 65535.' >&2
    exit 1
fi
# Resolve User from SSH configuration, not the local OS username.
username=$(ssh -G orcd | awk '$1 == "user" {print $2}')
if [[ ! "$username" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]]; then
    echo 'Set a valid User in your SSH Host orcd configuration.' >&2
    exit 1
fi
if [[ -z "$selector" ]]; then
    details=$(ssh -T orcd 'python3 ~/desktop-vnc/ensure-session.py')
else
    details=$(ssh -T orcd "python3 ~/desktop-vnc/find-session.py '$selector' --password")
fi
IFS=$'\t' read -r job host port password_file password <<< "$details"
if [[ ! "$job" =~ ^[0-9]+$ || ! "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ || ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
    echo 'Could not parse desktop lookup response.' >&2
    exit 1
fi
if [[ $mode == prepare-ssh ]]; then
    umask 077
    mkdir -p "$HOME/.ssh"
    config=$(mktemp "$HOME/.ssh/orcd-desktop-session.XXXXXXXX")
    printf 'HostName %s\nUser %s\nProxyJump orcd\nLocalForward 127.0.0.1:%s 127.0.0.1:%s\n' \
        "$host" "$username" "$local_port" "$port" > "$config"
    mv -f "$config" "$HOME/.ssh/orcd-desktop-session.conf"
    printf 'Connect TurboVNC to 127.0.0.1::%s once SSH connects.\n' "$local_port" >&2
    exit 0
fi
printf 'Found job %s on %s, VNC port %s\n' "$job" "$host" "$port"
if [[ $mode == ssh ]]; then
    exec ssh -t -J orcd "$username@$host"
fi
printf 'Connect TurboVNC Viewer to 127.0.0.1::%s\nVNC password: %s\n' "$local_port" "$password"
echo 'Leave this terminal open. Ctrl-C closes the tunnel; the desktop job keeps running.'
exec ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 \
    -J orcd -L "127.0.0.1:$local_port:127.0.0.1:$port" "$username@$host"
