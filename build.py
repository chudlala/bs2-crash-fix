"""Build the BS2 Crash Fix distribution.

  dist/BS2CrashFix.patch   src/patch.rb as one RGSS3 script-list entry
  dist/install.bat         generated from src/installer.ps1
  dist/uninstall.bat       generated from src/installer.ps1
  release/BS2CrashFix-vX.Y.Z.zip

The installer inserts BS2CrashFix.patch right before "Main" in the game's own
script list inside Game.rgss3a, on the player's machine. Nothing here contains
game code. Usage:  python build.py
"""
import pathlib
import zipfile
import zlib

VERSION = "1.0.1"
ROOT = pathlib.Path(__file__).resolve().parent
DIST = ROOT / "dist"
RELEASE = ROOT / "release"
PATCH = DIST / "BS2CrashFix.patch"

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
  1. Close the game.
  2. Extract this zip anywhere (Downloads is fine).
  3. Double-click install.bat, then play from Steam as usual.

The installer finds the game through Steam on its own. If it can't, it asks
you to paste the game folder (Steam: right-click the game > Manage > Browse
local files).

UNINSTALL
  Double-click uninstall.bat.

If Windows says "Windows protected your PC", click "More info" > "Run anyway".
If it says access is denied, right-click install.bat > Run as administrator.
After a game update or "Verify integrity of game files", run install.bat again.

Details, source and bug reports: https://github.com/chudlala/bs2-crash-fix
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


def build_patch():
    code = (ROOT / "src" / "patch.rb").read_text(encoding="utf-8").replace("\r\n", "\n")
    code.encode("ascii")  # keep the patch ASCII-only
    name = f"BS2 Crash Fix {VERSION}".encode()
    blob = zlib.compress(code.encode("utf-8"), 9)
    # One script-list entry: [0, "name", "zlib code"]. Strings are tagged UTF-8
    # via symlink ;0 (:E), which the game's script list always defines first;
    # the installer checks that before inserting.
    PATCH.write_bytes(b"[\x08i\x00"
                      + b'I"' + marshal_long(len(name)) + name + b"\x06;\x00T"
                      + b'I"' + marshal_long(len(blob)) + blob + b"\x06;\x00T")


def build_bats():
    body = (ROOT / "src" / "installer.ps1").read_text(encoding="utf-8")
    body.encode("ascii")
    for mode, title in (("install", "installer"), ("uninstall", "uninstaller")):
        (DIST / f"{mode}.bat").write_bytes(crlf(BAT_HEADER.format(mode=mode, title=title) + "\n" + body))


def build_zip():
    RELEASE.mkdir(exist_ok=True)
    out = RELEASE / f"BS2CrashFix-v{VERSION}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("install.bat", "uninstall.bat", PATCH.name):
            z.write(DIST / name, name)
        z.writestr("HOW TO INSTALL.txt", crlf(HOW_TO.format(version=VERSION)))
    return out


if __name__ == "__main__":
    DIST.mkdir(exist_ok=True)
    build_patch()
    build_bats()
    out = build_zip()
    for p in (PATCH, DIST / "install.bat", DIST / "uninstall.bat", out):
        print(f"{p.relative_to(ROOT)}  {p.stat().st_size} bytes")
