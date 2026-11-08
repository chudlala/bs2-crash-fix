@echo off
setlocal
cd /d "%~dp0"
echo BS2 Crash Fix - installer
echo.
if not exist "Game.exe" goto :wrongfolder
if not exist "Game.ini" goto :wrongfolder
if not exist "BS2CrashFix.rvdata2" (
  echo BS2CrashFix.rvdata2 is missing. Copy it into this folder too.
  goto :end
)
if not exist "Game.ini.bs2fix-backup" (
  copy /y "Game.ini" "Game.ini.bs2fix-backup" >nul || goto :failed
  echo Backed up Game.ini to Game.ini.bs2fix-backup
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$e=[Text.Encoding]::GetEncoding(28591); $t=[IO.File]::ReadAllText('Game.ini',$e); if ($t -notmatch '(?m)^Scripts=') { exit 2 }; $t=[regex]::Replace($t,'(?m)^Scripts=[^\r\n]*','Scripts=BS2CrashFix.rvdata2'); [IO.File]::WriteAllText('Game.ini',$t,$e)" || goto :failed
echo Installed. Game.ini now loads BS2CrashFix.rvdata2.
echo Launch the game from Steam as usual. Run uninstall.bat to undo.
goto :end

:wrongfolder
echo Put this file in the BLACK SOULS II folder (next to Game.exe) and run it there.
echo Steam: right-click the game, Manage, Browse local files.
goto :end

:failed
echo Something went wrong and nothing was changed. If it says access is denied,
echo right-click install.bat and choose "Run as administrator".

:end
echo.
pause
