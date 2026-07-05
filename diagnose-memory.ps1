Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ====" -ForegroundColor Cyan
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

function Show-MemorySummary {
    Write-Section "内存概览"
    $memory = Get-MemorySnapshot
    if ($null -eq $memory) {
        return
    }

    Write-Host ("总内存：{0} GB" -f $memory.TotalGB)
    Write-Host ("已用内存：{0} GB" -f $memory.UsedGB)
    Write-Host ("可用内存：{0} GB" -f $memory.FreeGB)
    Write-Host ("内存使用率：{0}%" -f $memory.UsedPercent)
}

function Show-TopMemoryProcesses {
    Write-Section "Top 15 内存占用进程"
    try {
        Get-Process |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First 15 @{Name = "进程名"; Expression = { $_.ProcessName } },
                @{Name = "PID"; Expression = { $_.Id } },
                @{Name = "内存(GB)"; Expression = { [math]::Round($_.WorkingSet64 / 1GB, 2) } } |
            Format-Table -AutoSize
    }
    catch {
        Write-Warning "无法读取进程列表：$($_.Exception.Message)"
    }
}

function Show-MemoryBreakdown {
    Write-Section "进程占用与系统内存说明"
    try {
        $allProcessesWorkingSet = (Get-Process | Measure-Object -Property WorkingSet64 -Sum).Sum
        Write-Host ("所有进程工作集占用合计：{0} GB" -f (Convert-BytesToGB $allProcessesWorkingSet))

        $memoryCounters = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
        $cacheGB = Convert-BytesToGB $memoryCounters.CacheBytes
        $pagedPoolGB = Convert-BytesToGB $memoryCounters.PoolPagedBytes
        $nonpagedPoolGB = Convert-BytesToGB $memoryCounters.PoolNonpagedBytes

        Write-Host ("系统 Cache Bytes：{0} GB" -f $cacheGB)
        Write-Host ("Paged Pool：{0} GB" -f $pagedPoolGB)
        Write-Host ("Nonpaged Pool：{0} GB" -f $nonpagedPoolGB)

        if ($pagedPoolGB -ge 4 -or $nonpagedPoolGB -ge 1) {
            Write-Warning "内核池占用偏高。Paged Pool 或 Nonpaged Pool 异常增大通常不是普通应用进程导致，常见原因是驱动、杀毒/安全软件、文件系统过滤驱动、虚拟化或硬件相关组件泄漏。"
        }
    }
    catch {
        Write-Warning "无法读取系统内存拆分：$($_.Exception.Message)"
    }

    Write-Host "说明：任务管理器里的已用内存不等于 Top 进程内存相加。"
    Write-Host "原因包括：系统文件缓存、Standby Cache、内存压缩、内核分页/非分页池、驱动占用、GPU 共享内存，以及 WSL2/Docker 虚拟化保留内存。"
    Write-Host "Top 15 只显示进程工作集中的前 15 个进程，不能代表整机全部内存来源。"
}

function Show-TopPagedMemoryProcesses {
    Write-Section "Top 10 进程提交/分页内存线索"
    try {
        Get-Process |
            Sort-Object -Property PagedMemorySize64 -Descending |
            Select-Object -First 10 @{Name = "进程名"; Expression = { $_.ProcessName } },
                @{Name = "PID"; Expression = { $_.Id } },
                @{Name = "PagedMemory(GB)"; Expression = { [math]::Round($_.PagedMemorySize64 / 1GB, 2) } },
                @{Name = "WorkingSet(GB)"; Expression = { [math]::Round($_.WorkingSet64 / 1GB, 2) } } |
            Format-Table -AutoSize
    }
    catch {
        Write-Warning "无法读取进程分页内存信息：$($_.Exception.Message)"
    }
}

function Test-ProcessExists {
    param([string]$Name)

    try {
        $process = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq $Name }
        return $null -ne $process
    }
    catch {
        return $false
    }
}

function Show-ProcessChecks {
    Write-Section "常见内存来源进程检查"
    $processNames = @(
        "vmmem",
        "vmmemWSL",
        "Docker Desktop",
        "com.docker.backend",
        "msedge",
        "Code",
        "Cursor"
    )

    foreach ($name in $processNames) {
        $exists = Test-ProcessExists -Name $name
        $status = if ($exists) { "存在" } else { "未发现" }
        Write-Host ("{0,-22} {1}" -f $name, $status)
    }
}

function Convert-NativeOutputToText {
    param([object[]]$Output)

    $text = ($Output | Out-String)
    return $text.Replace([string][char]0, "").Trim()
}

function Show-WSLStatus {
    Write-Section "WSL 运行状态"
    try {
        $output = & wsl.exe --list --running --quiet 2>&1
        $text = Convert-NativeOutputToText -Output $output
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "无法查询 WSL 状态：$text"
            return
        }

        $running = @($text -split "(`r`n|`n|`r)" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and ($_ -notmatch "Windows Subsystem for Linux") })

        if ($running.Count -gt 0) {
            Write-Host "正在运行的 WSL 发行版："
            $running | ForEach-Object { Write-Host " - $_" }
        }
        else {
            Write-Host "未发现正在运行的 WSL 发行版。"
        }
    }
    catch {
        Write-Warning "查询 WSL 状态失败：$($_.Exception.Message)"
    }
}

function Show-MemoryHints {
    Write-Section "可能的内存来源提示"
    Write-Host "1. WSL2：vmmem 或 vmmemWSL 占用较高时，通常来自运行中的 Linux 发行版。"
    Write-Host "2. Docker：Docker Desktop 和 com.docker.backend 可能通过 WSL2 或 Hyper-V 占用大量内存。"
    Write-Host "3. Edge：多标签页、扩展、后台进程可能持续占用内存。"
    Write-Host "4. IDE：VSCode、Cursor、AI 编译或语言服务可能占用较高内存。"
    Write-Host "5. Standby Cache：Windows 缓存会使用空闲内存，通常不是问题，系统会按需释放。"
    Write-Host "6. 驱动泄漏：若重启后短时间内内存持续异常上涨，可能需要检查驱动或内核组件。"
}

function Show-CleanupRecommendations {
    Write-Section "清理建议"
    Write-Host "1. 进程工作集高：优先关闭明确的大进程，例如浏览器、IDE、编译任务。"
    Write-Host "2. WSL2 / vmmemWSL 高：可运行 clean-memory.ps1，默认会执行 wsl --shutdown。"
    Write-Host "3. Docker 高：先停止容器；如需关闭 Docker Desktop，在 config.json 开启 allowKillDocker 后再运行清理。"
    Write-Host "4. Standby Cache / 系统缓存高：通常不需要清理，Windows 会在内存压力下自动回收。"
    Write-Host "5. Paged Pool / Nonpaged Pool 高：这类内核内存不能靠结束普通进程安全释放；建议先重启验证，若反复上涨，应排查驱动、安全软件、VPN、文件同步、虚拟化组件，可用 PoolMon 或 Windows Performance Recorder 定位。"
}

Show-MemorySummary
Show-TopMemoryProcesses
Show-MemoryBreakdown
Show-TopPagedMemoryProcesses
Show-WSLStatus
Show-ProcessChecks
Show-MemoryHints
Show-CleanupRecommendations
