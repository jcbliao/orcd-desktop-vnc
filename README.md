# ORCD desktop over SSH and VNC

Launch or reuse a KDE desktop in a Slurm allocation on MIT Engaging from your own computer. Slurm selects an eligible compute node; the helper discovers its hostname and VNC port automatically. VNC listens on loopback and is reached through an SSH tunnel.

You need your own Engaging access and permitted Slurm resources. This project does not provide an account or allocation. No personal usernames, account names, SSH keys, or session passwords are included.

## 1. Configure SSH on your computer

Use macOS, Linux, or a suitable Bash/OpenSSH environment such as WSL on Windows. Install a VNC viewer compatible with TurboVNC. On Windows with WSL, use the helper inside WSL; viewer access through localhost depends on your WSL networking setup.

Merge `ssh-config.example` into `~/.ssh/config`, replacing `YOUR_MIT_USERNAME` with your Engaging username. Keep your existing SSH entries and use your own authentication settings. If `Host orcd` already exists, update it instead of adding a duplicate. Protect the configuration with `chmod 600 ~/.ssh/config`.

Verify that this works first:

```bash
ssh orcd
```

Authentication, including any required interactive prompts, is handled by SSH. The login and compute-node connections can each require authentication. If you use a key outside the default paths, configure it for the login alias, `orcd-desktop`, and compute-node hosts as shown in the template. Do not disable host-key checking.

## 2. Install the remote scripts on Engaging

From the Engaging login shell:

```bash
git clone https://github.com/jcbliao/orcd-desktop-vnc.git
cp -R orcd-desktop-vnc/desktop-vnc ~/desktop-vnc
cd ~/desktop-vnc
cp config.example config.sh
```

Edit `config.sh` for your allocation. `DESKTOP_ACCOUNT` and `DESKTOP_QOS` are deliberately unset, so Slurm uses your defaults. If your allocation requires explicit values, uncomment those settings and supply your own. Adjust the partition, CPU count, memory, and wall time as needed. Default requests are 8 CPUs, 64 GB, and 6 hours in `mit_normal`.

The remote scripts require Python 3 (standard library only), Bash, Slurm tools, the modules initialization file `/etc/profile.d/modules.sh`, and Apptainer. They default to `apptainer/1.4.2` and the existing Engaging KDE image at `/home/systems/engaging-ood-ww/kde/mit/container.sif`. Configure a different module or compatible image in `config.sh` if necessary. The image must supply KDE Plasma, `vncserver`, `vncpasswd`, `kwriteconfig5`, and `dbus-run-session`. It is not included in this repository.

Eligible nodes need access to the image and the bind paths listed in `desktop.sbatch`: `/home`, `/orcd`, `/nfs`, `/net`, `/var/lib/sss`, `/var/run/munge`, and `/etc/slurm`. This is an Engaging-oriented setup, not a generic installer for every HPC cluster.

If `~/desktop-vnc` already exists, preserve it before installing; do not clone over your active session directory.

## 3. Install the helper on your computer

In a local terminal:

```bash
git clone https://github.com/jcbliao/orcd-desktop-vnc.git
cd orcd-desktop-vnc
cp desktop-vnc/connect.sh ~/connect-desktop.sh
chmod 700 ~/connect-desktop.sh
```

Keep any previous helper as a backup before replacing it. The helper gets your remote username from `ssh -G orcd`, so your local computer username need not match your Engaging username.

## 4. Launch and connect

```bash
bash ~/connect-desktop.sh
```

The helper starts a job if you have none, or reuses your existing desktop job. It waits for scheduling and VNC startup, prints the password, then opens the tunnel. Queue time depends on available resources. Open TurboVNC Viewer and connect to:

```text
127.0.0.1::15901
```

Enter the printed VNC password. Keep the terminal open while using the viewer. Closing the viewer or tunnel does not cancel the desktop; reconnect by running the helper again. The desktop ends when its job finishes, fails, or reaches its wall-time limit.

