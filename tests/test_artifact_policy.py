"""Validate the actual DEB, not just compiler flags or source substrings."""
from pathlib import Path, PurePosixPath
import copy
import hashlib
import io
import json
import os
import re
import struct
import sys
import tarfile
from macho import commands

ROOT = Path(__file__).resolve().parent.parent


def deb_members(raw):
    assert raw[:8] == b'!<arch>\n', 'invalid Debian archive'
    result, at = {}, 8
    while at < len(raw):
        header = raw[at:at + 60]
        assert len(header) == 60 and header[58:60] == b'`\n'
        length = int(header[48:58])
        name = header[:16].decode().strip().rstrip('/')
        data = raw[at + 60:at + 60 + length]
        assert len(data) == length
        if name.startswith('#1/'):
            count = int(name[3:])
            name, data = data[:count].rstrip(b'\0').decode(), data[count:]
        assert name not in result, 'duplicate ar member'
        result[name] = data
        at += 60 + length + (length & 1)
    assert at == len(raw) and result['debian-binary'] == b'2.0\n'
    return result


def tar_members(raw):
    files, metadata = {}, {}
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            if not member.isfile():
                continue
            name = str(path)
            assert name not in files, 'duplicate tar member'
            files[name] = archive.extractfile(member).read()
            metadata[name] = member
    return files, metadata


def deployment_target(image):
    versions = []
    for command, at, size in commands(image):
        if command == 0x32:
            platform, version = struct.unpack_from('<II', image, at + 8)
            assert platform == 2, 'non-device platform in the iOS package'
            versions.append(version)
        elif command == 0x25:
            versions.append(struct.unpack_from('<I', image, at + 8)[0])
    assert len(versions) == 1, 'missing or ambiguous deployment target'
    value = versions[0]
    return (value >> 16, (value >> 8) & 255, value & 255)


def code_signature_pages(image):
    signatures = [(at, size) for command, at, size in commands(image) if command == 0x1d]
    assert len(signatures) == 1, 'missing code signature'
    at, _ = signatures[0]
    start, reserved = struct.unpack_from('<II', image, at + 8)
    assert start + reserved <= len(image)
    magic, length, count = struct.unpack_from('>III', image, start)
    assert magic == 0xfade0cc0 and 12 + 8 * count <= length <= reserved
    checked = 0
    for index in range(count):
        slot, relative = struct.unpack_from('>II', image, start + 12 + index * 8)
        assert 12 + count * 8 <= relative <= length - 8
        blob = start + relative
        kind, blob_size = struct.unpack_from('>II', image, blob)
        assert relative + blob_size <= length
        if kind != 0xfade0c02:
            continue
        version, flags, hashes, identifier, special, pages, limit = struct.unpack_from('>7I', image, blob + 8)
        hash_size, hash_type, platform, shift = struct.unpack_from('4B', image, blob + 36)
        if version >= 0x20300 and blob_size >= 64:
            limit = max(limit, struct.unpack_from('>Q', image, blob + 56)[0])
        assert 0 < limit <= start and shift <= 20
        page_size = (1 << shift) if shift else limit
        assert pages == (limit + page_size - 1) // page_size
        assert hashes >= 44 + special * hash_size and hashes + pages * hash_size <= blob_size
        digest = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256, 4: hashlib.sha384}[hash_type]
        assert 0 < hash_size <= digest().digest_size
        for page in range(pages):
            data = image[page * page_size:min(limit, (page + 1) * page_size)]
            recorded = image[blob + hashes + page * hash_size:blob + hashes + (page + 1) * hash_size]
            assert recorded == digest(data).digest()[:hash_size], ('signature page mismatch', page)
        checked += 1
    assert checked, 'no CodeDirectory verified'
    return checked


def version_tuple(text):
    assert re.fullmatch(r'\d+\.\d+(?:\.\d+)?', text), ('invalid system version', text)
    parts = tuple(map(int, text.split('.')))
    return parts + (0,) * (3 - len(parts))


