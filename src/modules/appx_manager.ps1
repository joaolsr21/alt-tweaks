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
    param(
        [Parameter(Mandatory=$true)][array]$Entries,
        [switch]$DryRun
    )

    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    Write-ToolLog "${prefix}Iniciando remoção de $($Entries.Count) pacote(s) AppX..." "INFO"
    $removedCount = 0

    foreach ($entry in $Entries) {
        $pkgId = $entry.PackageId
        $display = $entry.Content
        if (-not $pkgId) { continue }

        if ($DryRun) {
            $instInfo = ""
            try {
                $pkgs = @(Get-AppxPackage -Name "*$pkgId*" -AllUsers -ErrorAction Stop)
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -like "*$pkgId*" })
                $instInfo = " - instalado(s): $($pkgs.Count), provisionado(s): $($prov.Count)"
            } catch {
                try {
                    $pkgsUser = @(Get-AppxPackage -Name "*$pkgId*" -ErrorAction SilentlyContinue)
                    $instInfo = " - instalado(s) no usuário atual: $($pkgsUser.Count)"
                } catch {
                    $instInfo = " - consulta detalhada requer Admin"
                }
            }
            Write-ToolLog "[DRY-RUN] Removeria [$display] ($pkgId)$instInfo." "INFO"
            continue
        }

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

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] Simulação de remoção AppX concluída ($($Entries.Count) pacote(s) analisados)." "SUCCESS"
    } else {
        Write-ToolLog "Remoção de AppX concluída! ($removedCount instância(s) removidas)." "SUCCESS"
    }
}

function Install-SelectedAppxPackages {
    param(
        [Parameter(Mandatory=$true)][array]$Entries,
        [switch]$DryRun
    )

    if (-not $DryRun -and -not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
        Write-ToolLog "WinGet é necessário para reinstalar pacotes AppX pela Microsoft Store." "ERROR"
        return
    }

    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    Write-ToolLog "${prefix}Iniciando reinstalação de $($Entries.Count) pacote(s) AppX via Microsoft Store..." "INFO"
    foreach ($entry in $Entries) {
        $storeId = $entry.StoreId
        $display = $entry.Content
        if (-not $storeId) {
            Write-ToolLog "[$display] não possui StoreId configurado (ignorado)." "WARN"
            continue
        }

        if ($DryRun) {
            Write-ToolLog "[DRY-RUN] Reinstalaria [$display] (StoreId: $storeId) via Microsoft Store." "INFO"
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

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] Simulação de reinstalação de AppX finalizada." "SUCCESS"
    } else {
        Write-ToolLog "Processo de reinstalação de AppX finalizado." "SUCCESS"
    }
}

function Get-AppxChangesPreview {
    param(
        [Parameter(Mandatory=$true)][array]$Entries,
        [ValidateSet("Remove", "Install")][string]$Action = "Remove"
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $Entries) {
        if ($null -eq $entry) { continue }
        $display = if ($entry.Content) { [string]$entry.Content } else { [string]$entry.PackageId }
        $pkgId = [string]$entry.PackageId
        $storeId = [string]$entry.StoreId
        $cat = if ($entry.Category) { [string]$entry.Category } else { "Outros" }

        $detail = if ($Action -eq "Remove") {
            "Remover pacote ($pkgId) para todos os usuários e provisionamento"
        } elseif ($storeId) {
            "Reinstalar via Microsoft Store (StoreId: $storeId)"
        } else {
            "Ignorado (StoreId ausente)"
        }

        [void]$items.Add([pscustomobject]@{
            Content   = $display
            PackageId = $pkgId
            StoreId   = $storeId
            Category  = $cat
            Action    = $Action
            Detail    = $detail
        })
    }
    return ,$items.ToArray()
}

function Format-AppxChangesPreviewText {
    param(
        [Parameter(Mandatory=$true)][array]$Entries,
        [ValidateSet("Remove", "Install")][string]$Action = "Remove"
    )

    $preview = Get-AppxChangesPreview -Entries $Entries -Action $Action
    $actionLabel = if ($Action -eq "Remove") { "REMOÇÃO DE PACOTES APPX" } else { "REINSTALAÇÃO DE PACOTES APPX" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("  PRÉ-VISUALIZAÇÃO: $actionLabel")
    [void]$sb.AppendLine("  Pacotes selecionados: $($preview.Count)")
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("")

    foreach ($item in $preview) {
        [void]$sb.AppendLine("* [$($item.Category)] $($item.Content)")
        [void]$sb.AppendLine("    PackageId : $($item.PackageId)")
        if ($item.StoreId) {
            [void]$sb.AppendLine("    StoreId   : $($item.StoreId)")
        }
        [void]$sb.AppendLine("    Ação      : $($item.Detail)")
    }

    return $sb.ToString().TrimEnd()
}
