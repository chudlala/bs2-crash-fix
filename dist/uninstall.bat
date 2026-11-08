@echo off
setlocal
cd /d "%~dp0"
echo BS2 Crash Fix - uninstaller
echo.
if not exist "Game.ini" (
  echo Put this file in the BLACK SOULS II folder, next to Game.exe, and run it there.
  goto :end
)
if exist "Game.ini.bs2fix-backup" (
  copy /y "Game.ini.bs2fix-backup" "Game.ini" >nul || goto :failed
  del "Game.ini.bs2fix-backup"
  echo Restored the original Game.ini.
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$e=[Text.Encoding]::GetEncoding(28591); $t=[IO.File]::ReadAllText('Game.ini',$e); $t=[regex]::Replace($t,'(?m)^Scripts=[^\r\n]*','Scripts=Data\Scripts.rvdata2'); [IO.File]::WriteAllText('Game.ini',$t,$e)" || goto :failed
  echo Game.ini set back to Scripts=Data\Scripts.rvdata2.
)
echo You can delete BS2CrashFix.rvdata2, install.bat and uninstall.bat now.
goto :end

:failed
echo Something went wrong. If it says access is denied, right-click
echo uninstall.bat and choose "Run as administrator".

:end
echo.
pause
