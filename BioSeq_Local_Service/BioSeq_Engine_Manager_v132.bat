@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title TMM BioSeq Engine Manager Launcher

set "MODE_ARG=%~1"
set "SELF=%~f0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "MANAGER_PS1=%ROOT%\BioSeq_Engine_Manager_v132.ps1"
set "TEMP_PS1=%TEMP%\BioSeq_Engine_Manager_v132_%RANDOM%_%RANDOM%.ps1"
set "MANAGER_URL=https://raw.githubusercontent.com/ttmmss278-png/TMM/main/BioSeq_Local_Service/BioSeq_Engine_Manager_v132.ps1"
set "LAUNCHER_LOG=%ROOT%\logs\launcher_v132.log"
set "PROTOCOL_MODE=0"

echo(%MODE_ARG%| findstr /I /B /C:"bioseq://" >nul 2>&1
if not errorlevel 1 set "PROTOCOL_MODE=1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs" >nul 2>&1
>"%LAUNCHER_LOG%" echo [%date% %time%] BioSeq manager launcher
>>"%LAUNCHER_LOG%" echo Self: %SELF%
>>"%LAUNCHER_LOG%" echo Mode: %MODE_ARG%

if "%PROTOCOL_MODE%"=="0" (
    echo =====================================================
    echo   TMM BioSeq Engine Manager Launcher
    echo =====================================================
    echo.
    echo 正在下载最新版管理器...
)

call :download_manager
if errorlevel 1 goto :download_failed

if "%PROTOCOL_MODE%"=="0" echo 正在启动环境检查和修复...
powershell -NoProfile -ExecutionPolicy Bypass -File "%MANAGER_PS1%" -ModeArg "%MODE_ARG%" -SelfBat "%SELF%"
set "MANAGER_EXIT=%ERRORLEVEL%"
>>"%LAUNCHER_LOG%" echo Manager exit code: %MANAGER_EXIT%

if "%PROTOCOL_MODE%"=="1" exit /b %MANAGER_EXIT%

echo.
if not "%MANAGER_EXIT%"=="0" (
    echo 管理器未成功完成，退出代码：%MANAGER_EXIT%
    echo 启动日志：%LAUNCHER_LOG%
    echo 管理器日志：%ROOT%\logs\manager_v132.log
    echo.
    if exist "%ROOT%\logs\manager_v132.log" (
        echo 最近的管理器日志：
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%ROOT%\logs\manager_v132.log' -Tail 30" 2>nul
        echo.
    )
) else (
    echo 管理器已正常完成。
)
echo 按任意键关闭此窗口...
pause >nul
exit /b %MANAGER_EXIT%

:download_manager
del /q "%TEMP_PS1%" >nul 2>&1
set "URL_ENV=%MANAGER_URL%"
set "TEMP_ENV=%TEMP_PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
 "Invoke-WebRequest -UseBasicParsing -Uri $env:URL_ENV -OutFile $env:TEMP_ENV" >>"%LAUNCHER_LOG%" 2>&1

if errorlevel 1 (
    >>"%LAUNCHER_LOG%" echo PowerShell download failed; trying curl.exe.
    where curl.exe >nul 2>&1
    if errorlevel 1 exit /b 1
    curl.exe -L --fail --retry 3 --connect-timeout 20 -o "%TEMP_PS1%" "%MANAGER_URL%" >>"%LAUNCHER_LOG%" 2>&1
    if errorlevel 1 exit /b 1
)

if not exist "%TEMP_PS1%" exit /b 1
for %%F in ("%TEMP_PS1%") do set "DOWNLOADED_SIZE=%%~zF"
if not defined DOWNLOADED_SIZE exit /b 1
if %DOWNLOADED_SIZE% LSS 5000 (
    >>"%LAUNCHER_LOG%" echo Downloaded manager is too small: %DOWNLOADED_SIZE% bytes.
    exit /b 1
)
move /Y "%TEMP_PS1%" "%MANAGER_PS1%" >>"%LAUNCHER_LOG%" 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:download_failed
>>"%LAUNCHER_LOG%" echo ERROR: Manager download failed.
if "%PROTOCOL_MODE%"=="1" exit /b 1
echo.
echo [错误] 无法下载 BioSeq Engine Manager。
echo 可能原因：代理、TLS、raw.githubusercontent.com 被拦截或网络中断。
echo 日志：%LAUNCHER_LOG%
echo.
if exist "%LAUNCHER_LOG%" type "%LAUNCHER_LOG%"
echo.
echo 按任意键关闭此窗口...
pause >nul
exit /b 1
