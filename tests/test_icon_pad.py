"""Icon plate contrast gate: the ring's light-mode plate must use a legible grey.

The ring draws a rounded plate behind every icon. Its colour is chosen by the
colour scheme: SwiftUI Color.black in dark mode, Color(uiColor: ...) in light mode.
The shipped colour was secondarySystemBackground (opaque 242,242,247 in light mode),
which lands within a few levels of a bright wallpaper and of the ring capsule, so the
plate that separates the icons from the backdrop disappeared. A first attempt used
secondarySystemFill (rgba 120,120,128,0.16), which still sat only about eighteen
levels below the capsule, and then systemGray4 (opaque D1D1D6), which measured no
better: on device screenshots the plate stayed six levels off the backdrop across
all three colours, so the plate is mixed at roughly a quarter strength and a base
colour near the backdrop can never separate. darkGray (85) then measured 197, still
faint, which matches the same formula. The plate can therefore never be darker than
0.75 * backdrop through a colour swap alone, so the frozen base now renames the one
selector that branch resolves to black (0), the darkest base UIColor offers, landing
the plate near B0 on a EB capsule and BF on white.

This gate pins the rename to the exact offsets and proves nothing else moved.
"""
from pathlib import Path
import hashlib, io, json, struct, tarfile

R = Path(__file__).resolve().parent.parent
frozen = json.loads((R / 'inputs/base-patched.json').read_text())
raw = (R / 'inputs/base-patched.deb').read_bytes()

assert hashlib.sha256(raw).hexdigest() == frozen['frozen_deb_sha256']
assert len(raw) == frozen['frozen_deb_bytes']

parts = {}
p = 8
assert raw[:8] == b'!<arch>\n'
while p < len(raw):
    h = raw[p:p + 60]
    assert h[58:60] == b'`\n'
    n = int(h[48:58])
    parts[h[:16].decode().strip().rstrip('/')] = raw[p + 60:p + 60 + n]
    p += 60 + n + n % 2
with tarfile.open(fileobj=io.BytesIO(parts['data.tar.xz'])) as t:
    rows = {x.name: (t.extractfile(x).read() if x.isfile() else b'') for x in t}

core = rows['./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib']
assert hashlib.sha256(core).hexdigest() == frozen['core_sha256']
assert len(core) == frozen['core_bytes']

record = frozen['icon_pad']
assert record['original'] == 'secondarySystemBackgroundColor'
assert record['previous'] == 'darkGrayColor'
assert record['composite_alpha'] == 0.25
assert record['replacement'] == 'blackColor'
assert record['selector_name_offset'] == '0xd3114'
assert record['selector_ref_offset'] == '0xe6798'

name_at = int(record['selector_name_offset'], 16)
ref_at = int(record['selector_ref_offset'], 16)
replacement = record['replacement'].encode()

# The renamed selector sits exactly where the record says, NUL terminated, padded so
# that the string that used to follow it keeps its offset.
assert core[name_at:name_at + len(replacement)] == replacement
assert core[name_at + len(replacement)] == 0
assert core[name_at + 31:name_at + 36] == b'self\0'
# blackColor already occurs once in the binary for an unrelated UIColor use, so the
# rename makes it appear twice: the original plus ours.
assert core.count(replacement) == 2
assert b'darkGrayColor' not in core
assert b'secondarySystemBackgroundColor' not in core
assert b'secondarySystemFillColor' not in core
assert b'systemGray4Color' not in core

# The single selector reference must still resolve to that string (the fixup keeps its
# chain bits; only the low 32 bits carry the rebase target), so dyld registers the
# renamed selector instead of the old one.
assert struct.unpack_from('<Q', core, ref_at)[0] & 0xffffffff == name_at

# The dark branch must stay untouched: it still imports SwiftUI Color.black.
assert b'_$s7SwiftUI5ColorV5blackACvgZ' in core
# The plate still goes through Color(uiColor:), so the branch structure is intact.
assert b'_$s7SwiftUI5ColorVyACSo7UIColorCcfC' in core

assert frozen['version'] == '2.0.59'
print('Icon plate: light branch uses black through one selref; dark branch keeps Color.black')
