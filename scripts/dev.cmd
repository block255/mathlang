@echo off
rem 数语引擎 · 双击启动开发实例（无需管理员）
rem 参数可传： -Device web   或  -Port 57134
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev_windows.ps1" %*
if errorlevel 1 (
  echo.
  echo [启动失败] 上面是错误信息，按任意键关闭…
  pause >nul
)
endlocal
