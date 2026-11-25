"""Read-only gate for the *linked/exported* arm64e native tail stubs.

Run after build.py: python3 tests/test_native_stub_abi.py [build-dir|deb|dylib]
A build directory checks the linked action/core images and every packaged deb,
including byte equality. A direct action dylib needs its sibling Stheno.dylib.
The actual exports, pointer loads, opcodes and original core entry RVAs are read;
no source assembly, manifest or symbol table substitutes for binary evidence.
--self-test uses an in-memory Mach-O only; it is NOT final-artifact evidence.
"""
from pathlib import Path
import argparse
import hashlib
import io
import struct
import tarfile

from macho import commands

ROOT = Path(__file__).resolve().parent.parent
ACTION = 'SthenoSystemActions.dylib'
CORE = 'Stheno.dylib'
PACKAGE_ACTION = 'Library/MobileSubstrate/DynamicLibraries/' + ACTION
PACKAGE_CORE = 'Library/MobileSubstrate/DynamicLibraries/' + CORE
# Reviewed core entry RVAs; do not derive the oracle from the assembly under test.
TARGETS = {
    '_STHNativeMinimized': 0xda600,
    '_STHNativeSetMinimized': 0xda690,
    '_STHNativeClassify': 0xda710,
    '_STHNativeTranslation': 0xda734,
    '_STHNativeMove': 0xda758,
    '_STHNativeRect': 0xda77c,
    '_STHNativeReset': 0xda7a0,
    '_STHNativeDock': 0xda89c,
    '_STHNativeOrientation': 0xda93c,
    '_STHNativeSetup': 0xda9c0,
    '_STHNativeUpdate': 0xda9e0,
    '_STHNativeEnd': 0xdaa00,
    '_STHNativeLong': 0xdaa20,
    '_STHNativeTap': 0xdaa44,
    '_STHNativeGetScale': 0xdaa6c,
    '_STHNativeGetOffset': 0xdaa90,
    '_STHNativeSetViewportGeometry': 0xdaab4,
    '_STHNativeCopyBundleID': 0xdaaf8,
    '_STHNativeRefreshGeometry': 0xdab1c,
    '_STHNativePresent': 0xdab40,
    '_STHNativeInitialSize': 0xdab64,
}


def uleb(data, at, end):
    assert 0 <= at <= end <= len(data), 'Out-of-range export ULEB'
    value = shift = 0
    while at < end and shift < 70:
        byte = data[at]
        at += 1
        value |= (byte & 127) << shift
        if byte < 128:
            assert value < 1 << 64, 'Overflowing export ULEB'
            return value, at
        shift += 7
    raise AssertionError('Unterminated/oversized export ULEB')


