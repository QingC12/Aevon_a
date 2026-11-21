"""Check emitted ARM64e bridge instructions, not source-string contracts.

This is a static ABI/ownership gate; it is not on-device ARC validation.
The consuming-setter rule is matched to the original native setter and the
existing STHDockNativeSetOffset bridge. Getter arguments remain borrowed.
"""
from pathlib import Path
import struct
import json
import sys

ROOT = Path(__file__).resolve().parent

class Image:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        d = self.data
        assert d[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin ARM64e Mach-O'
        _, cpu, sub, _, count, _, _, _ = struct.unpack_from('<8I', d)
        assert cpu == 0x100000c and sub & 0xffffff == 2
        self.segments, self.symbols = [], {}
        pos, symtab = 32, None
        for _ in range(count):
            cmd, size = struct.unpack_from('<II', d, pos)
            if cmd == 0x19:
                va, vs, fo, fs = struct.unpack_from('<4Q', d, pos + 24)
                self.segments.append((va, fs, fo))
            if cmd == 2:
                symtab = struct.unpack_from('<4I', d, pos + 8)
            pos += size
        assert symtab
        so, n, st, ss = symtab
        for i in range(n):
            no, typ, sec, desc, va = struct.unpack_from('<IBBHQ', d, so + 16*i)
            if sec and typ & 14 == 14:
                name = d[st+no:d.index(b'\0', st+no)].decode()
                self.symbols[name] = va

    def words(self, name):
        va = self.symbols[name]
        seg = next(s for s in self.segments if s[0] <= va < s[0]+s[1])
        off = seg[2] + va - seg[0]
        words = []
        for i in range(300):
            w = struct.unpack_from('<I', self.data, off+4*i)[0]
            words.append(w)
            if w == 0xd65f0fff:  # retab
                return words
        raise AssertionError(('Missing bounded bridge return', name))

def calls(words, base=0):
    result = []
    for i, w in enumerate(words):
        if w & 0xfc000000 == 0x94000000:
            imm=w & 0x3ffffff
            if imm & (1<<25): imm-=1<<26
            result.append((base+4*i+4*imm,i));continue
        if w != 0xd63f0120:  # blr x9, the core-entry macro
            continue
        assert i >= 3 and words[i-1] == 0x8b0a0129, 'Unexpected call target register'
        lo, hi = words[i-3], words[i-2]
        assert lo & 0xffe0001f == 0xd280000a
        assert hi & 0xffe0001f == 0xf2a0000a
        result.append(((((hi >> 5) & 65535) << 16) | ((lo >> 5) & 65535), i))
    return result

def setter(image, name):
    words = image.words(name)
    ops = calls(words, image.symbols[name])
    targets = [op for op, _ in ops]
    assert targets == [0xb091c, 0xb091c, 0xb0a2c, 0xaeedc], (name, 'consuming setter ownership violation', [hex(x) for x in targets])
    retain_i, setter_i = ops[2][1], ops[3][1]
    retain_back = 1 if words[retain_i] & 0xfc000000 == 0x94000000 else 6
    assert words[retain_i-retain_back] == 0xaa1403e0, (name, 'retain must receive borrowed model x20')
    # The setter receives the stack Bool, retained self, and both +1 key paths.
    args_end = setter_i if words[setter_i] & 0xfc000000 == 0x94000000 else setter_i-5
    assert words[args_end-4:args_end] == [0x910003e0, 0xaa1403e1, 0xa9410fe2, 0xd2800015]
    assert 0xa9bf57f4 in words or 0xa9be57f4 in words, 'Missing saved Swift context'
    # Derive the net transfer from the calls actually found in this bridge.
    assert targets.count(0xb0a2c) - targets.count(0xaeedc) == 0
    assert targets.count(0xb091c) - 2*targets.count(0xaeedc) == 0
    print(image.path.name, name, 'retained self + consumed paths; caller ownership preserved')

def getter(image, name):
    targets = [op for op, _ in calls(image.words(name),image.symbols[name])]
    assert targets == [0xb091c, 0xb091c, 0xaeecc, 0xb0a0c, 0xb0a0c], (name, targets)


def main():
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT/'build'
    manifest=json.loads((folder/'build-manifest.json').read_text()) if (folder/'build-manifest.json').exists() else {}
    actions = Image(folder/'SthenoSystemActions.dylib')
    if manifest.get('merged_springboard_runtime'):
        gesture=Image(folder/'Stheno.dylib')
        meta=manifest['native_bridges'];gesture.symbols.update(meta['exports'])
        assert __import__('hashlib').sha256(gesture.data[meta['base']:meta['end']]).hexdigest()==meta['code_sha256']
    else: gesture = Image(folder/'SthenoGesture.dylib')
    setter(gesture, '_STHNativeSetMinimized')
    setter(actions, '_STHChooserClearMinimized')
    getter(gesture, '_STHNativeMinimized')
    getter(actions, '_STHDockNativeMinimized')
    from embed_orion import exports
    assert '_STHViewportModelMinimized' in exports(actions.data if manifest.get('merged_springboard_runtime') else gesture.data), 'Dock cleanup callback must be dynamically visible'
    orient = actions.words('_STHDockNativeOrientation')
    assert 0x910083e8 in orient, 'Orientation result must use sp+32, outside saved x19'
    assert 0xf94013e0 in orient, 'Orientation result must be read from sp+32'
    print('Published bridge ABI passed: real machine-code ownership, getter releases and orientation result separation')

if __name__ == '__main__':
    main()
