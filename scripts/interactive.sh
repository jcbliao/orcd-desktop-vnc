#!/usr/bin/env bash
#SBATCH --job-name=interactive
#SBATCH --account=mit_amf_advanced_cpu
#SBATCH --qos=mit_amf_advanced_cpu
#SBATCH --partition=mit_normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2-00:00:00
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null

set -euo pipefail

# Run directly as `interactive.sh [cpu|gpu] [sbatch options...]` to select
# the matching account and QoS. Plain `sbatch interactive.sh` uses CPU defaults.
if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    target="${1:-cpu}"
    if (( $# > 0 )); then shift; fi
    case "$target" in
        cpu|mit_normal)
            account=mit_amf_advanced_cpu
            partition=mit_normal
            ;;
        gpu|mit_normal_gpu)
            account=mit_amf_advanced_gpu
            partition=mit_normal_gpu
            ;;
        *)
            echo "Usage: $0 [cpu|gpu] [sbatch options...]" >&2
            exit 2
            ;;
    esac
    exec sbatch --account="$account" --qos="$account" \
        --partition="$partition" "$@" "$(readlink -f "${BASH_SOURCE[0]}")"
fi

echo "Allocation ${SLURM_JOB_ID} is ready on $(hostname -s)."
echo "Attach from any login-node terminal with:"
echo "  srun --jobid=${SLURM_JOB_ID} --overlap --pty bash -l"
echo "Cancel it when finished with:"
echo "  scancel ${SLURM_JOB_ID}"

# Keep the allocation alive independently of the submitting terminal. Slurm
# terminates this process automatically at the requested time limit or scancel.
trap 'exit 0' TERM INT
while true; do
    sleep 3600 &
    wait $!
done
