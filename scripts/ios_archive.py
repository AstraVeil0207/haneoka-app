"""Read distribution metadata and declared permissions from a real IPA."""
import plistlib
import struct
import zipfile


def entitlements(binary):
    magic = binary[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = magic == b'\xca\xfe\xba\xbf'
        count = struct.unpack_from('>I', binary, 4)[0]
        result = set()
        for index in range(count):
            entry = 8 + index * (32 if wide else 20)
            offset, size = struct.unpack_from('>QQ' if wide else '>II', binary, entry + 8)
            result.update(entitlements(binary[offset:offset + size]))
        return result
    formats = {b'\xcf\xfa\xed\xfe': ('<', 32), b'\xce\xfa\xed\xfe': ('<', 28),
               b'\xfe\xed\xfa\xcf': ('>', 32), b'\xfe\xed\xfa\xce': ('>', 28)}
    if magic not in formats:
        raise ValueError('An IPA bundle executable is not a supported Mach-O file')
    endian, cursor = formats[magic]
    count = struct.unpack_from(endian + 'I', binary, 16)[0]
    result = set()
    for _ in range(count):
        command, length = struct.unpack_from(endian + 'II', binary, cursor)
        if length < 8 or cursor + length > len(binary):
            raise ValueError('Invalid Mach-O load command')
        if command == 0x1d:
            offset, size = struct.unpack_from(endian + 'II', binary, cursor + 8)
            signature = binary[offset:offset + size]
            if len(signature) != size or size < 12:
                raise ValueError('Invalid code signature size')
            marker, total, slots = struct.unpack_from('>III', signature)
            if marker != 0xfade0cc0 or total > size:
                raise ValueError('Unsupported code signature container')
            has_xml = has_der = False
            for index in range(slots):
                kind, start = struct.unpack_from('>II', signature, 12 + index * 8)
                if kind not in (5, 7):
                    continue
                blob_magic, blob_size = struct.unpack_from('>II', signature, start)
                if blob_size < 8 or start + blob_size > total:
                    raise ValueError('Invalid entitlement blob')
                if kind == 5 and blob_magic == 0xfade7171:
                    declared = plistlib.loads(signature[start + 8:start + blob_size])
                    if not isinstance(declared, dict):
                        raise ValueError('Entitlements must be a dictionary')
                    result.update(declared)
                    has_xml = True
                if kind == 7:
                    has_der = True
            if has_der and not has_xml:
                raise ValueError('DER-only entitlements require an XML entitlement export before release')
        cursor += length
    return result


def read_ipa(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        root = [name for name in names if name.startswith('Payload/')
                and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(root) != 1:
            raise ValueError('An IPA must contain exactly one main app')
        info = plistlib.loads(archive.read(root[0]))
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('The IPA must contain a device build for iPhoneOS')
        declared = set()
        privacy = {}
        for name in names:
            if not name.startswith('Payload/') or not name.endswith(('.app/Info.plist', '.appex/Info.plist')):
                continue
            bundle = plistlib.loads(archive.read(name))
            executable = bundle.get('CFBundleExecutable')
            if not executable:
                raise ValueError('An IPA app bundle has no executable')
            declared.update(entitlements(archive.read(name.rsplit('/', 1)[0] + '/' + executable)))
            for key, value in bundle.items():
                if key.startswith('NS') and 'UsageDescription' in key:
                    if key in privacy and privacy[key] != value:
                        raise ValueError('Conflicting privacy descriptions between app and extensions')
                    privacy[key] = value
        declared.difference_update({'application-identifier', 'com.apple.developer.team-identifier'})
        return info, {'entitlements': sorted(declared), 'privacy': privacy}
