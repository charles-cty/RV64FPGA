"""WSL board acceptance: preflight by default; --run programs SRAM and restarts Linux.

Requires the locally archived baseline artifacts. Does not program flash.
A failing selftest leaves the CPU held for diagnosis. All jobs are synchronous.
"""
import argparse
import json
import re
import struct
import time
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from check_linux_baseline import ROOT, DEFAULT, check, sha256
from verify_linux_acceptance import verify, verify_runtime


def windows(path):
    return subprocess.check_output(['wslpath', '-w', str(Path(path).resolve())], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest', type=Path, default=DEFAULT)
    p.add_argument('--output', type=Path, default=ROOT / 'build/linux-acceptance')
    p.add_argument('--vivado', default=r'C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat')
    p.add_argument('--run', action='store_true', help='program SRAM, load, verify, reload, leave CPU running')
    args = p.parse_args()
    manifest = json.loads(args.manifest.read_text())
    check(manifest, artifacts=True)
    artifacts = {name: ROOT / v['path'] for name, v in manifest['artifacts'].items()}
    busybox = artifacts['busybox'].read_bytes()
    if busybox[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', busybox, 18)[0] != 243:
        raise ValueError('Expected little-endian ELF64 RISC-V BusyBox')
    entry = struct.unpack_from('<Q', busybox, 24)[0]
    config = artifacts['linux_config'].read_text()
    match = re.search(r'^CONFIG_LOG_BUF_SHIFT=(\d+)$', config, re.M)
    if not match:
        raise ValueError('Missing CONFIG_LOG_BUF_SHIFT')
    size = 1 << int(match[1])
    # Validate symbols before any hardware mutation.
    names = {line.split()[-1] for line in artifacts['symbols'].read_text().splitlines()}
    if not {'jiffies', 'prb', 'log_buf', '__log_buf'} <= names:
        raise ValueError('Missing required kernel symbols')
    print(f'ACCEPTANCE_PREFLIGHT_PASS entry=0x{entry:x} printk_bytes={size}', flush=True)
    if not args.run:
        return
    out = args.output.resolve()
    if out.exists():
        raise ValueError(f'Use a new output directory, preserving previous evidence: {out}')
    out.mkdir(parents=True)
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    def job(name, script, arguments, sentinel):
        log = out / f'{name}.log'
        request = {'WorkingDirectory': windows(ROOT), 'Vivado': args.vivado,
                   'Script': windows(ROOT / 'scripts' / script), 'Log': windows(log),
                   'Arguments': [windows(a) if isinstance(a, Path) else str(a) for a in arguments]}
        request_path = out / f'{name}.request.json'
        request_path.write_text(json.dumps(request))
        print(f'ACCEPTANCE_STAGE {name}', flush=True)
        with (out / f'{name}.console.log').open('w') as stream:
            subprocess.run(['pwsh.exe', '-WorkingDirectory', windows(ROOT), '-File',
                            windows(ROOT / 'scripts/invoke-vivado-job.ps1'),
                            '-Request', windows(request_path)], stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=2400)
        if not re.search(r'^' + re.escape(sentinel), log.read_text(errors='replace'), re.M):
            raise ValueError(f'Missing success sentinel in {log}')
    def boot(prefix, folder):
        folder.mkdir(parents=True, exist_ok=True)
        job(prefix + '-load', 'load-rv64-linux-jtag.tcl',
            [artifacts['payload'], artifacts['probes'], 32, 'hold', artifacts['ddr_scrub']], 'JTAG_LINUX_LOAD_HOLD_PASS')
        job(prefix + '-entry', 'capture-rv64-linux-entry.tcl',
            [artifacts['probes'], folder / 'user.csv', hex(entry), 'release'], 'RV64_BUSYBOX_ENTRY_CAPTURE_PASS')
        print('Waiting 180 seconds for userspace selftest and continued execution', flush=True)
        time.sleep(180)
        job(prefix + '-progress', 'capture-rv64-linux-progress.tcl',
            [artifacts['probes'], folder / 'progress'], 'LIVE_CAPTURE_PASS kind=current3')
    job('program', 'program-jtag-bitstream.tcl', [artifacts['bitstream'], artifacts['probes']], 'JTAG_PROGRAM_DONE')
    boot('first', out / 'first')
    job('state', 'diagnose-rv64-linux-state-jtag.tcl',
        [artifacts['probes'], out / 'first/state', artifacts['symbols'], size], 'RV64_LINUX_STATE_READ_PASS')
    report = verify(out / 'first', artifacts['symbols'], entry)
    report['cpu_state'] = 'held_after_log_read'
    (out / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print('USERSPACE_SELFTEST_PASS; reloading clean payload', flush=True)
    report['cpu_state'] = 'final_restart_in_progress_state_unknown'
    (out / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    boot('final', out / 'final')
    report['final_runtime_functions'] = verify_runtime(out / 'final', artifacts['symbols'], entry)
    report['cpu_state'] = 'running_after_clean_reload'
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    report['manifest_sha256'] = sha256(args.manifest)
    (out / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    print('LINUX_ACCEPTANCE_PASS CPU_RUNNING', flush=True)


if __name__ == '__main__':
    main()
