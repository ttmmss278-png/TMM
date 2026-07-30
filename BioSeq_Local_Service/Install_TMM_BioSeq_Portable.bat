@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
title TMM BioSeq Portable Offline Installer

set "PACKAGE=%~dp0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "APP=%ROOT%\app"
set "PORTABLE_PY=%ROOT%\portable_python"
set "ARCHIVE=%PACKAGE%WGS_Tools_Linux_x86_64.tar.gz"
set "CHECKSUM=%PACKAGE%WGS_Tools_Linux_x86_64.sha256"
set "PACKAGE_APP=%PACKAGE%app"
set "PACKAGE_PY=%PACKAGE%portable_python"
set "QUICK=%PACKAGE%BioSeq_Quick_Start.bat"
set "LOGDIR=%ROOT%\logs"
set "LOG=%LOGDIR%\portable_install.log"
set "DISTRO="
set "WSL_ARCHIVE="
set "EXPECTED_SHA="
set "ACTUAL_SHA="

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
>"%LOG%" echo [%date% %time%] TMM BioSeq portable offline install

echo =====================================================
echo   TMM BioSeq Portable WGS Offline Installer
echo =====================================================
echo.
echo 本安装器只复制和解压已经打包好的文件：
echo - 不联网
echo - 不运行 apt
echo - 不在启动时安装软件
echo.

if not exist "%ARCHIVE%" (
    echo [错误] 缺少：
    echo %ARCHIVE%
    goto :failed
)
if not exist "%CHECKSUM%" (
    echo [错误] 缺少工具归档校验文件：
    echo %CHECKSUM%
    goto :failed
)
if not exist "%PACKAGE_APP%\backend\BioSeq_Server_v140.py" (
    echo [错误] 工具包中的 app 目录不完整。
    goto :failed
)
if not exist "%PACKAGE_PY%\python.exe" (
    echo [错误] 工具包中的 portable_python 目录不完整。
    goto :failed
)
if not exist "%QUICK%" (
    echo [错误] 缺少 BioSeq_Quick_Start.bat。
    goto :failed
)

echo [1/6] 正在校验离线 WGS 工具归档...
for /f "tokens=1" %%H in (%CHECKSUM%) do if not defined EXPECTED_SHA set "EXPECTED_SHA=%%H"
for /f "usebackq delims=" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%ARCHIVE%').Hash.ToLowerInvariant()"`) do if not defined ACTUAL_SHA set "ACTUAL_SHA=%%H"
if not defined EXPECTED_SHA (
    echo [错误] 无法读取预期 SHA-256。
    goto :failed
)
if not defined ACTUAL_SHA (
    echo [错误] 无法计算工具归档 SHA-256。
    goto :failed
)
if /I not "%EXPECTED_SHA%"=="%ACTUAL_SHA%" (
    echo [错误] 工具归档校验失败，文件可能下载不完整。
    echo 预期：%EXPECTED_SHA%
    echo 实际：%ACTUAL_SHA%
    goto :failed
)
echo 校验通过。

echo [2/6] 正在复制 BioSeq 应用文件...
if not exist "%APP%" mkdir "%APP%" >nul 2>&1
robocopy "%PACKAGE_APP%" "%APP%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS >>"%LOG%" 2>&1
set "ROBO_APP=!ERRORLEVEL!"
if !ROBO_APP! GEQ 8 (
    echo [错误] 复制 BioSeq 应用失败。
    goto :failed
)

echo [3/6] 正在复制便携 Python...
if not exist "%PORTABLE_PY%" mkdir "%PORTABLE_PY%" >nul 2>&1
robocopy "%PACKAGE_PY%" "%PORTABLE_PY%" /E /R:2 /W:1 /NFL /NDL /NJH /NJS >>"%LOG%" 2>&1
set "ROBO_PY=!ERRORLEVEL!"
if !ROBO_PY! GEQ 8 (
    echo [错误] 复制便携 Python 失败。
    goto :failed
)

echo [4/6] 正在检测 WSL Ubuntu...
call :detect_distro
if not defined DISTRO (
    echo [错误] 未找到已初始化的 Ubuntu WSL。
    echo 当前离线包不会在 BAT 中安装 Windows 系统组件。
    echo 请先在 Windows 中启用并启动一次 Ubuntu WSL，然后重新运行本安装器。
    goto :failed
)
echo 已找到：%DISTRO%

for /f "usebackq delims=" %%P in (`wsl.exe -d "%DISTRO%" -u root -- wslpath -a "%ARCHIVE%" 2^>nul`) do (
    if not defined WSL_ARCHIVE set "WSL_ARCHIVE=%%P"
)
if not defined WSL_ARCHIVE (
    echo [错误] 无法把工具包路径转换为 WSL 路径。
    goto :failed
)

echo [5/6] 正在解压预装 WGS 工具...
wsl.exe -d "%DISTRO%" -u root -- bash -lc "rm -rf /opt/tmm-bioseq-wgs && mkdir -p /opt/tmm-bioseq-wgs && tar -xzf '%WSL_ARCHIVE%' -C /opt/tmm-bioseq-wgs" 1>>"%LOG%" 2>>"%LOG%"
if errorlevel 1 (
    echo [错误] WGS 工具解压失败。
    goto :failed
)

wsl.exe -d "%DISTRO%" -u root -- bash -lc "test -x /opt/tmm-bioseq-wgs/bin/fastp && test -x /opt/tmm-bioseq-wgs/bin/bwa && test -x /opt/tmm-bioseq-wgs/bin/samtools && test -x /opt/tmm-bioseq-wgs/bin/bcftools && /opt/tmm-bioseq-wgs/bin/fastp --version >/dev/null && /opt/tmm-bioseq-wgs/bin/samtools --version >/dev/null && /opt/tmm-bioseq-wgs/bin/bcftools --version >/dev/null" 1>>"%LOG%" 2>>"%LOG%"
if errorlevel 1 (
    echo [错误] WGS 工具完整性或运行校验失败。
    goto :failed
)

reg add "HKCU\Software\TMMBioSeq" /v WslDistro /t REG_SZ /d "%DISTRO%" /f >nul
reg add "HKCU\Software\TMMBioSeq" /v WslToolRoot /t REG_SZ /d "/opt/tmm-bioseq-wgs" /f >nul

echo [6/6] 正在安装快速启动器并启动引擎...
copy /Y "%QUICK%" "%ROOT%\BioSeq_Quick_Start.bat" >nul 2>&1
if errorlevel 1 (
    echo [错误] 快速启动器复制失败。
    goto :failed
)

call "%ROOT%\BioSeq_Quick_Start.bat"
if errorlevel 1 (
    echo [错误] 工具已安装，但 BioSeq Engine 启动失败。
    goto :failed
)

echo.
echo =====================================================
echo 安装完成
echo =====================================================
echo WGS 工具目录：%DISTRO%:/opt/tmm-bioseq-wgs
echo BioSeq Engine：v1.4.0
echo.
echo 以后只需点击网页中的“启动”，或运行：
echo %ROOT%\BioSeq_Quick_Start.bat
echo.
echo 网页检测通常在数秒内完成，不再等待 240 次。
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

:failed
echo.
echo =====================================================
echo 安装未完成
echo =====================================================
echo 日志：
echo %LOG%
echo.
if exist "%LOG%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG%' -Tail 35" 2>nul
)
echo.
pause
exit /b 1