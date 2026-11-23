# ==============================================================================
# Módulo: Gerenciador Completo de Aplicativos Nativos (AppX / Microsoft Store)
# ==============================================================================

function Get-InstalledAppxPackageIds {
    Write-ToolLog "Consultando pacotes AppX instalados no sistema..." "INFO"
    try {
        $installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique
        Write-ToolLog "Total de pacotes AppX detectados no sistema: $($installed.Count)." "INFO"
        return @($installed)
    } catch {
        Write-ToolLog "Erro ao consultar AppX instalados: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Remove-SelectedAppxPackages {
    param([Parameter(Mandatory=$true)][array]$Entries)

    Write-ToolLog "Iniciando remoção de $($Entries.Count) pacote(s) AppX..." "INFO"
    $removedCount = 0

    foreach ($entry in $Entries) {
        $pkgId = $entry.PackageId
        $display = $entry.Content
        if (-not $pkgId) { continue }

        Write-ToolLog "Removendo [$display] ($pkgId)..." "INFO"
        try {
            $pkgs = Get-AppxPackage -Name "*$pkgId*" -AllUsers -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removedCount++
            }

            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$pkgId*" }
            foreach ($pv in $prov) {
                Remove-AppxProvisionedPackage -Online -PackageName $pv.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
            Write-ToolLog "  [OK] $display processado." "SUCCESS"
        } catch {
            Write-ToolLog "  [ERRO] Falha ao remover $display : $($_.Exception.Message)" "WARN"
        }
    }

    Write-ToolLog "Remoção de AppX concluída! ($removedCount instância(s) removidas)." "SUCCESS"
}

function Install-SelectedAppxPackages {
    param([Parameter(Mandatory=$true)][array]$Entries)

    if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
        Write-ToolLog "WinGet é necessário para reinstalar pacotes AppX pela Microsoft Store." "ERROR"
        return
    }

    Write-ToolLog "Iniciando reinstalação de $($Entries.Count) pacote(s) AppX via Microsoft Store..." "INFO"
    foreach ($entry in $Entries) {
        $storeId = $entry.StoreId
        $display = $entry.Content
        if (-not $storeId) {
            Write-ToolLog "[$display] não possui StoreId configurado (ignorado)." "WARN"
            continue
        }

        Write-ToolLog "Reinstalando [$display] (StoreId: $storeId)..." "INFO"
        try {
            $p = Start-Process -FilePath "winget.exe" -ArgumentList "install --id $storeId --source msstore --accept-package-agreements --accept-source-agreements --silent" -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-ToolLog "  [OK] $display reinstalado com sucesso!" "SUCCESS"
            } elseif ($p.ExitCode -eq -1978335189) {
                Write-ToolLog "  [INFO] $display já está instalado." "INFO"
            } else {
                Write-ToolLog "  [WARN] WinGet retornou código $($p.ExitCode) para $display." "WARN"
            }
        } catch {
            Write-ToolLog "  [ERRO] Falha ao instalar $display : $($_.Exception.Message)" "ERROR"
        }
    }

    Write-ToolLog "Processo de reinstalação de AppX finalizado." "SUCCESS"
}
