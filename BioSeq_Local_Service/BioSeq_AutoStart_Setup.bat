@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "BIOSEQ_SELF=%~f0"
set "BIOSEQ_PROTOCOL_ARG=%~1"
set "BIOSEQ_TMPPS=%TEMP%\TMMBioSeq_%RANDOM%_%RANDOM%.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$lines=Get-Content -LiteralPath $env:BIOSEQ_SELF;" ^
 "$marker=':__BIOSEQ_POWERSHELL__';" ^
 "$index=-1;" ^
 "for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -eq $marker){$index=$i;break}};" ^
 "if($index -lt 0){Write-Error 'PowerShell payload marker not found.';exit 3};" ^
 "$lines[($index+1)..($lines.Count-1)] | Set-Content -LiteralPath $env:BIOSEQ_TMPPS -Encoding UTF8"

if errorlevel 1 (
    echo.
    echo [错误] 无法提取安装程序脚本。
    echo 请重新下载最新版 BioSeq_AutoStart_Setup_Smart.bat。
    echo.
    pause
    exit /b 3
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%BIOSEQ_TMPPS%" -ProtocolArg "%BIOSEQ_PROTOCOL_ARG%" -SelfPath "%BIOSEQ_SELF%"
set "BIOSEQ_EXIT=%ERRORLEVEL%"

del /q "%BIOSEQ_TMPPS%" >nul 2>&1

if defined BIOSEQ_PROTOCOL_ARG exit /b %BIOSEQ_EXIT%

echo.
pause
exit /b %BIOSEQ_EXIT%

:__BIOSEQ_POWERSHELL__
param(
    [string]$ProtocolArg = '',
    [string]$SelfPath = ''
)

$ErrorActionPreference = 'Stop'

$IsProtocol = $ProtocolArg -like 'bioseq://start*'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'TMMBioSeq'
$AppDir = Join-Path $InstallRoot 'app'
$InstalledBat = Join-Path $InstallRoot 'BioSeq_AutoStart_Setup.bat'
$LauncherVbs = Join-Path $InstallRoot 'BioSeq_Protocol_Launcher.vbs'
$ConfigKey = 'HKCU:\Software\TMMBioSeq'
$DefaultStarter = Join-Path $AppDir 'BioSeq_Local_Service\BioSeq_Start.bat'
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

function Get-ConfiguredStarter {
    $candidates = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath $ConfigKey) {
        try {
            $saved = (Get-ItemProperty -Path $ConfigKey -Name 'EngineStartPath' -ErrorAction Stop).EngineStartPath
            if ($saved) {
                $candidates.Add([string]$saved)
            }
        }
        catch {}
    }

    $candidates.Add($DefaultStarter)

    if ($SelfPath) {
        $selfDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($SelfPath))
        $candidates.Add((Join-Path $selfDir 'BioSeq_Start.bat'))
        $candidates.Add((Join-Path $selfDir 'BioSeq_Local_Service\BioSeq_Start.bat'))
        $candidates.Add((Join-Path $selfDir 'TMM\BioSeq_Local_Service\BioSeq_Start.bat'))
        $candidates.Add((Join-Path $selfDir 'TMM-main\BioSeq_Local_Service\BioSeq_Start.bat'))
    }

    $commonRoots = @(
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents')
    )

    foreach ($root in $commonRoots) {
        $candidates.Add((Join-Path $root 'TMM\BioSeq_Local_Service\BioSeq_Start.bat'))
        $candidates.Add((Join-Path $root 'TMM-main\BioSeq_Local_Service\BioSeq_Start.bat'))
        $candidates.Add((Join-Path $root 'BioSeq_Local_Service\BioSeq_Start.bat'))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    return $null
}

function Download-App {
    Write-Step '未发现可用的本地 BioSeq Engine，正在下载最新版...'

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

        Copy-Item -Path (Join-Path $source.FullName '*') -Destination $AppDir -Recurse -Force
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $DefaultStarter -PathType Leaf)) {
        throw "下载后未找到启动文件：$DefaultStarter"
    }

    return $DefaultStarter
}

