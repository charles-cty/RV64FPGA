"""Verify a retained printk dump and CPU captures; never infer selftest from entry alone."""
import argparse
import bisect
import json
import re
from pathlib import Path
from analyze_ila_capture import read_capture

MARKER = 'RV64FPGA USERSPACE_CHECK_PASS proc sysfs tmpfs sleep fork exec wait'
ERRORS = ('Kernel panic - not syncing', 'RV64FPGA USERSPACE_CHECK_FAIL', 'Unable to handle kernel', 'Oops:')


def decode_printk(path):
    data = bytearray()
    expected = None
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if len(fields) < 2 or any(not re.fullmatch('[0-9a-fA-F]{8}', w) for w in fields):
            raise ValueError('Malformed AXI word dump')
        address = int(fields[0], 16)
        if expected is not None and address != expected:
            raise ValueError('Noncontiguous AXI word dump')
        data.extend(b''.join(int(w, 16).to_bytes(4, 'little') for w in fields[1:]))
        expected = address + 4 * (len(fields) - 1)
    return bytes(data), '\n'.join(s.decode('ascii') for s in re.findall(rb'[\x20-\x7e\t]{8,}', data))


def verify_printk(path):
    data, text = decode_printk(path)
    if MARKER not in text or any(s in text for s in ERRORS):
        raise ValueError('Missing userspace PASS or kernel/userspace failure in printk')
    return data, text


def verify_runtime(directory, symbols, entry):
    samples = read_capture(directory / 'user.csv')
    if not any(s.committed and not s.trapped and s.mode == 0 and s.pc == entry for s in samples):
        raise ValueError('No committed U-mode entry in capture')
    table = sorted((int(a, 16), n) for a, _, n in (l.split() for l in symbols.read_text().splitlines()))
    addresses = [a for a, _ in table]
    functions = set()
    for path in sorted((directory / 'progress').glob('current*.csv')):
        commits = [s for s in read_capture(path) if s.committed]
        if not commits:
            raise ValueError(f'No CPU commits: {path}')
        for s in commits:
            i = bisect.bisect_right(addresses, s.pc) - 1
            if i >= 0:
                name = table[i][1]
                if name in {'panic', 'panic_smp_self_stop'}:
                    raise ValueError(f'Panic path captured: {path}')
                functions.add(name)
    if len(list((directory / 'progress').glob('current*.csv'))) < 3:
        raise ValueError('Need three post-entry current captures')
    expected = {'hrtimer_interrupt', 'timekeeping_update', 'tick_nohz_next_event', 'arch_cpu_idle', 'clockevents_program_event'}
    if not functions & expected:
        raise ValueError('No recognized timer/idle progress; inspect captures manually')
    return sorted(functions & expected)


def verify(directory, symbols, entry):
    data, text = verify_printk(directory / 'state/printk-words.txt')
    runtime = verify_runtime(directory, symbols, entry)
    (directory / 'state/printk.bin').write_bytes(data)
    (directory / 'state/printk-strings.txt').write_text(text)
    return {'userspace_selftest': MARKER, 'runtime_functions': runtime}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory', type=Path)
    p.add_argument('--symbols', required=True, type=Path)
    p.add_argument('--entry', type=lambda s: int(s, 0), default=0x10144)
    a = p.parse_args()
    result = verify(a.directory, a.symbols, a.entry)
    (a.directory / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
    print('LINUX_ACCEPTANCE_PASS ' + json.dumps(result))
