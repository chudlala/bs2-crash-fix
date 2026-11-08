<# : BS2 Crash Fix installer -- double-click to run
@echo off
setlocal
set "BS2_SELF=%~f0"
set "BS2_MODE=install"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText($env:BS2_SELF))"
echo.
pause
exit /b
#>

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $env:BS2_SELF
$mode = $env:BS2_MODE
$patchName = 'BS2CrashFix.patch'
$recordName = 'Game.rgss3a.bs2fix'
$latin1 = [Text.Encoding]::GetEncoding(28591)

# RGSS3 only loads the script list from inside Game.rgss3a, so the fix is
# applied there: the patched script list is appended to the end of the archive
# and the Data\Scripts.rvdata2 table entry is pointed at it. Nothing else in
# the archive moves. Uninstall restores the entry and trims the file, which
# gives back the original archive byte for byte.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;

public static class BS2Archive
{
    public class Entry { public long TablePos; public uint Offset, Size, FileKey, TableKey; }

    public static Entry FindScripts(string path)
    {
        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            BinaryReader br = new BinaryReader(fs);
            byte[] magic = br.ReadBytes(8);
            if (magic.Length != 8 || Encoding.ASCII.GetString(magic, 0, 6) != "RGSSAD" || magic[6] != 0 || magic[7] != 3)
                throw new Exception("Game.rgss3a is not an RGSS3 archive.");
            uint key = unchecked(br.ReadUInt32() * 9u + 3u);
            while (true)
            {
                long pos = fs.Position;
                uint off = br.ReadUInt32() ^ key, size = br.ReadUInt32() ^ key;
                uint fkey = br.ReadUInt32() ^ key, nlen = br.ReadUInt32() ^ key;
                if (off == 0) break;
                if (nlen > 4096) throw new Exception("Game.rgss3a file table looks damaged.");
                byte[] name = br.ReadBytes((int)nlen);
                for (int i = 0; i < name.Length; i++) name[i] ^= (byte)(key >> (8 * (i % 4)));
                string n = Encoding.UTF8.GetString(name).Replace('/', '\\');
                if (string.Equals(n, "Data\\Scripts.rvdata2", StringComparison.OrdinalIgnoreCase))
                {
                    Entry e = new Entry();
                    e.TablePos = pos; e.Offset = off; e.Size = size; e.FileKey = fkey; e.TableKey = key;
                    return e;
                }
            }
        }
        throw new Exception("Data\\Scripts.rvdata2 was not found inside Game.rgss3a.");
    }

    public static byte[] Crypt(byte[] data, uint fkey)
    {
        byte[] o = new byte[data.Length];
        uint k = fkey;
        for (int i = 0; i < data.Length; i += 4)
        {
            for (int j = 0; j < 4 && i + j < data.Length; j++) o[i + j] = (byte)(data[i + j] ^ (byte)(k >> (8 * j)));
            k = unchecked(k * 7u + 3u);
        }
        return o;
    }

    static byte[] ReadAt(string path, long offset, int size)
    {
        using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            fs.Seek(offset, SeekOrigin.Begin);
            byte[] b = new byte[size];
            int got = 0;
            while (got < size) { int r = fs.Read(b, got, size - got); if (r <= 0) throw new Exception("Game.rgss3a ended early."); got += r; }
            return b;
        }
    }

    class MReader
    {
        public byte[] B; public int P; public byte[] LastStr; public string FirstSym;
        public MReader(byte[] b, int p) { B = b; P = p; }
        public int Long()
        {
            sbyte c = unchecked((sbyte)B[P++]);
            if (c == 0) return 0;
            if (c > 4) return c - 5;
            if (c < -4) return c + 5;
            int x = 0;
            if (c > 0) { for (int i = 0; i < c; i++) x |= B[P++] << (8 * i); return x; }
            x = -1;
            for (int i = 0; i < -c; i++) { x &= ~(0xff << (8 * i)); x |= B[P++] << (8 * i); }
            return x;
        }
        public void Skip()
        {
            byte t = B[P++];
            switch ((char)t)
            {
                case '0': case 'T': case 'F': return;
                case 'i': case ';': case '@': Long(); return;
                case ':': { int n = Long(); if (FirstSym == null) FirstSym = Encoding.UTF8.GetString(B, P, n); P += n; return; }
                case '"': { int n = Long(); LastStr = new byte[n]; Array.Copy(B, P, LastStr, 0, n); P += n; return; }
                case 'I': { Skip(); int n = Long(); for (int i = 0; i < n; i++) { Skip(); Skip(); } return; }
                case '[': { int n = Long(); for (int i = 0; i < n; i++) Skip(); return; }
                default: throw new Exception("Unexpected data in the game's script list (type " + t + ").");
            }
        }
    }

    static byte[] MarshalLong(int x)
    {
        if (x == 0) return new byte[] { 0 };
        if (x > 0 && x < 123) return new byte[] { (byte)(x + 5) };
        if (x >= 123 && x <= 0xFF) return new byte[] { 1, (byte)x };
        if (x > 0xFF && x <= 0xFFFF) return new byte[] { 2, (byte)x, (byte)(x >> 8) };
        throw new Exception("Too many scripts.");
    }

    // Returns the game's script list with the patch script inserted right before "Main".
    public static byte[] Splice(byte[] s, byte[] patch)
    {
        if (s.Length < 3 || s[0] != 4 || s[1] != 8 || s[2] != (byte)'[') throw new Exception("The game's script list has an unexpected format.");
        MReader r = new MReader(s, 3);
        int n = r.Long(), headerEnd = r.P, mainStart = -1, lastStart = -1;
        for (int i = 0; i < n; i++)
        {
            int start = r.P;
            if (s[r.P++] != (byte)'[') throw new Exception("The game's script list has an unexpected format.");
            int m = r.Long();
            if (m < 3) throw new Exception("The game's script list has an unexpected format.");
            r.Skip();
            r.LastStr = null; r.Skip();
            string name = r.LastStr == null ? "" : Encoding.UTF8.GetString(r.LastStr);
            for (int k = 2; k < m; k++) r.Skip();
            if (name.StartsWith("BS2 Crash Fix")) throw new Exception("ALREADY_PATCHED");
            if (name == "Main") mainStart = start;
            lastStart = start;
        }
        if (r.P != s.Length) throw new Exception("The game's script list has an unexpected format.");
        if (r.FirstSym != "E") throw new Exception("The game's script list has an unexpected format (encoding tag).");
        if (mainStart < 0) mainStart = lastStart;
        MemoryStream o = new MemoryStream();
        o.Write(new byte[] { 4, 8, (byte)'[' }, 0, 3);
        byte[] cnt = MarshalLong(n + 1); o.Write(cnt, 0, cnt.Length);
        o.Write(s, headerEnd, mainStart - headerEnd);
        o.Write(patch, 0, patch.Length);
        o.Write(s, mainStart, s.Length - mainStart);
        return o.ToArray();
    }

    static void WriteEntry(FileStream fs, Entry e, uint offset, uint size)
    {
        fs.Seek(e.TablePos, SeekOrigin.Begin);
        byte[] a = BitConverter.GetBytes(offset ^ e.TableKey), b = BitConverter.GetBytes(size ^ e.TableKey);
        fs.Write(a, 0, 4); fs.Write(b, 0, 4);
    }

    public static void Install(string archive, byte[] patch, string recordPath)
    {
        Entry e = FindScripts(archive);
        long length = new FileInfo(archive).Length;
        byte[] plain = Crypt(ReadAt(archive, e.Offset, (int)e.Size), e.FileKey);
        byte[] enc = Crypt(Splice(plain, patch), e.FileKey);
        if (length + enc.Length > uint.MaxValue) throw new Exception("Game.rgss3a is too large to patch.");
        File.WriteAllText(recordPath, string.Format(
            "BS2 Crash Fix archive patch. Used by uninstall.bat; don't edit.\r\nlength={0}\r\ntablepos={1}\r\noffset={2}\r\nsize={3}\r\nnewsize={4}\r\n",
            length, e.TablePos, e.Offset, e.Size, enc.Length));
        using (FileStream fs = new FileStream(archive, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            fs.Seek(length, SeekOrigin.Begin);
            fs.Write(enc, 0, enc.Length);
            fs.Flush(true);
            WriteEntry(fs, e, (uint)length, (uint)enc.Length);
            fs.Flush(true);
        }
    }

    // Returns true if the archive was restored, false if it had already been replaced (e.g. by a Steam update).
    public static bool Uninstall(string archive, string recordPath)
    {
        long length = 0, tablePos = 0, offset = 0, size = 0, newSize = 0;
        foreach (string line in File.ReadAllLines(recordPath))
        {
            string[] kv = line.Split('=');
            if (kv.Length != 2) continue;
            long v = long.Parse(kv[1].Trim());
            switch (kv[0].Trim())
            {
                case "length": length = v; break;
                case "tablepos": tablePos = v; break;
                case "offset": offset = v; break;
                case "size": size = v; break;
                case "newsize": newSize = v; break;
            }
        }
        Entry e = FindScripts(archive);
        long current = new FileInfo(archive).Length;
        if (e.TablePos != tablePos || e.Offset != length || e.Size != newSize || current != length + newSize) return false;
        using (FileStream fs = new FileStream(archive, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            WriteEntry(fs, e, (uint)offset, (uint)size);
            fs.SetLength(length);
            fs.Flush(true);
        }
        return true;
    }
}
'@

function Test-GameDir($dir) {
    $dir -and (Test-Path -LiteralPath (Join-Path $dir 'Game.exe')) -and
        (Test-Path -LiteralPath (Join-Path $dir 'Game.ini')) -and
        (Test-Path -LiteralPath (Join-Path $dir 'Game.rgss3a'))
}

function Find-GameDir {
    if (Test-GameDir $here) { return $here }
    $steamRoots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($name in 'SteamPath', 'InstallPath') {
                if ($item.$name) { $steamRoots += ($item.$name -replace '/', '\') }
            }
        } catch {}
    }
    $steamRoots += "${env:ProgramFiles(x86)}\Steam"
    $libraries = @()
    foreach ($root in ($steamRoots | Select-Object -Unique)) {
        $libraries += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"(?:path|\d+)"\s+"([A-Za-z]:[^"]+)"')) {
                $libraries += $m.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $dir = Join-Path $lib 'steamapps\common\BLACK SOULS II'
        if (Test-GameDir $dir) { return $dir }
    }
    Write-Host "Couldn't find BLACK SOULS II automatically."
    Write-Host "In Steam: right-click the game > Manage > Browse local files, copy the folder path,"
    $dir = (Read-Host "and paste it here, then press Enter").Trim().Trim('"')
    if (Test-GameDir $dir) { return $dir }
    throw "That folder doesn't contain Game.exe, Game.ini and Game.rgss3a."
}