Other options:

```bash
# Open a shell on the desktop's assigned node.
bash ~/connect-desktop.sh --ssh

# Connect to a specific already-running job, without launching another.
bash ~/connect-desktop.sh 12345678

# Use a different local port if 15901 is occupied.
VNC_LOCAL_PORT=15902 bash ~/connect-desktop.sh
```

With the optional `Match` section from `ssh-config.example`, this shortcut starts/reuses the desktop and opens a shell plus VNC tunnel:

```bash
ssh orcd-desktop
```

The shortcut regenerates `~/.ssh/orcd-desktop-session.conf` with the current node and port. Do not hardcode a node or share that generated file. SSH configuration inspection such as `ssh -G orcd-desktop` also evaluates `Match exec` and can start a job; use `ssh -G orcd` to inspect only the login alias.

## Manage jobs and troubleshoot

On Engaging:

```bash
squeue --me
scancel JOB_ID
```

Cancel only the desktop job you intend to stop. Changing `config.sh` affects new jobs; an existing desktop is reused with its original resources. To submit manually with resource overrides:

```bash
cd ~/desktop-vnc
bash launch.sh --detach --time=02:00:00 --mem=16G
```

Running `launch.sh` directly always submits a new job. If multiple desktop jobs exist, the automatic launcher asks you to resolve the ambiguity; the local helper can connect to a specific running job ID.

Each launch creates `sessions/session-XXXXXXXX/` containing `job-id`, `job.log`, `desktop.log`, `vnc.log`, and connection details. Check those logs if startup fails. A pending job is usually waiting for scheduling or has an allocation/resource issue; inspect it with `scontrol show job JOB_ID`. A missing module, image, or bind directory requires adapting the configuration to available cluster resources.

The container's KDE automatic screen lock is disabled because it has no usable desktop-login password. Access relies on SSH and the VNC password. Treat session files and logs as private: they can contain that password. They are created under a restrictive umask and excluded by `.gitignore`. Never commit keys, passwords, or generated session directories.

## Files

| File | Runs on | Purpose |
| --- | --- | --- |
| `desktop-vnc/connect.sh` | Your computer | Starts/reuses a session and connects through SSH |
| `ssh-config.example` | Your computer | Login alias and optional desktop shortcut |
| `ensure-session.py` | Engaging | Serializes discovery/submission and waits for readiness |
| `launch.sh` | Engaging | Submits a new desktop allocation |
| `config.example` | Engaging | Copy to private `config.sh` for your Slurm settings |
| `desktop.sbatch` | Assigned node | Starts the container, VNC, and KDE |
| `find-session.py` | Engaging | Resolves and validates the current job's host and port |

The scripts use no third-party Python packages. Cluster execution must be validated with your own allocation and environment.

## Companion allocation helper

`scripts/interactive.sh` reserves a CPU or GPU allocation without starting a desktop. It uses your Slurm default account/QoS; pass your own overrides when required:

```bash
bash scripts/interactive.sh cpu --account=YOUR_ACCOUNT --qos=YOUR_QOS --time=02:00:00
bash scripts/interactive.sh gpu --gres=gpu:1 --account=YOUR_ACCOUNT --qos=YOUR_QOS --time=02:00:00
```

CPU mode selects `mit_normal`; GPU mode selects `mit_normal_gpu`. It requests 4 CPUs and 16 GB by default; specify a permitted time limit (the original default is 2 days). The job stays alive until its time limit or cancellation. Use `squeue --me` to find its job ID and `srun --jobid=JOB_ID --overlap --pty bash -l` to attach. This is a community utility, not an official ORCD project.

## Offline validation

Run `python3 -m unittest discover -s tests -v` (or `uv run --no-project python -m unittest discover -s tests -v`). Tests stub SSH and Slurm; they do not submit jobs. A live desktop still requires an Engaging allocation and the container environment.
