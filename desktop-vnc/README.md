# Engaging desktop with TurboVNC

From an Engaging terminal, submit a desktop:

```bash
~/desktop-vnc/launch.sh
```

The launcher submits with `sbatch`, prints the job ID and VNC password, then
streams `job.log` into your terminal. The log may be quiet while the job is
queued. Press Ctrl-C or close the terminal to stop following the log; the
desktop continues under Slurm until it exits, reaches its time limit, or you
cancel it. The log viewer itself continues until you close it, even if the
job has finished.

To submit and return immediately without following logs:

```bash
~/desktop-vnc/launch.sh --detach
```

Defaults: partition `mit_normal`, account and QoS `mit_amf_advanced_cpu`,
8 CPUs, 64 GB RAM, 6 hours, KDE at 1920×1080. Override Slurm options as needed:

```bash
~/desktop-vnc/launch.sh --cpus-per-task=4 --mem=16G --time=02:00:00
```

## Connect by job name from your own computer

The default job name is `engaging-desktop-vnc`. Copy the connection helper to
your local computer once (macOS, Linux, or a Bash environment on Windows):

```bash
scp YOUR_ORCD_USERNAME@orcd-login.mit.edu:~/desktop-vnc/connect.sh ~/connect-desktop.sh
```

If your local username differs from your ORCD username, set this in your
local shell (or shell startup file):

```bash
export ORCD_USER=YOUR_ORCD_USERNAME
```

Each time you want to connect, run locally:

```bash
bash ~/connect-desktop.sh
```

It looks up your currently running `engaging-desktop-vnc` job, reads its VNC
port, and opens the SSH tunnel. Use `127.0.0.1::15901` in TurboVNC Viewer.
Both the launcher and the local connection helper print the VNC password.
The launcher creates it at submission, and the desktop reuses that password
when it starts. The connection helper retrieves it over SSH.
Launch the desktop first; the helper does not submit jobs. Job names are not
unique: if multiple matching desktops are running, specify the job ID:

```bash
bash ~/connect-desktop.sh JOB_ID
```

You can also pass a custom job name. To use another local port:
`VNC_LOCAL_PORT=15902 bash ~/connect-desktop.sh`.

## Manual connection and session management

### Reusable SSH config and job shells

Run `bash ~/connect-desktop.sh --ssh-config` on your computer and paste its
output into your local `~/.ssh/config`, before any `Host *` defaults. Set `ORCD_USER` before generating the config;
the generated entries save that username. SSH uses your normal keys and agent;
add an `IdentityFile` entry yourself if needed. This
provides `ssh orcd` for the login host and `ssh node1615.inband` (replace
the node name with your allocation's node) for compute nodes via the login
host. The wildcard covers the `node*.inband` nodes used by these desktops,
so the config does not need changing for each job. Access requires a running
allocation on the target node.

To look up the current job's node automatically and open an SSH shell:

```bash
bash ~/connect-desktop.sh --ssh
bash ~/connect-desktop.sh --ssh JOB_ID
```

Custom job names also work; use a job ID when several running jobs share a
name. Shell lookup works as soon as the single-node job is running, even
before VNC is ready. The helper also works without installing the config.
Its original invocation still opens the VNC tunnel.

The generated config also includes `orcd-desktop`. Copy the updated helper to
`~/connect-desktop.sh` on your computer, then use the `Match originalhost`
block and `Host orcd-desktop` entry printed by `--ssh-config`, replacing any
older `orcd-desktop` entry. Keep your existing `orcd` login entry.

`ssh orcd-desktop` reuses an existing `engaging-desktop-vnc` job or submits
one with the launcher defaults if none exists. It prints the VNC password,
reports queue/startup progress, and waits until VNC is ready before opening
both a shell and a VNC tunnel. Simultaneous connections through this helper
serialize job submission to avoid creating duplicate desktops. Leave the SSH session open and
connect TurboVNC Viewer to `127.0.0.1::15901`, using the password printed by
`launch.sh`. Stop any previous tunnel on port 15901 first.

The Match command refreshes `~/.ssh/orcd-desktop-session.conf` locally with
the current node and VNC port. SSH uses the actual node hostname for host-key
checking. Ctrl-C while waiting leaves the submitted job running; a later
connection reuses it. To request different resources, run `launch.sh` with
your desired Slurm options first. Because lookup/submission runs in a Match
command, even `ssh -G orcd-desktop` can submit a job.
Running `bash ~/connect-desktop.sh` still opens just the VNC tunnel and prints
the password.

The launcher prints the job ID and a unique session directory. Wait for the
job to start (`squeue -j JOB_ID`), then read `connection.txt` in that directory.
Run its SSH command on your own computer and keep that terminal open. It uses
MIT's login host as a jump host to the allocated compute node; complete the
normal SSH authentication prompts. The VNC server listens only on localhost.

Open TurboVNC Viewer and connect to `127.0.0.1::15901` (two colons indicate an
explicit port). Use the password printed by the launcher or connection helper;
it is also saved in the session's `password` file on Engaging.
The directory and password are private to your Unix account.
If local port 15901 is occupied, choose another local port in both the SSH
command and viewer address.

Closing TurboVNC or the tunnel does not stop the desktop. Reconnect while the
job is running, or stop it with `scancel JOB_ID`. Slurm also ends the desktop
at its time limit. The connection instructions are renamed to
`connection-ended.txt` on normal cleanup.

The launcher disables KDE's automatic idle and resume screen locks in your
cluster KDE preferences. These locks use desktop-login authentication, not
the VNC password, and cannot authenticate normally in this container. SSH
and the VNC password still protect connections. Disabling automatic locking
does not dismiss a desktop that is already locked.

Logs are `job.log`, `vnc.log`, and `desktop.log` in the session directory.
These sessions do not appear as connectable desktops in OnDemand. Applications
launched inside KDE use the job's allocated CPU and memory; this is a CPU
desktop, with no GPU requested.

Uses the same system KDE container as Engaging OnDemand:
`/home/systems/engaging-ood-ww/kde/mit/container.sif`.
MIT SSH documentation: https://orcd-docs.mit.edu/accessing-orcd/ssh-login/