def validate_policy(manifest, data, control):
    fields = dict(line.split(': ', 1) for line in control['control'].decode().splitlines() if ': ' in line and not line[0].isspace())
    version = json.loads((ROOT / 'inputs/base-patched.json').read_text())['version']
    assert fields['Version'] == manifest['version'] == version, 'package version mismatch'
    assert fields['Architecture'] == 'iphoneos-arm64e'
    assert manifest['artifact'] == f'stheno_{version}_iphoneos-arm64e.deb'
    assert manifest['device_tested'] is False
    source = manifest.get('source_commit')
    if source is not None:
        assert re.fullmatch('[0-9a-f]{40}', source)
    if os.environ.get('GITHUB_SHA'):
        assert source == os.environ['GITHUB_SHA'], 'source commit mismatch'
    lower = re.findall(r'(?:^|,)\s*firmware\s*\(>=\s*([\d.]+)\)', fields['Depends'])
    assert len(lower) == 1, 'missing firmware lower bound'
    images = {name: blob for name, blob in data.items() if blob[:4] == b'\xcf\xfa\xed\xfe'}
    assert len(images) == 8, ('unexpected executable set', sorted(images))
    minimum = max(deployment_target(image) for image in images.values())
    assert version_tuple(lower[0]) == minimum, 'firmware lower bound disagrees with Mach-O targets'
    assert version_tuple(manifest['minimum_ios']) == minimum
    diagnostics = os.environ.get('STH_DIAGNOSTICS', '0') == '1'
    assert manifest['diagnostics_enabled'] is diagnostics, 'diagnostics mode mismatch'
    assert manifest['viewport_keyboard_rebuild']['device_diagnostics'] is diagnostics
    for script in ('preinst', 'postinst', 'postrm'):
        assert control[script] == (ROOT / 'installer' / script).read_bytes(), ('installer source mismatch', script)
    return images


def must_fail(call, text):
    try:
        call()
    except AssertionError as error:
        assert text in str(error), ('negative control failed for the wrong reason', error)
    else:
        raise AssertionError('negative control unexpectedly passed: ' + text)


def main():
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'build'
    manifest = json.loads((folder / 'build-manifest.json').read_text())
    filename = manifest['artifact']
    assert Path(filename).name == filename
    raw = (folder / filename).read_bytes()
    assert len(raw) == manifest['size'] and hashlib.sha256(raw).hexdigest() == manifest['sha256']
    archive = deb_members(raw)
    data, _ = tar_members(archive['data.tar.xz'])
    control, modes = tar_members(archive['control.tar.xz'])
    images = validate_policy(manifest, data, control)
    for name in ('preinst', 'postinst', 'postrm'):
        assert modes[name].mode & 0o777 == 0o755
    directories = sum(code_signature_pages(image) for image in images.values())
    # Negative controls mutate bytes in RAM, never the package or source files.
    bad_control = copy.copy(control)
    bad_control['control'] = re.sub(rb'firmware\s*\(>=\s*[\d.]+\)', b'firmware (>= 16.0)', control['control'])
    must_fail(lambda: validate_policy(manifest, data, bad_control), 'firmware lower bound')
    bad_manifest = copy.deepcopy(manifest)
    bad_manifest['diagnostics_enabled'] = not manifest['diagnostics_enabled']
    must_fail(lambda: validate_policy(bad_manifest, data, control), 'diagnostics')
    image = bytearray(images['Library/MobileSubstrate/DynamicLibraries/SthenoViewport.dylib'])
    image[0x5000] ^= 1
    must_fail(lambda: code_signature_pages(image), 'signature page mismatch')
    print('Artifact policy: matching source/version/deployment/diagnostics; 8 arm64e device images;',
          directories, 'CodeDirectory page sets valid; exact reviewed installer scripts; 3 in-memory negative controls rejected')


if __name__ == '__main__':
    main()