function Install-Launcher([string]$Starter) {
    Write-Step '正在安装网页启动关联...'

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    $current = [System.IO.Path]::GetFullPath($SelfPath)
    $target = [System.IO.Path]::GetFullPath($InstalledBat)
    if ($current -ne $target) {
        Copy-Item -LiteralPath $current -Destination $InstalledBat -Force
    }

    $escapedBat = $InstalledBat.Replace('"', '""')
    $vbsLines = @(
        'Set shell = CreateObject("WScript.Shell")',
        'arg = ""',
        'If WScript.Arguments.Count > 0 Then arg = WScript.Arguments(0)',
        ('shell.Run Chr(34) & "{0}" & Chr(34) & " " & Chr(34) & arg & Chr(34), 0, False' -f $escapedBat)
    )
    Set-Content -LiteralPath $LauncherVbs -Value $vbsLines -Encoding Unicode

    New-Item -Path $ConfigKey -Force | Out-Null
    Set-ItemProperty -Path $ConfigKey -Name 'InstallRoot' -Value $InstallRoot
    Set-ItemProperty -Path $ConfigKey -Name 'LauncherBat' -Value $InstalledBat
    if ($Starter) {
        Set-ItemProperty -Path $ConfigKey -Name 'EngineStartPath' -Value ([System.IO.Path]::GetFullPath($Starter))
    }
}

function Register-Protocol {
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

function Start-BioSeqEngine([string]$Starter) {
    if (Test-BioSeqEngine) {
        if (-not $IsProtocol) {
            Write-Host '检测到 BioSeq Engine 已经在运行，已跳过下载和重复启动。' -ForegroundColor Green
        }
        return $true
    }

    if (-not $Starter -or -not (Test-Path -LiteralPath $Starter -PathType Leaf)) {
        return $false
    }

    Write-Step '正在启动现有 BioSeq Engine...'

    $windowStyle = if ($IsProtocol) { 'Minimized' } else { 'Normal' }
    Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/k', ('call "' + $Starter + '"')) `
        -WorkingDirectory (Split-Path -Parent $Starter) `
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
        Write-Host '引擎尚未连接，请检查刚打开的 BioSeq Engine 窗口。' -ForegroundColor Yellow
    }
    return $false
}

try {
    if ($IsProtocol) {
        if (Test-BioSeqEngine) {
            exit 0
        }

        $starter = Get-ConfiguredStarter
        if (-not $starter) {
            $starter = Download-App
        }

        Install-Launcher -Starter $starter
        Register-Protocol
        $ok = Start-BioSeqEngine -Starter $starter
        if ($ok) { exit 0 } else { exit 2 }
    }

    Write-Host '=====================================================' -ForegroundColor DarkCyan
    Write-Host '  TMM BioSeq Engine 智能安装与网页启动关联工具' -ForegroundColor White
    Write-Host '=====================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host '程序会优先复用电脑上已有的 BioSeq Engine。'
    Write-Host '只有未运行且找不到本地启动文件时，才会从 GitHub 下载。'
    Write-Host ''

    if (Test-BioSeqEngine) {
        $starter = Get-ConfiguredStarter
        Install-Launcher -Starter $starter
        Register-Protocol
        Write-Host '已检测到正在运行的 BioSeq Engine，未下载任何程序。' -ForegroundColor Green
        Write-Host '网页启动关联已完成。'
        exit 0
    }

    $starter = Get-ConfiguredStarter
    if ($starter) {
        Write-Host ('已找到现有 BioSeq Engine：' + $starter) -ForegroundColor Green
        Write-Host '将直接复用，不进行下载。'
    }
    else {
        $starter = Download-App
    }

    Install-Launcher -Starter $starter
    Register-Protocol
    $ok = Start-BioSeqEngine -Starter $starter

    Write-Host ''
    Write-Host '配置完成。' -ForegroundColor Green
    Write-Host '以后网页显示“分析引擎未启动”时，点击“启动”即可。'
    Write-Host '浏览器首次调用时，请选择“允许打开 TMM BioSeq Engine Launcher”。'
    Write-Host '当前下载的安装 BAT 配置完成后可以删除。'

    if ($ok) { exit 0 } else { exit 2 }
}
catch {
    if (-not $IsProtocol) {
        Write-Host ''
        Write-Host ('安装或启动失败：' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '请检查网络连接、PowerShell、Python 和启动文件路径。'
    }
    exit 1
}
