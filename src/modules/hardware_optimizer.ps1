# ==============================================================================
# Módulo: Otimização de Hardware (GPU NVIDIA/AMD & CPU AMD/Intel)
# ==============================================================================

function Get-HardwareOptimizationProfile {
    $cpuName = "CPU Desconhecida"
    $cpuVendor = "Other"
    $cpuCores = 0
    $cpuThreads = 0

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            if ($cpu.Name) { $cpuName = ([string]$cpu.Name).Trim() }
            $mfr = [string]$cpu.Manufacturer
            if ($cpuName -match 'AMD|Ryzen|EPYC|Athlon' -or $mfr -match 'AMD') {
                $cpuVendor = "AMD"
            } elseif ($cpuName -match 'Intel|Core|Xeon|Pentium|Celeron' -or $mfr -match 'Intel') {
                $cpuVendor = "Intel"
            }
            if ($cpu.NumberOfCores) { $cpuCores = [int]$cpu.NumberOfCores }
            if ($cpu.NumberOfLogicalProcessors) { $cpuThreads = [int]$cpu.NumberOfLogicalProcessors }
        }
    } catch {}

    $isRyzenX3D = ($cpuVendor -eq "AMD") -and ($cpuName -match 'X3D')
    $isIntelHybrid = ($cpuVendor -eq "Intel") -and ($cpuName -match '1[2-5]\d{2}|Ultra|Core\(TM\) [3579] 1\d{2}')

    $gpuList = New-Object System.Collections.Generic.List[string]
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        foreach ($g in $gpus) {
            $gName = ([string]$g.Name).Trim()
            if ($gName -and ($gName -notmatch 'Microsoft Basic|Remote|Parsec|Virtual|Meta')) {
                [void]$gpuList.Add($gName)
            }
        }
        if ($gpuList.Count -eq 0) {
            foreach ($g in $gpus) {
                $gName = ([string]$g.Name).Trim()
                if ($gName) { [void]$gpuList.Add($gName) }
            }
        }
    } catch {}

    $gpuArray = $gpuList.ToArray()
    $joinedGpu = $gpuArray -join " | "
    $hasNvidia = ($joinedGpu -match 'NVIDIA|GeForce|Quadro|RTX|GTX')
    $hasAmdGpu = ($joinedGpu -match 'AMD|Radeon')
    $hasIntelGpu = ($joinedGpu -match 'Intel')

    $primaryGpu = "GPU não detectada"
    $discrete = $gpuArray | Where-Object { $_ -match 'NVIDIA|GeForce|Quadro|RTX|GTX|Radeon RX|Radeon Pro|Arc' } | Select-Object -First 1
    if ($discrete) {
        $primaryGpu = $discrete
    } elseif ($gpuArray.Count -gt 0) {
        $primaryGpu = $gpuArray[0]
    }

    $tips = New-Object System.Collections.Generic.List[string]
    if ($hasNvidia) { [void]$tips.Add("NVIDIA detectada (MSI Mode e Telemetria disponíveis)") }
    if ($hasAmdGpu) { [void]$tips.Add("AMD Radeon detectada (Desativar ULPS e MSI Mode disponíveis)") }
    if ($cpuVendor -eq "AMD") {
        if ($isRyzenX3D) {
            [void]$tips.Add("Ryzen X3D detectado (mantenha o Modo de Jogo ativado para agendamento 3D V-Cache)")
        } else {
            [void]$tips.Add("CPU AMD Ryzen detectada (Core Parking e Boost AC recomendados)")
        }
    } elseif ($cpuVendor -eq "Intel") {
        if ($isIntelHybrid) {
            [void]$tips.Add("CPU Intel Híbrida detectada (agendamento prioritário de P-Cores recomendado)")
        } else {
            [void]$tips.Add("CPU Intel detectada (Core Parking e Speed Shift EPP disponíveis)")
        }
    }
    if ($tips.Count -eq 0) {
        [void]$tips.Add("Use os ajustes gerais de GPU e CPU ou clique em Auto-Selecionar Recomendados.")
    }

    return [pscustomobject]@{
        CpuName       = $cpuName
        CpuVendor     = $cpuVendor
        CpuCores      = $cpuCores
        CpuThreads    = $cpuThreads
        IsRyzenX3D    = $isRyzenX3D
        IsIntelHybrid = $isIntelHybrid
        GpuNames      = $gpuArray
        PrimaryGpuName = $primaryGpu
        HasNvidia     = $hasNvidia
        HasAmdGpu     = $hasAmdGpu
        HasIntelGpu   = $hasIntelGpu
        SummaryTips   = ($tips.ToArray() -join " | ")
    }
}

