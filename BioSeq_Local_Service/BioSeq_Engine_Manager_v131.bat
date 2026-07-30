@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "MODE_ARG=%~1"
set "SELF=%~f0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP=%ROOT%\app"
set "BACKEND=%APP%\backend"
set "RUNTIME=%ROOT%\runtime"
set "VENV=%RUNTIME%\venv"
set "VENV_PY=%VENV%\Scripts\python.exe"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\manager_v131.log"
set "ENGINE_OUT=%LOGDIR%\engine_v131_stdout.log"
set "ENGINE_ERR=%LOGDIR%\engine_v131_stderr.log"
set "FIXED=%ROOT%\BioSeq_Engine_Manager_v131.bat"
set "SERVER=%BACKEND%\BioSeq_Server_v131.py"
set "RUNNER=%BACKEND%\wgs_runner_v131.py"
set "REQ=%BACKEND%\requirements.txt"
set "STATUS_URL=http://127.0.0.1:8765/status"
set "ENV_URL=http://127.0.0.1:8765/environment"
set "EXPECTED_VERSION=1.3.1"
set "DISTRO=Ubuntu"
set "PROTOCOL=0"

echo(%MODE_ARG%| findstr /I /B /C:"bioseq://" >nul 2>&1
if not errorlevel 1 set "PROTOCOL=1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%APP%" mkdir "%APP%" >nul 2>&1
if not exist "%RUNTIME%" mkdir "%RUNTIME%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
>"%LOG%" echo [%date% %time%] TMM BioSeq Engine Manager v1.3.1
>>"%LOG%" echo Mode: %MODE_ARG%
>>"%LOG%" echo Launcher: %SELF%

if "%PROTOCOL%"=="0" (
    title TMM BioSeq Engine Manager v1.3.1
    echo =====================================================
    echo   TMM BioSeq Engine Manager v1.3.1
    echo =====================================================
    echo.
    echo 将检查并修复：引擎版本、Python、Flask、WSL 和 WGS 工具。
    echo.
)

call :register_protocol
if errorlevel 1 goto :failed
call :ensure_app
if errorlevel 1 goto :failed
if "%PROTOCOL%"=="0" echo [1/6] 正在同步 v1.3.1 后端...
call :update_core
if errorlevel 1 goto :failed
if "%PROTOCOL%"=="0" echo [2/6] 正在检查 Python 和 Flask...
call :ensure_python_environment
if errorlevel 1 goto :failed
if "%PROTOCOL%"=="0" echo [3/6] 正在检查 WGS 工具链...
call :wgs_tools_ready
if not errorlevel 1 goto :wgs_tools_confirmed
call :is_admin
if not errorlevel 1 goto :install_wgs_as_admin
if "%PROTOCOL%"=="0" echo 需要管理员权限安装 WSL/Ubuntu 和 WGS 工具。
call :elevate_manager
exit /b %ERRORLEVEL%

:install_wgs_as_admin
call :install_wgs_tools
if errorlevel 11 goto :restart_required
if errorlevel 10 goto :restart_required
if errorlevel 1 goto :failed

:wgs_tools_confirmed
call :wgs_tools_ready
if errorlevel 1 goto :failed
if "%PROTOCOL%"=="0" echo [4/6] 正在检查当前引擎版本...
call :engine_ready
if not errorlevel 1 goto :success
if "%PROTOCOL%"=="0" echo [5/6] 正在关闭旧引擎并启动 v1.3.1...
call :stop_engine
call :start_engine
if errorlevel 1 goto :failed
if "%PROTOCOL%"=="0" echo [6/6] 正在验证引擎和 WGS 环境...
for /L %%I in (1,1,180) do (
    call :engine_ready
    if not errorlevel 1 goto :success
    >nul 2>&1 ping 127.0.0.1 -n 2
)
echo [错误] v1.3.1 引擎未在规定时间内就绪。
goto :failed

:success
if "%PROTOCOL%"=="0" (
    echo.
    echo =====================================================
    echo 环境已就绪
    echo =====================================================
    echo BioSeq Engine：v1.3.1
    echo WGS 工具：fastp、BWA、samtools、bcftools
    echo 状态地址：%STATUS_URL%
    echo 环境地址：%ENV_URL%
    echo.
    echo 回到网页按 Ctrl+F5，页面应显示 v1.3.1 和 WSL/NATIVE。
    echo.
    pause
)
exit /b 0

:register_protocol
if /I not "%SELF%"=="%FIXED%" (
    copy /Y "%SELF%" "%FIXED%" >nul 2>&1
    if errorlevel 1 exit /b 1
)
if not exist "%FIXED%" exit /b 1
set "FIXED_ENV=%FIXED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$q=[char]34;$pct=[char]37;" ^
 "$root='HKCU:\Software\Classes\bioseq';" ^
 "New-Item -Path $root -Force|Out-Null;" ^
 "Set-Item -Path $root -Value 'URL:TMM BioSeq Engine Manager';" ^
 "New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null;" ^
 "$key=Join-Path $root 'shell\open\command';New-Item -Path $key -Force|Out-Null;" ^
 "$cmd=$q+$env:ComSpec+$q+' /d /c '+$q+$q+$env:FIXED_ENV+$q+' '+$q+$pct+'1'+$q+$q;" ^
 "Set-Item -Path $key -Value $cmd;" ^
 "$cfg='HKCU:\Software\TMMBioSeq';New-Item -Path $cfg -Force|Out-Null;" ^
 "Set-ItemProperty -Path $cfg -Name 'ManagerPath' -Value $env:FIXED_ENV" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:ensure_app
if exist "%APP%\backend\requirements.txt" exit /b 0
if "%PROTOCOL%"=="0" echo 未发现本机程序，正在下载 TMM...
set "ZIP=%TEMP%\TMMBioSeq_%RANDOM%_%RANDOM%.zip"
set "EXTRACT=%TEMP%\TMMBioSeq_extract_%RANDOM%_%RANDOM%"
set "ZIP_ENV=%ZIP%"
set "EXTRACT_ENV=%EXTRACT%"
set "APP_ENV=%APP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip' -OutFile $env:ZIP_ENV;" ^
 "Expand-Archive -LiteralPath $env:ZIP_ENV -DestinationPath $env:EXTRACT_ENV -Force;" ^
 "$src=Get-ChildItem -LiteralPath $env:EXTRACT_ENV -Directory|Where-Object{$_.Name -like 'TMM-*'}|Select-Object -First 1;" ^
 "if(-not $src){throw 'TMM directory missing'};" ^
 "Copy-Item -Path (Join-Path $src.FullName '*') -Destination $env:APP_ENV -Recurse -Force" >>"%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
del /q "%ZIP%" >nul 2>&1
rmdir /s /q "%EXTRACT%" >nul 2>&1
if not "%RC%"=="0" exit /b 1
if not exist "%APP%\backend\requirements.txt" exit /b 1
exit /b 0

:update_core
set "RAW=https://raw.githubusercontent.com/ttmmss278-png/TMM/main"
call :download_file "%RAW%/backend/BioSeq_Server_v131.py" "%SERVER%"
if errorlevel 1 exit /b 1
call :download_file "%RAW%/backend/wgs_runner_v131.py" "%RUNNER%"
if errorlevel 1 exit /b 1
call :download_file "%RAW%/backend/requirements.txt" "%REQ%"
if errorlevel 1 exit /b 1
findstr /C:"ENGINE_VERSION = \"1.3.1\"" "%SERVER%" >nul 2>&1
if errorlevel 1 exit /b 1
findstr /C:"Missing WGS tools:" "%RUNNER%" >nul 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:download_file
set "DL_URL=%~1"
set "DL_TARGET=%~2"
set "DL_TMP=%TEMP%\TMMBioSeq_download_%RANDOM%_%RANDOM%.tmp"
set "DL_URL_ENV=%DL_URL%"
set "DL_TARGET_ENV=%DL_TARGET%"
set "DL_TMP_ENV=%DL_TMP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "$parent=Split-Path -Parent $env:DL_TARGET_ENV;New-Item -ItemType Directory -Path $parent -Force|Out-Null;" ^
 "Invoke-WebRequest -UseBasicParsing -Uri $env:DL_URL_ENV -OutFile $env:DL_TMP_ENV;" ^
 "if((Get-Item -LiteralPath $env:DL_TMP_ENV).Length -lt 20){throw 'Empty download'};" ^
 "Move-Item -LiteralPath $env:DL_TMP_ENV -Destination $env:DL_TARGET_ENV -Force" >>"%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
del /q "%DL_TMP%" >nul 2>&1
if not "%RC%"=="0" exit /b 1
if not exist "%DL_TARGET%" exit /b 1
exit /b 0

:ensure_python_environment
if exist "%VENV_PY%" goto :check_python_packages
set "BASE_PY="
set "PY_PATH_FILE=%TEMP%\TMMBioSeq_python_%RANDOM%.txt"
del /q "%PY_PATH_FILE%" >nul 2>&1
where py >nul 2>&1
if not errorlevel 1 py -3 -c "import sys;print(sys.executable)" >"%PY_PATH_FILE%" 2>nul
for %%Z in ("%PY_PATH_FILE%") do if exist "%%~fZ" if %%~zZ EQU 0 del /q "%%~fZ" >nul 2>&1
if not exist "%PY_PATH_FILE%" (
    where python >nul 2>&1
    if not errorlevel 1 python -c "import sys;print(sys.executable)" >"%PY_PATH_FILE%" 2>nul
)
for %%Z in ("%PY_PATH_FILE%") do if exist "%%~fZ" if %%~zZ EQU 0 del /q "%%~fZ" >nul 2>&1
if exist "%PY_PATH_FILE%" (
    set /p BASE_PY=<"%PY_PATH_FILE%"
    del /q "%PY_PATH_FILE%" >nul 2>&1
)
if not defined BASE_PY if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "BASE_PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined BASE_PY (
    where winget >nul 2>&1
    if errorlevel 1 exit /b 1
    if "%PROTOCOL%"=="0" echo 未检测到 Python，正在安装 Python 3.12...
    winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
    if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "BASE_PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    if not defined BASE_PY if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "BASE_PY=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
)
if not defined BASE_PY exit /b 1
"%BASE_PY%" -m venv "%VENV%" >>"%LOG%" 2>&1
if errorlevel 1 exit /b 1
if not exist "%VENV_PY%" exit /b 1

