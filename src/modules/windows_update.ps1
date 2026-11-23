# ==============================================================================
# Módulo: Gerenciamento Completo do Windows Update
# ==============================================================================

function Clear-WindowsUpdateSystemDenyAcl {
    foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc", "WaaSMedicSvc")) {
        $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        try {
            if (-not (Test-Path $serviceKeyPath)) { continue }
            $acl = Get-Acl -Path $serviceKeyPath -ErrorAction Stop
            $denyRules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.AccessControlType -eq "Deny" -and $_.IdentityReference.Value -eq "S-1-5-18"
            })
            if ($denyRules.Count -gt 0) {
                foreach ($r in $denyRules) { [void]$acl.RemoveAccessRule($r) }
                Set-Acl -Path $serviceKeyPath -AclObject $acl -ErrorAction Stop
                Write-ToolLog "Removida restrição Deny de SYSTEM em [$serviceName]." "INFO"
            }
        } catch {}
    }
}

function Enable-WindowsUpdateScheduledTasks {
    $tasks = @(
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'
    )
    foreach ($t in $tasks) {
        Get-ScheduledTask -TaskPath $t -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }
}

function Set-WindowsUpdateRecommended {
    Write-ToolLog "Configurando Windows Update para o Modo Recomendado (Segurança Estável)..." "INFO"
    Write-ToolLog "Desativa drivers via Update, adia recursos por 365 dias e qualidade por 4 dias." "INFO"
    try {
        Clear-WindowsUpdateSystemDenyAcl

        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auPath = "$wuPath\AU"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }

        Remove-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $wuPath -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue

        Set-Service -Name "BITS" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "UsoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "UsoSvc" -ErrorAction SilentlyContinue
        Enable-WindowsUpdateScheduledTasks

        foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
            if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Value 0 -Type DWord -Force

        Set-ItemProperty -Path $wuPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 4 -Type DWord -Force

        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 3 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUPowerManagement" -Value 0 -Type DWord -Force

        Write-ToolLog "Windows Update configurado no modo 'Segurança e Estabilidade Recomendada'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar Windows Update: $_" "ERROR"
    }
}

function Reset-WindowsUpdateDefault {
    Write-ToolLog "Restaurando Windows Update para as configurações originais de fábrica..." "INFO"
    try {
        $registryCleanup = @(
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"; Names = @("NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; Names = @("ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays", "DisableWindowsUpdateAccess") },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"; Names = @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays", "PauseUpdatesExpiryTime", "PauseFeatureUpdatesStartTime", "PauseQualityUpdatesStartTime") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"; Names = @("PreventDeviceMetadataFromNetwork") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"; Names = @("DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled") },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"; Names = @("DODownloadMode") }
        )
        foreach ($entry in $registryCleanup) {
            foreach ($n in $entry.Names) {
                Remove-ItemProperty -Path $entry.Path -Name $n -ErrorAction SilentlyContinue
            }
        }

        Clear-WindowsUpdateSystemDenyAcl

        Set-Service -Name "BITS" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "UsoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "UsoSvc" -ErrorAction SilentlyContinue
        try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Type DWord -Value 3 -ErrorAction SilentlyContinue } catch {}
        Enable-WindowsUpdateScheduledTasks

        Write-ToolLog "Windows Update restaurado para o padrão original da Microsoft." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao restaurar Windows Update: $_" "ERROR"
    }
}

function Disable-WindowsUpdateAll {
    Write-ToolLog "Desativando completamente serviços e políticas do Windows Update..." "INFO"
    try {
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
        Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Type DWord -Value 1 -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Type DWord -Value 1 -Force

        $doPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
        if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
        Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Type DWord -Value 0 -Force

        foreach ($svc in @("BITS", "wuauserv", "UsoSvc")) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$svc] parado e desativado." "INFO"
        }

        Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue

        $tasks = @(
            '\Microsoft\Windows\InstallService\*',
            '\Microsoft\Windows\UpdateOrchestrator\*',
            '\Microsoft\Windows\UpdateAssistant\*',
            '\Microsoft\Windows\WaaSMedic\*',
            '\Microsoft\Windows\WindowsUpdate\*',
            '\Microsoft\WindowsUpdate\*'
        )
        foreach ($t in $tasks) {
            Get-ScheduledTask -TaskPath $t -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }

        Write-ToolLog "Windows Update desativado. Reinicie o computador para consolidar." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desativar Windows Update: $_" "ERROR"
    }
}

function Pause-WindowsUpdateExtended {
    Write-ToolLog "Pausando atualizações do Windows Update até 2042..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }

        Set-ItemProperty -Path $wuPath -Name "PauseUpdatesExpiryTime" -Value "2042-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseFeatureUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseQualityUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force

        Write-ToolLog "Atualizações do Windows pausadas até 2042." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao pausar atualizações: $_" "ERROR"
    }
}