function Get-HardwareOptimizationCatalog {
    $items = New-Object System.Collections.Generic.List[object]

    $defs = @(
        @{
            Key = "HwGpuHags"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Agendamento de GPU por Hardware (HAGS)"
            Description = "Ativa Hardware-Accelerated GPU Scheduling (HwSchMode=2) para reduzir latência de renderização e overhead de CPU em jogos compatíveis."
            ApplySummary = "HKLM:\...\GraphicsDrivers\HwSchMode = 2 (Requer reinício)"
            UndoSummary  = "HKLM:\...\GraphicsDrivers\HwSchMode = 1 (Padrão)"
        },
        @{
            Key = "HwGpuMmcss"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Prioridade MMCSS para Jogos (CPU/GPU/SFIO)"
            Description = "Ajusta Multimedia Class Scheduler (SystemResponsiveness=10, GPU Priority=8, Priority=6, Scheduling Category=High) para menor stuttering."
            ApplySummary = "HKLM:\...\Multimedia\SystemProfile + Tasks\Games -> Prioridade Alta"
            UndoSummary  = "HKLM:\...\Multimedia\SystemProfile + Tasks\Games -> Padrão Windows"
        },
        @{
            Key = "HwGpuPcieLspm"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Economia PCIe (ASPM / Link State)"
            Description = "Define Link State Power Management (SUB_PCIEXPRESS ASPM) para Desligado na tomada (AC), evitando quedas de largura de banda na GPU."
            ApplySummary = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0"
            UndoSummary  = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 2"
        },
        @{
            Key = "HwGpuShaderCache"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $false; Risk = "Seguro"
            Content = "Limpar Cache de Shaders (DirectX / NVIDIA / AMD)"
            Description = "Remove caches antigos de shaders (D3DSCache, DXCache, GLCache, VkCache) que podem causar travamentos após troca de driver ou updates."
            ApplySummary = "Limpar pastas de Shader Cache em LocalAppData / LocalLow"
            UndoSummary  = "Limpeza de cache é pontual (os shaders são recriados automaticamente)"
        },
        @{
            Key = "HwNvidiaMsiMode"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $true; Risk = "Seguro"
            Content = "Ativar MSI Mode na GPU NVIDIA (VEN_10DE)"
            Description = "Habilita Message Signaled Interrupts (MSISupported=1) no dispositivo PCI de vídeo NVIDIA para reduzir latência de interrupções DPC."
            ApplySummary = "HKLM:\...\PCI\VEN_10DE*\...\Interrupt Management\MSISupported = 1"
            UndoSummary  = "HKLM:\...\PCI\VEN_10DE*\...\Interrupt Management\MSISupported = 0"
        },
        @{
            Key = "HwNvidiaTelemetry"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Telemetria NVIDIA (NvTelemetryContainer)"
            Description = "Desativa o serviço NvTelemetryContainer e tarefas agendadas NvTmRep/NvTmMon que coletam métricas em segundo plano."
            ApplySummary = "Serviço NvTelemetryContainer -> Disabled + tarefas NvTm* desativadas"
            UndoSummary  = "Serviço NvTelemetryContainer -> Automatic + tarefas NvTm* reativadas"
        },
        @{
            Key = "HwNvidiaPowerMizer"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $false; Risk = "Avançado"
            Content = "Desativar PowerMizer Dinâmico (Clock Fixo Desktop)"
            Description = "Força PerfLevelSrc/PowerMizerLevel=1 na chave de vídeo NVIDIA para impedir redução agressiva de clock. Aumenta consumo em idle."
            ApplySummary = "Chave Class\{4d36e968...} NVIDIA: PowerMizerLevelAC=1, PerfLevelSrc=8738"
            UndoSummary  = "Remover entradas PowerMizer customizadas (retorna ao driver padrão)"
        },
        @{
            Key = "HwAmdUlps"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar ULPS (Ultra Low Power State - AMD)"
            Description = "Define EnableUlps=0 no driver AMD Radeon para evitar quedas bruscas de clock, tela preta ao acordar e microstuttering."
            ApplySummary = "Chave Class\{4d36e968...} AMD: EnableUlps = 0"
            UndoSummary  = "Chave Class\{4d36e968...} AMD: EnableUlps = 1"
        },
        @{
            Key = "HwAmdMsiMode"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Ativar MSI Mode na GPU AMD (VEN_1002)"
            Description = "Habilita Message Signaled Interrupts (MSISupported=1) na GPU PCI AMD Radeon para menor latência de interrupções."
            ApplySummary = "HKLM:\...\PCI\VEN_1002*\...\Interrupt Management\MSISupported = 1"
            UndoSummary  = "HKLM:\...\PCI\VEN_1002*\...\Interrupt Management\MSISupported = 0"
        },
        @{
            Key = "HwAmdCrashDefender"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Telemetria / Crash Defender AMD"
            Description = "Desativa os serviços AMD Crash Defender Service e AUEPLauncher, preservando AMD External Events Utility (FreeSync)."
            ApplySummary = "Serviços AMD Crash Defender / AUEPLauncher -> Disabled"
            UndoSummary  = "Serviços AMD Crash Defender / AUEPLauncher -> Manual"
        },
        @{
            Key = "HwCpuCoreParking"; Group = "CpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Core Parking na Tomada (CPMINCORES=100%)"
            Description = "Mantém 100% dos núcleos ativos no plano de energia atual na tomada (AC), reduzindo latência ao alternar cargas em jogos."
            ApplySummary = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100"
            UndoSummary  = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 10"
        },
        @{
            Key = "HwCpuPowerThrottling"; Group = "CpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Power Throttling do Windows"
            Description = "Define PowerThrottlingOff=1 no registro para evitar que o Windows limite clocks de processos e jogos em segundo plano."
            ApplySummary = "HKLM:\...\Control\Power\PowerThrottling\PowerThrottlingOff = 1"
            UndoSummary  = "Remover PowerThrottlingOff (comportamento padrão)"
        },
        @{
            Key = "HwCpuAmdRyzenBoost"; Group = "CpuAmd"; Vendor = "AMD_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Otimizar Boost & EPP para AMD Ryzen (AC)"
            Description = "Define PERFBOOSTMODE=2 (Aggressive) e PERFEPP=0 na tomada para resposta rápida de Precision Boost em CPUs Ryzen."
            ApplySummary = "powercfg AC: PERFBOOSTMODE=2, PERFEPP=0"
            UndoSummary  = "powercfg AC: PERFEPP=50"
        },
        @{
            Key = "HwCpuAmdX3DGameMode"; Group = "CpuAmd"; Vendor = "AMD_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Otimizar Agendamento Ryzen X3D (Modo de Jogo Ativo)"
            Description = "Garante AllowAutoGameMode=1 e AutoGameModeEnabled=1 para que o driver AMD 3D V-Cache direcione jogos ao CCD com V-Cache."
            ApplySummary = "HKCU:\Software\Microsoft\GameBar -> AutoGameModeEnabled = 1"
            UndoSummary  = "HKCU:\Software\Microsoft\GameBar -> AutoGameModeEnabled = 0"
        },
        @{
            Key = "HwCpuIntelHybridPolicy"; Group = "CpuIntel"; Vendor = "Intel_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Priorizar P-Cores em CPUs Intel Híbridas"
            Description = "Ajusta SCHEDPOLICY=2 e SHORTSCHEDPOLICY=2 (Performant processors) para priorizar núcleos de performance (P-Cores) em jogos."
            ApplySummary = "powercfg AC: SCHEDPOLICY=2, SHORTSCHEDPOLICY=2"
            UndoSummary  = "powercfg AC: SCHEDPOLICY=5, SHORTSCHEDPOLICY=5"
        },
        @{
            Key = "HwCpuIntelEpp"; Group = "CpuIntel"; Vendor = "Intel_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Intel Speed Shift / EPP Desempenho Máximo (AC)"
            Description = "Define Energy Performance Preference (PERFEPP=0) na tomada para atingir clocks turbo mais rápido sem atraso de rampa."
            ApplySummary = "powercfg AC: PERFEPP=0"
            UndoSummary  = "powercfg AC: PERFEPP=50"
        }
    )

    foreach ($d in $defs) {
        [void]$items.Add([pscustomobject]$d)
    }
    return ,$items.ToArray()
}

