"""Program a hash-checked candidate and verify Linux through the live console.

Default: preflight only. --run replaces FPGA SRAM and DDR contents, then leaves
Linux running. No flash programming or post-boot diagnostic reset is performed.
"""
import argparse
import json
import re
import struct
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from check_linux_baseline import ROOT, check, sha256
from run_linux_acceptance import windows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--vivado', default=r'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat')
    parser.add_argument('--run', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    check(manifest, artifacts=True)
    paths = {k: ROOT / v['path'] for k, v in manifest['artifacts'].items()}
    entry = struct.unpack_from('<Q', paths['busybox'].read_bytes(), 24)[0]
    print('JTAG_ACCEPTANCE_PREFLIGHT_PASS', flush=True)
    if not args.run:
        return
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    def job(name, script, arguments, sentinel):
        log = out / f'{name}.log'
        request = {'WorkingDirectory': windows(ROOT), 'Vivado': args.vivado,
                   'Script': windows(ROOT / 'scripts' / script), 'Log': windows(log),
                   'Arguments': [windows(x) if isinstance(x, Path) else str(x) for x in arguments]}
        request_path = out / f'{name}.request.json'
        request_path.write_text(json.dumps(request))
        print('JTAG_ACCEPTANCE_STAGE ' + name, flush=True)
        with (out / f'{name}.console.log').open('w') as stream:
            subprocess.run(['pwsh.exe', '-WorkingDirectory', windows(ROOT), '-File',
                            windows(ROOT / 'scripts/invoke-vivado-job.ps1'), '-Request', windows(request_path)],
                           stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=2400)
        if not re.search('^' + re.escape(sentinel), log.read_text(errors='replace'), re.M):
            raise ValueError('Missing stage success in ' + str(log))
    job('program', 'program-jtag-bitstream.tcl', [paths['bitstream'], paths['probes']], 'JTAG_PROGRAM_DONE')
    job('load', 'load-rv64-linux-jtag.tcl', [paths['payload'], paths['probes'], 32, 'hold', paths['ddr_scrub']], 'JTAG_LINUX_LOAD_HOLD_PASS')
    job('entry', 'capture-rv64-linux-entry.tcl', [paths['probes'], out / 'user.csv', hex(entry), 'release'], 'RV64_BUSYBOX_ENTRY_CAPTURE_PASS')
    for name, option in [('selftest', '--selftest'), ('reconnect', '--smoke')]:
        print('JTAG_ACCEPTANCE_STAGE ' + name, flush=True)
        with (out / f'{name}.log').open('w') as stream:
            subprocess.run([sys.executable, '-u', str(ROOT / 'tools/jtag_terminal.py'),
                            '--probes', str(paths['probes']), '--session', str(out / name),
                            '--vivado', args.vivado, option, '--timeout', '180'],
                           stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=360)
    result = {'status': 'JTAG_CONSOLE_ACCEPTANCE_PASS', 'cpu_state': 'running',
              'checks': ['U-mode entry', 'proc/sysfs/tmpfs/sleep/four child exec-waits', 'disconnect/reconnect echo nonce'],
              'manifest_sha256': sha256(args.manifest), 'completed_utc': datetime.now(timezone.utc).isoformat()}
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('JTAG_CONSOLE_ACCEPTANCE_PASS CPU_RUNNING', flush=True)


if __name__ == '__main__':
    main()
