# ==============================================================================
# Módulo: Recursos Opcionais, Acesso Remoto, NTP, Painéis & Perfil PowerShell
# ==============================================================================

function Get-FeatureStatus {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($f.State -eq 'Enabled')
    } catch {
        return $false
    }
}

function Enable-WslFeature {
    Write-ToolLog "Habilitando Subsistema Windows para Linux (WSL) e Plataforma de Máquina Virtual..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -NoRestart -ErrorAction Stop | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "WSL 2 habilitado com sucesso. (Reinicialização necessária para concluir)." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar WSL: $_" "ERROR"
    }
}

function Enable-WindowsSandbox {
    Write-ToolLog "Habilitando Área Restrita do Windows (Windows Sandbox)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Windows Sandbox habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Sandbox: $_" "ERROR"
    }
}

function Enable-HyperVFeature {
    Write-ToolLog "Habilitando Hyper-V e Ferramentas de Gerenciamento..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog "Hyper-V habilitado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao habilitar Hyper-V: $_" "ERROR"
    }
}

function Enable-NetFramework35 {
    Write-ToolLog "Instalando suporte ao .NET Framework 3.5 (.NET 2.0 e 3.0)..." "INFO"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -NoRestart -ErrorAction Stop | Out-Null
        Write-ToolLog ".NET Framework 3.5 instalado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao instalar .NET 3.5: $_" "ERROR"
    }
}

function Install-SelectedWindowsFeatures {
    param([Parameter(Mandatory=$true)][array]$FeatureEntries)

    Write-ToolLog "Iniciando instalação de $($FeatureEntries.Count) recurso(s) do Windows..." "INFO"
    foreach ($entry in $FeatureEntries) {
        $label = $entry.Content
        Write-ToolLog "Processando recurso: $label..." "INFO"
        try {
            if ($entry.feature) {
                foreach ($fname in @($entry.feature)) {
                    Write-ToolLog "  Habilitando recurso opcional [$fname]..." "INFO"
                    Enable-WindowsOptionalFeature -Online -FeatureName $fname -All -NoRestart -ErrorAction Stop | Out-Null
                }
            }
            if ($entry.InvokeScript) {
                foreach ($sc in @($entry.InvokeScript)) {
                    if ([string]::IsNullOrWhiteSpace($sc)) { continue }
                    $sb = [scriptblock]::Create($sc)
                    $out = & $sb *>&1
                    foreach ($line in @($out)) {
                        $txt = [string]$line
                        if (-not [string]::IsNullOrWhiteSpace($txt)) { Write-ToolLog "  -> $txt" "INFO" }
                    }
                }
            }
            Write-ToolLog "  [OK] $label concluído!" "SUCCESS"
        } catch {
            Write-ToolLog "  [ERRO] Falha em $label : $($_.Exception.Message)" "ERROR"
        }
    }
    Write-ToolLog "Instalação dos recursos selecionados finalizada. Reinicie o PC se solicitado." "SUCCESS"
}

function Enable-OpenSshServer {
    Write-ToolLog "Configurando Servidor OpenSSH no Windows..." "INFO"
    try {
        $cap = Get-WindowsCapability -Name "OpenSSH.Server*" -Online -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cap -and $cap.State -ne "Installed") {
            Write-ToolLog "Instalando recurso OpenSSH.Server..." "INFO"
            Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
        }

        Set-Service -Name "sshd" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "sshd" -ErrorAction Stop
        Set-Service -Name "ssh-agent" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "ssh-agent" -ErrorAction SilentlyContinue

        $fw = Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue
        if (-not $fw) {
            New-NetFirewallRule -Name "sshd" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null
        } else {
            Enable-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue | Out-Null
        }

        $sshDir = Join-Path $env:ProgramData "ssh"
        if (-not (Test-Path $sshDir)) { New-Item -Path $sshDir -ItemType Directory -Force | Out-Null }
        $authFile = Join-Path $sshDir "administrators_authorized_keys"
        if (-not (Test-Path $authFile)) { New-Item -Path $authFile -ItemType File -Force | Out-Null }

        $acl = Get-Acl -Path $authFile
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
        foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
            [void]$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($sid), "FullControl", "Allow"))
        }
        Set-Acl -Path $authFile -AclObject $acl

        Write-ToolLog "Servidor OpenSSH instalado e ativo na porta 22!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar OpenSSH Server: $($_.Exception.Message)" "ERROR"
    }
}

