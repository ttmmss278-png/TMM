@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title TMM BioSeq WGS Tools Immediate Installer

set "SELF=%~f0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\wgs_tools_immediate_install.log"
set "DISTRO="
set "ENGINE_OK=0"

if /I not "%~1"=="--admin" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo 正在请求管理员权限...
        set "SELF_ENV=%SELF%"
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Start-Process -FilePath $env:SELF_ENV -ArgumentList '--admin' -Verb RunAs -PassThru -Wait;exit $p.ExitCode"
        exit /b !ERRORLEVEL!
    )
)

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
>"%LOG%" echo [%date% %time%] TMM BioSeq immediate WGS tools installation

cls
echo =====================================================
echo   TMM BioSeq WGS 必需工具一键安装
echo =====================================================
echo.
echo 将安装：fastp、BWA、samtools、bcftools
echo 安装位置：已有 Ubuntu WSL
echo 这是一次性安装；以后启动引擎不再重复安装。
echo.

where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] Windows 中没有检测到 WSL。
    echo 请先启用 Windows 适用于 Linux 的子系统，然后重新运行。
    goto :failed
)

echo [1/5] 正在检测 Ubuntu WSL...
call :detect_distro
if not defined DISTRO (
    echo 未找到已初始化的 Ubuntu，正在安装 Ubuntu WSL...
    wsl.exe --install -d Ubuntu --web-download >>"%LOG%" 2>&1
    timeout /t 3 /nobreak >nul
    call :detect_distro
)

if not defined DISTRO (
    echo.
    echo Windows 已开始安装 Ubuntu WSL，但需要重启电脑完成初始化。
    echo 重启后打开一次 Ubuntu，等待初始化完成，再重新运行本文件。
    echo.
    pause
    exit /b 10
)

echo 已找到：%DISTRO%
reg add "HKCU\Software\TMMBioSeq" /v WslDistro /t REG_SZ /d "%DISTRO%" /f >nul


echo [2/5] 正在检查现有工具...
call :test_tools
if not errorlevel 1 (
    echo fastp、BWA、samtools、bcftools 已全部安装，跳过重复安装。
    goto :restart_engine
)


echo [3/5] 正在更新 Ubuntu 软件源...
echo 网络速度不同，此步骤通常需要数分钟。窗口会持续显示安装输出，请不要关闭。
wsl.exe -d "%DISTRO%" -u root -- bash -lc "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; export DEBIAN_FRONTEND=noninteractive; apt-get update -o Acquire::Retries=3"
if errorlevel 1 (
    echo [%date% %time%] apt-get update failed.>>"%LOG%"
    echo [错误] Ubuntu 软件源更新失败。
    goto :failed
)


echo [4/5] 正在安装 fastp、BWA、samtools 和 bcftools...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends ca-certificates fastp bwa samtools bcftools"
if errorlevel 1 (
    echo [%date% %time%] apt-get install failed.>>"%LOG%"
    echo [错误] WGS 工具安装失败。
    goto :failed
)

call :test_tools
if errorlevel 1 (
    echo [错误] 安装完成后仍有工具无法调用。
    goto :failed
)

:restart_engine
echo [5/5] 正在重启 BioSeq Engine...
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":8765 .*LISTENING"') do taskkill /PID %%P /F >nul 2>&1
timeout /t 2 /nobreak >nul

if exist "%ROOT%\BioSeq_Quick_Start.bat" (
    start "TMM BioSeq Engine" /min "%ROOT%\BioSeq_Quick_Start.bat"
) else if exist "%ROOT%\BioSeq_Engine_Launcher.bat" (
    start "TMM BioSeq Engine" /min "%ROOT%\BioSeq_Engine_Launcher.bat" "bioseq://start"
) else if exist "%ROOT%\app\BioSeq_Local_Service\BioSeq_Start.bat" (
    start "TMM BioSeq Engine" /min "%ROOT%\app\BioSeq_Local_Service\BioSeq_Start.bat"
) else (
    echo 未找到本地启动器。工具已安装，请在网页点击“启动”。
    goto :success
)

for /L %%I in (1,1,15) do (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try{$s=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 2;if($s.version){exit 0}}catch{};exit 1" >nul 2>&1
    if not errorlevel 1 (
        set "ENGINE_OK=1"
        goto :success
    )
    timeout /t 1 /nobreak >nul
)

:success
echo.
echo =====================================================
echo 安装完成
echo =====================================================
echo.
echo 已安装：
wsl.exe -d "%DISTRO%" -u root -- bash -lc "fastp --version; echo BWA; bwa 2>&1 | head -n 3; samtools --version | head -n 1; bcftools --version | head -n 1"
echo.
if "%ENGINE_OK%"=="1" (
    echo BioSeq Engine 已重新连接。
) else (
    echo WGS 工具已安装。请回到网页点击“启动”或“检测分析环境”。
)
echo.
echo 回到 WGS 页面按 Ctrl+F5，然后点击“检测分析环境”。
echo 日志：%LOG%
echo.
pause
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

:test_tools
if not defined DISTRO exit /b 1
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 && command -v bcftools >/dev/null 2>&1" 1>>"%LOG%" 2>>"%LOG%"
exit /b %ERRORLEVEL%

:failed
echo.
echo =====================================================
echo 安装未完成
echo =====================================================
echo 日志：%LOG%
echo.
if exist "%LOG%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 40" 2>nul
echo.
pause
exit /b 1
