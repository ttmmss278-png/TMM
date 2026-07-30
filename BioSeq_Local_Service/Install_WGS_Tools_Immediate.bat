@echo off
setlocal EnableExtensions
chcp 65001 >nul
title TMM BioSeq WGS Tools Installer v2

set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\wgs_tools_install_v2.log"
set "DISTRO="

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

>"%LOG%" echo [%date% %time%] TMM BioSeq WGS tools installer v2

echo =====================================================
echo   TMM BioSeq WGS 必需工具安装器 v2
echo =====================================================
echo.
echo 将安装并验证：
echo   fastp
echo   BWA
echo   samtools
echo   bcftools
echo.
echo 本版本不执行 Windows 自提权，也不修改 BioSeq Engine。
echo 安装完成后只需返回网页重新检测环境。
echo.

where wsl.exe >nul 2>&1
if errorlevel 1 goto NO_WSL

echo [1/4] 正在查找已初始化的 WSL 发行版...
call :TRY_DISTRO Ubuntu
if defined DISTRO goto DISTRO_FOUND
call :TRY_DISTRO Ubuntu-24.04
if defined DISTRO goto DISTRO_FOUND
call :TRY_DISTRO Ubuntu-22.04
if defined DISTRO goto DISTRO_FOUND
call :TRY_DISTRO Ubuntu-20.04
if defined DISTRO goto DISTRO_FOUND
call :TRY_DISTRO Debian
if defined DISTRO goto DISTRO_FOUND
goto NO_DISTRO

:DISTRO_FOUND
echo 已找到：%DISTRO%
reg add "HKCU\Software\TMMBioSeq" /v WslDistro /t REG_SZ /d "%DISTRO%" /f >nul 2>&1

echo [2/4] 正在检查现有工具...
call :CHECK_TOOLS
if not errorlevel 1 goto ALREADY_READY

echo [3/4] 正在更新 Linux 软件源...
echo 此步骤取决于网络速度，请保持窗口开启。
wsl.exe -d "%DISTRO%" -u root -- bash -lc "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; export DEBIAN_FRONTEND=noninteractive; apt-get update -o Acquire::Retries=3"
if errorlevel 1 goto UPDATE_FAILED

echo.
echo 正在启用软件源并安装工具...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; export DEBIAN_FRONTEND=noninteractive; apt-get install -y software-properties-common ca-certificates; if command -v add-apt-repository >/dev/null 2>&1; then add-apt-repository -y universe || true; fi; apt-get update -o Acquire::Retries=3; apt-get install -y --no-install-recommends fastp bwa samtools bcftools"
if errorlevel 1 goto INSTALL_FAILED

echo [4/4] 正在验证工具...
call :CHECK_TOOLS
if errorlevel 1 goto VERIFY_FAILED
goto SUCCESS

:ALREADY_READY
echo 四个工具已经存在，不重复安装。
goto SUCCESS

:SUCCESS
echo.
echo =====================================================
echo 安装与验证成功
echo =====================================================
echo.
wsl.exe -d "%DISTRO%" -u root -- bash -lc "echo fastp:; fastp --version; echo; echo BWA:; bwa 2>&1 | head -n 3; echo; samtools --version | head -n 1; bcftools --version | head -n 1"
echo.
echo 请执行：
echo   1. 回到 WGS 网页
echo   2. 按 Ctrl+F5
echo   3. 点击“检测分析环境”
echo.
echo 不需要重新安装 BioSeq Engine。
echo 日志：%LOG%
echo.
pause
exit /b 0

:TRY_DISTRO
wsl.exe -d "%~1" -u root -- bash -lc "exit 0" >>"%LOG%" 2>&1
if not errorlevel 1 set "DISTRO=%~1"
exit /b 0

:CHECK_TOOLS
wsl.exe -d "%DISTRO%" -u root -- bash -lc "command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1 && command -v bcftools >/dev/null 2>&1" >>"%LOG%" 2>&1
exit /b %ERRORLEVEL%

:NO_WSL
echo.
echo [错误] Windows 未检测到 wsl.exe。
echo 请先在“启用或关闭 Windows 功能”中启用：
echo   适用于 Linux 的 Windows 子系统
echo   虚拟机平台
goto FAILED

:NO_DISTRO
echo.
echo [错误] 没有找到已完成初始化的 Ubuntu 或 Debian。
echo 请先从开始菜单打开 Ubuntu，完成首次初始化，再重新运行本文件。
goto FAILED

:UPDATE_FAILED
echo.
echo [错误] Linux 软件源更新失败。
echo 请检查网络、代理或 Ubuntu 网络连接。
goto FAILED

:INSTALL_FAILED
echo.
echo [错误] fastp、BWA、samtools 或 bcftools 安装失败。
goto FAILED

:VERIFY_FAILED
echo.
echo [错误] 安装命令已结束，但仍有工具无法调用。
goto FAILED

:FAILED
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
