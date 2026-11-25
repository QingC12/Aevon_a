"""Require the exact pre-fix Host callbacks to hit the transaction guard."""
from pathlib import Path
import resource
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BASELINE = '93c9c8006980403d6015133a40cfd7bb490189ad'

def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    old = subprocess.check_output(
        ['git', 'show', BASELINE + ':ViewportHost.m'], cwd=ROOT, text=True)
    with tempfile.TemporaryDirectory(prefix='stheno-old-host-') as folder:
        temp = Path(folder)
        (temp / 'ViewportHost.m').write_text(old)
        (temp / 'test_viewport_host.m').write_text(
            (ROOT / 'test_viewport_host.m').read_text())
        binary = temp / 'old-host'
        subprocess.run([
            'xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-Wall',
            '-Wextra', '-Wno-unused-parameter', '-I', str(ROOT),
            str(temp / 'test_viewport_host.m'), '-framework', 'Foundation',
            '-framework', 'CoreGraphics', '-o', str(binary)], check=True)
        for case in ('opening', 'shorter'):
            run = subprocess.run([str(binary), '--delayed-' + case],
                                 capture_output=True, text=True)
            marker = ('STHV_HOST_TRANSACTION_VIOLATION:' + case +
                      ':STHNativeSetViewportGeometry:depth=0')
            assert run.returncode == -signal.SIGABRT and marker in run.stderr, (
                case, run.returncode, run.stdout, run.stderr)
            print('Exact original callback rejected:', case)

if __name__ == '__main__':
    main()
