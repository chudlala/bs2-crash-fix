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
$fixName = 'BS2CrashFix.rvdata2'
$latin1 = [Text.Encoding]::GetEncoding(28591)

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

function Set-ScriptsLine($ini, $value) {
    $text = [IO.File]::ReadAllText($ini, $latin1)
    if ($text -notmatch '(?m)^Scripts=') { throw "Game.ini has no Scripts= line." }
    $text = [regex]::Replace($text, '(?m)^Scripts=[^\r\n]*', "Scripts=$value")
    [IO.File]::WriteAllText($ini, $text, $latin1)
}

try {
    $game = Find-GameDir
    $ini = Join-Path $game 'Game.ini'
    $backup = Join-Path $game 'Game.ini.bs2fix-backup'
    Write-Host "Game folder: $game"
    if ($mode -eq 'install') {
        $src = Join-Path $here $fixName
        if (-not (Test-Path -LiteralPath $src)) { throw "$fixName is missing. Keep it in the same folder as install.bat." }
        if ($here -ne $game) { Copy-Item -LiteralPath $src -Destination (Join-Path $game $fixName) -Force }
        if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $ini -Destination $backup }
        Set-ScriptsLine $ini $fixName
        Write-Host ""
        Write-Host "Installed! Launch BLACK SOULS II from Steam as usual." -ForegroundColor Green
        Write-Host "To undo it, run uninstall.bat."
    } else {
        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $ini -Force
            Remove-Item -LiteralPath $backup
        } else {
            Set-ScriptsLine $ini 'Data\Scripts.rvdata2'
        }
        $fix = Join-Path $game $fixName
        if (Test-Path -LiteralPath $fix) { Remove-Item -LiteralPath $fix }
        Write-Host ""
        Write-Host "Uninstalled. The game is back to normal." -ForegroundColor Green
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'denied|unauthori') {
        Write-Host "Windows blocked the change. Right-click the .bat file and choose 'Run as administrator'."
    } else {
        Write-Host "Game.ini was not changed."
    }
}