class NativeImage:
    def __init__(self, data):
        assert len(data) >= 32, 'Truncated Mach-O header'
        count, total = struct.unpack_from('<II', data, 16)
        assert total <= len(data) - 32 and count <= total // 8, 'Truncated/invalid load commands'
        at, end = 32, 32 + total
        for _ in range(count):
            assert at + 8 <= end, 'Truncated load-command header'
            _, size = struct.unpack_from('<II', data, at)
            assert size >= 8 and size % 8 == 0 and at + size <= end, 'Invalid load-command size'
            at += size
        assert at == end, 'Load-command size mismatch'
        self.data = data
        self.segments = []
        modern = legacy = None
        for cmd, pos, size in commands(data):
            if cmd == 0x19:  # LC_SEGMENT_64
                assert size >= 72
                name = data[pos + 8:pos + 24].split(b'\0')[0]
                va, vs, off, fs = struct.unpack_from('<4Q', data, pos + 24)
                prot = struct.unpack_from('<I', data, pos + 60)[0]
                assert fs <= vs and off + fs <= len(data) and va + vs < 1 << 64, 'Invalid segment range'
                sections = struct.unpack_from('<I', data, pos + 64)[0]
                assert 72 + sections * 80 <= size, 'Truncated segment sections'
                self.segments.append((name, va, vs, off, fs, prot))
            elif cmd == 0x80000033:  # LC_DYLD_EXPORTS_TRIE
                assert size >= 16 and modern is None
                modern = struct.unpack_from('<II', data, pos + 8)
            elif cmd in (0x22, 0x80000022):  # LC_DYLD_INFO[_ONLY]
                assert size >= 48 and legacy is None
                legacy = struct.unpack_from('<II', data, pos + 40)
        text = [s for s in self.segments if s[0] == b'__TEXT']
        assert len(text) == 1 and text[0][3] == 0 and text[0][4] > 0
        self.base = text[0][1]  # Trie regular addresses are relative to this.
        off, size = modern if modern and modern[1] else legacy or (0, 0)
        assert size > 0 and off + size <= len(data), 'Missing/bad export trie'
        trie = data[off:off + size]
        self.exports = {}

        visited = 0

        def walk(at, prefix, ancestors):
            nonlocal visited
            visited += 1
            assert visited <= len(trie) and len(ancestors) < 128, 'Excessive export-trie traversal'
            assert 0 <= at < len(trie) and at not in ancestors, 'Invalid/cyclic export trie'
            terminal, p = uleb(trie, at, len(trie))
            end = p + terminal
            assert end < len(trie)
            if terminal:
                flags, q = uleb(trie, p, end)
                # Only regular (optionally weak) *definitions* have this ABI.
                # A re-export or stub/resolver is not an actual local entry.
                if flags & ~4 == 0:
                    address, q = uleb(trie, q, end)
                    assert q == end and prefix not in self.exports
                    assert self.base + address < 1 << 64, 'Overflowing exported RVA'
                    self.exports[prefix] = self.base + address
            p = end
            count = trie[p]
            p += 1
            for _ in range(count):
                end = trie.find(0, p)
                assert end > p, 'Missing/empty export edge'
                try:
                    edge = trie[p:end].decode('utf-8')
                except UnicodeDecodeError as error:
                    raise AssertionError('Invalid UTF-8 export edge') from error
                target, p = uleb(trie, end + 1, len(trie))
                walk(target, prefix + edge, ancestors | {at})
        walk(0, '', set())

    def offset(self, va, size=20):
        assert 0 <= va < 1 << 64 and size > 0 and va + size < 1 << 64, 'Invalid code VA/size'
        matches = [s for s in self.segments if s[1] <= va and va + size <= s[1] + s[4]]
        assert len(matches) == 1 and matches[0][5] & 4, 'Entry is not file-backed executable code'
        s = matches[0]
        return s[3] + va - s[1]


def verify_image(data):
    image = NativeImage(data)
    assert len(TARGETS) == 21 and TARGETS.keys() <= image.exports.keys(), 'Missing real stub exports'
    core = image.exports.get('_sth_core_base')
    assert core is not None and core % 8 == 0, 'Missing/alignment of exported core-base storage'
    assert any(s[1] <= core and core + 8 <= s[1] + s[2] and s[5] & 2 and not s[5] & 4
               for s in image.segments), 'Core-base export is not writable non-code storage'
    spans = []
    for name, rva in TARGETS.items():
        entry = image.exports[name]
        assert entry % 4 == 0, (name, 'unaligned entry')
        off = image.offset(entry)
        a, load, high, low, tail = struct.unpack_from('<5I', data, off)
        assert a & 0x9f00001f == 0x90000010, (name, 'expected ADRP x16')
        pages = ((a >> 29) & 3) | (((a >> 5) & 0x7ffff) << 2)
        if pages & (1 << 20):
            pages -= 1 << 21
        page = (entry & ~0xfff) + (pages << 12)
        assert load & 0xffc003ff == 0xf9400210, (name, 'expected LDR x16,[x16,#imm]')
        assert page + ((load >> 10) & 0xfff) * 8 == core, (name, 'load does not read _sth_core_base')
        assert high & 0xffc003ff == 0x91400210, (name, 'expected ADD x16,x16,#hi,LSL #12')
        assert low & 0xffc003ff == 0x91000210, (name, 'expected ADD x16,x16,#lo')
        target = (((high >> 10) & 0xfff) << 12) + ((low >> 10) & 0xfff)
        assert target == rva, (name, 'wrong core RVA', hex(target), hex(rva))
        assert tail == 0xd61f0200, (name, 'must tail-BR x16; no BLR/RET/PAC/SP/context change')
        assert all(entry + 20 <= first or last <= entry for first, last in spans), (name, 'overlapping stubs')
        spans.append((entry, entry + 20))
    return image


