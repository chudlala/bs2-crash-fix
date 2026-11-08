"""Build the BS2 Crash Fix distribution.

  dist/BS2CrashFix.rvdata2   loader + patch (src/loader.rb + src/patch.rb)
  dist/install.bat           generated from src/installer.ps1
  dist/uninstall.bat         generated from src/installer.ps1
  release/BS2CrashFix-vX.Y.Z.zip

The .rvdata2 is an RGSS3 script list holding ONE script (the loader with the
patch embedded). It contains no game code. Usage:  python build.py
"""
import pathlib
import zipfile
import zlib

VERSION = "1.0.0"
ROOT = pathlib.Path(__file__).resolve().parent
DIST = ROOT / "dist"
RELEASE = ROOT / "release"
FIX = DIST / "BS2CrashFix.rvdata2"

BAT_HEADER = """<# : BS2 Crash Fix {title} -- double-click to run
@echo off
setlocal
set "BS2_SELF=%~f0"
set "BS2_MODE={mode}"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText($env:BS2_SELF))"
echo.
pause
exit /b
#>
"""

HOW_TO = """BS2 Crash Fix {version} (experimental)
=====================================

INSTALL
  1. Extract this zip anywhere (Downloads is fine).
  2. Double-click install.bat.
  3. Play from Steam as usual.

The installer finds the game through Steam on its own. If it can't, it asks
you to paste the game folder (Steam: right-click the game > Manage > Browse
local files).

UNINSTALL
  Double-click uninstall.bat.

If Windows says "Windows protected your PC", click "More info" > "Run anyway".
If it says access is denied, right-click install.bat > Run as administrator.

Details, source and bug reports: https://github.com/realchudlala/bs2-crash-fix
"""


def marshal_long(x):
    if x == 0:
        return b"\0"
    if 0 < x < 123:
        return bytes([x + 5])
    if -124 < x < 0:
        return bytes([(x - 5) & 0xFF])
    raw = x.to_bytes((x.bit_length() + 7) // 8, "little")
    return bytes([len(raw)]) + raw


def crlf(text):
    return text.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii")


def build_fix():
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
    FIX.write_bytes(data)


def build_bats():
    body = (ROOT / "src" / "installer.ps1").read_text(encoding="utf-8")
    for mode, title in (("install", "installer"), ("uninstall", "uninstaller")):
        (DIST / f"{mode}.bat").write_bytes(crlf(BAT_HEADER.format(mode=mode, title=title) + "\n" + body))


def build_zip():
    RELEASE.mkdir(exist_ok=True)
    out = RELEASE / f"BS2CrashFix-v{VERSION}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("install.bat", "uninstall.bat", "BS2CrashFix.rvdata2"):
            z.write(DIST / name, name)
        z.writestr("HOW TO INSTALL.txt", crlf(HOW_TO.format(version=VERSION)))
    return out


if __name__ == "__main__":
    DIST.mkdir(exist_ok=True)
    build_fix()
    build_bats()
    out = build_zip()
    for p in (FIX, DIST / "install.bat", DIST / "uninstall.bat", out):
        print(f"{p.relative_to(ROOT)}  {p.stat().st_size} bytes")