:check_python_packages
"%VENV_PY%" -c "import flask,flask_cors,werkzeug" >nul 2>&1
if not errorlevel 1 exit /b 0
"%VENV_PY%" -m pip install --disable-pip-version-check -r "%REQ%" >>"%LOG%" 2>&1
if errorlevel 1 exit /b 1
"%VENV_PY%" -c "import flask,flask_cors,werkzeug" >nul 2>&1
exit /b %ERRORLEVEL%

:wgs_tools_ready
where fastp >nul 2>&1
if not errorlevel 1 (
    where bwa >nul 2>&1
    if not errorlevel 1 (
        where samtools >nul 2>&1
        if not errorlevel 1 exit /b 0
    )
)
where wsl.exe >nul 2>&1
if errorlevel 1 exit /b 1
call :resolve_distro
if errorlevel 1 exit /b 1
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1" >nul 2>&1
exit /b %ERRORLEVEL%

:resolve_distro
set "DISTRO_FILE=%TEMP%\TMMBioSeq_distro_%RANDOM%.txt"
set "DISTRO_OUTPUT=%DISTRO_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$items=@(wsl.exe -l -q 2>$null);$hit=$items|ForEach-Object{$_.Trim()}|Where-Object{$_ -like 'Ubuntu*'}|Select-Object -First 1;if($hit){$hit|Set-Content -LiteralPath $env:DISTRO_OUTPUT -Encoding ASCII;exit 0};exit 1" >nul 2>&1
set "RC=%ERRORLEVEL%"
if exist "%DISTRO_FILE%" (
    set /p DISTRO=<"%DISTRO_FILE%"
    del /q "%DISTRO_FILE%" >nul 2>&1
)
if not "%RC%"=="0" exit /b 1
reg add "HKCU\Software\TMMBioSeq" /v "WslDistro" /t REG_SZ /d "%DISTRO%" /f >nul
exit /b 0