def verify_core_targets(data):
    """A raw header+RVA pointer lands at the reviewed core PACIBSP entry.

    Tail BRAA/BRAAZ would be wrong: these pointers are not PAC-signed. The
    original bridge signs its return address itself, without a wrapper frame.
    Whole core-body identity is independently covered by the frozen-core gate.
    """
    image = NativeImage(data)
    for name, rva in TARGETS.items():
        at = image.offset(image.base + rva, 4)
        assert struct.unpack_from('<I', data, at)[0] == 0xd503237f, (name, 'core RVA is not original PACIBSP entry')
    return image


def negative_controls(data):
    image = verify_image(data)
    original = hashlib.sha256(data).digest()
    count = 0
    for name in TARGETS:
        off = image.offset(image.exports[name])
        # All mutations are memory-only. A correct opcode with a wrong address
        # also has to fail, not only an obviously invalid instruction.
        words = struct.unpack_from('<5I', data, off)
        mutations = [
            (3, words[3] ^ (1 << 10), 'wrong core RVA'),
            (2, words[2] ^ (1 << 10), 'wrong core RVA'),
            (1, words[1] ^ (1 << 30), 'expected LDR x16,[x16,#imm]'),
            (0, words[0] ^ (1 << 29), 'load does not read _sth_core_base'),
            (0, words[0] ^ (1 << 23), 'load does not read _sth_core_base'),
            (4, 0xd63f0200, 'must tail-BR x16; no BLR/RET/PAC/SP/context change'),  # BLR x16
            (4, 0xd61f0a1f, 'must tail-BR x16; no BLR/RET/PAC/SP/context change'),  # BRAAZ x16
            (4, 0xd71f0a11, 'must tail-BR x16; no BLR/RET/PAC/SP/context change'),  # BRAA x16,x17
            (4, 0xd61f0220, 'must tail-BR x16; no BLR/RET/PAC/SP/context change'),  # BR x17
            (4, 0xd65f03c0, 'must tail-BR x16; no BLR/RET/PAC/SP/context change'),  # RET
            (3, 0x910003ff, 'expected ADD x16,x16,#lo'),  # ADD SP,SP,#0
        ]
        for index, word, reason in mutations:
            changed = bytearray(data)
            struct.pack_into('<I', changed, off + 4 * index, word)
            try:
                verify_image(bytes(changed))
            except AssertionError as failure:
                # An unrelated parser failure is NOT evidence of the ABI check.
                detail = failure.args[0] if failure.args else None
                assert isinstance(detail, tuple) and detail[:2] == (name, reason), (name, 'wrong negative failure', detail)
                count += 1
            else:
                raise AssertionError((name, 'negative control accepted', reason))
    assert count == 21 * 11 and hashlib.sha256(data).digest() == original
    return count


def packaged_image(path, member=PACKAGE_ACTION):
    raw = path.read_bytes()
    assert raw[:8] == b'!<arch>\n', 'Expected Debian ar archive'
    parts, p = {}, 8
    while p < len(raw):
        header = raw[p:p + 60]
        assert len(header) == 60 and header[58:60] == b'`\n'
        size = int(header[48:58])
        assert size >= 0 and p + 60 + size <= len(raw)
        name = header[:16].decode().strip().rstrip('/')
        assert name not in parts
        parts[name] = raw[p + 60:p + 60 + size]
        p += 60 + size + size % 2
    assert p == len(raw)
    archives = [v for n, v in parts.items() if n == 'data.tar' or n.startswith('data.tar.')]
    assert len(archives) == 1
    with tarfile.open(fileobj=io.BytesIO(archives[0]), mode='r:*') as archive:
        entries = [e for e in archive if e.name.removeprefix('./') == member]
        assert len(entries) == 1 and entries[0].isfile(), ('Deb must contain one final dylib', member)
        return archive.extractfile(entries[0]).read()


def inspect_target(path):
    if path.is_dir():
        binary, core_path, packages = path / ACTION, path / CORE, sorted(path.glob('*.deb'))
        assert binary.is_file() and core_path.is_file() and packages, 'Build directory needs linked action/core dylibs AND final deb'
        linked, core = binary.read_bytes(), core_path.read_bytes()
        yield str(binary), linked, core
        for package in packages:
            shipped, shipped_core = packaged_image(package), packaged_image(package, PACKAGE_CORE)
            assert shipped == linked, ('Deb action differs from final linked action', str(package))
            assert shipped_core == core, ('Deb core differs from final linked core', str(package))
            yield str(package) + ':' + ACTION, shipped, shipped_core
    elif path.suffix == '.deb':
        yield str(path) + ':' + ACTION, packaged_image(path), packaged_image(path, PACKAGE_CORE)
    else:
        core_path = path.with_name(CORE)
        assert path.is_file() and path.name == ACTION and core_path.is_file(), 'Expected final action dylib plus sibling Stheno.dylib, deb, or build directory'
        yield str(path), path.read_bytes(), core_path.read_bytes()


