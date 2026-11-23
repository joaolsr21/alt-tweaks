# ==============================================================================
# Módulo: Sistema de Logging e Status Assíncrono (Thread-Safe entre Runspaces e UI)
# ==============================================================================

function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
    }

    Write-Host $logLine -ForegroundColor $color

    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync -and $sync.LogQueue) {
        $sync.LogQueue.Enqueue($logLine)
    }
}

function Set-TaskStatus {
    param (
        [string]$Text = "Pronto",
        [bool]$IsRunning = $false
    )

    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync) {
        $sync.TaskStatus = $Text
        $sync.IsRunning = $IsRunning
    }
}
