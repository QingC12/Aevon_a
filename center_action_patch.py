"""Stheno exact-image patch for the three native RingEnv pan callbacks only."""
import os
from pathlib import Path
import struct
import subprocess

BASE = 0xDA000
PACIBSP = bytes.fromhex('7f2303d5')
SITES = {0x56630: BASE, 0x56FCC: BASE + 0x80, 0x578E0: BASE + 0x100}
EXTERNALS = {
    '_STHCenterCoreBeginPlus4': 0x56634,
    '_STHCenterCoreChangePlus4': 0x56FD0,
    '_STHCenterCoreFinishPlus4': 0x578E4,
    '_STHCenterCoreDlsym': 0xB03BC,
}


def branch(source, target):
    delta = target - source
    if delta % 4 or not -(1 << 27) <= delta < (1 << 27):
        raise ValueError('Center chooser branch out of range')
    return struct.pack('<I', 0x14000000 | ((delta // 4) & 0x3ffffff))


def center_dispatch(obj):
    """Read only the generated arm64e object's text and branch relocations."""
    magic, cpu, subtype, kind, count = struct.unpack_from('<5I', obj)
    if (magic, cpu, subtype & 0xff, kind) != (0xfeedfacf, 0x100000c, 2, 1):
        raise ValueError('Expected an arm64e Mach-O object')
    off = 32
    text = symtab = None
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', obj, off)
        if cmd == 2:
            symtab = struct.unpack_from('<4I', obj, off + 8)
        elif cmd == 0x19:
            nsects, = struct.unpack_from('<I', obj, off + 64)
            for i in range(nsects):
                s = off + 72 + 80 * i
                if obj[s:s + 32] == b'__text'.ljust(16, b'\0') + b'__TEXT'.ljust(16, b'\0'):
                    text = struct.unpack_from('<QIIII', obj, s + 40)
        off += size
    if text is None or symtab is None:
        raise ValueError('Missing center dispatcher object sections')
    length, start, _, relocs, nreloc = text
    syms, nsyms, strings, strings_size = symtab
    code = bytearray(obj[start:start + length])
    if not 0x180 < len(code) <= 0x200 or nreloc != len(EXTERNALS):
        raise ValueError('Unexpected center dispatcher size or relocations')
    seen = set()
    for i in range(nreloc):
        at, flags = struct.unpack_from('<II', obj, relocs + 8 * i)
        symbol = flags & 0xffffff
        # ARM64_RELOC_BRANCH26, extern, 4-byte instruction, PC-relative.
        if flags >> 24 != 0x2d or symbol >= nsyms or at % 4 or at + 4 > length:
            raise ValueError('Unexpected center dispatcher relocation')
        name_at, = struct.unpack_from('<I', obj, syms + 16 * symbol)
        name = obj[strings + name_at:strings + strings_size].split(b'\0', 1)[0].decode()
        if name in seen or name not in EXTERNALS or code[at:at + 4] != branch(0, 0):
            raise ValueError('Unexpected center dispatcher branch: ' + name)
        seen.add(name)
        code[at:at + 4] = branch(BASE + at, EXTERNALS[name])
    return code


def patch_center_action(image, out):
    image = bytearray(image)
    aliases = {0x59864: 0x56630, 0x59868: 0x56FCC, 0x5986C: 0x578E0}
    for at, target in aliases.items():
        if image[at:at + 4] != branch(at, target):
            raise ValueError(f'Center ring alias mismatch at {at:#x}')
    for at in SITES:
        if image[at:at + 4] != PACIBSP:
            raise ValueError(f'Center ring prologue mismatch at {at:#x}')
    if image[BASE:BASE + 0x200] != bytes(0x200):
        raise ValueError('Center dispatcher reservation is not empty')
    source = Path(__file__).with_name('CenterChooserNative.S')
    obj = Path(out) / 'CenterChooserCore.o'
    compiler = [os.environ['STH_CENTER_CLANG']] if 'STH_CENTER_CLANG' in os.environ else ['xcrun', 'clang']
    subprocess.check_call(compiler + ['-target', 'arm64e-apple-ios16.1',
                           '-DSTH_CENTER_CORE_PATCH', '-c', str(source), '-o', str(obj)])
    code = center_dispatch(obj.read_bytes())
    image[BASE:BASE + len(code)] = code
    for at, target in SITES.items():
        image[at:at + 4] = branch(at, target)
    return image, {
        'dispatch_base': hex(BASE), 'dispatch_bytes': len(code),
        'gesture': 'native-ring-pan', 'ring_geometry_modified': False,
        'patches': {hex(at): {'target': hex(target), 'kind': 'b', 'original': PACIBSP.hex()}
                    for at, target in SITES.items()},
    }
