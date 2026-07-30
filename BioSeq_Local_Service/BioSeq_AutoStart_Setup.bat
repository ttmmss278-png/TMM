@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "ARG=%~1"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "MANAGER=%ROOT%\BioSeq_Engine_Manager_v131.bat"
set "TEMP_MANAGER=%TEMP%\BioSeq_Engine_Manager_v131_%RANDOM%_%RANDOM%.bat"
set "MANAGER_URL=https://raw.githubusercontent.com/ttmmss278-png/TMM/main/BioSeq_Local_Service/BioSeq_Engine_Manager_v131.bat"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
set "URL_ENV=%MANAGER_URL%"
set "TEMP_ENV=%TEMP_MANAGER%"
set "TARGET_ENV=%MANAGER%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "Invoke-WebRequest -UseBasicParsing -Uri $env:URL_ENV -OutFile $env:TEMP_ENV;" ^
 "if((Get-Item -LiteralPath $env:TEMP_ENV).Length -lt 5000){throw 'Manager download is incomplete'};" ^
 "Move-Item -LiteralPath $env:TEMP_ENV -Destination $env:TARGET_ENV -Force"
if errorlevel 1 (
    echo [错误] 无法下载 BioSeq Engine Manager v1.3.1。
    echo 请检查网络后重试。
    pause
    exit /b 1
)

if defined ARG (
    call "%MANAGER%" "%ARG%"
) else (
    call "%MANAGER%"
)
exit /b %ERRORLEVEL%
