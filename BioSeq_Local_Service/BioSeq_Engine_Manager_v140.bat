@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title TMM BioSeq Engine Manager v1.4.0

set "SELF=%~f0"
set "FIRST_ARG=%~1"
set "SECOND_ARG=%~2"
set "MODE=%FIRST_ARG%"

if /I "%FIRST_ARG%"=="--admin" (
    set "MODE=%SECOND_ARG%"
    goto :admin_ready
)

net session >nul 2>&1
if errorlevel 1 (
    echo 正在请求管理员权限...
    set "SELF_ENV=%SELF%"
    set "MODE_ENV=%MODE%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$args=@('--admin');if($env:MODE_ENV){$args+=$env:MODE_ENV};$p=Start-Process -FilePath $env:SELF_ENV -ArgumentList $args -Verb RunAs -PassThru -Wait;exit $p.ExitCode"
    exit /b !ERRORLEVEL!
)

:admin_ready
set "PROTOCOL_MODE=0"
echo(!MODE!| findstr /I /B /C:"bioseq://" >nul 2>&1
if not errorlevel 1 set "PROTOCOL_MODE=1"

set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP=%ROOT%\app"
set "BACKEND=%APP%\backend"
set "RUNTIME=%ROOT%\runtime"
set "VENV=%RUNTIME%\venv"
set "VENV_PY=%VENV%\Scripts\python.exe"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\manager_v140.log"
set "ENGINE_OUT=%LOGDIR%\engine_v131_stdout.log"
set "ENGINE_ERR=%LOGDIR%\engine_v131_stderr.log"
set "ENGINE_CMD=%ROOT%\run_engine_v131.cmd"
set "FIXED=%ROOT%\BioSeq_Engine_Manager_v140.bat"
set "SERVER=%BACKEND%\BioSeq_Server_v131.py"
set "RUNNER=%BACKEND%\wgs_runner_v131.py"
set "REQ=%BACKEND%\requirements.txt"
set "STATUS_URL=http://127.0.0.1:8765/status"
set "ENV_URL=http://127.0.0.1:8765/environment"
set "EXPECTED_VERSION=1.3.1"
set "RAW_BASE=https://raw.githubusercontent.com/ttmmss278-png/TMM/main"
set "DISTRO="

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%APP%" mkdir "%APP%" >nul 2>&1
if not exist "%RUNTIME%" mkdir "%RUNTIME%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

>"%LOG%" echo [%date% %time%] TMM BioSeq Engine Manager v1.4.0
>>"%LOG%" echo Self: %SELF%
>>"%LOG%" echo Mode: %MODE%

if /I not "%SELF%"=="%FIXED%" copy /Y "%SELF%" "%FIXED%" >nul 2>&1
call :register_protocol

if "%PROTOCOL_MODE%"=="0" (
    echo =====================================================
    echo   TMM BioSeq Engine Manager v1.4.0
    echo =====================================================
    echo.
)

echo [1/7] 正在检查本地 BioSeq 程序...
call :ensure_app
if errorlevel 1 goto :failed

echo [2/7] 正在同步 BioSeq Engine v1.3.1 后端...
call :download_file "%RAW_BASE%/backend/BioSeq_Server_v131.py" "%SERVER%" 5000
if errorlevel 1 goto :failed
call :download_file "%RAW_BASE%/backend/wgs_runner_v131.py" "%RUNNER%" 5000
if errorlevel 1 goto :failed
call :download_file "%RAW_BASE%/backend/requirements.txt" "%REQ%" 20
if errorlevel 1 goto :failed

findstr /C:"ENGINE_VERSION = \"1.3.1\"" "%SERVER%" >nul 2>&1
if errorlevel 1 (
    echo [错误] 后端版本校验失败。
    goto :failed
)
findstr /C:"Missing WGS tools:" "%RUNNER%" >nul 2>&1
if errorlevel 1 (
    echo [错误] WGS 后端校验失败。
    goto :failed
)

echo [3/7] 正在检查 Python 和 Flask...
call :ensure_python
if errorlevel 1 goto :failed

echo [4/7] 正在检查 WSL Ubuntu...
call :detect_distro
if not defined DISTRO (
    echo 未发现可用的 Ubuntu，正在安装 WSL Ubuntu...
    call :install_ubuntu
    if errorlevel 1 goto :restart_required
    call :detect_distro
)
if not defined DISTRO goto :restart_required

>>"%LOG%" echo WSL distro: %DISTRO%
echo 已找到：%DISTRO%

echo [5/7] 正在检查 fastp、BWA、samtools 和 bcftools...
call :test_wgs_tools
if errorlevel 1 (
    echo 正在安装 WGS 工具，首次执行可能需要数分钟...
    call :install_wgs_tools
    if errorlevel 1 goto :failed
)
call :test_wgs_tools
if errorlevel 1 (
    echo [错误] 安装后仍未检测到完整 WGS 工具链。
    goto :failed
)

echo [6/7] 正在关闭旧引擎并启动 v1.3.1...
call :stop_engine
call :start_engine
if errorlevel 1 goto :failed

echo [7/7] 正在验证引擎和 WGS 环境...
set "ENGINE_READY=0"
for /L %%I in (1,1,180) do (
    call :test_engine_ready
    if not errorlevel 1 (
        set "ENGINE_READY=1"
        goto :engine_ready
    )
    timeout /t 1 /nobreak >nul
)

:engine_ready
if not "%ENGINE_READY%"=="1" (
    echo [错误] BioSeq Engine v1.3.1 未能完成启动验证。
    goto :failed
)

echo.
echo =====================================================
echo 环境已就绪
echo =====================================================
echo BioSeq Engine：v1.3.1
echo WGS 工具链：%DISTRO%
echo 状态地址：%STATUS_URL%
echo 环境地址：%ENV_URL%
echo.
echo 回到网页按 Ctrl+F5，页面应显示：
echo 分析引擎已连接 · v1.3.1 · WSL
echo.

if "%PROTOCOL_MODE%"=="1" exit /b 0
pause
exit /b 0

:ensure_app
if exist "%REQ%" if exist "%BACKEND%\file_scanner.py" if exist "%BACKEND%\r_runner.py" exit /b 0

echo 本机程序不完整，正在下载 TMM...
set "ZIP=%TEMP%\TMMBioSeq_%RANDOM%_%RANDOM%.zip"
set "EXTRACT=%TEMP%\TMMBioSeq_extract_%RANDOM%_%RANDOM%"
call :download_file "https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip" "%ZIP%" 1000
if errorlevel 1 exit /b 1

if exist "%EXTRACT%" rmdir /S /Q "%EXTRACT%" >nul 2>&1
mkdir "%EXTRACT%" >nul 2>&1
set "ZIP_ENV=%ZIP%"
set "EXTRACT_ENV=%EXTRACT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath $env:ZIP_ENV -DestinationPath $env:EXTRACT_ENV -Force" >>"%LOG%" 2>&1
if errorlevel 1 (
    where tar.exe >nul 2>&1
    if errorlevel 1 exit /b 1
    tar.exe -xf "%ZIP%" -C "%EXTRACT%" >>"%LOG%" 2>&1
    if errorlevel 1 exit /b 1
)

if not exist "%EXTRACT%\TMM-main" exit /b 1
xcopy "%EXTRACT%\TMM-main\*" "%APP%\" /E /I /Y /Q >>"%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
del /Q "%ZIP%" >nul 2>&1
rmdir /S /Q "%EXTRACT%" >nul 2>&1
if not "%RC%"=="0" if not "%RC%"=="1" exit /b 1
if not exist "%REQ%" exit /b 1
exit /b 0

:download_file
set "DL_URL=%~1"
set "DL_TARGET=%~2"
set "DL_MIN=%~3"
set "DL_TMP=%TEMP%\TMMBioSeq_download_%RANDOM%_%RANDOM%.tmp"
del /Q "!DL_TMP!" >nul 2>&1

where curl.exe >nul 2>&1
if not errorlevel 1 (
    curl.exe -L --fail --retry 3 --connect-timeout 25 -o "!DL_TMP!" "!DL_URL!" >>"%LOG%" 2>&1
)

if not exist "!DL_TMP!" (
    set "URL_ENV=!DL_URL!"
    set "TMP_ENV=!DL_TMP!"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;Invoke-WebRequest -UseBasicParsing -Uri $env:URL_ENV -OutFile $env:TMP_ENV" >>"%LOG%" 2>&1
)

if not exist "!DL_TMP!" (
    echo [错误] 下载失败：!DL_URL!
    exit /b 1
)

for %%Z in ("!DL_TMP!") do set "DL_SIZE=%%~zZ"
if !DL_SIZE! LSS !DL_MIN! (
    echo [错误] 下载文件不完整：!DL_URL!
    del /Q "!DL_TMP!" >nul 2>&1
    exit /b 1
)

for %%Z in ("!DL_TARGET!") do if not exist "%%~dpZ" mkdir "%%~dpZ" >nul 2>&1
move /Y "!DL_TMP!" "!DL_TARGET!" >>"%LOG%" 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:ensure_python
if exist "%VENV_PY%" goto :python_dependencies

set "PY_MODE="
set "PY_EXE="

where py.exe >nul 2>&1
if not errorlevel 1 (
    py -3 --version >nul 2>&1
    if not errorlevel 1 set "PY_MODE=launcher"
)

if not defined PY_MODE (
    where python.exe >nul 2>&1
    if not errorlevel 1 (
        python --version >nul 2>&1
        if not errorlevel 1 (
            set "PY_MODE=exe"
            set "PY_EXE=python"
        )
    )
)

if not defined PY_MODE (
    for %%P in (
        "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    ) do (
        if not defined PY_MODE if exist "%%~P" (
            set "PY_MODE=exe"
            set "PY_EXE=%%~P"
        )
    )
)

if not defined PY_MODE (
    where winget.exe >nul 2>&1
    if errorlevel 1 (
        echo [错误] 未检测到 Python，系统也没有 winget。
        exit /b 1
    )
    echo 未检测到 Python，正在安装 Python 3.12...
    winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements >>"%LOG%" 2>&1
    if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
        set "PY_MODE=exe"
        set "PY_EXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    )
)

if not defined PY_MODE (
    echo [错误] Python 安装或定位失败。
    exit /b 1
)

if /I "%PY_MODE%"=="launcher" (
    py -3 -m venv "%VENV%" >>"%LOG%" 2>&1
) else (
    "%PY_EXE%" -m venv "%VENV%" >>"%LOG%" 2>&1
)
if errorlevel 1 exit /b 1
if not exist "%VENV_PY%" exit /b 1

:python_dependencies
"%VENV_PY%" -c "import flask, flask_cors, werkzeug" >nul 2>&1
if errorlevel 1 (
    "%VENV_PY%" -m pip install --disable-pip-version-check -r "%REQ%" >>"%LOG%" 2>&1
    if errorlevel 1 (
        echo [错误] Flask 依赖安装失败。
        exit /b 1
    )
)
exit /b 0

:detect_distro
set "DISTRO="
for %%D in (Ubuntu Ubuntu-24.04 Ubuntu-22.04 Ubuntu-20.04) do (
    if not defined DISTRO (
        wsl.exe -d "%%D" -u root -- bash -lc "exit 0" 1>>"%LOG%" 2>>"%LOG%"
        if not errorlevel 1 set "DISTRO=%%D"
    )
)
exit /b 0

:install_ubuntu
where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] Windows 中没有 wsl.exe。
    exit /b 1
)

