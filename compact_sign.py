"""Compact only trailing ad-hoc signature reservation; rehash the changed header pages."""
import hashlib, struct
from pathlib import Path

def compact_signature(path):
    path = Path(path); data = bytearray(path.read_bytes()); commands = struct.unpack_from('<I', data, 16)[0]
    pos = 32; signature = linkedit = None
    for _ in range(commands):
        cmd, size = struct.unpack_from('<II', data, pos)
        if cmd == 0x1d: signature = pos
        if cmd == 0x19 and bytes(data[pos+8:pos+24]).split(b'\0')[0] == b'__LINKEDIT': linkedit = pos
        pos += size
    assert signature is not None and linkedit is not None
    start, reserved = struct.unpack_from('<II', data, signature+8)
    magic, length, count = struct.unpack_from('>III', data, start)
    assert magic == 0xfade0cc0 and 12+count*8 <= length <= reserved and start+reserved == len(data)
    final = start + ((length+15)&~15)
    if final == len(data): return {'before': len(data), 'after': len(data), 'saved': 0}
    before = len(data); data = data[:final]
    struct.pack_into('<I', data, signature+12, final-start)
    fileoff = struct.unpack_from('<Q', data, linkedit+40)[0]
    filesize = final-fileoff
    struct.pack_into('<Q', data, linkedit+48, filesize)
    struct.pack_into('<Q', data, linkedit+32, (filesize+0x3fff)&~0x3fff)
    checked = 0
    for i in range(count):
        slot, offset = struct.unpack_from('>II', data, start+12+i*8)
        assert 12+count*8 <= offset < length
        blob = start+offset
        kind, size = struct.unpack_from('>II', data, blob)
        assert offset+size <= length
        if kind != 0xfade0c02: continue
        version, flags, hash_offset, identifier, special, pages, limit = struct.unpack_from('>7I', data, blob+8)
        hash_size, hash_type, platform, page_shift = struct.unpack_from('4B', data, blob+36)
        assert flags & 2, 'Only ad-hoc signatures are eligible'
        assert not flags & 0x10000, 'Do not alter runtime-hardened images'
        if version >= 0x20300 and limit == 0xffffffff: limit = struct.unpack_from('>Q', data, blob+56)[0]
        assert limit == start and pages == (limit+(1<<page_shift)-1)//(1<<page_shift)
        assert hash_offset+pages*hash_size <= size
        digest = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256, 4: hashlib.sha384}[hash_type]
        for page in range(pages):
            block = data[page*(1<<page_shift):min(limit,(page+1)*(1<<page_shift))]
            value = digest(block).digest()[:hash_size]
            at = blob+hash_offset+page*hash_size; data[at:at+hash_size] = value
        checked += 1
    assert checked
    path.write_bytes(data)
    return {'before': before, 'after': len(data), 'saved': before-len(data), 'code_directories': checked}

if __name__ == '__main__':
    import sys, json
    print(json.dumps({p: compact_signature(p) for p in sys.argv[1:]}, indent=2))
