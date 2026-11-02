#!/usr/bin/env bash
set -euo pipefail
umask 077
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# This private file is shell syntax; copy config.example first.
[[ ! -f "$base/config.sh" ]] || source "$base/config.sh"
follow_logs=1
slurm_args=()
for arg in "$@"; do
    if [[ "$arg" == --detach ]]; then follow_logs=0; else slurm_args+=("$arg"); fi
done
mkdir -p "$base/sessions"
session=$(mktemp -d "$base/sessions/session-XXXXXXXX")
: > "$session/job.log"
python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(8)))' > "$session/password"
account_args=()
[[ -z ${DESKTOP_ACCOUNT:-} ]] || account_args+=("--account=$DESKTOP_ACCOUNT")
[[ -z ${DESKTOP_QOS:-} ]] || account_args+=("--qos=$DESKTOP_QOS")
if ! job=$(sbatch --parsable --job-name=engaging-desktop-vnc \
    --partition="${DESKTOP_PARTITION:-mit_normal}" ${account_args[@]+"${account_args[@]}"} \
    --nodes=1 --ntasks=1 --cpus-per-task="${DESKTOP_CPUS:-8}" \
    --mem="${DESKTOP_MEMORY:-64G}" --time="${DESKTOP_TIME:-06:00:00}" \
    --export=NONE --chdir="$session" --output="$session/job.log" \
    ${slurm_args[@]+"${slurm_args[@]}"} "$base/desktop.sbatch" \
    "${DESKTOP_IMAGE:-/home/systems/engaging-ood-ww/kde/mit/container.sif}" \
    "${DESKTOP_APPTAINER_MODULE:-apptainer/1.4.2}"); then
    echo "Submission failed. Session directory: $session" >&2
    exit 1
fi
job=${job%%;*}
printf '%s\n' "$job" > "$session/job-id"
printf 'Submitted desktop job %s\nSession directory: %s\n' "$job" "$session"
printf 'VNC password: %s\n' "$(cat "$session/password")"
printf 'Check status: squeue -j %s\nStop desktop: scancel %s\n' "$job" "$job"
if (( follow_logs )); then
    echo 'Following logs. Ctrl-C stops viewing; the job keeps running.'
    exec tail -n +1 -F "$session/job.log"
fi
