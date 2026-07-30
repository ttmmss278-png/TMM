@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title TMM BioSeq Engine Quick Start

set "ARG=%~1"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP=%ROOT%\app"
set "FIXED=%ROOT%\BioSeq_Quick_Start.bat"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\quick_start.log"
set "SERVER=%APP%\backend\BioSeq_Server_v140.py"
set "PY_PORTABLE=%ROOT%\portable_python\python.exe"
set "PY_VENV=%ROOT%\runtime\venv\Scripts\python.exe"
set "STATUS_URL=http://127.0.0.1:8765/status"
set "EXPECTED_VERSION=1.4.0"
set "ENGINE_CMD=%ROOT%\run_engine_v140.cmd"
set "PROTOCOL_MODE=0"

echo(%ARG%| findstr /I /B /C:"bioseq://" >nul 2>&1
if not errorlevel 1 set "PROTOCOL_MODE=1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
>"%LOG%" echo [%date% %time%] BioSeq quick start

if /I not "%~f0"=="%FIXED%" copy /Y "%~f0" "%FIXED%" >nul 2>&1
call :register_protocol

call :engine_ready
if not errorlevel 1 (
    if "%PROTOCOL_MODE%"=="0" (
        echo BioSeq Engine v1.4.0 已经在运行。
        timeout /t 2 /nobreak >nul
    )
    exit /b 0
)

if not exist "%SERVER%" (
    if "%PROTOCOL_MODE%"=="0" (
        echo [错误] 未找到便携后端：
        echo %SERVER%
        echo 请先运行离线工具包中的 Install_TMM_BioSeq_Portable.bat。
        pause
    )
    exit /b 2
)

set "PYTHON="
if exist "%PY_PORTABLE%" set "PYTHON=%PY_PORTABLE%"
if not defined PYTHON if exist "%PY_VENV%" set "PYTHON=%PY_VENV%"
if not defined PYTHON (
    if "%PROTOCOL_MODE%"=="0" (
        echo [错误] 未找到便携 Python 运行环境。
        echo 请先运行离线工具包中的 Install_TMM_BioSeq_Portable.bat。
        pause
    )
    exit /b 3
)

for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do (
    taskkill /PID %%P /F >>"%LOG%" 2>&1
)
timeout /t 1 /nobreak >nul

>"%ENGINE_CMD%" echo @echo off
>>"%ENGINE_CMD%" echo cd /d "%APP%"
>>"%ENGINE_CMD%" echo "%PYTHON%" "%SERVER%" 1^>^>"%LOG%" 2^>^&1
start "TMM BioSeq Engine v1.4.0" /min "%ComSpec%" /c call "%ENGINE_CMD%"

for /L %%I in (1,1,15) do (
    call :engine_ready
    if not errorlevel 1 (
        if "%PROTOCOL_MODE%"=="0" (
            echo BioSeq Engine v1.4.0 已启动。
            timeout /t 2 /nobreak >nul
        )
        exit /b 0
    )
    timeout /t 1 /nobreak >nul
)

if "%PROTOCOL_MODE%"=="0" (
    echo [错误] 引擎未在 15 秒内启动。
    echo 日志：%LOG%
    if exist "%LOG%" type "%LOG%"
    pause
)
exit /b 4

:engine_ready
set "STATUS_ENV=%STATUS_URL%"
set "VERSION_ENV=%EXPECTED_VERSION%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$s=Invoke-RestMethod -Uri $env:STATUS_ENV -TimeoutSec 2;if([string]$s.version -eq $env:VERSION_ENV){exit 0}}catch{};exit 1" >nul 2>&1
exit /b %ERRORLEVEL%

:register_protocol
if not exist "%FIXED%" exit /b 0
set "FIXED_ENV=%FIXED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34;$pct=[char]37;$root='HKCU:\Software\Classes\bioseq';New-Item -Path $root -Force|Out-Null;Set-Item -Path $root -Value 'URL:TMM BioSeq Quick Start';New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null;$key=Join-Path $root 'shell\open\command';New-Item -Path $key -Force|Out-Null;$cmd=$q+$env:ComSpec+$q+' /d /c '+$q+$q+$env:FIXED_ENV+$q+' '+$q+$pct+'1'+$q+$q;Set-Item -Path $key -Value $cmd" >>"%LOG%" 2>&1
exit /b 0