def encode_uleb(value):
    assert isinstance(value, int) and 0 <= value < 1 << 64, 'Invalid unsigned export RVA'
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def fixture(negative_adrp=False, overrides=None):
    """In-memory linked layout; NEVER final-artifact evidence or a normal input.

    A separate late executable segment exercises a real negative ADRP distance
    without inventing negative ULEB RVAs or overlapping virtual segments.
    """
    base, code, data_va, trie_at = 0x100000000, 0x400, 0x100008000, 0x1000
    code_rva = 0xc400 if negative_adrp else code
    code_file = 0x2400 if negative_adrp else code
    symbols = {name: (0, code_rva + 20 * i) for i, name in enumerate(TARGETS)}
    symbols['_sth_core_base'] = (0, data_va + 0x28 - base)
    symbols.update(overrides or {})
    nodes = []
    for flags, address in symbols.values():
        payload = encode_uleb(flags) + encode_uleb(address)
        nodes.append(encode_uleb(len(payload)) + payload + b'\0')
    root_size = 2
    for _ in range(10):
        root, at = bytearray([0, len(symbols)]), root_size
        for name, node in zip(symbols, nodes):
            root += name.encode() + b'\0' + encode_uleb(at)
            at += len(node)
        if len(root) == root_size:
            break
        root_size = len(root)
    else:
        raise AssertionError('Export fixture did not converge')
    trie = bytes(root) + b''.join(nodes)
    image = bytearray(0x4000 if negative_adrp else 0x2000)
    count, total = (4, 232) if negative_adrp else (3, 160)
    struct.pack_into('<8I', image, 0, 0xfeedfacf, 0x100000c, 2, 6, count, total, 0, 0)

    def segment(at, name, va, vs, off, fs, prot):
        struct.pack_into('<II16s4Q4I', image, at, 0x19, 72, name, va, vs, off, fs, prot, prot, 0, 0)
    segment(32, b'__TEXT', base, 0x2000, 0, 0x2000, 5)
    segment(104, b'__DATA', data_va, 0x1000, 0x2000, 0, 3)
    export_at = 176
    if negative_adrp:
        segment(176, b'__TEXT_EXEC', base + 0xc000, 0x2000, 0x2000, 0x2000, 5)
        export_at += 72
    struct.pack_into('<4I', image, export_at, 0x80000033, 16, trie_at, len(trie))
    image[trie_at:trie_at + len(trie)] = trie
    for i, (name, rva) in enumerate(TARGETS.items()):
        off, entry = code_file + 20 * i, base + code_rva + 20 * i
        pages = ((data_va & ~0xfff) - (entry & ~0xfff)) >> 12
        pages &= 0x1fffff
        words = [0x90000010 | ((pages & 3) << 29) | ((pages >> 2) << 5),
                 0xf9400210 | (5 << 10),
                 0x91400210 | ((rva >> 12) << 10),
                 0x91000210 | ((rva & 0xfff) << 10), 0xd61f0200]
        struct.pack_into('<5I', image, off, *words)
    return bytes(image)


