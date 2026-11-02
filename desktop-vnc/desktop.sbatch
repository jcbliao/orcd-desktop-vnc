#!/bin/bash
set -eo pipefail
umask 077
if [[ -z ${SLURM_JOB_ID:-} ]]; then
    echo 'Use launch.sh to submit this desktop to Slurm.' >&2
    exit 1
fi
session=$PWD
image=${1:-/home/systems/engaging-ood-ww/kde/mit/container.sif}
source /etc/profile.d/modules.sh
module purge
module load "${2:-apptainer/1.4.2}"
export APPTAINER_BINDPATH=/home,/orcd,/nfs,/net,/var/lib/sss,/var/run/munge,/etc/slurm
instance="desktop-vnc-${SLURM_JOB_ID}-$$"
display=
desktop_pid=
started=0
cleanup() {
    trap - EXIT
    trap '' TERM INT
    if (( started )); then
        if [[ -n "$display" ]]; then
            apptainer exec "instance://$instance" vncserver -kill ":$display" || true
        fi
        apptainer instance stop "$instance" || true
    fi
    [[ -z "$desktop_pid" ]] || kill "$desktop_pid" 2>/dev/null || true
    [[ ! -f "$session/connection.txt" ]] || mv "$session/connection.txt" "$session/connection-ended.txt"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
unset DISPLAY DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER WAYLAND_DISPLAY
apptainer instance start "$image" "$instance"
started=1
# The container has no usable desktop-login password; use VNC + SSH auth.
apptainer exec "instance://$instance" kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock --type bool false
apptainer exec "instance://$instance" kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume --type bool false
if [[ ! -s "$session/password" ]]; then
    python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(8)))' > "$session/password"
fi
apptainer exec "instance://$instance" vncpasswd -f < "$session/password" > "$session/vnc.passwd"
vnc_output=$(apptainer exec "instance://$instance" vncserver \
    -localhost -securitytypes VNC -noxstartup -geometry 1920x1080 -depth 24 \
    -rfbauth "$session/vnc.passwd" -log "$session/vnc.log" 2>&1) || {
    printf '%s\n' "$vnc_output" >&2
    exit 1
}
printf '%s\n' "$vnc_output"
display=$(printf '%s\n' "$vnc_output" | sed -nE '/^Desktop/s/.*:([0-9]+)[[:space:]]*$/\1/p' | tail -1)
if [[ ! "$display" =~ ^[0-9]+$ ]]; then
    echo 'Could not determine the VNC display. See job.log and vnc.log.' >&2
    exit 1
fi
port=$((5900 + display))
export APPTAINERENV_DISPLAY=":$display"
export APPTAINERENV_XDG_CURRENT_DESKTOP=KDE
export APPTAINERENV_KDE_FULL_SESSION=true
export APPTAINERENV_KDE_SESSION_VERSION=5
export APPTAINERENV_QT_QPA_PLATFORMTHEME=KDE
apptainer exec "instance://$instance" dbus-run-session -- startplasma-x11 > "$session/desktop.log" 2>&1 &
desktop_pid=$!
sleep 5
if ! kill -0 "$desktop_pid" 2>/dev/null; then
    echo 'KDE exited during startup. See desktop.log.' >&2
    wait "$desktop_pid"
    exit 1
fi
node=$(hostname -f)
username=$(id -un)
# Publish readiness atomically so readers never see partial connection details.
cat > "$session/connection.tmp" <<END
Desktop job: $SLURM_JOB_ID
Compute node: $node
VNC display: :$display (TCP port $port)

On your own computer, run and leave this SSH tunnel open:
ssh -N -T -o ExitOnForwardFailure=yes -J $username@orcd-login.mit.edu -L 127.0.0.1:15901:127.0.0.1:$port $username@$node

In TurboVNC Viewer, connect to: 127.0.0.1::15901
VNC password: $(cat "$session/password")

Closing the viewer leaves the job running.
Stop the desktop when finished: scancel $SLURM_JOB_ID
END
mv "$session/connection.tmp" "$session/connection.txt"
cat "$session/connection.txt"
wait "$desktop_pid"
