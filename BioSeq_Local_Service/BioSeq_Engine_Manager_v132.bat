@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "MODE_ARG=%~1"
set "SELF=%~f0"
set "ROOT=%LOCALAPPDATA%\TMMBioSeq"
set "MANAGER_PS1=%ROOT%\BioSeq_Engine_Manager_v132.ps1"
set "TEMP_PS1=%TEMP%\BioSeq_Engine_Manager_v132_%RANDOM%_%RANDOM%.ps1"
set "MANAGER_URL=https://raw.githubusercontent.com/ttmmss278-png/TMM/main/BioSeq_Local_Service/BioSeq_Engine_Manager_v132.ps1"

if not exist "%ROOT%" mkdir "%ROOT%" >nul 2>&1
set "URL_ENV=%MANAGER_URL%"
set "TEMP_ENV=%TEMP_PS1%"
set "TARGET_ENV=%MANAGER_PS1%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "Invoke-WebRequest -UseBasicParsing -Uri $env:URL_ENV -OutFile $env:TEMP_ENV;" ^
 "if((Get-Item -LiteralPath $env:TEMP_ENV).Length -lt 5000){throw 'Manager download is incomplete'};" ^
 "Move-Item -LiteralPath $env:TEMP_ENV -Destination $env:TARGET_ENV -Force"
if errorlevel 1 (
    echo [错误] 无法下载 BioSeq Engine Manager v1.3.2。
    echo 请检查网络后重试。
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%MANAGER_PS1%" -ModeArg "%MODE_ARG%" -SelfBat "%SELF%"
exit /b %ERRORLEVEL%