def malformed_controls(data):
    """Reject bad inputs deliberately, not via IndexError/struct.error/recursion."""
    image = verify_image(data)
    count = 0

    def reject(call, expected):
        nonlocal count
        try:
            call()
        except AssertionError as error:
            assert expected in str(error), ('Wrong malformed-input failure', expected, str(error))
            count += 1
        else:
            raise AssertionError(('Malformed input accepted', expected))

    def changed(at, fmt, *values):
        raw = bytearray(data)
        struct.pack_into(fmt, raw, at, *values)
        return bytes(raw)

    for raw in (b'', data[:31]):
        reject(lambda raw=raw: verify_image(raw), 'Truncated Mach-O header')
    reject(lambda: verify_image(data[:180]), 'Truncated/invalid load commands')
    reject(lambda: verify_image(changed(16, '<I', 4)), 'Truncated load-command header')
    reject(lambda: verify_image(changed(36, '<I', 0)), 'Invalid load-command size')
    reject(lambda: verify_image(changed(32 + 48, '<Q', len(data) + 1)), 'Invalid segment range')
    reject(lambda: verify_image(changed(32 + 64, '<I', 1)), 'Truncated segment sections')
    reject(lambda: verify_image(changed(184, '<I', len(data))), 'Missing/bad export trie')
    reject(lambda: verify_image(changed(32 + 60, '<I', 1)), 'Entry is not file-backed executable code')
    name = next(iter(TARGETS))
    for flags in (1, 2, 8, 16):  # thread-local, absolute, re-export, stub+resolver
        reject(lambda flags=flags: verify_image(fixture(overrides={name: (flags, 0x400)})), 'Missing real stub exports')
    verify_image(fixture(overrides={name: (4, 0x400)}))  # Weak regular definition is still real code.
    reject(lambda: verify_image(fixture(overrides={name: (0, (1 << 64) - 1)})), 'Overflowing exported RVA')
    reject(lambda: verify_image(fixture(overrides={name: (0, 0x100000)})), 'Entry is not file-backed executable code')
    reject(lambda: verify_image(fixture(overrides={name: (0, 0x401)})), 'unaligned entry')
    reject(lambda: verify_image(fixture(overrides={'_sth_core_base': (0, 0x4028)})), 'Core-base export is not writable non-code storage')
    for trie, reason in [(b'\x80' * 10, 'Unterminated/oversized export ULEB'),
                         (b'\0\1x\0\0', 'Invalid/cyclic export trie'),
                         (b'\0\1\xff\0\0', 'Invalid UTF-8 export edge'),
                         (b'\0\1xx', 'Missing/empty export edge')]:
        raw = bytearray(data)
        raw[0x1000:0x1000 + len(trie)] = trie
        struct.pack_into('<I', raw, 188, len(trie))
        reject(lambda raw=bytes(raw): verify_image(raw), reason)
    reject(lambda: uleb(b'\xff' * 9 + b'\2', 0, 10), 'Overflowing export ULEB')
    reject(lambda: uleb(b'\0', -1, 1), 'Out-of-range export ULEB')
    for value in (-1, 1 << 64):
        reject(lambda value=value: encode_uleb(value), 'Invalid unsigned export RVA')
        reject(lambda value=value: image.offset(value), 'Invalid code VA/size')
    reject(lambda: image.offset(image.base, 0), 'Invalid code VA/size')
    reject(lambda: image.offset(image.base + 0x1ffc), 'Entry is not file-backed executable code')
    return count


def self_test():
    data = fixture()
    image = verify_image(data)
    assert image.base == 0x100000000
    assert image.exports['_STHNativeMinimized'] == image.base + 0x400
    assert image.exports['_sth_core_base'] == image.base + 0x8028
    count = negative_controls(data)
    backwards = fixture(negative_adrp=True)
    late = verify_image(backwards)
    assert late.exports['_STHNativeMinimized'] == late.base + 0xc400
    assert late.exports['_sth_core_base'] < late.exports['_STHNativeMinimized']
    assert negative_controls(backwards) == count
    malformed = malformed_controls(data)
    # Exercise the legacy dyld-info export trie too, without a symtab fallback.
    legacy = bytearray(data)
    legacy[176:224] = struct.pack('<12I', 0x80000022, 48, *([0] * 8),
                                   *struct.unpack_from('<II', data, 184))
    struct.pack_into('<I', legacy, 20, 192)
    verify_image(bytes(legacy))
    print(f'Native stub parser self-test ONLY: 21 export addresses/entries; {count} exact ABI corruptions rejected per positive/negative ADRP layout; {malformed} malformed/negative-RVA cases rejected; modern and legacy export tries; no final build claimed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', nargs='?', type=Path, default=ROOT / 'build')
    parser.add_argument('--self-test', action='store_true', help='in-memory parser tests only, NOT artifact verification')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    for label, data, core in inspect_target(args.target):
        verify_image(data)
        verify_core_targets(core)
        rejected = negative_controls(data)
        print(f'{label}: 21 real exported stubs load _sth_core_base, add reviewed RVAs and tail-BR x16 to file-backed original core PACIBSP entries; {rejected} exact in-memory corruptions rejected; files unchanged')


if __name__ == '__main__':
    main()
