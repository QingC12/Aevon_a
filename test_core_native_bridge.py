"""Local clang byte-level migration/ABI tests; no iOS runtime is claimed."""
import copy
import hashlib
import io
import shutil
import struct
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import core_native_bridge as bridge
from embed_orion import prepare

ROOT = Path(__file__).resolve().parent
COMPILER = ['clang'] if shutil.which('clang') else ['xcrun', 'clang']
BODY_RANGES = [(0x4C368, 0x4C8A8), (0x507BC, 0x50A58), (0x4473C, 0x447D4),
               (0x447D8, 0x449DC), (0x4994C, 0x4AD44), (0x4AD48, 0x4B82C),
               (0x4D3DC, 0x4D4E0), (0x51454, 0x51588)]


def base_image():
    raw = (ROOT / 'inputs/base.deb').read_bytes()
    assert hashlib.sha256(raw).hexdigest() == '67937ea54f1a79d43bb48242c436e0c78b0177ef79d251e4c21465286ee1dace'
    assert raw[:8] == b'!<arch>\n'
    pos, archives = 8, {}
    while pos < len(raw):
        header = raw[pos:pos + 60]
        assert header[58:60] == b'`\n'
        size = int(header[48:58])
        archives[header[:16].strip().rstrip(b'/').decode()] = raw[pos + 60:pos + 60 + size]
        pos += 60 + size + size % 2
    with tarfile.open(fileobj=io.BytesIO(archives['data.tar.xz'])) as archive:
        matches = [m for m in archive if m.isfile() and m.name.endswith('/Stheno.dylib')]
        assert len(matches) == 1
        image = archive.extractfile(matches[0]).read()
    assert hashlib.sha256(image).hexdigest() == 'd5612f269f5a63347d8187fd25f75a0dca45c1608bdf38986112a5bb770fb9e7'
    return image


def compile_source(path, output, keep_labels=False):
    subprocess.run(COMPILER + ['-target', 'arm64e-apple-ios16.1'] +
                   (['-Wa,-L'] if keep_labels else []) +
                   ['-c', str(path), '-o', str(output)], check=True, capture_output=True)
    return bridge._object(output.read_bytes())