function Get-DisplayPciDeviceRegPaths {
    param([Parameter(Mandatory=$true)][string]$VendorId)

    $results = New-Object System.Collections.Generic.List[string]
    $pciRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    if (-not (Test-Path $pciRoot)) { return ,$results.ToArray() }

    try {
        $venDirs = Get-ChildItem -Path $pciRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "${VendorId}*" }
        foreach ($vd in $venDirs) {
            $instDirs = Get-ChildItem -Path $vd.PSPath -ErrorAction SilentlyContinue
            foreach ($inst in $instDirs) {
                $props = Get-ItemProperty -Path $inst.PSPath -ErrorAction SilentlyContinue
                if ($props -and ($props.ClassGUID -eq "{4d36e968-e325-11ce-bfc1-08002be10318}")) {
                    $msiPath = Join-Path $inst.PSPath "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    $msiPath = $msiPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\'
                    [void]$results.Add($msiPath)
                }
            }
        }
    } catch {}
    return ,$results.ToArray()
}

function Get-DisplayClassRegPaths {
    param([Parameter(Mandatory=$true)][string]$ProviderPattern)

    $results = New-Object System.Collections.Generic.List[string]
    $classRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    if (-not (Test-Path $classRoot)) { return ,$results.ToArray() }

    try {
        $subKeys = Get-ChildItem -Path $classRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }
        foreach ($sk in $subKeys) {
            $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
            if ($props -and ($props.ProviderName -match $ProviderPattern -or $props.DriverDesc -match $ProviderPattern)) {
                $cleanPath = $sk.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\'
                [void]$results.Add($cleanPath)
            }
        }
    } catch {}
    return ,$results.ToArray()
}

