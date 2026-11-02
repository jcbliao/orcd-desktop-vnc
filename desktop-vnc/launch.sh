#!/usr/bin/env bash
# Extra arguments override the defaults below, e.g. --time=02:00:00 --mem=16G.
set -euo pipefail
umask 077
follow_logs=1
slurm_args=()
for arg in "$@"; do
    if [[ "$arg" == --detach ]]; then
        follow_logs=0
    else
        slurm_args+=("$arg")
    fi
done
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$base/sessions"
session=$(mktemp -d "$base/sessions/session-XXXXXXXX")
: > "$session/job.log"
python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(8)))' > "$session/password"
if ! job=$(sbatch --parsable --job-name=engaging-desktop-vnc \
    --partition=mit_normal --account=mit_amf_advanced_cpu \
    --qos=mit_amf_advanced_cpu --nodes=1 --ntasks=1 \
    --cpus-per-task=8 --mem=64G --time=06:00:00 \
    --export=NONE --chdir="$session" --output="$session/job.log" \
    "${slurm_args[@]}" "$base/desktop.sbatch"); then
    echo "Submission failed. Session directory: $session" >&2
    exit 1
fi
job=${job%%;*}
printf '%s\n' "$job" > "$session/job-id"
printf 'Submitted desktop job %s\nSession directory: %s\n\n' "$job" "$session"
printf 'VNC password: %s\n\n' "$(cat "$session/password")"
printf 'Check status: squeue -j %s\n' "$job"
printf 'Once running, read the connection instructions:\n  cat %q/connection.txt\n' "$session"
printf 'Stop the desktop: scancel %s\n' "$job"
if (( follow_logs )); then
    printf '\nFollowing the job log (it may be quiet while the job is queued).\n'
    printf 'Press Ctrl-C or close this terminal to stop viewing logs; the desktop job keeps running.\n'
    printf 'To view the log again: tail -n +1 -F %q/job.log\n\n' "$session"
    # This process only reads the log. Slurm owns the separately submitted job.
    exec tail -n +1 -F "$session/job.log"
fi
