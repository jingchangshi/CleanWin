param(
    [switch]$IncludeHyperVServices
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ====" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "[步骤] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[跳过] $Message" -ForegroundColor Yellow
}

function Convert-BytesToGB {
    param([double]$Bytes)
    return [math]::Round($Bytes / 1GB, 2)
}

function Get-MemorySnapshot {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $freeBytes = [double]$os.FreePhysicalMemory * 1KB
        $usedBytes = $totalBytes - $freeBytes
        $usedPercent = if ($totalBytes -gt 0) { [math]::Round(($usedBytes / $totalBytes) * 100, 1) } else { 0 }

        [pscustomobject]@{
            TotalGB = Convert-BytesToGB $totalBytes
            UsedGB = Convert-BytesToGB $usedBytes
            FreeGB = Convert-BytesToGB $freeBytes
            UsedPercent = $usedPercent
        }
    }
    catch {
        Write-Warning "无法读取内存信息：$($_.Exception.Message)"
        return $null
    }
}

function Show-MemorySnapshot {
    param([string]$Title)

    Write-Section $Title
    $memory = Get-MemorySnapshot
    if ($null -eq $memory) {
        return
    }

    Write-Host ("总内存：{0} GB" -f $memory.TotalGB)
    Write-Host ("已用内存：{0} GB" -f $memory.UsedGB)
    Write-Host ("可用内存：{0} GB" -f $memory.FreeGB)
    Write-Host ("内存使用率：{0}%" -f $memory.UsedPercent)
}

function Get-Config {
    $defaultConfig = [pscustomobject]@{
        allowKillEdge = $true
        allowShutdownWSL = $true
        allowCleanTemp = $true
        allowKillDocker = $false
        allowEmptyRecycleBin = $false
        allowCleanWindowsUpdateCache = $false
    }

    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.json"
    if (-not (Test-Path -Path $configPath)) {
        Write-Warning "未找到 config.json，将使用默认配置。"
        return $defaultConfig
    }

    try {
        return Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "读取 config.json 失败，将使用默认配置：$($_.Exception.Message)"
        return $defaultConfig
    }
}

function Confirm-DangerousAction {
    param([string]$ActionName)

    Write-Host ""
    Write-Host "危险操作：$ActionName" -ForegroundColor Red
    $answer = Read-Host "请输入 YES 确认执行"
    return $answer -eq "YES"
}

function Invoke-SafeStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Step $Name
    try {
        & $Action
    }
    catch {
        Write-Warning "$Name 失败：$($_.Exception.Message)"
    }
}

function Stop-WSL {
    param($Config)

    if (-not $Config.allowShutdownWSL) {
        Write-Skip "配置禁止执行 wsl --shutdown。"
        return
    }

    Invoke-SafeStep "关闭 WSL2 发行版以释放 vmmem/vmmemWSL 内存" {
        $output = & wsl.exe --shutdown 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "wsl --shutdown 返回错误：$output"
        }
        else {
            Write-Host "WSL 已关闭。"
        }
    }
}

function Stop-EdgeBackgroundProcesses {
    param($Config)

    if (-not $Config.allowKillEdge) {
        Write-Skip "配置禁止关闭 Edge 后台进程。"
        return
    }

    Invoke-SafeStep "关闭 Edge 后台进程" {
        $processes = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
        if ($null -eq $processes) {
            Write-Host "未发现 Edge 进程。"
            return
        }

        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Write-Host ("已关闭 msedge PID {0}" -f $process.Id)
            }
            catch {
                Write-Warning ("关闭 msedge PID {0} 失败：{1}" -f $process.Id, $_.Exception.Message)
            }
        }
    }
}

function Clear-DirectoryChildren {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Warning "路径为空，已跳过。"
        return
    }

    try {
        if (-not (Test-Path -Path $Path)) {
            Write-Skip "路径不存在：$Path"
            return
        }

        Get-ChildItem -Path $Path -Force -ErrorAction Stop | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                Write-Host ("已删除：{0}" -f $_.FullName)
            }
            catch {
                Write-Warning ("删除失败：{0}，原因：{1}" -f $_.FullName, $_.Exception.Message)
            }
        }
    }
    catch {
        Write-Warning "读取目录失败：$Path，原因：$($_.Exception.Message)"
    }
}