function Invoke-PowerCfgSetting {
    param(
        [Parameter(Mandatory=$true)][string]$Subgroup,
        [Parameter(Mandatory=$true)][string]$Setting,
        [Parameter(Mandatory=$true)][int]$Value,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] powercfg /setacvalueindex SCHEME_CURRENT $Subgroup $Setting $Value" "INFO"
        return
    }

    try {
        $p = Start-Process -FilePath "powercfg.exe" -ArgumentList "/setacvalueindex SCHEME_CURRENT $Subgroup $Setting $Value" -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            $null = Start-Process -FilePath "powercfg.exe" -ArgumentList "/setactive SCHEME_CURRENT" -NoNewWindow -Wait -PassThru
            Write-ToolLog "Energia (powercfg): $Subgroup/$Setting = $Value aplicado." "INFO"
        } else {
            Write-ToolLog "powercfg retornou código $($p.ExitCode) para $Subgroup/$Setting (pode não ser suportado nesta CPU/plano)." "WARN"
        }
    } catch {
        Write-ToolLog "Aviso ao executar powercfg ($Subgroup/$Setting): $($_.Exception.Message)" "WARN"
    }
}

function Clear-GpuShaderCaches {
    param([switch]$DryRun)

    $cacheDirs = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
        (Join-Path (Split-Path $env:LOCALAPPDATA) "LocalLow\NVIDIA\PerDriverVersion\DXCache")
    )

    $totalRemoved = 0
    foreach ($dir in $cacheDirs) {
        if (-not (Test-Path $dir)) { continue }
        $files = @(Get-ChildItem -Path $dir -Recurse -File -Force -ErrorAction SilentlyContinue)
        if ($DryRun) {
            Write-ToolLog "[DRY-RUN] Limparia $($files.Count) arquivo(s) em $dir" "INFO"
            continue
        }
        foreach ($f in $files) {
            try {
                Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                $totalRemoved++
            } catch {}
        }
    }

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] Limpeza de Shader Cache simulada." "SUCCESS"
    } else {
        Write-ToolLog "Limpeza de Shader Cache concluída ($totalRemoved arquivo(s) removidos; arquivos em uso foram preservados)." "SUCCESS"
    }
}

