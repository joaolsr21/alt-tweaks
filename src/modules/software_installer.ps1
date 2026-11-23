# ==============================================================================
# Módulo: Gerenciador de Pacotes & Softwares (WinGet + Chocolatey)
# ==============================================================================

function Ensure-WinGetInstalled {
    param([switch]$Force)

    if (-not $Force -and (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
        return $true
    }

    Write-ToolLog "Instalando ou reparando o gerenciador WinGet (Microsoft.WinGet.Client)..." "INFO"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber -ErrorAction Stop | Out-Null
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
        Write-ToolLog "WinGet instalado/reparado com sucesso!" "SUCCESS"
        return $true
    } catch {
        Write-ToolLog "Falha ao reparar WinGet: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Ensure-ChocolateyInstalled {
    if (Get-Command "choco.exe" -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-ToolLog "Chocolatey não encontrado. Tentando instalar..." "INFO"
    try {
        if (Get-Command "winget.exe" -ErrorAction SilentlyContinue) {
            $p = Start-Process -FilePath "winget.exe" -ArgumentList "install --id Chocolatey.Chocolatey --exact --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
            $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
            if (Get-Command "choco.exe" -ErrorAction SilentlyContinue) {
                Write-ToolLog "Chocolatey instalado com sucesso via WinGet!" "SUCCESS"
                return $true
            }
        }

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $tmpScript = Join-Path $env:TEMP "choco_install_setup.ps1"
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://community.chocolatey.org/install.ps1", $tmpScript)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpScript | ForEach-Object { Write-ToolLog "$_" "INFO" }
        Remove-Item $tmpScript -Force -ErrorAction SilentlyContinue
        $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

        if (Get-Command "choco.exe" -ErrorAction SilentlyContinue) {
            Write-ToolLog "Chocolatey instalado com sucesso!" "SUCCESS"
            return $true
        }
        Write-ToolLog "Chocolatey foi instalado, porém pode exigir reiniciar o terminal." "WARN"
        return $false
    } catch {
        Write-ToolLog "Falha ao instalar Chocolatey: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-PackagesBatch {
    param(
        [Parameter(Mandatory=$true)][array]$Apps,
        [ValidateSet("WinGet", "Choco")][string]$Manager = "WinGet"
    )

    if ($Manager -eq "WinGet") {
        if (-not (Ensure-WinGetInstalled)) { return }
    } else {
        if (-not (Ensure-ChocolateyInstalled)) { return }
    }

    Write-ToolLog "Iniciando instalação/atualização em lote de $($Apps.Count) aplicativo(s) via $Manager..." "INFO"

    foreach ($app in $Apps) {
        $name = $app.Content
        if ($Manager -eq "WinGet") {
            $pkgIds = @($app.Winget -split ';' | Where-Object { $_ -and $_ -ne "na" })
            foreach ($id in $pkgIds) {
                Write-ToolLog "[$Manager] Instalando $name ($id)..." "INFO"
                try {
                    $p = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $id --exact --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait -PassThru
                    if ($p.ExitCode -eq 0) {
                        Write-ToolLog "  [OK] $name ($id) instalado!" "SUCCESS"
                    } elseif ($p.ExitCode -eq -1978335189) {
                        Write-ToolLog "  [INFO] $name ($id) já está na versão mais recente." "INFO"
                    } else {
                        Write-ToolLog "  [WARN] WinGet retornou código $($p.ExitCode) para $id." "WARN"
                    }
                } catch {
                    Write-ToolLog "  [ERRO] Falha ao instalar $id : $_" "ERROR"
                }
            }
        } else {
            $chocoIds = @($app.Choco -split ';' | Where-Object { $_ -and $_ -ne "na" })
            foreach ($id in $chocoIds) {
                Write-ToolLog "[$Manager] Instalando $name ($id)..." "INFO"
                try {
                    $p = Start-Process -FilePath "choco.exe" -ArgumentList "install $id -y" -NoNewWindow -Wait -PassThru
                    if ($p.ExitCode -eq 0) {
                        Write-ToolLog "  [OK] $name ($id) instalado!" "SUCCESS"
                    } else {
                        Write-ToolLog "  [WARN] Choco retornou código $($p.ExitCode) para $id." "WARN"
                    }
                } catch {
                    Write-ToolLog "  [ERRO] Falha ao instalar $id : $_" "ERROR"
                }
            }
        }
    }

    Write-ToolLog "Instalação em lote via $Manager finalizada!" "SUCCESS"
}

function Uninstall-PackagesBatch {
    param(
        [Parameter(Mandatory=$true)][array]$Apps,
        [ValidateSet("WinGet", "Choco")][string]$Manager = "WinGet"
    )

    Write-ToolLog "Iniciando desinstalação de $($Apps.Count) aplicativo(s) via $Manager..." "INFO"

    foreach ($app in $Apps) {
        $name = $app.Content
        if ($Manager -eq "WinGet") {
            if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) { Write-ToolLog "WinGet ausente." "ERROR"; return }
            $pkgIds = @($app.Winget -split ';' | Where-Object { $_ -and $_ -ne "na" })
            foreach ($id in $pkgIds) {
                Write-ToolLog "[$Manager] Desinstalando $name ($id)..." "INFO"
                $p = Start-Process -FilePath "winget.exe" -ArgumentList "uninstall --id $id --exact --silent --accept-source-agreements" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -eq 0) {
                    Write-ToolLog "  [OK] $name desinstalado." "SUCCESS"
                } else {
                    Write-ToolLog "  [WARN] WinGet retornou código $($p.ExitCode) ao desinstalar $id." "WARN"
                }
            }
        } else {
            if (-not (Get-Command "choco.exe" -ErrorAction SilentlyContinue)) { Write-ToolLog "Chocolatey ausente." "ERROR"; return }
            $chocoIds = @($app.Choco -split ';' | Where-Object { $_ -and $_ -ne "na" })
            foreach ($id in $chocoIds) {
                Write-ToolLog "[$Manager] Desinstalando $name ($id)..." "INFO"
                $p = Start-Process -FilePath "choco.exe" -ArgumentList "uninstall $id -y" -NoNewWindow -Wait -PassThru
                if ($p.ExitCode -eq 0) {
                    Write-ToolLog "  [OK] $name desinstalado." "SUCCESS"
                } else {
                    Write-ToolLog "  [WARN] Choco retornou código $($p.ExitCode) ao desinstalar $id." "WARN"
                }
            }
        }
    }

    Write-ToolLog "Desinstalação em lote concluída!" "SUCCESS"
}

function Upgrade-AllPackages {
    param([ValidateSet("WinGet", "Choco")][string]$Manager = "WinGet")

    if ($Manager -eq "WinGet") {
        if (-not (Ensure-WinGetInstalled)) { return }
        Write-ToolLog "Atualizando TODOS os softwares do sistema via WinGet..." "INFO"
        Start-Process -FilePath "winget.exe" -ArgumentList "upgrade --all --silent --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
        Write-ToolLog "Atualização geral via WinGet finalizada." "SUCCESS"
    } else {
        if (-not (Ensure-ChocolateyInstalled)) { return }
        Write-ToolLog "Atualizando TODOS os pacotes via Chocolatey..." "INFO"
        Start-Process -FilePath "choco.exe" -ArgumentList "upgrade all -y" -NoNewWindow -Wait
        Write-ToolLog "Atualização geral via Chocolatey finalizada." "SUCCESS"
    }
}

function Get-InstalledPackagesIds {
    param([ValidateSet("WinGet", "Choco")][string]$Manager = "WinGet")

    Write-ToolLog "Verificando aplicativos instalados via $Manager..." "INFO"
    $rawText = ""
    if ($Manager -eq "WinGet") {
        if (Get-Command "winget.exe" -ErrorAction SilentlyContinue) {
            $rawText = (& winget.exe list --accept-source-agreements 2>$null) -join "`n"
        }
    } else {
        if (Get-Command "choco.exe" -ErrorAction SilentlyContinue) {
            $rawText = (& choco.exe list --local-only 2>$null) -join "`n"
        }
    }
    return $rawText
}

function Install-SelectedSoftwareList {
    param([Parameter(Mandatory=$true)][string[]]$PackageIds)
    $list = foreach ($id in $PackageIds) { [pscustomobject]@{ Content = $id; Winget = $id; Choco = "" } }
    Install-PackagesBatch -Apps $list -Manager "WinGet"
}
