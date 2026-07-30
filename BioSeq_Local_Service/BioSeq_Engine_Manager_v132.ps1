param(
    [string]$ModeArg = '',
    [string]$SelfBat = ''
)

$ErrorActionPreference = 'Stop'
$ProtocolMode = $ModeArg -like 'bioseq://*'
$AutomaticMode = $ProtocolMode -or $ModeArg -in @('--admin-repair', '--resume')

$Root = Join-Path $env:LOCALAPPDATA 'TMMBioSeq'
$App = Join-Path $Root 'app'
$Backend = Join-Path $App 'backend'
$Runtime = Join-Path $Root 'runtime'
$Venv = Join-Path $Runtime 'venv'
$VenvPython = Join-Path $Venv 'Scripts\python.exe'
$LogDir = Join-Path $Root 'logs'
$Log = Join-Path $LogDir 'manager_v133.log'
$EngineStdout = Join-Path $LogDir 'engine_v131_stdout.log'
$EngineStderr = Join-Path $LogDir 'engine_v131_stderr.log'
$FixedBat = Join-Path $Root 'BioSeq_Engine_Manager_v132.bat'
$Server = Join-Path $Backend 'BioSeq_Server_v131.py'
$Runner = Join-Path $Backend 'wgs_runner_v131.py'
$Requirements = Join-Path $Backend 'requirements.txt'
$StatusUrl = 'http://127.0.0.1:8765/status'
$EnvironmentUrl = 'http://127.0.0.1:8765/environment'
$ExpectedVersion = '1.3.1'
$RawBase = 'https://raw.githubusercontent.com/ttmmss278-png/TMM/main'

New-Item -ItemType Directory -Path $Root, $App, $Runtime, $LogDir -Force | Out-Null
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TMM BioSeq Engine Manager v1.3.3`nMode: $ModeArg`nSelf: $SelfBat" |
    Set-Content -LiteralPath $Log -Encoding UTF8

function Write-Step {
    param([string]$Text)
    if (-not $ProtocolMode) {
        Write-Host $Text -ForegroundColor Cyan
    }
}

function Pause-Manual {
    if (-not $AutomaticMode) {
        [void](Read-Host '按 Enter 键关闭')
    }
}

function Add-Log {
    param([string]$Text)
    Add-Content -LiteralPath $Log -Value $Text -Encoding UTF8
}

