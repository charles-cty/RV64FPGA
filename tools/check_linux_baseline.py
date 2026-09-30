"""Check archived successful FPGA inputs without rebuilding or accessing hardware."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / 'verification/linux-userspace-pass-20260930.json'


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(manifest, artifacts=False):
    for name, expected in manifest['source_sha256'].items():
        if sha256(ROOT / name) != expected:
            raise ValueError(f'Baseline source mismatch: {name}')
    if artifacts:
        for name, entry in manifest['artifacts'].items():
            if sha256(ROOT / entry['path']) != entry['sha256']:
                raise ValueError(f'Baseline artifact mismatch: {name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=DEFAULT)
    parser.add_argument('--artifacts', action='store_true', help='also require local archived binaries')
    args = parser.parse_args()
    check(json.loads(args.manifest.read_text()), args.artifacts)
    print('LINUX_BASELINE_PASS')