# v1.0.0 changed Game.ini instead (which the engine ignores). Undo that.
function Undo-V100($game) {
    $ini = Join-Path $game 'Game.ini'
    $iniBackup = Join-Path $game 'Game.ini.bs2fix-backup'
    if (Test-Path -LiteralPath $iniBackup) {
        Copy-Item -LiteralPath $iniBackup -Destination $ini -Force
        Remove-Item -LiteralPath $iniBackup
    } else {
        $text = [IO.File]::ReadAllText($ini, $latin1)
        if ($text -match '(?m)^Scripts=BS2CrashFix') {
            $text = [regex]::Replace($text, '(?m)^Scripts=[^\r\n]*', 'Scripts=Data\Scripts.rvdata2')
            [IO.File]::WriteAllText($ini, $text, $latin1)
        }
    }
    $old = Join-Path $game 'BS2CrashFix.rvdata2'
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old }
}

try {
    $game = Find-GameDir
    Write-Host "Game folder: $game"
    $running = Get-Process -Name 'Game' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($game, [StringComparison]::OrdinalIgnoreCase) }
    if ($running) { throw "BLACK SOULS II is running. Close the game first, then run this again." }

    $archive = Join-Path $game 'Game.rgss3a'
    $record = Join-Path $game $recordName
    Undo-V100 $game

    if (Test-Path -LiteralPath $record) {
        [void][BS2Archive]::Uninstall($archive, $record)
        Remove-Item -LiteralPath $record
    }

    if ($mode -eq 'install') {
        $patchFile = Join-Path $here $patchName
        if (-not (Test-Path -LiteralPath $patchFile)) { throw "$patchName is missing. Keep it in the same folder as install.bat." }
        try {
            [BS2Archive]::Install($archive, [IO.File]::ReadAllBytes($patchFile), $record)
        } catch {
            if ($_.Exception.Message -match 'ALREADY_PATCHED') {
                throw "The game already contains a copy of the fix whose uninstall record is missing. In Steam, right-click the game > Properties > Installed Files > Verify integrity of game files, then run install.bat again."
            }
            throw
        }
        Write-Host ""
        Write-Host "Installed! Launch BLACK SOULS II from Steam as usual." -ForegroundColor Green
        Write-Host "To undo it, run uninstall.bat."
    } else {
        Write-Host ""
        Write-Host "Uninstalled. The game is back to normal." -ForegroundColor Green
    }
} catch {
    $msg = $_.Exception.Message
    if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
    Write-Host "Error: $msg" -ForegroundColor Red
    if ($msg -match 'denied|unauthori|being used') {
        Write-Host "Close the game, then right-click the .bat file and choose 'Run as administrator'."
    }
}