function Clear-TempDirectories {
    param($Config)

    if (-not $Config.allowCleanTemp) {
        Write-Skip "配置禁止清理临时目录。"
        return
    }

    Invoke-SafeStep "清理用户临时目录" {
        Clear-DirectoryChildren -Path $env:TEMP
    }

    Invoke-SafeStep "清理 Windows Temp" {
        Clear-DirectoryChildren -Path (Join-Path -Path $env:WINDIR -ChildPath "Temp")
    }
}

function Stop-DockerDesktop {
    param($Config)

    if (-not $Config.allowKillDocker) {
        Write-Skip "配置未允许关闭 Docker Desktop。"
        return
    }

    if (-not (Confirm-DangerousAction -ActionName "关闭 Docker Desktop 和 Docker 后台进程")) {
        Write-Skip "用户未确认关闭 Docker Desktop。"
        return
    }

    Invoke-SafeStep "关闭 Docker Desktop 和 Docker 后台进程" {
        $names = @("Docker Desktop", "com.docker.backend")
        foreach ($name in $names) {
            $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq $name }
            foreach ($process in $processes) {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Write-Host ("已关闭 {0} PID {1}" -f $name, $process.Id)
                }
                catch {
                    Write-Warning ("关闭 {0} PID {1} 失败：{2}" -f $name, $process.Id, $_.Exception.Message)
                }
            }
        }
    }
}

function Stop-HyperVServices {
    param([switch]$Enabled)

    if (-not $Enabled) {
        Write-Skip "未指定 -IncludeHyperVServices，不会停止 Hyper-V 相关服务。"
        return
    }

    if (-not (Confirm-DangerousAction -ActionName "停止 Hyper-V 相关服务，可能影响 WSL2、Docker 和虚拟机")) {
        Write-Skip "用户未确认停止 Hyper-V 相关服务。"
        return
    }

    Invoke-SafeStep "停止 Hyper-V 相关服务" {
        $serviceNames = @("vmcompute", "vmms")
        foreach ($serviceName in $serviceNames) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($null -eq $service) {
                    Write-Skip "未发现服务：$serviceName"
                    continue
                }

                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                Write-Host "已停止服务：$serviceName"
            }
            catch {
                Write-Warning "停止服务 $serviceName 失败：$($_.Exception.Message)"
            }
        }
    }
}

function Clear-RecycleBinSafe {
    param($Config)

    if (-not $Config.allowEmptyRecycleBin) {
        Write-Skip "配置未允许清空回收站。"
        return
    }

    if (-not (Confirm-DangerousAction -ActionName "清空回收站")) {
        Write-Skip "用户未确认清空回收站。"
        return
    }

    Invoke-SafeStep "清空回收站" {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "回收站已清空。"
    }
}

function Clear-WindowsUpdateCache {
    param($Config)

    if (-not $Config.allowCleanWindowsUpdateCache) {
        Write-Skip "配置未允许清理 Windows Update 缓存。"
        return
    }

    if (-not (Confirm-DangerousAction -ActionName "清理 Windows Update 缓存")) {
        Write-Skip "用户未确认清理 Windows Update 缓存。"
        return
    }

    Invoke-SafeStep "清理 Windows Update 缓存" {
        Stop-Service -Name "wuauserv" -Force -ErrorAction Stop
        Clear-DirectoryChildren -Path (Join-Path -Path $env:WINDIR -ChildPath "SoftwareDistribution\Download")
        Start-Service -Name "wuauserv" -ErrorAction Stop
        Write-Host "Windows Update 缓存清理完成。"
    }
}

$config = Get-Config
Show-MemorySnapshot -Title "清理前内存"
Stop-WSL -Config $config
Stop-EdgeBackgroundProcesses -Config $config
Clear-TempDirectories -Config $config
Stop-DockerDesktop -Config $config
Stop-HyperVServices -Enabled:$IncludeHyperVServices
Clear-RecycleBinSafe -Config $config
Clear-WindowsUpdateCache -Config $config
Show-MemorySnapshot -Title "清理后内存"

Write-Host ""
Write-Host "安全清理流程结束。未默认删除用户文件，也未 compact WSL vhdx。" -ForegroundColor Green
