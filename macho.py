"""Thin arm64e Mach-O reader shared by the ABI tests.

Only pure inspection lives here: no rewriting, no patching, no I/O. The
release build reads the frozen base instead of rewriting load commands, so
this module exists purely so tests can assert what the shipped images
actually import and export.
"""
import struct

LOAD_COMMANDS = {0xc, 0x18, 0x1f, 0x20, 0x80000018, 0x8000001f, 0x80000023}


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