wsl.exe --install -d Ubuntu --web-download --no-launch >>"%LOG%" 2>&1
call :detect_distro
if defined DISTRO exit /b 0

wsl.exe --install -d Ubuntu --web-download >>"%LOG%" 2>&1
call :detect_distro
if defined DISTRO exit /b 0

wsl.exe --install -d Ubuntu >>"%LOG%" 2>&1
call :detect_distro
if defined DISTRO exit /b 0

exit /b 1

:test_wgs_tools
if not defined DISTRO exit /b 1
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 && command -v bcftools >/dev/null 2>&1" 1>>"%LOG%" 2>>"%LOG%"
exit /b %ERRORLEVEL%

:install_wgs_tools
set "APT_SCRIPT=unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; export DEBIAN_FRONTEND=noninteractive; apt-get update -o Acquire::Retries=3; apt-get install -y software-properties-common; add-apt-repository -y universe || true; apt-get update -o Acquire::Retries=3; apt-get install -y fastp bwa samtools bcftools"
wsl.exe -d "%DISTRO%" -u root -- bash -lc "%APT_SCRIPT%" 1>>"%LOG%" 2>>"%LOG%"
if errorlevel 1 (
    echo [错误] Ubuntu 安装 WGS 工具失败。
    echo 详细日志：%LOG%
    exit /b 1
)
exit /b 0