function Download-File {
    param(
        [string]$Url,
        [string]$Target,
        [int64]$MinimumBytes = 20
    )
    $parent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $env:TEMP ('TMMBioSeq_' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporary
        $length = (Get-Item -LiteralPath $temporary).Length
        if ($length -lt $MinimumBytes) {
            throw "Downloaded file is incomplete: $Url"
        }
        Move-Item -LiteralPath $temporary -Destination $Target -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Register-Protocol {
    if (-not $SelfBat -or -not (Test-Path -LiteralPath $SelfBat -PathType Leaf)) {
        throw 'The BAT launcher path is unavailable.'
    }

    $source = [System.IO.Path]::GetFullPath($SelfBat)
    $target = [System.IO.Path]::GetFullPath($FixedBat)
    if ($source -ne $target) {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    $protocolRoot = 'HKCU:\Software\Classes\bioseq'
    New-Item -Path $protocolRoot -Force | Out-Null
    Set-Item -Path $protocolRoot -Value 'URL:TMM BioSeq Engine Manager'
    New-ItemProperty -Path $protocolRoot -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

    $commandKey = Join-Path $protocolRoot 'shell\open\command'
    New-Item -Path $commandKey -Force | Out-Null
    $command = '"' + $env:ComSpec + '" /d /c ""' + $FixedBat + '" "%1""'
    Set-Item -Path $commandKey -Value $command

    $configKey = 'HKCU:\Software\TMMBioSeq'
    New-Item -Path $configKey -Force | Out-Null
    Set-ItemProperty -Path $configKey -Name 'ManagerPath' -Value $FixedBat
}

function Ensure-App {
    if (Test-Path -LiteralPath (Join-Path $Backend 'requirements.txt') -PathType Leaf) {
        return
    }

    Write-Step '未发现本机 BioSeq 程序，正在下载 TMM...'
    $zipPath = Join-Path $env:TEMP ('TMMBioSeq_' + [guid]::NewGuid().ToString('N') + '.zip')
    $extractPath = Join-Path $env:TEMP ('TMMBioSeq_extract_' + [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ttmmss278-png/TMM/archive/refs/heads/main.zip' -OutFile $zipPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
        $source = Get-ChildItem -LiteralPath $extractPath -Directory |
            Where-Object { $_.Name -like 'TMM-*' } |
            Select-Object -First 1
        if (-not $source) {
            throw 'The downloaded archive does not contain the TMM project.'
        }
        Copy-Item -Path (Join-Path $source.FullName '*') -Destination $App -Recurse -Force
    }
    finally {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Backend 'requirements.txt') -PathType Leaf)) {
        throw 'The local BioSeq application is incomplete after download.'
    }
}

function Update-Core {
    Write-Step '[1/6] 正在同步 BioSeq Engine v1.3.1 后端...'
    Download-File "$RawBase/backend/BioSeq_Server_v131.py" $Server 5000
    Download-File "$RawBase/backend/wgs_runner_v131.py" $Runner 5000
    Download-File "$RawBase/backend/requirements.txt" $Requirements 20

    $serverText = Get-Content -LiteralPath $Server -Raw
    $runnerText = Get-Content -LiteralPath $Runner -Raw
    $needle = 'ENGINE_VERSION = ' + [char]34 + '1.3.1' + [char]34
    if (-not $serverText.Contains($needle) -or -not $runnerText.Contains('Missing WGS tools:')) {
        throw 'The downloaded v1.3.1 backend failed validation.'
    }
}

function Find-BasePython {
    if (Test-Path -LiteralPath $VenvPython -PathType Leaf) {
        return $VenvPython
    }

    $pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        try {
            $path = (& $pyLauncher.Source -3 -c 'import sys;print(sys.executable)' 2>$null | Select-Object -First 1)
            if ($path -and (Test-Path -LiteralPath $path.Trim() -PathType Leaf)) {
                return $path.Trim()
            }
        }
        catch {}
    }

    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        try {
            $path = (& $pythonCommand.Source -c 'import sys;print(sys.executable)' 2>$null | Select-Object -First 1)
            if ($path -and (Test-Path -LiteralPath $path.Trim() -PathType Leaf)) {
                return $path.Trim()
            }
        }
        catch {}
    }

    foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Ensure-PythonEnvironment {
    Write-Step '[2/6] 正在检查 Python 和 Flask...'
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        $basePython = Find-BasePython
        if (-not $basePython) {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $winget) {
                throw 'Python is missing and winget is unavailable.'
            }
            Write-Step '未检测到 Python，正在安装 Python 3.12...'
            & $winget.Source install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements *>> $Log
            $basePython = Find-BasePython
        }
        if (-not $basePython) {
            throw 'Python 3 could not be installed or located.'
        }
        & $basePython -m venv $Venv *>> $Log
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
            throw 'Failed to create the BioSeq Python virtual environment.'
        }
    }

    & $VenvPython -c 'import flask, flask_cors, werkzeug' 2>$null
    if ($LASTEXITCODE -ne 0) {
        & $VenvPython -m pip install --disable-pip-version-check -r $Requirements *>> $Log
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to install the BioSeq Python dependencies.'
        }
    }
}

function Invoke-WslSafe {
    param(
        [string[]]$Arguments,
        [switch]$CaptureOutput
    )

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return [pscustomobject]@{ ExitCode = 127; Output = @(); ErrorText = 'wsl.exe is unavailable.' }
    }

    $oldPreference = $ErrorActionPreference
    $nativeVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    $oldNativePreference = $null
    if ($nativeVariable) {
        $oldNativePreference = $global:PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = 'Continue'
        if ($nativeVariable) {
            $global:PSNativeCommandUseErrorActionPreference = $false
        }

        if ($CaptureOutput) {
            $output = @(& $wsl.Source @Arguments 2>> $Log)
        }
        else {
            $output = @(& $wsl.Source @Arguments *>> $Log)
        }
        $exitCode = $LASTEXITCODE

        if ($CaptureOutput -and $output.Count -gt 0) {
            Add-Content -LiteralPath $Log -Value ($output -join [Environment]::NewLine) -Encoding UTF8
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output
            ErrorText = ''
        }
    }
    finally {
        $ErrorActionPreference = $oldPreference
        if ($nativeVariable) {
            $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }
}

function Get-UbuntuDistro {
    $result = Invoke-WslSafe -Arguments @('-l', '-q') -CaptureOutput
    if ($result.ExitCode -ne 0) {
        return $null
    }

    foreach ($item in $result.Output) {
        $clean = ([string]$item -replace "`0", '').Trim()
        if ($clean -like 'Ubuntu*') {
            return $clean
        }
    }
    return $null
}

