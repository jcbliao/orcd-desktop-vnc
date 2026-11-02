#!/usr/bin/env python3
"""Start or reuse a desktop, reporting progress on stderr and details on stdout."""
import fcntl
import getpass
from pathlib import Path
import re
import subprocess
import sys
import time

BASE = Path(__file__).resolve().parent
NAME = 'engaging-desktop-vnc'


def report(message):
    print(message, file=sys.stderr, flush=True)


def jobs():
    output = subprocess.check_output(
        ['squeue', '--noheader', '--user=' + getpass.getuser(),
         '--format=%i|%j|%T|%Z'], universal_newlines=True)
    return [line.strip().split('|', 3) for line in output.splitlines()
            if len(line.strip().split('|', 3)) == 4]


def ensure():
    # Serialize discovery/submission so simultaneous connections reuse one job.
    with (BASE / '.launch.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        matches = [j for j in jobs() if j[1] == NAME]
        if len(matches) > 1:
            raise ValueError('Multiple desktop jobs exist: ' +
                             ', '.join(j[0] for j in matches))
        if matches:
            job = matches[0][0]
            report('Reusing desktop job ' + job)
            password = Path(matches[0][3]) / 'password'
            if password.is_file():
                report('VNC password: ' + password.read_text().strip())
        else:
            report('Submitting desktop job...')
            output = subprocess.check_output(
                ['bash', str(BASE / 'launch.sh'), '--detach'],
                universal_newlines=True)
            match = re.search(r'^Submitted desktop job (\d+)$', output, re.M)
            if not match:
                raise ValueError('Could not read the submitted job ID: ' + output)
            job = match[1]
            for line in output.splitlines():
                if line.startswith(('Submitted desktop job ', 'VNC password:')):
                    report(line)

    report('Waiting for the desktop. Ctrl-C stops waiting; the job keeps running.')
    previous = None
    last_report = 0
    running_since = None
    while True:
        current = next((j for j in jobs() if j[0] == job), None)
        if current is None:
            raise ValueError('Desktop job ' + job + ' ended before VNC was ready. '
                             'Check its session job.log.')
        state = current[2]
        now = time.monotonic()
        if state != previous or now - last_report >= 30:
            report('Job {}: {}{}'.format(
                job, state, ' — waiting for VNC startup' if state == 'RUNNING' else ''))
            previous, last_report = state, now
        if state == 'RUNNING':
            if running_since is None:
                running_since = now
            result = subprocess.run(
                ['python3', str(BASE / 'find-session.py'), job, '--password'],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                universal_newlines=True)
            if result.returncode == 0:
                fields = result.stdout.strip().split('\t')
                if len(fields) != 5:
                    raise ValueError('Invalid desktop lookup response.')
                report('Desktop job {} is active on {}; VNC is ready.'.format(job, fields[1]))
                report('VNC password: ' + fields[4])
                print(result.stdout.strip(), flush=True)
                return
            if now - running_since > 600:
                raise ValueError('VNC startup timed out: ' + result.stderr.strip())
        elif state not in ('PENDING', 'CONFIGURING', 'SUSPENDED'):
            raise ValueError('Desktop job {} entered state {}.'.format(job, state))
        time.sleep(5)


if __name__ == '__main__':
    try:
        ensure()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
    except KeyboardInterrupt:
        sys.exit('Stopped waiting; the submitted desktop job is not cancelled.')