:stop_engine
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do (
    taskkill /PID %%P /F >>"%LOG%" 2>&1
)
timeout /t 2 /nobreak >nul
exit /b 0

:start_engine
>"%ENGINE_CMD%" echo @echo off
>>"%ENGINE_CMD%" echo cd /d "%APP%"
>>"%ENGINE_CMD%" echo "%VENV_PY%" "%SERVER%" 1^>^>"%ENGINE_OUT%" 2^>^>"%ENGINE_ERR%"
start "TMM BioSeq Engine v1.3.1" /min "%ComSpec%" /c call "%ENGINE_CMD%"
exit /b 0

:test_engine_ready
powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$s=Invoke-RestMethod -Uri $env:STATUS_URL -TimeoutSec 3;if([string]$s.version -ne $env:EXPECTED_VERSION){exit 1};$e=Invoke-RestMethod -Uri $env:ENV_URL -TimeoutSec 15;if($e.wgs.ready){exit 0}}catch{};exit 1" >nul 2>&1
exit /b %ERRORLEVEL%

:register_protocol
if not exist "%FIXED%" exit /b 0
set "FIXED_ENV=%FIXED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34;$pct=[char]37;$root='HKCU:\Software\Classes\bioseq';New-Item -Path $root -Force|Out-Null;Set-Item -Path $root -Value 'URL:TMM BioSeq Engine Manager';New-ItemProperty -Path $root -Name 'URL Protocol' -Value '' -PropertyType String -Force|Out-Null;$key=Join-Path $root 'shell\open\command';New-Item -Path $key -Force|Out-Null;$cmd=$q+$env:ComSpec+$q+' /d /c '+$q+$q+$env:FIXED_ENV+$q+' '+$q+$pct+'1'+$q+$q;Set-Item -Path $key -Value $cmd" >>"%LOG%" 2>&1
exit /b 0

:restart_required
echo.
echo =====================================================
echo Windows 需要重启
echo =====================================================
echo WSL Ubuntu 尚未完成初始化。
echo 请重启电脑，然后再次运行本 BAT。
echo.
echo 日志：%LOG%
if "%PROTOCOL_MODE%"=="1" exit /b 10
pause
exit /b 10

:failed
echo.
echo =====================================================
echo 修复未完成
echo =====================================================
echo 日志：%LOG%
echo 引擎错误：%ENGINE_ERR%
echo.
if exist "%LOG%" (
    echo 最近的管理器日志：
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 35" 2>nul
)
if exist "%ENGINE_ERR%" (
    echo.
    echo 最近的引擎错误：
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%ENGINE_ERR%' -Tail 25" 2>nul
)
echo.
if "%PROTOCOL_MODE%"=="1" exit /b 1
pause
exit /b 1
