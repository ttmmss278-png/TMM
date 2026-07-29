@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "SELF=%~f0"
set "BASE=%~dp0"
set "STARTER=%BASE%BioSeq_Start.bat"
set "BIOSEQ_LAUNCHER=%SELF%"

if /I "%~1"=="bioseq://start" goto :protocol_start
if /I "%~1"=="bioseq://start/" goto :protocol_start

title TMM BioSeq Auto Start Setup

echo =====================================================
echo   TMM BioSeq Engine - 一键启动协议安装器
echo =====================================================
echo.

if not exist "%STARTER%" goto :missing_starter

echo [1/3] 正在注册 bioseq:// 启动协议...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$q=[char]34;" ^
 "$base='HKCU:\Software\Classes\bioseq';" ^
 "New-Item -Path $base -Force ^| Out-Null;" ^
 "Set-Item -Path $base -Value 'URL:BioSeq Engine Launcher';" ^
 "New-ItemProperty -Path $base -Name 'URL Protocol' -Value '' -PropertyType String -Force ^| Out-Null;" ^
 "New-Item -Path ($base+'\DefaultIcon') -Force ^| Out-Null;" ^
 "Set-Item -Path ($base+'\DefaultIcon') -Value ($env:SystemRoot+'\System32\cmd.exe,0');" ^
 "New-Item -Path ($base+'\shell\open\command') -Force ^| Out-Null;" ^
 "$command=$q+$env:SystemRoot+'\System32\cmd.exe'+$q+' /d /c '+$q+$q+$env:BIOSEQ_LAUNCHER+$q+' '+$q+'%%1'+$q+$q;" ^
 "Set-Item -Path ($base+'\shell\open\command') -Value $command;"

if errorlevel 1 (
  echo.
  echo [失败] 无法注册启动协议。
  echo 请确认 Windows PowerShell 可正常运行，然后重试。
  pause
  exit /b 1
)

echo [2/3] 启动协议注册完成。
echo [3/3] 正在检查并启动 BioSeq Engine...
call :start_if_needed

echo.
echo 安装完成。
echo 以后网页显示“分析引擎未启动”时，直接点击“启动”即可。
echo 浏览器首次调用时请选择“允许打开 BioSeq Engine Launcher”。
echo.
pause
exit /b 0

:protocol_start
if not exist "%STARTER%" exit /b 2
call :start_if_needed
exit /b 0

:start_if_needed
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 1; if($r.StatusCode -eq 200){exit 0}else{exit 1} } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 (
  echo BioSeq Engine 已经在运行，无需重复启动。
  exit /b 0
)

start "TMM BioSeq Engine" /min "%ComSpec%" /k call "%STARTER%"
exit /b 0

:missing_starter
echo [错误] 未找到：
echo %STARTER%
echo.
echo 请把本文件放到 TMM\BioSeq_Local_Service 文件夹中，
echo 并确认同一文件夹内存在 BioSeq_Start.bat。
echo.
pause
exit /b 2
