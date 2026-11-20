@echo off
chcp 65001 >nul
title TimesCam Host
cd /d "%~dp0"

if exist "TimesCamHost.exe" (
    start "" "TimesCamHost.exe"
    exit /b 0
)
if exist "dist\TimesCamHost.exe" (
    start "" "dist\TimesCamHost.exe"
    exit /b 0
)

where python >nul 2>nul
if errorlevel 1 (
    echo.
    echo   没有找到 TimesCamHost.exe，也没有找到 Python。
    echo   先执行 python build.py 打包，或安装 Python 3.9+ 后运行 python main.py。
    echo.
    pause
    exit /b 1
)

python main.py %*
if errorlevel 1 (
    echo.
    echo   启动失败，可以把上面的报错发给我。
    pause
)
