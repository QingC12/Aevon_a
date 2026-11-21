"""Bounded native.S migration; no linkedit, exports, or original bodies change."""
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

BASE, LIMIT = 0xDA600, 0xDC000
CAPACITY, DISPATCH_END = LIMIT - BASE, 0xDA5A8
ROOT = Path(__file__).resolve().parent
SOURCE_SHA256 = '1ec36a6b2dffcecbf3b7b79681e4edb869f8334da443a86a5b589767146f16e9'
RELOC_NAMES = {0: 'UNSIGNED', 2: 'BRANCH26', 3: 'PAGE21', 4: 'PAGEOFF12'}


class BridgeError(ValueError):
    """Reject unsupported inputs rather than emitting a partial migration."""


def _require(ok, message):
    if not ok:
        raise BridgeError(message)


def _span(data, offset, size):
    _require(0 <= offset <= len(data) and 0 <= size <= len(data) - offset,
             'Mach-O range outside file')
    return data[offset:offset + size]


def _commands(data, filetype):
    _require(len(data) >= 32, 'Truncated Mach-O header')
    magic, cpu, sub, kind, count, size, _, _ = struct.unpack_from('<8I', data)
    _require(magic == 0xFEEDFACF and cpu == 0x100000C and
             sub & 0xFFFFFF == 2 and kind == filetype, 'Expected thin arm64e Mach-O')
    _span(data, 32, size)
    pos, commands = 32, []
    for _ in range(count):
        _require(pos + 8 <= 32 + size, 'Truncated load command')
        cmd, length = struct.unpack_from('<II', data, pos)
        _require(length >= 8 and length % 8 == 0 and pos + length <= 32 + size,
                 'Invalid load command size')
        commands.append((cmd, pos, length))
        pos += length
    _require(pos == 32 + size, 'Load command size mismatch')
    return commands


def _cstring(data, start, end):
    _require(0 <= start < end <= len(data), 'Invalid symbol string offset')
    stop = data.find(b'\0', start, end)
    _require(stop >= 0, 'Unterminated Mach-O string')
    try:
        return data[start:stop].decode('ascii')
    except UnicodeDecodeError as exc:
        raise BridgeError('Non-ASCII Mach-O symbol') from exc


def _object(data):
    """Read a single-section assembler object, not a general-purpose linker."""
    sections, symtab = [], None
    for cmd, pos, length in _commands(data, 1):
        if cmd == 0x19:
            _require(length >= 72, 'Truncated segment')
            count = struct.unpack_from('<I', data, pos + 64)[0]
            _require(length == 72 + count * 80, 'Invalid segment section table')
            for i in range(count):
                q = pos + 72 + i * 80
                name = _cstring(data, q, q + 16)
                segment = _cstring(data, q + 16, q + 32)
                addr, size, offset, align, rel, nrel = struct.unpack_from('<QQ4I', data, q + 32)
                sections.append((name, segment, addr, size, offset, align, rel, nrel))
        elif cmd == 2:
            _require(length == 24 and symtab is None, 'Invalid symbol table command')
            symtab = struct.unpack_from('<4I', data, pos + 8)
        else:
            _require(cmd in (0xB, 0x24, 0x25, 0x32), 'Unsupported assembler load command')
    _require(len(sections) == 1 and sections[0][:2] == ('__text', '__TEXT'),
             'Only one __TEXT,__text section is supported')
    _, _, addr, size, offset, align, rel, nrel = sections[0]
    _require(addr % 4 == 0 and size % 4 == 0 and align >= 2, 'Unaligned object text')
    code = bytearray(_span(data, offset, size))
    _span(data, rel, nrel * 8)
    _require(symtab is not None, 'Missing object symbol table')
    so, count, st, ss = symtab
    _span(data, so, count * 16)
    _span(data, st, ss)
    symbols, names = [], set()
    for i in range(count):
        no, typ, section, desc, value = struct.unpack_from('<IBBHQ', data, so + i * 16)
        _require(no < ss, 'Invalid symbol string index')
        name = _cstring(data, st + no, st + ss)
        _require(name and name not in names, 'Duplicate or empty object symbol')
        names.add(name)
        _require((typ in (0xE, 0xF) and section == 1 and addr <= value <= addr + size)
                 or (typ == 1 and section == 0 and value == 0), 'Unsupported symbol kind')
        _require(desc == 0, 'Unsupported symbol descriptor')
        symbols.append((name, typ, section, value))
    relocations = [struct.unpack_from('<II', data, rel + i * 8) for i in range(nrel)]
    return {'code': code, 'addr': addr, 'symbols': symbols, 'relocations': relocations}