function Set-ScheduledTasksByPrefix {
    param(
        [Parameter(Mandatory=$true)][string]$Pattern,
        [bool]$Enable = $false,
        [switch]$DryRun
    )

    $actionLabel = if ($Enable) { "Habilitar" } else { "Desabilitar" }
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $Pattern })
        if ($tasks.Count -eq 0) {
            $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "${prefix}Nenhuma tarefa agendada encontrada para [$Pattern]." "INFO"
            return
        }
        foreach ($t in $tasks) {
            if ($DryRun) {
                Write-ToolLog "[DRY-RUN] $actionLabel tarefa agendada: $($t.TaskPath)$($t.TaskName)" "INFO"
            } else {
                if ($Enable) {
                    Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                }
                Write-ToolLog "Tarefa [$($t.TaskName)] -> $actionLabel." "INFO"
            }
        }
    } catch {}
}

function Invoke-HardwareOptimization {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [switch]$Undo,
        [switch]$DryRun
    )

    $catalog = Get-HardwareOptimizationCatalog
    $item = $catalog | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    $label = if ($item) { $item.Content } else { $Key }
    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    $verb = if ($Undo) { "Desfazendo" } else { "Aplicando" }

    Write-ToolLog "${prefix}$verb [$label]..." "INFO"

    switch ($Key) {
        "HwGpuHags" {
            $val = if ($Undo) { 1 } else { 2 }
            Set-RegistryEntry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwGpuMmcss" {
            $sysResp = if ($Undo) { 20 } else { 10 }
            $gpuPrio = if ($Undo) { 2 } else { 8 }
            $prio    = if ($Undo) { 2 } else { 6 }
            $sched   = if ($Undo) { "Medium" } else { "High" }
            $sfio    = if ($Undo) { "Normal" } else { "High" }

            $mmRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            $games  = "$mmRoot\Tasks\Games"
            Set-RegistryEntry -Path $mmRoot -Name "SystemResponsiveness" -Type "DWord" -Value $sysResp -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "GPU Priority" -Type "DWord" -Value $gpuPrio -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "Priority" -Type "DWord" -Value $prio -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "Scheduling Category" -Type "String" -Value $sched -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "SFIO Priority" -Type "String" -Value $sfio -DryRun:$DryRun
        }
        "HwGpuPcieLspm" {
            $val = if ($Undo) { 2 } else { 0 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PCIEXPRESS" -Setting "ASPM" -Value $val -DryRun:$DryRun
        }
        "HwGpuShaderCache" {
            if ($Undo) {
                Write-ToolLog "${prefix}Limpeza de Shader Cache não requer reversão (caches são recriados pelos jogos)." "INFO"
            } else {
                Clear-GpuShaderCaches -DryRun:$DryRun
            }
        }
        "HwNvidiaMsiMode" {
            $paths = Get-DisplayPciDeviceRegPaths -VendorId "VEN_10DE"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma GPU PCI NVIDIA (VEN_10DE) encontrada neste sistema." "INFO"
            } else {
                $val = if ($Undo) { 0 } else { 1 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "MSISupported" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwNvidiaTelemetry" {
            $svcMode = if ($Undo) { "Automatic" } else { "Disabled" }
            Set-ServiceStartupSafe -Name "NvTelemetryContainer" -StartupType $svcMode -DryRun:$DryRun
            Set-ScheduledTasksByPrefix -Pattern "NvTmRep*" -Enable:$Undo -DryRun:$DryRun
            Set-ScheduledTasksByPrefix -Pattern "NvTmMon*" -Enable:$Undo -DryRun:$DryRun
        }
        "HwNvidiaPowerMizer" {
            $paths = Get-DisplayClassRegPaths -ProviderPattern "NVIDIA"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma chave de classe de vídeo NVIDIA encontrada." "INFO"
            } else {
                foreach ($p in $paths) {
                    if ($Undo) {
                        foreach ($n in @("PerfLevelSrc", "PowerMizerEnable", "PowerMizerLevel", "PowerMizerLevelAC")) {
                            Set-RegistryEntry -Path $p -Name $n -Type "DWord" -Value "<RemoveEntry>" -DryRun:$DryRun
                        }
                    } else {
                        Set-RegistryEntry -Path $p -Name "PerfLevelSrc" -Type "DWord" -Value 8738 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerEnable" -Type "DWord" -Value 1 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerLevel" -Type "DWord" -Value 1 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerLevelAC" -Type "DWord" -Value 1 -DryRun:$DryRun
                    }
                }
            }
        }
        "HwAmdUlps" {
            $paths = Get-DisplayClassRegPaths -ProviderPattern "AMD|ATI|Radeon"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma chave de classe de vídeo AMD encontrada." "INFO"
            } else {
                $val = if ($Undo) { 1 } else { 0 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "EnableUlps" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwAmdMsiMode" {
            $paths = Get-DisplayPciDeviceRegPaths -VendorId "VEN_1002"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma GPU PCI AMD (VEN_1002) encontrada neste sistema." "INFO"
            } else {
                $val = if ($Undo) { 0 } else { 1 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "MSISupported" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwAmdCrashDefender" {
            $svcMode = if ($Undo) { "Manual" } else { "Disabled" }
            Set-ServiceStartupSafe -Name "AMD Crash Defender Service" -StartupType $svcMode -DryRun:$DryRun
            Set-ServiceStartupSafe -Name "AUEPLauncher" -StartupType $svcMode -DryRun:$DryRun
        }
        "HwCpuCoreParking" {
            $val = if ($Undo) { 10 } else { 100 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "CPMINCORES" -Value $val -DryRun:$DryRun
        }
        "HwCpuPowerThrottling" {
            $ptPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
            $val = if ($Undo) { "<RemoveEntry>" } else { 1 }
            Set-RegistryEntry -Path $ptPath -Name "PowerThrottlingOff" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwCpuAmdRyzenBoost" {
            if ($Undo) {
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value 50 -DryRun:$DryRun
            } else {
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFBOOSTMODE" -Value 2 -DryRun:$DryRun
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value 0 -DryRun:$DryRun
            }
        }
        "HwCpuAmdX3DGameMode" {
            $gbPath = "HKCU:\Software\Microsoft\GameBar"
            $val = if ($Undo) { 0 } else { 1 }
            Set-RegistryEntry -Path $gbPath -Name "AllowAutoGameMode" -Type "DWord" -Value $val -DryRun:$DryRun
            Set-RegistryEntry -Path $gbPath -Name "AutoGameModeEnabled" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwCpuIntelHybridPolicy" {
            $val = if ($Undo) { 5 } else { 2 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "SCHEDPOLICY" -Value $val -DryRun:$DryRun
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "SHORTSCHEDPOLICY" -Value $val -DryRun:$DryRun
        }
        "HwCpuIntelEpp" {
            $val = if ($Undo) { 50 } else { 0 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value $val -DryRun:$DryRun
        }
        default {
            Write-ToolLog "Otimização de hardware desconhecida: $Key" "WARN"
            return
        }
    }

    Write-ToolLog "${prefix}Concluído: $label" "SUCCESS"
}

function Get-HardwareChangesPreview {
    param(
        [Parameter(Mandatory=$true)][string[]]$Keys,
        [switch]$Undo
    )

    $catalog = Get-HardwareOptimizationCatalog
    $byKey = @{}
    foreach ($c in $catalog) { $byKey[$c.Key] = $c }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($k in $Keys) {
        if (-not $byKey.ContainsKey($k)) { continue }
        $c = $byKey[$k]
        $detail = if ($Undo) { $c.UndoSummary } else { $c.ApplySummary }
        [void]$items.Add([pscustomobject]@{
            Key     = $c.Key
            Content = $c.Content
            Group   = $c.Group
            Vendor  = $c.Vendor
            Risk    = $c.Risk
            Action  = if ($Undo) { "Desfazer" } else { "Aplicar" }
            Detail  = $detail
        })
    }
    return ,$items.ToArray()
}

function Format-HardwareChangesPreviewText {
    param(
        [Parameter(Mandatory=$true)][string[]]$Keys,
        [switch]$Undo
    )

    $preview = Get-HardwareChangesPreview -Keys $Keys -Undo:$Undo
    $modeLabel = if ($Undo) { "REVERSÃO (DESFAZER)" } else { "APLICAÇÃO" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("  PRÉ-VISUALIZAÇÃO DE HARDWARE (GPU & CPU) - $modeLabel")
    [void]$sb.AppendLine("  Ajustes selecionados: $($preview.Count)")
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("")

    foreach ($p in $preview) {
        [void]$sb.AppendLine("* $($p.Content) [$($p.Key)] ($($p.Risk))")
        [void]$sb.AppendLine("    Alvo/Ação: $($p.Detail)")
        [void]$sb.AppendLine("")
    }

    return $sb.ToString().TrimEnd()
}

function Invoke-HardwareExternalTool {
    param(
        [Parameter(Mandatory=$true)][string]$ToolKey,
        [switch]$DryRun
    )

    $tools = @{
        NVCleanstall   = @{ Name = "NVCleanstall";            Winget = "TechPowerUp.NVCleanstall";                 Url = "https://www.techpowerup.com/nvcleanstall/" }
        DDU            = @{ Name = "Display Driver Uninstaller (DDU)"; Winget = "Wagnardsoft.DisplayDriverUninstaller"; Url = "https://www.wagnardsoft.com/display-driver-uninstaller-ddu-" }
        MSIAfterburner = @{ Name = "MSI Afterburner";         Winget = "Guru3D.Afterburner";                       Url = "https://www.msi.com/Landing/afterburner/graphics-cards" }
        GPUZ           = @{ Name = "TechPowerUp GPU-Z";       Winget = "TechPowerUp.GPU-Z";                        Url = "https://www.techpowerup.com/gpuz/" }
        CPUZ           = @{ Name = "CPUID CPU-Z";             Winget = "CPUID.CPU-Z";                              Url = "https://www.cpuid.com/softwares/cpu-z.html" }
        HWiNFO         = @{ Name = "HWiNFO";                  Winget = "REALiX.HWiNFO";                            Url = "https://www.hwinfo.com/download/" }
        NvidiaDrivers  = @{ Name = "Drivers Oficiais NVIDIA"; Winget = "";                                         Url = "https://www.nvidia.com/Download/index.aspx" }
        AmdDrivers     = @{ Name = "Drivers Oficiais AMD";    Winget = "";                                         Url = "https://www.amd.com/en/support" }
        IntelDrivers   = @{ Name = "Drivers Oficiais Intel";  Winget = "";                                         Url = "https://www.intel.com/content/www/us/en/support/detect.html" }
    }

    if (-not $tools.ContainsKey($ToolKey)) {
        Write-ToolLog "Ferramenta externa desconhecida: $ToolKey" "WARN"
        return
    }

    $t = $tools[$ToolKey]
    if ($DryRun) {
        if ($t.Winget) {
            Write-ToolLog "[DRY-RUN] Instalaria $($t.Name) via WinGet ($($t.Winget)) ou abriria $($t.Url)." "INFO"
        } else {
            Write-ToolLog "[DRY-RUN] Abriria página oficial $($t.Name): $($t.Url)" "INFO"
        }
        return
    }

    if ($t.Winget -and (Get-Command "winget.exe" -ErrorAction SilentlyContinue) -and (Get-Command "Install-PackagesBatch" -ErrorAction SilentlyContinue)) {
        Install-PackagesBatch -Apps @([pscustomobject]@{ Content = $t.Name; Winget = $t.Winget; Choco = "na" }) -Manager "WinGet"
    } else {
        Write-ToolLog "Abrindo página oficial de $($t.Name): $($t.Url)" "INFO"
        try {
            Start-Process $t.Url
        } catch {
            Write-ToolLog "Erro ao abrir URL $($t.Url): $($_.Exception.Message)" "ERROR"
        }
    }
}