def words(code):
    return list(struct.unpack('<' + 'I' * (len(code) // 4), code))


def adr_target(word, pc):
    imm = ((word >> 29) & 3) | (((word >> 5) & 0x7FFFF) << 2)
    return pc + bridge._signed(imm, 21)


def branch_target(word, pc):
    return pc + bridge._signed(word & 0x3FFFFFF, 26) * 4


def normalize(code, origin, callback, original):
    """Compare every emitted instruction, abstracting only the two migrations."""
    data, rows, i = words(code), [], 0
    while i < len(data):
        word, pc, length = data[i], origin + i * 4, 1
        if original and i + 5 < len(data) and data[i:i + 2] == [0x90000009, 0xF9400129] and data[i + 5] == 0xD63F0120:
            lo, hi, add = data[i + 2:i + 5]
            assert lo & 0xFFE0001F == 0xD280000A and hi & 0xFFE0001F == 0xF2A0000A
            assert add == 0x8B0A0129
            token, length = ('CALL', ((hi >> 5) & 65535) * 65536 + ((lo >> 5) & 65535)), 6
        elif original and word & 0xFFFFFFE0 == 0x90000000:
            reg = word & 31
            assert data[i + 1] == 0xF9400000 | (reg << 5) | reg
            token, length = ('BASE', reg), 2
        elif not original and word & 0x9F000000 == 0x10000000 and adr_target(word, pc) == origin:
            reg = word & 31
            assert data[i + 1] == 0xD1400000 | ((origin >> 12) << 10) | (reg << 5) | reg
            assert data[i + 2] == 0xD1000000 | ((origin & 4095) << 10) | (reg << 5) | reg
            token, length = ('BASE', reg), 3
        elif word & 0x9F000000 == 0x10000000:
            assert adr_target(word, pc) == callback
            token = ('ADR_CALLBACK', word & 31)
        elif word & 0xFC000000 == 0x94000000:
            target = branch_target(word, pc)
            token = ('LOCAL_CALL', 'LresetSize') if target == callback else ('CALL', target)
            assert not original or target == callback
        elif word & 0xFF000010 == 0x54000000:
            target = pc + bridge._signed((word >> 5) & 0x7FFFF, 19) * 4
            token = ('COND', word & 0xFF00001F, target)
        else:
            token = ('WORD', word)
        rows.append((pc, token))
        i += length
    positions = {pc: i for i, (pc, _) in enumerate(rows)}
    return [(t[0], t[1], positions[t[2]]) if t[0] == 'COND' else t for _, t in rows]


class MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='native-bridge-')
        cls.out = Path(cls.temp.name)
        cls.original = base_image()
        cls.image, cls.meta, cls.stub = bridge.migrate_native_bridge(cls.original, cls.out, COMPILER)
        cls.reference = compile_source(ROOT / 'native.S', cls.out / 'reference.o', True)
        cls.ref_symbols = {n: v for n, _, s, v in cls.reference['symbols'] if s}
        cls.code = cls.image[bridge.BASE:cls.meta['end']]
        cls.normal = normalize(cls.code, bridge.BASE, cls.meta['callbacks']['LresetSize'], False)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_complete_emitted_semantic_equivalence(self):
        reference = normalize(self.reference['code'], 0, self.ref_symbols['LresetSize'], True)
        self.assertEqual(reference, self.normal)
        self.assertEqual(len(self.meta['exports']), 23)
        expected = {n for n, t, _, _ in self.reference['symbols'] if t == 0xF}
        self.assertEqual(expected, self.meta['exports'].keys())
        self.assertEqual(hashlib.sha256((ROOT / 'native.S').read_bytes()).hexdigest(), bridge.SOURCE_SHA256)

    def test_exact_bounds_and_original_bodies(self):
        self.assertEqual(self.image[:bridge.BASE], self.original[:bridge.BASE])
        self.assertEqual(self.image[self.meta['end']:], self.original[self.meta['end']:])
        self.assertEqual(self.meta['capacity'], 0x1A00)
        self.assertLessEqual(self.meta['size'], 0x1A00)
        self.assertGreaterEqual(bridge.BASE, bridge.DISPATCH_END)
        self.assertEqual(self.image[self.meta['end']:bridge.LIMIT], bytes(bridge.LIMIT - self.meta['end']))
        for start, stop in BODY_RANGES:
            self.assertEqual(self.image[start:stop], self.original[start:stop])
        self.assertEqual(len(self.image), len(self.original))

    def test_real_direct_targets_and_callback_authentication(self):
        self.assertEqual(len(self.meta['direct_calls']), 43)
        decoded = []
        for record in self.meta['direct_calls']:
            word = struct.unpack_from('<I', self.image, record['rva'])[0]
            self.assertEqual(word & 0xFC000000, 0x94000000)
            self.assertEqual(branch_target(word, record['rva']), record['target'])
            decoded.append(record['target'])
        self.assertEqual(decoded, [t[1] for t in self.normal if t[0] == 'CALL'])
        self.assertNotIn(0xD63F0120, words(self.code))
        for rva in list(self.meta['exports'].values()) + list(self.meta['callbacks'].values()):
            self.assertEqual(struct.unpack_from('<I', self.image, rva)[0], 0xD503237F)
        callback = self.meta['callbacks']['LresetSize']
        callback_calls = [branch_target(w, bridge.BASE + i * 4) for i, w in enumerate(words(self.code))
                          if w & 0xFC000000 == 0x94000000 and
                          branch_target(w, bridge.BASE + i * 4) == callback]
        self.assertEqual(callback_calls, [callback])
        self.assertIn(('ADR_CALLBACK', 16), self.normal)
        self.assertIn(('WORD', 0xD65F0FFF), self.normal)  # RETAB
        self.assertEqual(self.meta['original_callbacks'], {'dock': 0x4D4C4, 'initializer': 0x4FF20})
        self.assertEqual(sum(t[0] == 'BASE' for t in self.normal), 10)
        self.assertEqual(self.meta['base_loads'], 10)
        self.assertEqual(self.meta['source_base_load_pairs'], 9)

    def test_retained_model_and_consumed_keypaths(self):
        starts = sorted(self.meta['exports'].items(), key=lambda row: row[1])
        setter_start = self.meta['exports']['_STHNativeSetMinimized']
        setter_end = next(rva for _, rva in starts if rva > setter_start)
        code = self.image[setter_start:setter_end]
        ops = words(code)
        calls = [(i, branch_target(w, setter_start + i * 4)) for i, w in enumerate(ops)
                 if w & 0xFC000000 == 0x94000000]
        self.assertEqual([t for _, t in calls], [0xB091C, 0xB091C, 0xB0A2C, 0xAEEDC])
        self.assertEqual(ops[calls[2][0] - 1], 0xAA1403E0)  # borrowed model -> retain
        self.assertEqual(ops[calls[3][0] - 4:calls[3][0]],
                         [0x910003E0, 0xAA1403E1, 0xA9410FE2, 0xD2800015])
        getter_end = self.meta['exports']['_STHNativeSetMinimized']
        getter = words(self.image[bridge.BASE:getter_end])
        self.assertEqual([branch_target(w, bridge.BASE + i * 4) for i, w in enumerate(getter)
                          if w & 0xFC000000 == 0x94000000],
                         [0xB091C, 0xB091C, 0xAEECC, 0xB0A0C, 0xB0A0C])

    def test_helper_tail_jumps_preserve_all_abi_inputs(self):
        obj = compile_source(self.stub, self.out / 'stubs.o')
        helper, global_address, core_runtime_base = 0x500FF0, 0x701AB8, 0x100000000
        code, definitions, relocs = bridge._relocate(obj, helper, {'_sth_core_base': global_address})
        exported = {n for n, t, _, _ in obj['symbols'] if t == 0xF}
        self.assertEqual(exported, self.meta['exports'].keys())
        self.assertEqual(len(relocs), 2 * len(exported))
        self.assertEqual({r['type'] for r in relocs}, {'PAGE21', 'PAGEOFF12'})
        for name, rva in self.meta['exports'].items():
            pc = definitions[name]
            emitted = words(code[pc - helper:pc - helper + 20])
            self.assertEqual(len(emitted), 5)
            self.assertEqual(emitted[0] & 0x9F00001F, 0x90000010)
            imm = ((emitted[0] >> 29) & 3) | (((emitted[0] >> 5) & 0x7FFFF) << 2)
            regs = {i: 0xABC00000 + i for i in range(31)}
            before = dict(regs)
            regs[16] = (pc & ~4095) + bridge._signed(imm, 21) * 4096
            self.assertEqual(emitted[1] & ~0x003FFC00, 0xF9400210)
            load_address = regs[16] + ((emitted[1] >> 10) & 4095) * 8
            self.assertEqual(load_address, global_address)
            regs[16] = core_runtime_base
            self.assertEqual(emitted[2] & ~0x003FFC00, 0x91400210)
            self.assertEqual(emitted[3] & ~0x003FFC00, 0x91000210)
            regs[16] += ((emitted[2] >> 10) & 4095) * 4096
            regs[16] += (emitted[3] >> 10) & 4095
            self.assertEqual(emitted[4], 0xD61F0200)  # BR x16, never BL/BLRAA
            self.assertEqual(regs[16], core_runtime_base + rva)
            self.assertEqual({k: v for k, v in regs.items() if k != 16},
                             {k: v for k, v in before.items() if k != 16})
            # The only emitted writes are x16: LR/SP/FP, x8 and x20/x21 survive.

    def test_prepare_order_and_existing_dispatch_bytes(self):
        changed = bytearray(self.original)
        dock = compile_source(ROOT / 'DockDispatch.S', self.out / 'dock-dispatch.o')
        external = {'_STHDockCoreDlsym': 0xB03BC, '_STHDockMinimizePlus4': 0x447D8,
                    '_STHDockRestorePlus4': 0x449E0, '_STHDockGeometryPlus4': 0x9D7F8}
        dock_code, _, _ = bridge._relocate(dock, 0xDA400, external)
        self.assertEqual(0xDA400 + len(dock_code), bridge.DISPATCH_END)
        changed[0xDA400:bridge.DISPATCH_END] = dock_code
        prepared, _, _ = prepare(changed, (ROOT / 'inputs/Orion.arm64e').read_bytes())
        first, first_meta, _ = bridge.migrate_native_bridge(prepared, self.out / 'after', COMPILER)
        migrated, _, _ = bridge.migrate_native_bridge(changed, self.out / 'before', COMPILER)
        second, _, _ = prepare(migrated, (ROOT / 'inputs/Orion.arm64e').read_bytes())
        self.assertEqual(first, second)
        self.assertEqual(first[0xDA400:bridge.DISPATCH_END], changed[0xDA400:bridge.DISPATCH_END])
        self.assertEqual(first_meta['exports'], self.meta['exports'])
        self.assertEqual(changed[bridge.BASE:bridge.LIMIT], bytes(bridge.CAPACITY))

    def test_fail_closed_without_mutating_caller(self):
        for position in (bridge.BASE, bridge.LIMIT - 1):
            dirty = bytearray(self.original)
            dirty[position] = 1
            saved = bytes(dirty)
            with self.assertRaisesRegex(bridge.BridgeError, 'not all zero'):
                bridge.migrate_native_bridge(dirty, self.out / 'dirty', COMPILER)
            self.assertEqual(dirty, saved)
        with self.assertRaisesRegex(bridge.BridgeError, 'not all zero'):
            bridge.migrate_native_bridge(self.image, self.out / 'twice', COMPILER)
        with self.assertRaisesRegex(bridge.BridgeError, 'audited'):
            bridge._transform((ROOT / 'native.S').read_text() + '\n')
        obj = bridge._object((self.out / 'core-native.o').read_bytes())
        too_large = copy.deepcopy(obj)
        too_large['code'] += bytes(bridge.CAPACITY)
        original = bytearray(self.original)
        with patch.object(bridge, '_object', return_value=too_large):
            with self.assertRaisesRegex(bridge.BridgeError, 'exceeds'):
                bridge.migrate_native_bridge(original, self.out / 'overflow', COMPILER)
        unknown = copy.deepcopy(obj)
        unknown['symbols'].append(('UnexpectedLocal', 0xE, 1, 0))
        with patch.object(bridge, '_object', return_value=unknown):
            with self.assertRaisesRegex(bridge.BridgeError, 'Unrecognized generated symbol'):
                bridge.migrate_native_bridge(original, self.out / 'unknown', COMPILER)
        self.assertEqual(original, self.original)


class RelocationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='native-reloc-')
        self.out = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def assemble(self, source):
        path = self.out / 'test.S'
        path.write_text('.text\n.p2align 2\n' + source)
        return compile_source(path, self.out / 'test.o')

    def test_all_four_real_object_relocation_kinds(self):
        obj = self.assemble('Local:\n.globl _probe\n_probe:\n bl _target\n b _target\n'
                            ' adrp x9,_target@PAGE\n add x9,x9,_target@PAGEOFF\n'
                            ' adrp x10,_target@PAGE\n ldr x0,[x10,_target@PAGEOFF]\n'
                            ' adrp x11,Local@PAGE\n add x11,x11,Local@PAGEOFF\n'
                            ' .quad _target+8\n .quad Local\n')
        target = 0xB0918
        code, _, records = bridge._relocate(obj, bridge.BASE, {'_target': target})
        self.assertEqual({r['type'] for r in records}, set(bridge.RELOC_NAMES.values()))
        emitted = words(code)
        for i in (0, 1):
            self.assertEqual(branch_target(emitted[i], bridge.BASE + i * 4), target)
        for index, expected in ((2, target), (4, target), (6, bridge.BASE)):
            word, pc = emitted[index], bridge.BASE + index * 4
            imm = ((word >> 29) & 3) | (((word >> 5) & 0x7FFFF) << 2)
            page = (pc & ~4095) + bridge._signed(imm, 21) * 4096
            low = (emitted[index + 1] >> 10) & 4095
            self.assertEqual(page + low * (8 if index == 4 else 1), expected)
        self.assertEqual(struct.unpack_from('<Q', code, 32)[0], target + 8)
        self.assertEqual(struct.unpack_from('<Q', code, 40)[0], bridge.BASE)

    def test_unknown_symbols_addend_got_and_bad_opcodes_rejected(self):
        obj = self.assemble(' bl _unknown\n')
        with self.assertRaisesRegex(bridge.BridgeError, 'Unrecognized external'):
            bridge._relocate(obj, bridge.BASE, {})
        for source in (' b _target+4\n', ' adrp x0,_target@GOTPAGE\n'):
            obj = self.assemble(source)
            with self.assertRaisesRegex(bridge.BridgeError, 'Unsupported ARM64 relocation'):
                bridge._relocate(obj, bridge.BASE, {'_target': 0xB091C})
        obj = self.assemble(' bl _target\n')
        obj['code'][:4] = bytes(4)
        with self.assertRaisesRegex(bridge.BridgeError, 'opcode mismatch'):
            bridge._relocate(obj, bridge.BASE, {'_target': 0xB091C})

    def test_ranges_flags_alignment_and_truncation_rejected(self):
        obj = self.assemble(' bl _target\n')
        for target in (bridge.BASE + (1 << 27), bridge.BASE + 1):
            with self.assertRaisesRegex(bridge.BridgeError, 'out of range'):
                bridge._relocate(obj, bridge.BASE, {'_target': target})
        obj['relocations'] = [(r, info ^ (1 << 24)) for r, info in obj['relocations']]
        with self.assertRaisesRegex(bridge.BridgeError, 'flags'):
            bridge._relocate(obj, bridge.BASE, {'_target': 0xB091C})
        obj = self.assemble(' adrp x0,_target@PAGE\n')
        with self.assertRaisesRegex(bridge.BridgeError, 'out of range'):
            bridge._relocate(obj, bridge.BASE, {'_target': 1 << 44})
        obj = self.assemble(' adrp x0,_target@PAGE\n ldr x0,[x0,_target@PAGEOFF]\n')
        with self.assertRaisesRegex(bridge.BridgeError, 'Misaligned'):
            bridge._relocate(obj, bridge.BASE, {'_target': 0xB0919})
        obj = self.assemble(' .quad _target+8\n')
        with self.assertRaisesRegex(bridge.BridgeError, 'overflow'):
            bridge._relocate(obj, bridge.BASE, {'_target': (1 << 64) - 1})
        for length in (0, 31, 32, 80):
            with self.assertRaises(bridge.BridgeError):
                bridge._object((self.out / 'test.o').read_bytes()[:length])


if __name__ == '__main__':
    unittest.main(verbosity=2)