def _signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def _relocate(obj, base, externals):
    """Apply only audited ARM64 relocation forms, with explicit symbol resolution."""
    code, symbols, records, used = bytearray(obj['code']), obj['symbols'], [], set()
    for name, typ, section, value in symbols:
        _require(section or name in externals, 'Unrecognized external symbol: ' + name)
    for offset, info in obj['relocations']:
        index, pcrel = info & 0xFFFFFF, (info >> 24) & 1
        length, external, kind = (info >> 25) & 3, (info >> 27) & 1, info >> 28
        _require(kind in RELOC_NAMES, 'Unsupported ARM64 relocation: ' + str(kind))
        width = 8 if kind == 0 else 4
        _require(offset < 0x80000000 and offset % 4 == 0 and
                 offset + width <= len(code), 'Invalid relocation site')
        span = set(range(offset, offset + width))
        _require(not used.intersection(span), 'Overlapping relocations')
        used.update(span)
        _require(length == (3 if kind == 0 else 2) and pcrel == (kind in (2, 3)),
                 'Invalid ARM64 relocation flags')
        if external:
            _require(index < len(symbols), 'Invalid relocation symbol index')
            name, _, section, value = symbols[index]
            target = base + value - obj['addr'] if section else externals[name]
        else:
            _require(kind == 0 and index == 1, 'Unsupported section relocation')
            name, target = '__text', base - obj['addr']
        _require(isinstance(target, int) and 0 <= target < 1 << 64, 'Invalid symbol address')
        pc = base + offset
        if kind == 0:
            addend = struct.unpack_from('<Q', code, offset)[0]
            target += addend
            _require(target < 1 << 64, 'Unsigned relocation overflow')
            struct.pack_into('<Q', code, offset, target)
        else:
            word = struct.unpack_from('<I', code, offset)[0]
            if kind == 2:
                _require(word & 0x7C000000 == 0x14000000, 'BRANCH26 opcode mismatch')
                target += _signed(word & 0x3FFFFFF, 26) * 4
                delta = target - pc
                _require(delta % 4 == 0 and -(1 << 27) <= delta < 1 << 27,
                         'BRANCH26 target out of range')
                word = (word & 0xFC000000) | ((delta // 4) & 0x3FFFFFF)
            elif kind == 3:
                _require(word & 0x9F000000 == 0x90000000, 'PAGE21 opcode mismatch')
                _require(word & 0x60FFFFE0 == 0, 'PAGE21 inline addend unsupported')
                pages = ((target & ~4095) - (pc & ~4095)) // 4096
                _require(-(1 << 20) <= pages < 1 << 20, 'PAGE21 target out of range')
                imm = pages & 0x1FFFFF
                word = (word & ~0x60FFFFE0) | ((imm & 3) << 29) | ((imm >> 2) << 5)
            else:
                _require(word & 0x003FFC00 == 0, 'PAGEOFF12 inline addend unsupported')
                if word & 0xFFC00000 == 0x91000000:  # ADD Xd, Xn, #imm12
                    scale = 0
                else:
                    _require(word & 0x3B000000 == 0x39000000, 'PAGEOFF12 opcode mismatch')
                    size, vector, opc = word >> 30, (word >> 26) & 1, (word >> 22) & 3
                    _require(not vector or opc < 2 or size == 0, 'Invalid SIMD page offset')
                    scale = 4 if vector and opc >= 2 else size
                low = target & 4095
                _require(low % (1 << scale) == 0, 'Misaligned PAGEOFF12 target')
                word |= (low >> scale) << 10
            struct.pack_into('<I', code, offset, word)
        records.append({'rva': pc, 'target': target, 'symbol': name, 'type': RELOC_NAMES[kind]})
    definitions = {name: base + value - obj['addr'] for name, _, sec, value in symbols if sec}
    return code, definitions, sorted(records, key=lambda r: r['rva'])


def _transform(source):
    _require(hashlib.sha256(source.encode()).hexdigest() == SOURCE_SHA256,
             'native.S differs from the audited migration input')
    exports = set(re.findall(r'^begin (STHNative\w+)\s*$', source, re.M))
    exports.update(re.findall(r'^\.globl _(STHNative\w+)\s*$', source, re.M))
    exports = {'_' + name for name in exports}
    targets = {f'_STHCoreRVA_{raw}': int(raw, 0) for raw in
               re.findall(r'^\s*target\s+(0x[0-9a-f]+)\s*$', source, re.M)}
    macro = r'(?m)^\.macro target value\n.*?^\.endm'
    source, count = re.subn(macro, lambda _: '.macro target value\n bl _STHCoreRVA_\\value\n.endm',
                            source, flags=re.S)
    _require(count == 1, 'Missing target macro')
    pair = (r'(?m)^[ \t]*adrp[ \t]+(x[0-9]+),[ \t]*_sth_core_base@PAGE[ \t]*\n'
            r'[ \t]*ldr[ \t]+\1,[ \t]*\[\1,[ \t]*_sth_core_base@PAGEOFF\][ \t]*$')

    def local_base(match):
        reg = match[1]
        return (f' adr {reg}, STHCoreImage\n'
                f' sub {reg}, {reg}, #0x{BASE >> 12:x}, lsl #12\n'
                f' sub {reg}, {reg}, #0x{BASE & 4095:x}')

    source, loads = re.subn(pair, local_base, source)
    _require(loads > 0 and '_sth_core_base' not in source, 'Unconverted core-base reference')
    callbacks = re.findall(r'^(L\w+):$', source, re.M)
    _require(callbacks == ['LresetSize'], 'Unexpected local native callbacks')
    for name in callbacks:
        source = source.replace(name + ':', 'STHCoreLocal_' + name + ':\n' + name + ':')
    source = '.text\n.p2align 2\nSTHCoreImage:\n' + source
    return source, exports, targets, callbacks, loads


def _cave_offset(image):
    texts = []
    for cmd, pos, length in _commands(image, 6):
        if cmd != 0x19:
            continue
        _require(length >= 72, 'Truncated core segment')
        if _cstring(image, pos + 8, pos + 24) == '__TEXT':
            texts.append(struct.unpack_from('<4Q2I', image, pos + 24))
    _require(len(texts) == 1, 'Expected exactly one core __TEXT segment')
    vmaddr, vmsize, fileoff, filesize, maxprot, initprot = texts[0]
    _require(fileoff == 0 and vmsize >= LIMIT and filesize >= LIMIT and
             maxprot & 4 and initprot & 4, 'Cave is not file-backed executable __TEXT')
    _span(image, fileoff, filesize)
    _require(DISPATCH_END <= BASE and CAPACITY == 0x1A00, 'Cave overlaps dispatch')
    return fileoff + BASE


def _stubs(exports):
    lines = ['// Tail jumps leave LR, SP, Swift self/context and arguments unchanged.',
             '// Only the ABI scratch register x16 is used; PAC starts in the core body.',
             '.text', '.p2align 2']
    for name, rva in sorted(exports.items(), key=lambda item: item[1]):
        lines += [f'.globl {name}', name + ':',
                  ' adrp x16, _sth_core_base@PAGE',
                  ' ldr x16, [x16, _sth_core_base@PAGEOFF]',
                  f' add x16, x16, #0x{rva >> 12:x}, lsl #12',
                  f' add x16, x16, #0x{rva & 4095:x}', ' br x16']
    return '\n'.join(lines) + '\n'


def migrate_native_bridge(image, out, compiler):
    """Return (new_bytearray, JSON_metadata, stub_source_Path).

    Compile the returned .S instead of native.S in the existing helper. The
    helper still owns/initializes sth_core_base. This call never mutates image.
    Signing must happen after migration. No linker or Apple SDK is needed here.
    """
    original = bytes(image)
    offset = _cave_offset(original)
    _require(_span(original, offset, CAPACITY) == bytes(CAPACITY), 'Native cave is not all zero')
    source, exports, targets, callbacks, loads = _transform((ROOT / 'native.S').read_text())
    _require(isinstance(compiler, (list, tuple)) and compiler, 'compiler must be a command list')
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    assembly, objpath = out / 'core-native.S', out / 'core-native.o'
    stubpath, manifest = out / 'core-native-stubs.S', out / 'core-native.json'
    assembly.write_text(source)
    subprocess.run([str(x) for x in compiler] + ['-target', 'arm64e-apple-ios16.1',
                   '-c', str(assembly), '-o', str(objpath)], check=True, capture_output=True)
    obj = _object(objpath.read_bytes())
    for name, typ, section, value in obj['symbols']:
        allowed = (name in exports and typ == 0xF) or (name in targets and not section)
        allowed |= (typ == 0xE and (name == 'STHCoreImage' or
                    name in {'STHCoreLocal_' + c for c in callbacks} or
                    re.fullmatch(r'ltmp[0-9]+', name) is not None))
        _require(allowed, 'Unrecognized generated symbol: ' + name)
    _require({n for n, t, _, _ in obj['symbols'] if t == 0xF} == exports,
             'Generated bridge export mismatch')
    code, definitions, records = _relocate(obj, BASE, targets)
    _require(0 < len(code) <= CAPACITY, 'Native bridge exceeds 0x1a00 cave')
    _require(definitions.get('STHCoreImage') == BASE, 'Core anchor is not at cave start')
    _require(all(r['type'] == 'BRANCH26' and r['symbol'] in targets for r in records),
             'Unexpected relocation in migrated native.S')
    assigned = {name: definitions[name] for name in sorted(exports)}
    for name, rva in assigned.items():
        _require(BASE <= rva < BASE + len(code) and rva % 4 == 0 and
                 struct.unpack_from('<I', code, rva - BASE)[0] == 0xD503237F,
                 'Missing original PAC prologue: ' + name)
    local = {name: definitions['STHCoreLocal_' + name] for name in callbacks}
    _require(all(struct.unpack_from('<I', code, rva - BASE)[0] == 0xD503237F
                 for rva in local.values()), 'Missing local callback PAC prologue')
    base_loads = 0
    for pos in range(0, len(code), 4):
        word = struct.unpack_from('<I', code, pos)[0]
        if word & 0x9F000000 != 0x10000000:
            continue
        imm = ((word >> 29) & 3) | (((word >> 5) & 0x7FFFF) << 2)
        target = BASE + pos + _signed(imm, 21)
        if target == BASE:
            reg = word & 31
            expected = (0xD1400000 | ((BASE >> 12) << 10) | (reg << 5) | reg,
                        0xD1000000 | ((BASE & 4095) << 10) | (reg << 5) | reg)
            _require(pos + 12 <= len(code) and
                     struct.unpack_from('<2I', code, pos + 4) == expected,
                     'Invalid emitted core-base derivation')
            base_loads += 1
        else:
            _require(target in local.values(), 'Unrecognized ADR target')
    result = bytearray(original)
    result[offset:offset + len(code)] = code
    _require(result[:offset] == original[:offset] and
             result[offset + len(code):] == original[offset + len(code):],
             'Migration changed bytes outside its code range')
    meta = {'base': BASE, 'limit': LIMIT, 'capacity': CAPACITY, 'size': len(code),
            'end': BASE + len(code), 'file_offset': offset, 'exports': assigned,
            'callbacks': local, 'original_callbacks': {'dock': 0x4D4C4, 'initializer': 0x4FF20},
            'base_loads': base_loads, 'source_base_load_pairs': loads, 'direct_calls': records,
            'source_sha256': SOURCE_SHA256,
            'code_sha256': hashlib.sha256(code).hexdigest(), 'stub_source': str(stubpath)}
    stubpath.write_text(_stubs(assigned))
    manifest.write_text(json.dumps(meta, indent=2, sort_keys=True) + '\n')
    return result, meta, stubpath
