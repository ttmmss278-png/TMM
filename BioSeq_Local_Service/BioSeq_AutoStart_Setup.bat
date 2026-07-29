@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "BIOSEQ_SELF=%~f0"
set "BIOSEQ_PROTOCOL_ARG=%~1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$raw=Get-Content -LiteralPath $env:BIOSEQ_SELF -Raw;" ^
 "$parts=$raw -split ':__POWERSHELL_PAYLOAD__',2;" ^
 "if($parts.Count -lt 2){throw 'Installer payload not found.'};" ^
 "Invoke-Expression $parts[1]"

set "BIOSEQ_EXIT=%ERRORLEVEL%"
if defined BIOSEQ_PROTOCOL_ARG exit /b %BIOSEQ_EXIT%

echo.
pause
exit /b %BIOSEQ_EXIT%

:__POWERSHELL_PAYLOAD__

$ErrorActionPreference = 'Stop'

$IsProtocol = $env:BIOSEQ_PROTOCOL_ARG -like 'bioseq://start*'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'TMMBioSeq'
$AppDir = Join-Path $InstallRoot 'app'
$InstalledBat = Join-Path $InstallRoot 'BioSeq_AutoStart_Setup.bat'
$LauncherVbs = Join-Path $InstallRoot 'BioSeq_Protocol_Launcher.vbs'
$RepoZipUrl = 'https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip'
$StatusUrl = 'http://127.0.0.1:8765/status'

function Write-Step([string]$Text) {
    if (-not $IsProtocol) {
        Write-Host $Text -ForegroundColor Cyan
    }
}

function Test-BioSeqEngine {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $StatusUrl -TimeoutSec 1
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Install-OrUpdateApp {
    Write-Step '[1/4] 正在下载最新版 TMM BioSeq Engine...'

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

    $tempRoot = Join-Path $env:TEMP ('TMMBioSeq_' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot 'TMM-main.zip'
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri $RepoZipUrl -OutFile $zipPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $source = Get-ChildItem -LiteralPath $extractPath -Directory |
            Where-Object { $_.Name -like 'TMM-*' } |
            Select-Object -First 1

        if (-not $source) {
            throw '下载包中未找到 TMM 项目目录。'
        }

        # 不使用镜像删除模式，因此本机已有参考基因组、索引和结果不会被删除。
        Copy-Item -Path (Join-Path $source.FullName '*') -Destination $AppDir -Recurse -Force
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $starter = Join-Path $AppDir 'BioSeq_Local_Service\BioSeq_Start.bat'
    if (-not (Test-Path -LiteralPath $starter)) {
        throw "安装后未找到启动文件：$starter"
    }
}

function Install-Launcher {
    Write-Step '[2/4] 正在安装本地启动器...'

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    $current = [System.IO.Path]::GetFullPath($env:BIOSEQ_SELF)
    $target = [System.IO.Path]::GetFullPath($InstalledBat)
    if ($current -ne $target) {
        Copy-Item -LiteralPath $current -Destination $InstalledBat -Force
    }

    $escapedBat = $InstalledBat.Replace('"', '""')
    $vbsContent = @"
Set shell = CreateObject("WScript.Shell")
arg = ""
If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)
shell.Run Chr(34) & "$escapedBat" & Chr(34) & " " & Chr(34) & arg & Chr(34), 0, False
"@
    Set-Content -LiteralPath $LauncherVbs -Value $vbsContent -Encoding Unicode

    $configKey = 'HKCU:\Software\TMMBioSeq'
    New-Item -Path $configKey -Force | Out-Null
    Set-ItemProperty -Path $configKey -Name 'InstallRoot' -Value $InstallRoot
    Set-ItemProperty -Path $configKey -Name 'AppDir' -Value $AppDir
    Set-ItemProperty -Path $configKey -Name 'LauncherBat' -Value $InstalledBat
}

function Register-Protocol {
    Write-Step '[3/4] 正在关联网页“启动分析引擎”按钮...'

    $protocolRoot = 'HKCU:\Software\Classes\bioseq'
    New-Item -Path $protocolRoot -Force | Out-Null
    Set-Item -Path $protocolRoot -Value 'URL:TMM BioSeq Engine Launcher'
    New-ItemProperty -Path $protocolRoot -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

    $iconKey = Join-Path $protocolRoot 'DefaultIcon'
    New-Item -Path $iconKey -Force | Out-Null
    Set-Item -Path $iconKey -Value ($env:SystemRoot + '\System32\wscript.exe,0')

    $commandKey = Join-Path $protocolRoot 'shell\open\command'
    New-Item -Path $commandKey -Force | Out-Null
    $command = '"' + $env:SystemRoot + '\System32\wscript.exe" "' + $LauncherVbs + '" "%1"'
    Set-Item -Path $commandKey -Value $command
}

function Start-BioSeqEngine {
    if (Test-BioSeqEngine) {
        if (-not $IsProtocol) {
            Write-Host 'BioSeq Engine 已经在运行。' -ForegroundColor Green
        }
        return $true
    }

    $starter = Join-Path $AppDir 'BioSeq_Local_Service\BioSeq_Start.bat'
    if (-not (Test-Path -LiteralPath $starter)) {
        return $false
    }

    Write-Step '[4/4] 正在启动 BioSeq Engine...'

    $windowStyle = if ($IsProtocol) { 'Minimized' } else { 'Normal' }
    Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/k', ('call "' + $starter + '"')) `
        -WorkingDirectory (Split-Path -Parent $starter) `
        -WindowStyle $windowStyle | Out-Null

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 750
        if (Test-BioSeqEngine) {
            if (-not $IsProtocol) {
                Write-Host 'BioSeq Engine 已成功启动。' -ForegroundColor Green
            }
            return $true
        }
    }

    if (-not $IsProtocol) {
        Write-Host '引擎尚未连接。请查看刚打开的 BioSeq Engine 窗口中的提示。' -ForegroundColor Yellow
    }
    return $false
}

try {
    if ($IsProtocol) {
        if (-not (Test-Path -LiteralPath (Join-Path $AppDir 'BioSeq_Local_Service\BioSeq_Start.bat'))) {
            Install-OrUpdateApp
            Install-Launcher
            Register-Protocol
        }
        $ok = Start-BioSeqEngine
        if ($ok) { exit 0 } else { exit 2 }
    }

    Write-Host '=====================================================' -ForegroundColor DarkCyan
    Write-Host '  TMM BioSeq Engine 独立安装与网页启动关联工具' -ForegroundColor White
    Write-Host '=====================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '该文件可以放在桌面或下载目录，不需要预先存在 TMM 文件夹。'
    Write-Host '程序将安装到：' -NoNewline
    Write-Host $InstallRoot -ForegroundColor Yellow
    Write-Host ''

    Install-OrUpdateApp
    Install-Launcher
    Register-Protocol
    $ok = Start-BioSeqEngine

    Write-Host ''
    Write-Host '安装完成。' -ForegroundColor Green
    Write-Host '以后在网页中点击“启动”，即可自动启动本机 BioSeq Engine。'
    Write-Host '浏览器首次调用时，请选择“允许打开 TMM BioSeq Engine Launcher”。'
    Write-Host ''
    Write-Host '安装后的程序位置：' -NoNewline
    Write-Host $InstallRoot -ForegroundColor Yellow
    Write-Host '当前下载的 BAT 文件现在可以删除。'

    if ($ok) { exit 0 } else { exit 2 }
}
catch {
    if (-not $IsProtocol) {
        Write-Host ''
        Write-Host ('安装或启动失败：' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '请检查网络连接、PowerShell 和 Python 环境。'
    }
    exit 1
}
