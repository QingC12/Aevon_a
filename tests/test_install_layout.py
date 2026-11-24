"""Clean-install layout: no archive member may depend on a directory that the
package does not create itself.

dpkg opens every regular member with O_CREAT|O_EXCL directly inside the
destination directory and never creates a missing parent. An archive that ships
/usr/local/share/stheno/com.nx.stheno.plist without that chain therefore aborts
a first-time install with:

  unable to create '.../com.nx.stheno.plist.dpkg-new' (while processing
  './usr/local/share/stheno/com.nx.stheno.plist'): No such file or directory

while an overwrite install still succeeds because an earlier package left the
directory behind. This gate replays dpkg's unpack order and refuses any package
that would repeat the failure.
"""
from pathlib import Path
import io, json, tarfile

R = Path(__file__).resolve().parent.parent
manifest = json.loads((R / 'build' / 'build-manifest.json').read_text())
artifact = R / 'build' / manifest['artifact']
assert manifest['artifact'].startswith('stheno_') and manifest['artifact'].endswith('.deb')


def ar_members(pkg):
    raw = pkg.read_bytes(); assert raw[:8] == b'!<arch>\n'; out = {}; pos = 8
    while pos < len(raw):
        header = raw[pos:pos + 60]; assert header[58:60] == b'`\n'
        size = int(header[48:58]); name = header[:16].decode().strip().rstrip('/')
        payload = raw[pos + 60:pos + 60 + size]
        if name.startswith('#1/'):
            n = int(name[3:]); name = payload[:n].rstrip(b'\0').decode(); payload = payload[n:]
        out[name] = payload; pos += 60 + size + (size % 2)
    return out


def open_tar(name):
    return tarfile.open(fileobj=io.BytesIO(ar_members(artifact)[name]))


def normalize(blob):
    return blob.replace(b'\r\n', b'\n')


assert ar_members(artifact)['debian-binary'] == b'2.0\n'

# Replay dpkg's order: a directory member must be seen before any member below
# it, because dpkg creates directories eagerly and files only into an existing
# parent directory.
directories = set()
files = []
missing = []
with open_tar('data.tar.xz') as tar:
    for member in tar:
        name = member.name.rstrip('/')
        if member.isdir():
            directories.add(name)
            continue
        if not member.isfile():
            continue
        parent = name.rsplit('/', 1)[0] if '/' in name else '.'
        walk = parent
        while walk not in ('.', '/', ''):
            if walk not in directories:
                missing.append((name, walk))
            walk = walk.rsplit('/', 1)[0] if '/' in walk else '.'
        files.append(name)

assert not missing, ('dpkg would abort on a missing parent directory', missing[:8])
assert './usr/local/share/stheno' in directories
assert './usr/local/share/stheno/com.nx.stheno.plist' in files
assert manifest['install_layout']['synthesized_directories'], 'the fix must be recorded in the manifest'
for directory in manifest['install_layout']['synthesized_directories']:
    assert directory in directories, ('synthesized directory absent from the archive', directory)
    assert directory.startswith('./usr'), directory

# The preinst is what makes the first unpack succeed on any dpkg build, and it
# must stay a pure directory creator: the previous package dropped a preinst
# exactly because that one deleted SthenoFix and SthenoKb.
with open_tar('control.tar.xz') as tar:
    scripts = {Path(m.name).name: (m.mode, tar.extractfile(m).read()) for m in tar if m.isfile()}
assert 'preinst' in scripts and 'postinst' in scripts and 'postrm' in scripts
assert 'control' in scripts
mode, preinst = scripts['preinst']
assert mode == 0o755, oct(mode)
assert normalize(preinst) == normalize((R / 'installer/preinst').read_bytes())
assert b'mkdir -p' in preinst
assert b'/var/jb/usr/local/share/stheno' in preinst and b'/usr/local/share/stheno' in preinst
assert b'rm ' not in preinst and b'rmdir' not in preinst, 'the preinst must never delete anything'
assert normalize(scripts['postinst'][1]) == normalize((R / 'installer/postinst').read_bytes())
assert scripts['postinst'][0] == 0o755

print('Install layout gate passed:', len(files), 'files,', len(directories), 'directories,',
      len(manifest['install_layout']['synthesized_directories']), 'synthesized parents, preinst creates the chain')
