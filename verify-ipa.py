import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


path = Path(sys.argv[1])
digest = hashlib.sha256(path.read_bytes()).hexdigest()
with zipfile.ZipFile(path) as package:
    infos = [n for n in package.namelist() if n.count("/") == 2 and n.endswith(".app/Info.plist")]
    assert len(infos) == 1, "Expected one main app"
    root = infos[0].removesuffix("Info.plist")
    info = plistlib.loads(package.read(infos[0]))
    binary = package.read(root + info["CFBundleExecutable"])
    magic, cpu, subtype, filetype, commands, size, flags, reserved = struct.unpack_from("<8I", binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, "Expected ARM64 Mach-O executable"
    assert info["MinimumOSVersion"] == "26.0", "Unexpected minimum iOS"
    offset = 32
    build = None
    encrypted = None
    for _ in range(commands):
        command, length = struct.unpack_from("<II", binary, offset)
        assert length >= 8 and offset + length <= len(binary), "Invalid Mach-O command"
        if command == 0x32:
            platform, minimum, sdk = struct.unpack_from("<III", binary, offset + 8)
            version = lambda value: f"{value >> 16}.{(value >> 8) & 255}.{value & 255}"
            build = {"platform": platform, "minimum": version(minimum), "sdk": version(sdk)}
        elif command in (0x21, 0x2C):
            encrypted = struct.unpack_from("<I", binary, offset + 16)[0]
        offset += length
    assert build and build["platform"] == 2 and build["minimum"] == "26.0.0", "Expected real iOS target"
    assert encrypted in (None, 0), "Executable is encrypted"
    assert b"--ui-preview" not in binary, "Debug fixture in Release IPA"
    assert b"--ui-layout-clean" not in binary, "Debug layout flag in Release IPA"
    assert b"--ui-battery-discharge" not in binary, "Debug battery fixture in Release IPA"
    assert b"--ui-history-slow" not in binary, "Debug history delay in Release IPA"
    assert b"--ui-energy-empty" not in binary and b"--ui-energy-error" not in binary, "Debug energy fixture in Release IPA"
    assert not any(n.endswith((".p12", ".key", "ha-session.json")) for n in package.namelist()), "Private material in IPA"
    print(json.dumps({
        "file": str(path), "bytes": path.stat().st_size, "sha256": digest,
        "bundle_id": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "name": info.get("CFBundleDisplayName"), "minimum_ios": info["MinimumOSVersion"],
        "architecture": "ARM64", "build": build, "encrypted": bool(encrypted),
        "debug_fixtures": False, "entries": len(package.namelist()),
    }, indent=2))
