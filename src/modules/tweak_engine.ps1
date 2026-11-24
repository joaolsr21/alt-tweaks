# ==============================================================================
# Módulo: Motor Declarativo de Tweaks, Preferências, Energia e Relatórios
# ==============================================================================

function Set-RegistryEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Type = "DWord",
        $Value
    )

    try {
        if (-not (Get-PSDrive -Name "HKU" -ErrorAction SilentlyContinue)) {
            New-PSDrive -PSProvider Registry -Name "HKU" -Root "HKEY_USERS" -ErrorAction SilentlyContinue | Out-Null
        }

        if ($Value -eq "<RemoveEntry>") {
            $exists = $true
            try {
                Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Out-Null
            } catch {
                $exists = $false
            }
            if (-not $exists) {
                Write-ToolLog "Registro $Path\$Name já está ausente." "INFO"
                return
            }
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
            Write-ToolLog "Removido registro: $Path\$Name" "INFO"
            return
        }

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        $typedVal = switch ($Type) {
            "DWord" { [int]$Value }
            "QWord" { [long]$Value }
            default { [string]$Value }
        }
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $typedVal -Force -ErrorAction Stop | Out-Null
        Write-ToolLog "Registro definido: $Path\$Name = $typedVal ($Type)" "INFO"
    } catch {
        Write-ToolLog "Erro no registro ($Path\$Name): $($_.Exception.Message)" "WARN"
    }
}

function Set-ServiceStartupSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$StartupType
    )

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $current = if ($svc.PSObject.Properties.Name -contains "StartType") { [string]$svc.StartType } else { "" }
        if ($current -eq $StartupType) {
            return
        }

        if (($PSVersionTable.PSVersion.Major -lt 7) -and ($StartupType -eq "AutomaticDelayedStart")) {
            sc.exe config $Name start= delayed-auto | Out-Null
        } else {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
        Write-ToolLog "Serviço [$Name] ajustado para: $StartupType" "INFO"
    } catch {
        if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
            Write-ToolLog "Serviço [$Name] não encontrado neste sistema (ignorado)." "INFO"
        } else {
            Write-ToolLog "Não foi possível alterar o serviço [$Name]: $($_.Exception.Message)" "WARN"
        }
    }
}

function Invoke-ExplorerRefresh {
    param([string]$Action = "refresh")

    try {
        if ($Action -eq "restart") {
            $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
            Get-Process -Name "explorer" -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -eq $sessionId } |
                ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 300
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })) {
                Start-Process "explorer.exe"
            }
            Write-ToolLog "Windows Explorer reiniciado para aplicar alterações visuais." "INFO"
        } else {
            if (-not ([System.Management.Automation.PSTypeName]"WinRepairNativeWin32").Type) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinRepairNativeWin32 {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@
            }
            $result = [IntPtr]::Zero
            [void][WinRepairNativeWin32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, "ImmersiveColorSet", 0x2, 200, [ref]$result)
        }
    } catch {
        Write-ToolLog "Aviso ao atualizar Explorer: $($_.Exception.Message)" "WARN"
    }
}

function Invoke-ThemeRefresh {
    param([string]$Theme = "Auto")
    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync) {
        $sync.PendingThemeSync = $Theme
    }
}

function Set-ClassicContextMenu {
    param([switch]$Undo)

    $clsidPath = "HKCU:\Software\Classes\CLSID"
    $legacyPath = "$clsidPath\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $inprocLegacy = "$legacyPath\InprocServer32"

    try {
        if ($Undo) {
            if (Test-Path -LiteralPath $legacyPath) {
                Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction Stop
            }
            Write-ToolLog "Menu de contexto moderno do Windows 11 restaurado." "SUCCESS"
        } else {
            New-Item -Path $inprocLegacy -Force -ErrorAction Stop | Out-Null
            Set-Item -LiteralPath $inprocLegacy -Value "" -Force -ErrorAction Stop
            Write-ToolLog "Menu de contexto clássico ativado." "SUCCESS"
        }
        Invoke-ExplorerRefresh -Action "restart"
    } catch {
        Write-ToolLog "Erro ao alternar menu de contexto clássico: $($_.Exception.Message)" "ERROR"
    }
}

function Get-ToggleCurrentState {
    param($TweakObj)

    if (-not $TweakObj -or -not $TweakObj.registry) { return $false }

    if (-not (Get-PSDrive -Name "HKU" -ErrorAction SilentlyContinue)) {
        New-PSDrive -PSProvider Registry -Name "HKU" -Root "HKEY_USERS" -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($reg in $TweakObj.registry) {
        $currentVal = $null
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $props) {
                $currentVal = $props.($reg.Name)
            }
        }

        if ($null -eq $currentVal) {
            if ($reg.DefaultState -eq "true") {
                $currentVal = $reg.Value
            } elseif ($reg.DefaultState -eq "false") {
                $currentVal = $reg.OriginalValue
            }
        }

        if ($null -eq $currentVal) {
            if ($reg.Value -ne "<RemoveEntry>") { return $false }
        } elseif ([string]$currentVal -ne [string]$reg.Value) {
            return $false
        }
    }

    return $true
}