function Test-WgsTools {
    $nativeReady =
        (Get-Command fastp.exe -ErrorAction SilentlyContinue) -and
        (Get-Command bwa.exe -ErrorAction SilentlyContinue) -and
        (Get-Command samtools.exe -ErrorAction SilentlyContinue)
    if ($nativeReady) {
        return $true
    }

    $distro = Get-UbuntuDistro
    if (-not $distro) {
        return $false
    }

    $result = Invoke-WslSafe -Arguments @(
        '-d', $distro, '-u', 'root', '--', 'bash', '-lc',
        'command -v fastp >/dev/null 2>&1 && command -v bwa >/dev/null 2>&1 && command -v samtools >/dev/null 2>&1'
    )
    return $result.ExitCode -eq 0
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-ResumeAfterRestart {
    $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    New-Item -Path $runOnce -Force | Out-Null
    Set-ItemProperty -Path $runOnce -Name 'TMMBioSeqResume' -Value ('"' + $FixedBat + '" --resume')
}

function Install-WgsTools {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'wsl.exe is unavailable on this Windows installation.'
    }

    $distro = Get-UbuntuDistro
    if (-not $distro) {
        Write-Step '正在启用 WSL 并安装 Ubuntu...'
        $attempts = @(
            @('--install', '-d', 'Ubuntu', '--web-download', '--no-launch'),
            @('--install', '-d', 'Ubuntu', '--web-download'),
            @('--install', '-d', 'Ubuntu')
        )
        foreach ($arguments in $attempts) {
            $null = Invoke-WslSafe -Arguments $arguments
            Start-Sleep -Seconds 3
            $distro = Get-UbuntuDistro
            if ($distro) {
                break
            }
        }
        if (-not $distro) {
            Set-ResumeAfterRestart
            return 10
        }
    }

    $configKey = 'HKCU:\Software\TMMBioSeq'
    New-Item -Path $configKey -Force | Out-Null
    Set-ItemProperty -Path $configKey -Name 'WslDistro' -Value $distro

    $readyResult = Invoke-WslSafe -Arguments @('-d', $distro, '-u', 'root', '--', 'bash', '-lc', 'echo TMM_BIOSEQ_WSL_READY')
    if ($readyResult.ExitCode -ne 0) {
        Set-ResumeAfterRestart
        return 11
    }

    Write-Step '正在安装 fastp、BWA、samtools 和 bcftools...'
    $installScript = 'set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update -o Acquire::Retries=3; apt-get install -y software-properties-common; add-apt-repository -y universe || true; apt-get update -o Acquire::Retries=3; apt-get install -y fastp bwa samtools bcftools'
    $installResult = Invoke-WslSafe -Arguments @('-d', $distro, '-u', 'root', '--', 'bash', '-lc', $installScript)

    if ($installResult.ExitCode -ne 0) {
        Write-Step '检测到 WSL 网络或代理异常，正在清除 Linux 代理变量后重试...'
        $retryScript = 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy; ' + $installScript
        $installResult = Invoke-WslSafe -Arguments @('-d', $distro, '-u', 'root', '--', 'bash', '-lc', $retryScript)
    }

    if ($installResult.ExitCode -ne 0) {
        throw 'Ubuntu failed to install the WGS packages. The localhost proxy warning is no longer treated as fatal; check the manager log for the real apt error.'
    }

    $validationResult = Invoke-WslSafe -Arguments @(
        '-d', $distro, '-u', 'root', '--', 'bash', '-lc',
        'command -v fastp && command -v bwa && command -v samtools && command -v bcftools'
    )
    if ($validationResult.ExitCode -ne 0) {
        throw 'The WGS tools failed post-installation validation.'
    }

    return 0
}

function Elevate-Manager {
    $process = Start-Process -FilePath $FixedBat -ArgumentList '--admin-repair' -Verb RunAs -PassThru -Wait
    return $process.ExitCode
}

function Test-EngineReady {
    try {
        $status = Invoke-RestMethod -Uri $StatusUrl -TimeoutSec 3
        if ([string]$status.version -ne $ExpectedVersion) {
            return $false
        }
        $environment = Invoke-RestMethod -Uri $EnvironmentUrl -TimeoutSec 20
        return [bool]$environment.wgs.ready
    }
    catch {
        return $false
    }
}

