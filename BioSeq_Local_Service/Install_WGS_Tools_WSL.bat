@echo off
setlocal EnableExtensions
chcp 65001 >nul
title TMM BioSeq WGS 工具自动安装

set "DISTRO=Ubuntu"
set "AUTO_MODE=0"
if /I "%~1"=="--auto" set "AUTO_MODE=1"
if /I "%~1"=="--resume" set "AUTO_MODE=1"
set "BIOSEQ_ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP_DIR=%BIOSEQ_ROOT%\app"
set "BACKEND_FILE=%APP_DIR%\backend\wgs_runner.py"
set "FIXED_INSTALLER=%BIOSEQ_ROOT%\Install_WGS_Tools_WSL.bat"
set "RAW_BACKEND=https://raw.githubusercontent.com/ttmmss278-png/TMM/main/backend/wgs_runner.py"
set "LOG_DIR=%BIOSEQ_ROOT%\logs"
set "LOG_FILE=%LOG_DIR%\wgs_tools_install.log"

if not exist "%BIOSEQ_ROOT%" mkdir "%BIOSEQ_ROOT%" >nul 2>&1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1

if /I not "%~f0"=="%FIXED_INSTALLER%" (
    copy /Y "%~f0" "%FIXED_INSTALLER%" >nul 2>&1
)

net session >nul 2>&1
if errorlevel 1 (
    echo 正在请求管理员权限...
    set "INSTALLER_ARG=%~1"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$args=@();if($env:INSTALLER_ARG){$args+=$env:INSTALLER_ARG};$p=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('""'+$env:FIXED_INSTALLER+'" '+($args -join ' ')+'"')) -Verb RunAs -PassThru -Wait;exit $p.ExitCode"
    exit /b %ERRORLEVEL%
)

>"%LOG_FILE%" echo [%date% %time%] TMM BioSeq WGS tool installation
>>"%LOG_FILE%" echo Installer: %~f0

echo =====================================================
echo   TMM BioSeq WGS 分析工具自动安装
echo =====================================================
echo.
echo 将安装：
echo   fastp
echo   bwa
echo   samtools
echo   bcftools
echo.
echo 安装位置：Windows WSL / Ubuntu
echo.

where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] 当前 Windows 找不到 wsl.exe。
    echo 请确认系统为 Windows 10 2004 或更高版本，或者 Windows 11。
    goto :failed
)

call :check_distro
if not errorlevel 1 goto :distro_ready

echo [1/5] 未检测到 Ubuntu WSL，正在安装...
>>"%LOG_FILE%" echo Installing Ubuntu WSL.
wsl.exe --install -d "%DISTRO%" --web-download --no-launch >>"%LOG_FILE%" 2>&1
if errorlevel 1 wsl.exe --install -d "%DISTRO%" --web-download >>"%LOG_FILE%" 2>&1
if errorlevel 1 wsl.exe --install -d "%DISTRO%" >>"%LOG_FILE%" 2>&1

call :check_distro
if errorlevel 1 (
    echo.
    echo Windows 已开始安装 WSL，但必须重启电脑后才能继续。
    echo 本安装器已经设置为登录后自动继续。
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "TMMBioSeqWGSInstall" /t REG_SZ /d "\"%FIXED_INSTALLER%\" --resume" /f >nul
    echo.
    echo 请现在重启电脑。重启登录后会自动继续安装。
    echo.
    if "%AUTO_MODE%"=="0" pause
    exit /b 10
)

:distro_ready
echo [1/5] Ubuntu WSL 已就绪。
wsl.exe --set-default "%DISTRO%" >>"%LOG_FILE%" 2>&1
reg add "HKCU\Software\TMMBioSeq" /v "WslDistro" /t REG_SZ /d "%DISTRO%" /f >nul

echo [2/5] 正在初始化 Ubuntu...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "echo TMM_BIOSEQ_WSL_READY" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo.
    echo Ubuntu 尚未完成初始化，Windows 可能仍要求重启。
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "TMMBioSeqWGSInstall" /t REG_SZ /d "\"%FIXED_INSTALLER%\" --resume" /f >nul
    echo 请重启电脑，登录后安装器会自动继续。
    echo.
    if "%AUTO_MODE%"=="0" pause
    exit /b 11
)

echo [3/5] 正在更新 Ubuntu 软件源并安装 WGS 工具...
echo 此步骤受网络速度影响，可能需要几分钟。
>>"%LOG_FILE%" echo Installing fastp bwa samtools bcftools.
wsl.exe -d "%DISTRO%" -u root -- bash -lc "set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y software-properties-common; add-apt-repository -y universe; apt-get update; apt-get install -y fastp bwa samtools bcftools" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [错误] Ubuntu 软件包安装失败。
    echo 请检查网络，然后查看日志：
    echo %LOG_FILE%
    goto :failed
)