function ConvertFrom-ComboValuesMap {
    param($ValuesData)

    $map = [ordered]@{}
    if ($null -eq $ValuesData) { return $map }

    if ($ValuesData -is [string] -and $ValuesData -match '@\{(.*)\}') {
        $pairs = $Matches[1] -split ';'
        foreach ($pair in $pairs) {
            if ($pair -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
                $map[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    } elseif ($ValuesData -is [psobject]) {
        foreach ($p in $ValuesData.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    return $map
}

function Get-RegistryComboState {
    param(
        $Registry,
        [string[]]$ComboItems
    )

    if (-not $Registry) { return $null }
    $items = if ($ComboItems) { $ComboItems } else { @() }
    if ($items.Count -eq 0) {
        $firstMap = ConvertFrom-ComboValuesMap $Registry[0].Values
        $items = @($firstMap.Keys)
    }

    foreach ($stateName in $items) {
        $allMatch = $true
        foreach ($setting in @($Registry)) {
            $valMap = ConvertFrom-ComboValuesMap $setting.Values
            $targetVal = $valMap[$stateName]
            $expected = if ($targetVal -eq "<RemoveEntry>" -or $null -eq $targetVal) { [string]$setting.DefaultValue } else { [string]$targetVal }

            $actual = [string]$setting.DefaultValue
            if (Test-Path $setting.Path) {
                $p = Get-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
                if ($null -ne $p -and $null -ne $p.($setting.Name)) {
                    $actual = [string]$p.($setting.Name)
                }
            }
            if ($actual -ne $expected) {
                $allMatch = $false
                break
            }
        }
        if ($allMatch) { return $stateName }
    }

    return ($items | Select-Object -First 1)
}

function Set-RegistryComboState {
    param(
        $Registry,
        [Parameter(Mandatory=$true)][string]$State
    )

    if (-not $Registry) { return }
    foreach ($setting in @($Registry)) {
        $valMap = ConvertFrom-ComboValuesMap $setting.Values
        if ($valMap.Contains($State)) {
            Set-RegistryEntry -Path $setting.Path -Name $setting.Name -Type $setting.Type -Value $valMap[$State]
        }
    }
    Write-ToolLog "Estado do ajuste aplicado: $State" "SUCCESS"
}

function Invoke-DeclarativeTweak {
    param(
        [Parameter(Mandatory=$true)][string]$TweakKey,
        [Parameter(Mandatory=$true)]$TweakObj,
        [switch]$Undo
    )

    $label = if ($TweakObj.Content) { $TweakObj.Content } else { $TweakKey }
    $actionText = if ($Undo) { "Desfazendo" } else { "Aplicando" }
    Write-ToolLog "$actionText [$label]..." "INFO"

    # 1. Serviços
    if ($TweakObj.service) {
        foreach ($svcItem in @($TweakObj.service)) {
            $targetType = if ($Undo) { $svcItem.OriginalType } else { $svcItem.StartupType }
            if ($targetType) {
                Set-ServiceStartupSafe -Name $svcItem.Name -StartupType $targetType
            }
        }
    }

    # 2. Registros
    if ($TweakObj.registry) {
        foreach ($regItem in @($TweakObj.registry)) {
            $targetVal = if ($Undo) { $regItem.OriginalValue } else { $regItem.Value }
            if ($null -ne $targetVal) {
                Set-RegistryEntry -Path $regItem.Path -Name $regItem.Name -Type $regItem.Type -Value $targetVal
            }
        }
    }

    # 3. Scripts customizados
    $scripts = if ($Undo) { $TweakObj.UndoScript } else { $TweakObj.InvokeScript }
    if ($scripts) {
        foreach ($scriptText in @($scripts)) {
            if ([string]::IsNullOrWhiteSpace($scriptText)) { continue }
            try {
                $sb = [scriptblock]::Create($scriptText)
                $out = & $sb *>&1
                foreach ($line in @($out)) {
                    $txt = [string]$line
                    if (-not [string]::IsNullOrWhiteSpace($txt)) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            Write-ToolLog "  -> $txt" "WARN"
                        } elseif ($line -is [System.Management.Automation.WarningRecord]) {
                            Write-ToolLog "  -> $txt" "WARN"
                        } else {
                            Write-ToolLog "  -> $txt" "INFO"
                        }
                    }
                }
            } catch {
                Write-ToolLog "Aviso ao executar script de [$label]: $($_.Exception.Message)" "WARN"
            }
        }
    }

    Write-ToolLog "Concluído: $label" "SUCCESS"
}

function Set-UltimatePowerPlan {
    param([switch]$Enable)

    try {
        if ($Enable) {
            Write-ToolLog "Duplicando e ativando plano 'Desempenho Máximo' (Ultimate Performance)..." "INFO"
            $dup = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
            $guid = ($dup | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value | Select-Object -First 1
            if ($guid) {
                powercfg /setactive $guid | Out-Null
                Write-ToolLog "Plano Desempenho Máximo ativado ($guid)." "SUCCESS"
            } else {
                powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                Write-ToolLog "Comando de ativação do plano de energia executado." "SUCCESS"
            }
        } else {
            Write-ToolLog "Restaurando esquemas de energia padrão do Windows..." "INFO"
            powercfg /restoredefaultschemes | Out-Null
            Write-ToolLog "Planos de energia restaurados para o padrão de fábrica." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao configurar plano de energia: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-OOSU10 {
    Write-ToolLog "Preparando O&O ShutUp10++..." "INFO"
    $dir = Join-Path $env:LOCALAPPDATA "Alts"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $exePath = Join-Path $dir "OOSU10.exe"

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        Write-ToolLog "Baixando versão oficial de dl5.oo-software.com..." "INFO"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.DownloadFile("https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe", $exePath)
        Write-ToolLog "Iniciando O&O ShutUp10++ ($exePath)..." "SUCCESS"
        Start-Process -FilePath $exePath
    } catch {
        Write-ToolLog "Falha ao baixar/iniciar O&O ShutUp10++: $($_.Exception.Message)" "ERROR"
    }
}

function Export-EnvironmentReport {
    Write-ToolLog "Gerando Relatório Completo do Ambiente..." "INFO"
    $desktop = [Environment]::GetFolderPath("Desktop")
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $outFile = Join-Path $desktop "Relatorio_Ambiente_${env:COMPUTERNAME}_${stamp}.txt"

    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("  RELAT$([char]0xD3)RIO DO AMBIENTE - ALT'S")
        [void]$sb.AppendLine("  Data: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) | Host: $($env:COMPUTERNAME)")
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("")

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        [void]$sb.AppendLine("[SISTEMA OPERACIONAL & HARDWARE]")
        if ($os) { [void]$sb.AppendLine("OS: $($os.Caption) | Versão: $($os.Version) Build $($os.BuildNumber) | Arq: $($os.OSArchitecture)") }
        if ($cpu) { [void]$sb.AppendLine("CPU: $($cpu.Name) ($($cpu.NumberOfLogicalProcessors) threads)") }
        if ($cs) { [void]$sb.AppendLine("RAM: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB | Fabricante: $($cs.Manufacturer) $($cs.Model)") }
        [void]$sb.AppendLine("PowerShell: $($PSVersionTable.PSVersion)")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("[GERENCIADORES DE PACOTES]")
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        $ch = Get-Command choco.exe -ErrorAction SilentlyContinue
        [void]$sb.AppendLine("WinGet: $(if ($wg) { (& winget --version 2>$null) } else { 'Não instalado' })")
        [void]$sb.AppendLine("Chocolatey: $(if ($ch) { (& choco --version 2>$null) } else { 'Não instalado' })")
        [void]$sb.AppendLine("")

        $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
        if ($sync -and $sync.Configs -and $sync.Configs.Tweaks) {
            [void]$sb.AppendLine("[ESTADO ATUAL DE PREFERÊNCIAS & TOGGLES]")
            foreach ($p in $sync.Configs.Tweaks.PSObject.Properties) {
                if ($p.Value.Type -eq "Toggle") {
                    $st = Get-ToggleCurrentState -TweakObj $p.Value
                    [void]$sb.AppendLine("  [$($st)] $($p.Value.Content) ($($p.Name))")
                }
            }
            [void]$sb.AppendLine("")
        }

        if ($sync -and $sync.RecentLogs) {
            [void]$sb.AppendLine("[LOGS DA SESSÃO ATUAL]")
            foreach ($l in @($sync.RecentLogs)) {
                [void]$sb.AppendLine($l)
            }
        }

        [System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
        Write-ToolLog "Relatório de Ambiente salvo em: $outFile" "SUCCESS"
        Start-Process notepad.exe -ArgumentList "`"$outFile`""
    } catch {
        Write-ToolLog "Erro ao gerar relatório do ambiente: $($_.Exception.Message)" "ERROR"
    }
}