:is_admin
net session >nul 2>&1
exit /b %ERRORLEVEL%

:elevate_manager
set "FIXED_ENV=%FIXED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$argument='/d /c \"\"'+$env:FIXED_ENV+'\" --admin-repair\"';" ^
 "$process=Start-Process -FilePath $env:ComSpec -ArgumentList $argument -Verb RunAs -PassThru -Wait;" ^
 "exit $process.ExitCode" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:install_wgs_tools
where wsl.exe >nul 2>&1
if errorlevel 1 exit /b 1
call :resolve_distro
if errorlevel 1 (
    echo 正在安装 WSL Ubuntu...
    wsl.exe --install -d Ubuntu --web-download --no-launch >>"%LOG%" 2>&1
    if errorlevel 1 wsl.exe --install -d Ubuntu --web-download >>"%LOG%" 2>&1
    if errorlevel 1 wsl.exe --install -d Ubuntu >>"%LOG%" 2>&1
    call :resolve_distro
    if errorlevel 1 (
        reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "TMMBioSeqResume" /t REG_SZ /d "\"%FIXED%\" --resume" /f >nul
        exit /b 10
    )
)
wsl.exe -d "%DISTRO%" -u root -- bash -lc "echo TMM_BIOSEQ_WSL_READY" >>"%LOG%" 2>&1
if errorlevel 1 (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "TMMBioSeqResume" /t REG_SZ /d "\"%FIXED%\" --resume" /f >nul
    exit /b 11
)
echo 正在安装 fastp、BWA、samtools 和 bcftools...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "set -e;export DEBIAN_FRONTEND=noninteractive;apt-get update;apt-get install -y software-properties-common;add-apt-repository -y universe;apt-get update;apt-get install -y fastp bwa samtools bcftools" >>"%LOG%" 2>&1
if errorlevel 1 exit /b 1
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp && command -v bwa && command -v samtools && command -v bcftools" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:engine_ready
set "EXPECTED_ENV_VERSION=%EXPECTED_VERSION%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "try{" ^
 "$status=(Invoke-WebRequest -UseBasicParsing -Uri $env:STATUS_URL -TimeoutSec 3).Content|ConvertFrom-Json;" ^
 "if($status.version -ne $env:EXPECTED_ENV_VERSION){exit 1};" ^
 "$environment=(Invoke-WebRequest -UseBasicParsing -Uri $env:ENV_URL -TimeoutSec 15).Content|ConvertFrom-Json;" ^
 "if($environment.wgs.ready -eq $true){exit 0}" ^
 "}catch{};exit 1" >nul 2>&1
exit /b %ERRORLEVEL%

:stop_engine
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do taskkill /PID %%P /F >>"%LOG%" 2>&1
>nul 2>&1 ping 127.0.0.1 -n 3
exit /b 0

:start_engine
if not exist "%VENV_PY%" exit /b 1
if not exist "%SERVER%" exit /b 1
del /q "%ENGINE_OUT%" "%ENGINE_ERR%" >nul 2>&1
set "START_PY=%VENV_PY%"
set "START_SERVER=%SERVER%"
set "START_APP=%APP%"
set "START_OUT=%ENGINE_OUT%"
set "START_ERR=%ENGINE_ERR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Start-Process -FilePath $env:START_PY -ArgumentList @($env:START_SERVER) -WorkingDirectory $env:START_APP -WindowStyle Hidden -RedirectStandardOutput $env:START_OUT -RedirectStandardError $env:START_ERR" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:restart_required
if "%PROTOCOL%"=="0" (
    echo.
    echo Windows 已启用 WSL/Ubuntu，但必须重启电脑才能继续。
    echo 已设置登录后自动续装。请现在重启电脑。
    echo.
    pause
)
exit /b 10

:failed
if "%PROTOCOL%"=="0" (
    echo.
    echo =====================================================
    echo 修复未完成
    echo =====================================================
    echo 管理器日志：%LOG%
    echo 引擎错误：%ENGINE_ERR%
    echo.
    if exist "%LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 45"
    if exist "%ENGINE_ERR%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%ENGINE_ERR%' -Tail 30"
    echo.
    pause
)
exit /b 1