function Install-EnhancedPowerShellProfile {
    Write-ToolLog "Configurando perfil aprimorado para PowerShell 7+..." "INFO"
    try {
        $pwshCmd = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
        if (-not $pwshCmd) {
            Write-ToolLog "PowerShell 7 (pwsh) não encontrado neste PC. Instale-o pela aba Softwares antes." "WARN"
            return
        }

        $profilePath = (& $pwshCmd.Source -NoProfile -NonInteractive -Command '$PROFILE' | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($profilePath)) {
            Write-ToolLog "Não foi possível determinar o caminho de $PROFILE no PowerShell 7." "ERROR"
            return
        }

        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) { New-Item -Path $profileDir -ItemType Directory -Force | Out-Null }

        if (Test-Path $profilePath) {
            Copy-Item -Path $profilePath -Destination "$profilePath.bak" -Force
            Write-ToolLog "Backup do perfil anterior criado em: $profilePath.bak" "INFO"
        }

        $profileContent = @'
# Perfil Aprimorado Alt's - PowerShell 7+
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
}
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh | Invoke-Expression
}
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String
'@
        [System.IO.File]::WriteAllText($profilePath, $profileContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-ToolLog "Perfil do PowerShell 7 instalado em: $profilePath" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao instalar perfil PowerShell 7: $($_.Exception.Message)" "ERROR"
    }
}

function Uninstall-EnhancedPowerShellProfile {
    Write-ToolLog "Removendo/Restaurando perfil do PowerShell 7+..." "INFO"
    try {
        $pwshCmd = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
        if (-not $pwshCmd) {
            Write-ToolLog "PowerShell 7 não encontrado neste PC." "WARN"
            return
        }

        $profilePath = (& $pwshCmd.Source -NoProfile -NonInteractive -Command '$PROFILE' | Select-Object -First 1).Trim()
        $backupPath = "$profilePath.bak"

        if (Test-Path $backupPath) {
            Move-Item -Path $backupPath -Destination $profilePath -Force
            Write-ToolLog "Perfil original restaurado de $backupPath." "SUCCESS"
        } elseif (Test-Path $profilePath) {
            Remove-Item -Path $profilePath -Force
            Write-ToolLog "Perfil removido: $profilePath." "SUCCESS"
        } else {
            Write-ToolLog "Nenhum perfil personalizado encontrado para remover." "WARN"
        }
    } catch {
        Write-ToolLog "Erro ao remover perfil PowerShell 7: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-SysinternalsAutologon {
    Write-ToolLog "Baixando Sysinternals Autologon oficial..." "INFO"
    $dir = Join-Path $env:LOCALAPPDATA "Alts"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $exe = Join-Path $dir "Autologon.exe"

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://live.sysinternals.com/Autologon.exe", $exe)
        Write-ToolLog "Executando Sysinternals Autologon..." "SUCCESS"
        Start-Process -FilePath $exe -ArgumentList "/accepteula"
    } catch {
        Write-ToolLog "Erro ao baixar/executar Autologon: $($_.Exception.Message)" "ERROR"
    }
}

function Set-NtpPoolTimeSync {
    Write-ToolLog "Configurando sincronização de horário com pool.ntp.org..." "INFO"
    try {
        Start-Service -Name "w32time" -ErrorAction SilentlyContinue
        w32tm /config /update /manualpeerlist:"pool.ntp.org,0x8" /syncfromflags:MANUAL | Out-Null
        Restart-Service -Name "w32time" -Force -ErrorAction SilentlyContinue
        $res = w32tm /resync 2>&1
        Write-ToolLog "Servidor NTP configurado (pool.ntp.org): $res" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar NTP: $($_.Exception.Message)" "ERROR"
    }
}