function Stop-Engine {
    try {
        $connections = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
        foreach ($connection in $connections) {
            Stop-Process -Id $connection.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}

    try {
        $netstat = netstat -ano | Select-String ':8765\s+.*LISTENING'
        foreach ($line in $netstat) {
            $parts = ([string]$line).Trim() -split '\s+'
            $pidValue = $parts[-1]
            if ($pidValue -match '^\d+$') {
                Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {}

    Start-Sleep -Seconds 2
}

function Start-Engine {
    Remove-Item -LiteralPath $EngineStdout, $EngineStderr -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $VenvPython `
        -ArgumentList @($Server) `
        -WorkingDirectory $App `
        -WindowStyle Hidden `
        -RedirectStandardOutput $EngineStdout `
        -RedirectStandardError $EngineStderr | Out-Null
}

function Show-Success {
    if (-not $ProtocolMode) {
        Write-Host ''
        Write-Host '=====================================================' -ForegroundColor DarkCyan
        Write-Host '环境已就绪' -ForegroundColor Green
        Write-Host '=====================================================' -ForegroundColor DarkCyan
        Write-Host 'BioSeq Engine：v1.3.1'
        Write-Host 'WGS 工具链：已就绪'
        Write-Host "状态地址：$StatusUrl"
        Write-Host "环境地址：$EnvironmentUrl"
        Write-Host ''
        Write-Host '回到网页按 Ctrl+F5，页面应显示 v1.3.1 和 WSL/NATIVE。'
        Write-Host ''
    }
}

try {
    if (-not $ProtocolMode) {
        Write-Host '=====================================================' -ForegroundColor DarkCyan
        Write-Host '  TMM BioSeq Engine Manager v1.3.3' -ForegroundColor White
        Write-Host '=====================================================' -ForegroundColor DarkCyan
        Write-Host ''
    }

    Register-Protocol
    Ensure-App
    Update-Core
    Ensure-PythonEnvironment

    Write-Step '[3/6] 正在检查 WGS 工具链...'
    if (-not (Test-WgsTools)) {
        if (-not (Test-Administrator)) {
            if (-not $ProtocolMode) {
                Write-Host '需要管理员权限安装 WSL/Ubuntu 和 WGS 工具。' -ForegroundColor Yellow
            }
            $elevatedExit = Elevate-Manager
            if ($elevatedExit -in @(10, 11)) {
                if (-not $ProtocolMode) {
                    Write-Host 'Windows 需要重启后继续安装 WSL。' -ForegroundColor Yellow
                    Pause-Manual
                }
                exit 10
            }
            if ($elevatedExit -ne 0) {
                throw "The elevated environment repair failed with exit code $elevatedExit."
            }
        }
        else {
            $installExit = Install-WgsTools
            if ($installExit -in @(10, 11)) {
                if (-not $ProtocolMode) {
                    Write-Host 'Windows 需要重启后继续安装 WSL。' -ForegroundColor Yellow
                    Pause-Manual
                }
                exit 10
            }
        }
    }

    if (-not (Test-WgsTools)) {
        throw 'fastp, BWA and samtools are still unavailable after repair.'
    }

    Write-Step '[4/6] 正在检查当前引擎版本...'
    if (-not (Test-EngineReady)) {
        Write-Step '[5/6] 正在关闭旧引擎并启动 v1.3.1...'
        Stop-Engine
        Start-Engine

        Write-Step '[6/6] 正在验证引擎和 WGS 环境...'
        $ready = $false
        for ($attempt = 1; $attempt -le 180; $attempt++) {
            if (Test-EngineReady) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) {
            throw 'BioSeq Engine v1.3.1 did not become ready within the allowed time.'
        }
    }

    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'TMMBioSeqResume' -ErrorAction SilentlyContinue
    Show-Success
    Pause-Manual
    exit 0
}
catch {
    Add-Log ("ERROR: " + $_.Exception.Message)
    if (-not $ProtocolMode) {
        Write-Host ''
        Write-Host '修复未完成：' -NoNewline -ForegroundColor Red
        Write-Host $_.Exception.Message
        Write-Host "管理器日志：$Log"
        Write-Host "引擎错误：$EngineStderr"
        if (Test-Path -LiteralPath $Log) {
            Write-Host ''
            Get-Content -LiteralPath $Log -Tail 40
        }
        if (Test-Path -LiteralPath $EngineStderr) {
            Write-Host ''
            Write-Host 'Python 后端错误：' -ForegroundColor Yellow
            Get-Content -LiteralPath $EngineStderr -Tail 25
        }
        Pause-Manual
    }
    exit 1
}
