import hashlib
import io
from pathlib import Path
import struct
import tarfile
import unittest

from embed_orion import (prepare, commands, name_at, imports_from, exports,
    LOAD_COMMANDS, ORION_MAIN_LOAD, ORION_PRIVATE_ID, ORION_SUBSTRATE)

ROOT = Path(__file__).resolve().parent


def ar_members(data):
    assert data.startswith(b'!<arch>\n')
    pos = 8
    result = {}
    while pos < len(data):
        header = data[pos:pos + 60]
        assert header[58:60] == b'`\n'
        name = header[:16].decode().strip().rstrip('/')
        size = int(header[48:58])
        result[name] = data[pos + 60:pos + 60 + size]
        pos += 60 + size + size % 2
    return result


def library_commands(image):
    return [(cmd, name_at(image, pos, size)) for cmd, pos, size in commands(image)
            if cmd in LOAD_COMMANDS]


def symtab_and_fixups(image):
    result = {}
    for cmd, pos, size in commands(image):
        if cmd == 2:
            off, count, strings, length = struct.unpack_from('<4I', image, pos + 8)
            result['symbols'] = image[off:off + 16 * count]
            result['strings'] = image[strings:strings + length]
        elif cmd in (0x80000033, 0x80000034):
            off, length = struct.unpack_from('<II', image, pos + 8)
            result[cmd] = image[off:off + length]
    return result


class EmbeddedOrionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        members = ar_members((ROOT / 'inputs/base.deb').read_bytes())
        with tarfile.open(fileobj=io.BytesIO(members['data.tar.xz'])) as archive:
            cls.core = archive.extractfile('./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib').read()
        cls.runtime = (ROOT / 'inputs/Orion.arm64e').read_bytes()
        cls.new_core, cls.new_runtime, cls.info = prepare(cls.core, cls.runtime)

    def test_complete_swift_abi_surface(self):
        required = imports_from(self.core, '@rpath/Orion.framework/Orion')
        self.assertEqual(len(required), 79)
        self.assertFalse(required - exports(self.new_runtime))
        self.assertEqual(required, imports_from(self.new_core, ORION_MAIN_LOAD))

    def test_no_global_orion_resolution_required(self):
        main_deps = library_commands(self.new_core)
        old_main_deps = library_commands(self.core)
        self.assertEqual(len(main_deps), len(old_main_deps))
        for old, new in zip(old_main_deps, main_deps):
            self.assertEqual(old[0], new[0])
            self.assertEqual(new[1], ORION_MAIN_LOAD if old[1] == '@rpath/Orion.framework/Orion' else old[1])
        self.assertNotIn('@rpath/Orion.framework/Orion', [n for _, n in main_deps])
        runtime_deps = library_commands(self.new_runtime)
        self.assertIn((0x80000018, ORION_SUBSTRATE), runtime_deps)
        self.assertTrue(all('Orion.framework' not in n for _, n in runtime_deps))
        ids = [name_at(self.new_runtime, p, n) for c, p, n in commands(self.new_runtime) if c == 0xd]
        self.assertEqual(ids, [ORION_PRIVATE_ID])

    def test_no_code_or_ordinal_fixup_changes(self):
        self.assertEqual(self.core[0x4000:], self.new_core[0x4000:])
        self.assertEqual(self.runtime[0x4000:], self.new_runtime[0x4000:])
        self.assertEqual(symtab_and_fixups(self.core), symtab_and_fixups(self.new_core))
        self.assertEqual(symtab_and_fixups(self.runtime), symtab_and_fixups(self.new_runtime))

    def test_wrong_runtime_is_rejected(self):
        bad = bytearray(self.runtime)
        bad[0x5000] ^= 1
        with self.assertRaises(AssertionError):
            prepare(self.core, bad)

    def test_license_is_preserved(self):
        license = (ROOT / 'inputs/Orion-LICENSE.txt').read_bytes()
        self.assertEqual(hashlib.sha256(license).hexdigest(), '5afa9b37c934d452ecd7d3c184367657f279149add82a6d62b0ca23490b116a4')


if __name__ == '__main__':
    unittest.main(verbosity=2)
