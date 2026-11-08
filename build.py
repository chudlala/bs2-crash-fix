"""Build dist/BS2CrashFix.rvdata2 from src/loader.rb + src/patch.rb.

The output is an RGSS3 script list holding ONE script (the loader with the
patch embedded). It contains no game code. Usage:  python build.py
"""
import pathlib
import zlib

VERSION = "1.0.0"
ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "dist" / "BS2CrashFix.rvdata2"


def marshal_long(x):
    if x == 0:
        return b"\0"
    if 0 < x < 123:
        return bytes([x + 5])
    if -124 < x < 0:
        return bytes([(x - 5) & 0xFF])
    raw = x.to_bytes((x.bit_length() + 7) // 8, "little")
    return bytes([len(raw)]) + raw


def build():
    patch = (ROOT / "src" / "patch.rb").read_text(encoding="utf-8").replace("\r\n", "\n")
    loader = (ROOT / "src" / "loader.rb").read_text(encoding="utf-8").replace("\r\n", "\n")
    assert "BS2FIX_PATCH_EOF" not in patch
    patch.encode("ascii")  # keep the patch ASCII-only
    code = loader.replace("__PATCH_SOURCE__", patch.rstrip("\n")).replace("__VERSION__", VERSION)
    name = f"BS2 Crash Fix Loader {VERSION}".encode()
    blob = zlib.compress(code.encode("utf-8"), 9)
    # [[0, "name", "zlib code"]] -- strings tagged UTF-8 (:E => true)
    data = (b"\x04\x08[\x06[\x08i\x00"
            + b'I"' + marshal_long(len(name)) + name + b"\x06:\x06ET"
            + b'I"' + marshal_long(len(blob)) + blob + b"\x06;\x00T")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_bytes(data)
    print(f"wrote {OUT} ({len(data)} bytes, loader+patch {len(code)} chars)")


if __name__ == "__main__":
    build()
