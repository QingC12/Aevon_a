"""Bundle the official Orion runtime privately; preserve all library ordinals."""
import hashlib
import struct
from pathlib import Path

ORION_MAIN_LOAD = '@loader_path/.stheno/Orion'
ORION_PRIVATE_ID = '@rpath/SthenoOrion'
ORION_SUBSTRATE = '@loader_path/../.jbroot/usr/lib/libsubstrate.dylib'
LOAD_COMMANDS = {0xc, 0x18, 0x1f, 0x20, 0x80000018, 0x8000001f, 0x80000023}
EXPECTED_ORION_SHA256 = 'e7cbd6e055d9ec30c750741c9a2831d73c5ce7efaf812053e7b279a4e92dbe85'


def commands(image):
    magic, cpu, sub, _, count, total, _, _ = struct.unpack_from('<8I', image)
    assert magic == 0xfeedfacf and cpu == 0x100000c and sub & 0xffffff == 2
    pos = 32
    result = []
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', image, pos)
        assert size >= 8 and size % 8 == 0 and pos + size <= 32 + total
        result.append((cmd, pos, size))
        pos += size
    assert pos == 32 + total
    return result


def name_at(image, pos, size):
    start = struct.unpack_from('<I', image, pos + 8)[0]
    assert 8 <= start < size
    return image[pos + start:pos + size].split(b'\0')[0].decode()


def rewrite_names(image, replacements):
    image = bytes(image)
    cmds = commands(image)
    first_data = len(image)
    new = []
    changed = []
    for cmd, pos, size in cmds:
        data = image[pos:pos + size]
        if cmd == 0x19:
            nsects = struct.unpack_from('<I', image, pos + 64)[0]
            for i in range(nsects):
                sec = pos + 72 + i * 80
                offset = struct.unpack_from('<I', image, sec + 48)[0]
                if offset:
                    first_data = min(first_data, offset)
        if cmd in LOAD_COMMANDS | {0xd, 0x8000001c}:
            old = name_at(image, pos, size)
            if old in replacements:
                off = struct.unpack_from('<I', data, 8)[0]
                newname = replacements[old].encode() + b'\0'
                updated = bytearray(data[:off] + newname)
                updated += bytes((-len(updated)) % 8)
                struct.pack_into('<I', updated, 4, len(updated))
                data = bytes(updated)
                changed.append(old)
        new.append(data)
    assert sorted(changed) == sorted(replacements), changed
    block = b''.join(new)
    assert 32 + len(block) <= first_data
    out = bytearray(image)
    out[32:first_data] = block + bytes(first_data - 32 - len(block))
    struct.pack_into('<II', out, 16, len(cmds), len(block))
    commands(out)
    assert out[first_data:] == image[first_data:]
    return out


def imports_from(image, library):
    ordinal = 0
    wanted = None
    symtab = None
    for cmd, pos, size in commands(image):
        if cmd in LOAD_COMMANDS:
            ordinal += 1
            if name_at(image, pos, size) == library:
                wanted = ordinal
        elif cmd == 2:
            symtab = struct.unpack_from('<4I', image, pos + 8)
    assert wanted is not None and symtab
    so, count, st, sz = symtab
    result = set()
    for i in range(count):
        si, typ, sect, desc, value = struct.unpack_from('<IBBHQ', image, so + i * 16)
        if typ & 0xe == 0 and not sect and (desc >> 8) & 255 == wanted:
            result.add(image[st + si:st + sz].split(b'\0')[0].decode())
    assert result
    return result


def exports(image):
    trie = None
    for cmd, pos, size in commands(image):
        if cmd == 0x80000033:
            off, n = struct.unpack_from('<II', image, pos + 8)
            trie = image[off:off + n]
        elif cmd in (0x22, 0x80000022) and trie is None:
            off, n = struct.unpack_from('<II', image, pos + 40)
            trie = image[off:off + n]
    assert trie
    result = set()

    def uleb(pos):
        value = shift = 0
        while True:
            byte = trie[pos]
            pos += 1
            value |= (byte & 127) << shift
            shift += 7
            assert shift <= 70
            if byte < 128:
                return value, pos

    def walk(at, prefix, ancestors):
        assert at not in ancestors and 0 <= at < len(trie)
        terminal, p = uleb(at)
        if terminal:
            result.add(prefix)
        p += terminal
        count = trie[p]
        p += 1
        for _ in range(count):
            end = trie.index(0, p)
            edge = trie[p:end].decode()
            target, p = uleb(end + 1)
            walk(target, prefix + edge, ancestors | {at})
    walk(0, '', set())
    return result


def prepare(core, runtime):
    assert hashlib.sha256(runtime).hexdigest() == EXPECTED_ORION_SHA256
    required = imports_from(core, '@rpath/Orion.framework/Orion')
    available = exports(runtime)
    missing = required - available
    assert not missing, sorted(missing)
    core = rewrite_names(core, {'@rpath/Orion.framework/Orion': ORION_MAIN_LOAD})
    runtime = rewrite_names(runtime, {
        '@rpath/Orion.framework/Orion': ORION_PRIVATE_ID,
        '@rpath/CydiaSubstrate.framework/CydiaSubstrate': ORION_SUBSTRATE,
    })
    assert imports_from(core, ORION_MAIN_LOAD) == required
    assert required <= exports(runtime)
    return core, runtime, {'version': '1.0.2', 'required_symbols': len(required),
        'resolved_symbols': len(required), 'load_path': ORION_MAIN_LOAD,
        'private_id': ORION_PRIVATE_ID, 'substrate_path': ORION_SUBSTRATE,
        'source_arm64e_sha256': EXPECTED_ORION_SHA256}
