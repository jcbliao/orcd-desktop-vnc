# ORCD desktop VNC

Personal utilities for running a KDE desktop on MIT ORCD's Engaging cluster
through Slurm, Apptainer, TurboVNC, and an SSH tunnel. This is an
ORCD-specific setup, not an official ORCD project.

## Contents

- `desktop-vnc/launch.sh`: submit a desktop with a private session directory.
- `desktop-vnc/desktop.sbatch`: run the system KDE container and localhost-only VNC server.
- `desktop-vnc/connect.sh`: connect from your computer, open a job shell, or generate SSH configuration.
- `desktop-vnc/find-session.py`: resolve a running job's node and VNC connection details.
- `desktop-vnc/ensure-session.py`: reuse or submit a desktop for `ssh orcd-desktop`.
- `scripts/interactive.sh`: companion CPU/GPU allocation helper, independent of VNC.

## Install on Engaging

Requires an ORCD account with SSH and Slurm access. The desktop uses the
cluster's `apptainer/1.4.2` module and existing KDE image at
`/home/systems/engaging-ood-ww/kde/mit/container.sif`; neither is bundled here.
The scripts also require Bash and Python 3 (standard library only).

```bash
git clone https://github.com/jcbliao/orcd-desktop-vnc.git
cp -R orcd-desktop-vnc/desktop-vnc ~/desktop-vnc
```

The copy command assumes `~/desktop-vnc` does not exist. If you already have
an installation, compare and update its source files individually, preserving
your existing `sessions/` directory. The local connection helper expects the
cluster scripts at `~/desktop-vnc`.

Launch a desktop on the login node:

```bash
~/desktop-vnc/launch.sh --detach
```

Defaults are `mit_normal`, account/QoS `mit_amf_advanced_cpu`, 8 CPUs,
64 GB RAM, and 6 hours. These are the original setup's defaults; if your
allocation differs, supply your permitted account, QoS, and partition:

```bash
~/desktop-vnc/launch.sh --detach \
  --account=YOUR_ACCOUNT --qos=YOUR_QOS --partition=YOUR_PARTITION \
  --cpus-per-task=4 --mem=16G --time=02:00:00
```

## Connect from your computer

Install TurboVNC Viewer and use a shell with Bash and OpenSSH. Copy the helper:

```bash
scp YOUR_ORCD_USERNAME@orcd-login.mit.edu:~/desktop-vnc/connect.sh ~/connect-desktop.sh
export ORCD_USER=YOUR_ORCD_USERNAME
bash ~/connect-desktop.sh
```

Open TurboVNC Viewer at `127.0.0.1::15901` with the password printed by the
helper. Keep the SSH tunnel open. `ORCD_USER` defaults to your local `$USER`;
set it in your local shell startup file if the usernames differ.

For automatic desktop submission and an SSH shell with VNC forwarding:

```bash
bash ~/connect-desktop.sh --ssh-config
```

Review and place that output in your local `~/.ssh/config` before `Host *`
defaults, then run `ssh orcd-desktop`. This mode submits a desktop with the
launcher defaults if none exists. If you need different resources, launch
the desktop explicitly first. Even `ssh -G orcd-desktop` triggers the lookup
and may submit a job because it evaluates the generated `Match exec` rule.

See [desktop usage and troubleshooting](desktop-vnc/README.md) for job-ID
selection, alternate local ports, manual tunnels, and session management.

## Companion allocation helper

Run on Engaging to reserve resources without starting a desktop:

```bash
bash scripts/interactive.sh cpu --time=02:00:00
bash scripts/interactive.sh gpu --gres=gpu:1 --time=02:00:00
squeue -u "$USER"
srun --jobid=JOB_ID --overlap --pty bash -l
scancel JOB_ID
```

The GPU mode selects `mit_normal_gpu` and account/QoS `mit_amf_advanced_gpu`;
request GPU resources explicitly with the appropriate Slurm flags. CPU mode
uses `mit_normal` and `mit_amf_advanced_cpu`. Extra `sbatch` arguments override
these defaults. The helper defaults to 4 CPUs, 16 GB, and 2 days; adjust the
time limit for your partition. Job output is discarded by default, so use
`squeue` to obtain the assigned node or override `--output`/`--error`.

## Runtime files and behavior

Session passwords, connection details, logs, and lock files are generated
locally and excluded from Git. Do not upload session directories, SSH keys,
shell configuration, or OnDemand output. VNC listens only on localhost and
is reached through SSH. Closing a viewer or tunnel leaves the Slurm job
running; stop it with `scancel JOB_ID`.

Starting a desktop disables KDE automatic idle/resume locking in your cluster
KDE preferences because the container cannot authenticate that lock screen.
SSH and VNC authentication still apply. The desktop requests no GPU.

Fiji and other desktop applications are optional user installations, not
dependencies of these access scripts. Application binaries, personal desktop
preferences, and local application launchers are not bundled.
