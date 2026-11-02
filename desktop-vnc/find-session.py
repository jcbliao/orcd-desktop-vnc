#!/usr/bin/env python3
"""Resolve this user's desktop; optionally return its VNC password over SSH."""
import getpass
import os
from pathlib import Path
import re
import subprocess
import sys


def resolve(selector, host_only=False):
    result = subprocess.run(
        ['squeue', '--noheader', '--user=' + getpass.getuser(),
         '--format=%i|%j|%T|%N|%Z'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
    )
    jobs = [line.strip().split('|', 4) for line in result.stdout.splitlines()]
    matches = [j for j in jobs if len(j) == 5 and selector in (j[0], j[1])]
    running = [j for j in matches if j[2] == 'RUNNING']
    if not running:
        states = ', '.join(j[0] + ': ' + j[2] for j in matches)
        raise ValueError('No running desktop matches ' + repr(selector) +
                         ('. Matching jobs: ' + states if states else
                          '. Launch one with ~/desktop-vnc/launch.sh on Engaging.'))
    if len(running) != 1:
        raise ValueError('Multiple running jobs match this name: ' +
                         ', '.join(j[0] for j in running) +
                         '. Pass the desired job ID to connect.sh.')
    job, _, _, nodes, workdir = running[0]
    hosts = subprocess.check_output(['scontrol', 'show', 'hostnames', nodes], universal_newlines=True).split()
    if len(hosts) != 1:
        raise ValueError('Expected a desktop on one compute node.')
    if host_only:
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', hosts[0]):
            raise ValueError('Invalid allocation hostname.')
        return job, hosts[0]
    directory = Path(workdir)
    connection = directory / 'connection.txt'
    if connection.exists():
        content = connection.read_text()
        host = re.search(r'^Compute node: (\S+)$', content, re.M)
        port = re.search(r'TCP port (\d+)\)', content)
        recorded_job = re.search(r'^Desktop job: (\d+)$', content, re.M)
        if not (host and port and recorded_job and recorded_job[1] == job):
            raise ValueError('Desktop connection information is incomplete or stale.')
        host, port = host[1], port[1]
        password_file = directory / 'password'
    elif (directory / 'connection.yml').exists():
        # OnDemand's generated YAML uses simple scalar host and port fields.
        fields = {}
        for line in (directory / 'connection.yml').read_text().splitlines():
            key, sep, value = line.partition(':')
            if sep and key in ('host', 'port'):
                fields[key] = value.strip().strip('"\'')
        host, port = fields.get('host', ''), fields.get('port', '')
        password_file = directory / 'connection.yml'
    else:
        raise ValueError('Job ' + job + ' is running but VNC is not ready. Try again shortly.')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', host):
        raise ValueError('Invalid desktop hostname.')
    if host.split('.')[0] != hosts[0].split('.')[0]:
        raise ValueError('Desktop hostname does not match the current job allocation.')
    if not port.isdigit() or not 1 <= int(port) <= 65535:
        raise ValueError('Invalid VNC port.')
    if any(c in str(password_file) for c in '\t\r\n'):
        raise ValueError('Unsupported characters in the session path.')
    return job, host, port, str(password_file)


if __name__ == '__main__':
    try:
        if '--proxy' in sys.argv[1:]:
            # Resolve and connect on the login host without shell parsing.
            if len(sys.argv) != 4 or sys.argv[2] != '--proxy':
                raise ValueError('Usage: find-session.py SELECTOR --proxy PORT')
            port = sys.argv[3]
            if not port.isdigit() or not 1 <= int(port) <= 65535:
                raise ValueError('Invalid SSH port.')
            job, host = resolve(sys.argv[1], host_only=True)
            os.execvp('nc', ['nc', host, port])
        args = [a for a in sys.argv[1:] if a not in ('--password', '--host')]
        result = resolve(args[0] if args else 'engaging-desktop-vnc',
                         host_only='--host' in sys.argv[1:])
        if '--host' in sys.argv[1:] and '--password' in sys.argv[1:]:
            raise ValueError('Use either --host or --password, not both.')
        if '--password' in sys.argv[1:]:
            path = Path(result[3])
            if path.name == 'connection.yml':
                password = next((line.partition(':')[2].strip().strip('"\'')
                                 for line in path.read_text().splitlines()
                                 if line.startswith('password:')), '')
            else:
                password = path.read_text().strip()
            if not password or any(c in password for c in '\t\r\n'):
                raise ValueError('VNC password is missing or invalid.')
            result += (password,)
        print('\t'.join(result))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