echo [4/5] 正在验证工具...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "set -e; command -v fastp; command -v bwa; command -v samtools; command -v bcftools; fastp --version; samtools --version | head -n 1; bcftools --version | head -n 1" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [错误] 工具安装后验证失败。
    goto :failed
)

if not exist "%APP_DIR%\backend" (
    echo [错误] 没有找到本机 BioSeq Engine：
    echo %APP_DIR%
    echo.
    echo 请先运行 BioSeq_Engine_Repair_and_Start.bat，再重新运行本安装器。
    goto :failed
)

echo [5/5] 正在更新 BioSeq Engine 的 WSL 支持并重启...
set "TMP_BACKEND=%TEMP%\TMMBioSeq_wgs_runner_%RANDOM%.py"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%RAW_BACKEND%' -OutFile '%TMP_BACKEND%'"
if errorlevel 1 (
    echo [错误] 无法下载最新版 WGS 后端。
    goto :failed
)

copy /Y "%TMP_BACKEND%" "%BACKEND_FILE%" >nul
del /q "%TMP_BACKEND%" >nul 2>&1
if errorlevel 1 (
    echo [错误] 无法更新：
    echo %BACKEND_FILE%
    goto :failed
)

for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do (
    taskkill /PID %%P /F >nul 2>&1
)

if exist "%BIOSEQ_ROOT%\BioSeq_Engine_Launcher.bat" (
    start "" /min "%BIOSEQ_ROOT%\BioSeq_Engine_Launcher.bat"
) else if exist "%APP_DIR%\BioSeq_Local_Service\BioSeq_Start.bat" (
    start "" /min "%APP_DIR%\BioSeq_Local_Service\BioSeq_Start.bat"
) else (
    echo [错误] 找不到 BioSeq Engine 启动器。
    goto :failed
)

set "ENGINE_OK=0"
for /L %%I in (1,1,90) do (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$r=Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 1;if($r.StatusCode -eq 200){exit 0}}catch{};exit 1" >nul 2>&1
    if not errorlevel 1 (
        set "ENGINE_OK=1"
        goto :engine_ready
    )
    >nul 2>&1 ping 127.0.0.1 -n 2
)

:engine_ready
echo.
if "%ENGINE_OK%"=="1" (
    echo =====================================================
    echo 安装成功
    echo =====================================================
    echo.
    echo fastp、bwa、samtools、bcftools 已安装。
    echo BioSeq Engine 已重新启动。
    echo 网页刷新后即可重新运行 WGS 分析。
    echo.
    echo 工具版本：
    wsl.exe -d "%DISTRO%" -u root -- bash -lc "fastp --version; echo BWA:; bwa 2>&1 | head -n 3; samtools --version | head -n 1; bcftools --version | head -n 1"
    echo.
    echo 验证地址：
    echo http://127.0.0.1:8765/status
    echo.
    if "%AUTO_MODE%"=="0" pause
    exit /b 0
)

echo 工具已经安装，但 BioSeq Engine 没有自动重新连接。
echo 请重新双击 BioSeq_Engine_Repair_and_Start.bat。
echo 安装日志：
echo %LOG_FILE%
if "%AUTO_MODE%"=="0" pause
exit /b 2

:check_distro
set "DISTRO_LIST=%TEMP%\TMMBioSeq_distro_%RANDOM%_%RANDOM%.txt"
set "DISTRO_OUTPUT=%DISTRO_LIST%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$items=@(wsl.exe -l -q 2>$null);$hit=$items|ForEach-Object{$_.Trim()}|Where-Object{$_ -like 'Ubuntu*'}|Select-Object -First 1;if($hit){$hit|Set-Content -LiteralPath $env:DISTRO_OUTPUT -Encoding ASCII;exit 0};exit 1" >nul 2>&1
set "DISTRO_RESULT=%ERRORLEVEL%"
if exist "%DISTRO_LIST%" (
    set /p DISTRO=<"%DISTRO_LIST%"
    del /q "%DISTRO_LIST%" >nul 2>&1
)
exit /b %DISTRO_RESULT%

:failed
echo.
echo =====================================================
echo 安装未完成
echo =====================================================
echo.
echo 日志文件：
echo %LOG_FILE%
echo.
if exist "%LOG_FILE%" (
    echo 日志最后 25 行：
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG_FILE%' -Tail 25"
)
echo.
if "%AUTO_MODE%"=="0" pause
exit /b 1
