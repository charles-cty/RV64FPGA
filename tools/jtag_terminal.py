"""Interactive WSL terminal over persistent Windows Vivado JTAG AXI. Ctrl-] exits.

Requires a new console-enabled bitstream and an already released CPU. Does not
program/reset the FPGA, access DDR, or alter the loader control register.
"""
import argparse
from contextlib import contextmanager, nullcontext
import os
from pathlib import Path
import select
import secrets
import subprocess
import sys
import termios
import time
import tty
import json

ROOT = Path(__file__).resolve().parents[1]


def windows(path):
    return subprocess.check_output(['wslpath', '-w', str(path)], text=True).strip()


@contextmanager
def raw_terminal(fd):
    saved = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        yield
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


def input_bytes(data):
    """Do not send local escape or bytes after it to the target."""
    head, separator, _ = data.partition(b'\x1d')
    return head, bool(separator)


def has_marker(data, marker):
    """Only complete output lines count; the echoed 'echo MARKER' is not proof."""
    return marker in data.replace(b'\r', b'').split(b'\n')[:-1]


def selftest_command(marker):
    # One canonical input line. Do not depend on optional BusyBox applets.
    command = (
        "jtag_check() { "
        "p=0; s=0; t=0; "
        "while read dev point type rest; do case \"$point:$type\" in "
        "/proc:proc) p=1;; /sys:sysfs) s=1;; /tmp:tmpfs) t=1;; esac; done < /proc/mounts; "
        "test \"$p$s$t\" = 111 || return 1; "
        "test -d /sys/kernel || return 1; "
        "read before rest < /proc/uptime || return 1; "
        "sleep 1 || return 1; read after rest < /proc/uptime || return 1; "
        "test \"$before\" != \"$after\" || return 1; "
        "for child in 1 2 3 4; do "
        "/bin/sh -c 'echo child-ok' > /tmp/jtag-child || return 1; "
        "read result < /tmp/jtag-child || return 1; "
        "test \"$result\" = child-ok || return 1; done; }; "
        "if jtag_check; then echo " + marker.decode('ascii') +
        "; else echo JTAG_CHECK_FAILED; fi\r"
    )
    return command.encode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probes', required=True, type=Path)
    parser.add_argument('--session', type=Path, required=True, help='new Windows-mounted directory for logs/spool')
    parser.add_argument('--vivado', default=r'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat')
    parser.add_argument('--selftest', action='store_true', help='exercise proc/sysfs/tmpfs, sleep and four child processes through the shell')
    parser.add_argument('--smoke', action='store_true', help='execute echo with a fresh nonce and require the exact returned line')
    parser.add_argument('--timeout', type=float, default=60, help='smoke response timeout in seconds')
    args = parser.parse_args()
    args.smoke = args.smoke or args.selftest
    if not args.smoke and (not sys.stdin.isatty() or not sys.stdout.isatty()):
        parser.error('run in an interactive WSL terminal')
    probes = args.probes.absolute()
    if not probes.is_file():
        parser.error('probes file does not exist')
    # Preserve the caller's /mnt path spelling (managed WSL mount permissions).
    session = args.session.absolute()
    if not windows(session).lower().startswith(tuple(f'{letter}:\\' for letter in 'cdefghijklmnopqrstuvwxyz')):
        parser.error('session must be on a Windows drive, not a WSL UNC path')
    session.mkdir(parents=True, exist_ok=False)
    (session / 'input.bin').touch()
    (session / 'output.bin').touch()
    (session / 'heartbeat').write_text(str(time.monotonic_ns()))
    request = {'WorkingDirectory': windows(session), 'Vivado': args.vivado,
               'Script': windows(ROOT / 'scripts/jtag-console.tcl'),
               'Log': windows(session / 'vivado.log'), 'Arguments': [windows(probes), windows(session)]}
    (session / 'request.json').write_text(json.dumps(request))
    last_dropped = 0
    print('Connecting to JTAG console. Ctrl-] exits; Ctrl-C is sent to Linux.', flush=True)
    with (session / 'console.log').open('w') as log, (session / 'input.bin').open('ab', buffering=0) as sink, (session / 'output.bin').open('rb', buffering=0) as source:
        process = subprocess.Popen(['pwsh.exe', '-WorkingDirectory', windows(session), '-File',
                                    windows(ROOT / 'scripts/invoke-vivado-job.ps1'), '-Request',
                                    windows(session / 'request.json')], stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 120
            while not (session / 'ready').exists():
                (session / 'heartbeat').write_text(str(time.monotonic_ns()))
                if process.poll() is not None:
                    raise RuntimeError(f'Vivado exited before attachment; see {session / "console.log"}')
                if time.monotonic() > deadline:
                    raise TimeoutError('JTAG attach timeout')
                time.sleep(.1)
            marker = ('JTAG_CONSOLE_' + secrets.token_hex(12)).encode() if args.smoke else None
            received = b''
            if marker:
                sink.write(selftest_command(marker) if args.selftest else b'echo ' + marker + b'\r')
            response_deadline = time.monotonic() + args.timeout
            with (nullcontext() if args.smoke else raw_terminal(sys.stdin.fileno())):
                while process.poll() is None:
                    (session / 'heartbeat').write_text(str(time.monotonic_ns()))
                    data = source.read(65536)
                    if data:
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
                    if marker:
                        received = (received + data)[-65536:]
                        if has_marker(received, marker):
                            break
                        if time.monotonic() > response_deadline:
                            raise TimeoutError('Linux did not return the exact nonce line')
                    try:
                        dropped = int((session / 'dropped.txt').read_text())
                    except (FileNotFoundError, ValueError):
                        dropped = last_dropped
                    if dropped != last_dropped:
                        sys.stderr.write(f'\r\n[JTAG: {dropped} output bytes dropped since CPU reset]\r\n')
                        last_dropped = dropped
                    if args.smoke:
                        time.sleep(.05)
                        continue
                    ready, _, _ = select.select([sys.stdin], [], [], .05)
                    if ready:
                        data = os.read(sys.stdin.fileno(), 4096)
                        send, quit_requested = input_bytes(data)
                        sink.write(send)
                        if quit_requested or not data:
                            break
                if process.poll() is not None:
                    raise RuntimeError(f'Console backend stopped; see {session / "console.log"}')
        finally:
            (session / 'stop').touch()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                # Do not indiscriminately kill Vivado/hw_server. The RTL lease
                # expires if access stops; the Tcl loop checks stop/heartbeat.
                print(f'Backend still exiting; check {session / "console.log"}', file=sys.stderr)
    print('\nJTAG_CONSOLE_SELFTEST_PASS' if args.selftest else ('\nJTAG_CONSOLE_SMOKE_PASS' if args.smoke else '\nDisconnected; Linux remains running.'))


if __name__ == '__main__':
    main()
