from pathlib import Path
import subprocess, tempfile

R = Path(__file__).resolve().parent.parent
script = (R / "installer/postinst").read_text()
assert script.index('/var/mobile/Library/Preferences/com.nx.stheno.plist') < script.index('/var/jb/usr/local/share/stheno/com.nx.stheno.plist')
assert 'TMP="$T.tmp.$$"' in script and 'ln "$TMP" "$T"' in script
start = script.index('      if [ -e "$T" ] || [ -L "$T" ] ; then')
end = script.index('      N=$((N + 1))', script.index('      chmod 0600 "$T"', start)) + len('      N=$((N + 1))')
block = script[start:end]

def run_case(existing):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / "template"
        target = root / "preferences"
        source.write_bytes(b"default-template")
        if existing is not None:
            target.write_bytes(existing)
        command = f'SRC="{source}"; T="{target}"; N=0; for J in one; do\n{block}\ndone'
        subprocess.run(["/bin/sh", "-c", command], check=True)
        return target.read_bytes()

for previous in (b"short-without-key", b"valid-user-settings-with-different-key", b"nondefault-mask-and-apps"):
    assert run_case(previous) == previous
assert run_case(None) == b"default-template"
print("Installer preferences: existing files preserved; defaults seeded only when absent")
