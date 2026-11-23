# ==============================================================================
# Módulo Avançado: Criador, Customizador de ISO & Gravador USB (Win 10 / 11)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms

function Select-IsoFileDialog {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Arquivos de Imagem ISO (*.iso)|*.iso|Todos os Arquivos (*.*)|*.*"
    $dialog.Title = "Selecione a ISO Oficial do Windows 10 ou 11"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("UserProfile") + "\Downloads"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Select-OutputFolderDialog {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Selecione a pasta onde a nova ISO modificada será salva"
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Inspect-IsoEditions {
    param([Parameter(Mandatory=$true)][string]$IsoPath)

    if (-not (Test-Path $IsoPath)) {
        Write-ToolLog "Arquivo ISO não encontrado: $IsoPath" "ERROR"
        return @()
    }

    Write-ToolLog "Montando ISO temporariamente para ler edições disponíveis..." "INFO"
    try {
        $mounted = Mount-DiskImage -ImagePath $IsoPath -PassThru -ErrorAction Stop
        Start-Sleep -Milliseconds 600
        $driveLetter = ($mounted | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            Start-Sleep -Seconds 1
            $driveLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume).DriveLetter
        }

        $drivePath = "${driveLetter}:\"
        Write-ToolLog "ISO montada em $drivePath" "INFO"

        $wimPath = Join-Path $drivePath "sources\install.wim"
        if (-not (Test-Path $wimPath)) {
            $wimPath = Join-Path $drivePath "sources\install.esd"
        }
        if (-not (Test-Path $wimPath)) {
            Write-ToolLog "Não foi possível localizar install.wim ou install.esd na ISO." "ERROR"
            Dismount-DiskImage -ImagePath $IsoPath | Out-Null
            return @()
        }

        $images = Get-WindowsImage -ImagePath $wimPath
        $editions = New-Object System.Collections.Generic.List[object]

        foreach ($img in $images) {
            $detail = $null
            try { $detail = Get-WindowsImage -ImagePath $wimPath -Index $img.ImageIndex -ErrorAction SilentlyContinue } catch {}
            $edId = if ($detail -and $detail.EditionId) { $detail.EditionId } else { "" }
            $editions.Add([pscustomobject]@{
                ImageIndex = [int]$img.ImageIndex
                ImageName  = [string]$img.ImageName
                EditionId  = [string]$edId
            })
        }

        Dismount-DiskImage -ImagePath $IsoPath | Out-Null

        Write-ToolLog "Edições detectadas ($($editions.Count)):" "SUCCESS"
        foreach ($e in $editions) {
            $idSuffix = if ($e.EditionId) { " [$($e.EditionId)]" } else { "" }
            Write-ToolLog "  -> [Índice $($e.ImageIndex)]: $($e.ImageName)$idSuffix" "INFO"
        }

        return $editions.ToArray()
    } catch {
        Write-ToolLog "Falha ao inspecionar ISO: $($_.Exception.Message)" "ERROR"
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
        return @()
    }
}

function Add-IsoSetupCustomizations {
    param(
        [Parameter(Mandatory=$true)][string]$XmlContent,
        [Parameter(Mandatory=$true)][int]$InstallImageIndex
    )

    $appxList = @(
        'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch',
        'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes',
        'Microsoft.OutlookForWindows', 'Microsoft.Paint', 'Microsoft.PowerAutomateDesktop',
        'Microsoft.StartExperiencesApp', 'Microsoft.Todos', 'Microsoft.Windows.DevHome',
        'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsSoundRecorder',
        'Microsoft.ZuneMusic', 'MicrosoftCorporationII.QuickAssist', 'MSTeams'
    ) | ForEach-Object { "    '$_'" }
    $appxBlock = $appxList -join "`r`n"

    $postInstallScript = @"
`$ErrorActionPreference = 'Continue'
Start-Transcript -Path 'C:\Windows\Setup\Scripts\WinRepair-PostInstall.log' -Append -ErrorAction SilentlyContinue
try {
    `$packages = @(
$appxBlock
    )
    foreach (`$package in `$packages) {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { `$_.DisplayName -like "*`$package*" } |
            ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName `$_.PackageName -ErrorAction SilentlyContinue | Out-Null }
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { `$_.Name -like "*`$package*" } |
            ForEach-Object { Remove-AppxPackage -AllUsers -Package `$_.PackageFullName -ErrorAction SilentlyContinue | Out-Null }
    }
    reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' /v ShippedWithReserves /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg.exe add 'HKLM\SYSTEM\CurrentControlSet\Control\BitLocker' /v PreventDeviceEncryption /t REG_DWORD /d 1 /f 2>&1 | Out-Null
    reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' /v AllowTelemetry /t REG_DWORD /d 0 /f 2>&1 | Out-Null
    reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f 2>&1 | Out-Null
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}
"@

    $xmlDoc = [xml]::new()
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.LoadXml($XmlContent)
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')

    $setupComp = $xmlDoc.SelectSingleNode('/u:unattend/u:settings[@pass="windowsPE"]/u:component[@name="Microsoft-Windows-Setup"]', $nsMgr)
    $extensions = $xmlDoc.SelectSingleNode('//sg:Extensions', $nsMgr)
    $firstLogon = $xmlDoc.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\FirstLogon.ps1"]', $nsMgr)

    if ($setupComp) {
        $imgInst = $setupComp.SelectSingleNode('u:ImageInstall', $nsMgr)
        if (-not $imgInst) {
            $imgInst = $xmlDoc.CreateElement('ImageInstall', $setupComp.NamespaceURI)
            [void]$setupComp.AppendChild($imgInst)
        }
        $osImg = $imgInst.SelectSingleNode('u:OSImage', $nsMgr)
        if (-not $osImg) {
            $osImg = $xmlDoc.CreateElement('OSImage', $setupComp.NamespaceURI)
            [void]$imgInst.AppendChild($osImg)
        }
        $instFrom = $osImg.SelectSingleNode('u:InstallFrom', $nsMgr)
        if (-not $instFrom) {
            $instFrom = $xmlDoc.CreateElement('InstallFrom', $setupComp.NamespaceURI)
            [void]$osImg.AppendChild($instFrom)
        }
        foreach ($oldMeta in @($instFrom.SelectNodes('u:MetaData', $nsMgr))) {
            [void]$instFrom.RemoveChild($oldMeta)
        }
        $meta = $xmlDoc.CreateElement('MetaData', $setupComp.NamespaceURI)
        $attr = $xmlDoc.CreateAttribute('wcm', 'action', 'http://schemas.microsoft.com/WMIConfig/2002/State')
        $attr.Value = 'add'
        [void]$meta.Attributes.Append($attr)
        $kEl = $xmlDoc.CreateElement('Key', $setupComp.NamespaceURI)
        $kEl.InnerText = '/IMAGE/INDEX'
        [void]$meta.AppendChild($kEl)
        $vEl = $xmlDoc.CreateElement('Value', $setupComp.NamespaceURI)
        $vEl.InnerText = [string]$InstallImageIndex
        [void]$meta.AppendChild($vEl)
        [void]$instFrom.AppendChild($meta)
    }

    if ($extensions -and $firstLogon) {
        $postFile = $xmlDoc.CreateElement('File', $extensions.NamespaceURI)
        $postFile.SetAttribute('path', 'C:\Windows\Setup\Scripts\WinRepair-PostInstall.ps1')
        $postFile.InnerText = $postInstallScript
        [void]$extensions.AppendChild($postFile)
        $firstLogon.InnerText = "& 'C:\Windows\Setup\Scripts\WinRepair-PostInstall.ps1';`r`n`r`n$($firstLogon.InnerText.Trim())"
    }

    return $xmlDoc.OuterXml
}

function Stage-IsoSetupScriptsFallback {
    param(
        [Parameter(Mandatory=$true)][string]$ContentRoot,
        [Parameter(Mandatory=$true)][string]$XmlContent
    )

    $xmlDoc = [xml]::new()
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.LoadXml($XmlContent)
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $nsMgr.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    $nsMgr.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')

    $scriptsRoot = Join-Path $ContentRoot 'sources\$OEM$\$$\Setup\Scripts'
    $count = 0
    foreach ($fileNode in $xmlDoc.SelectNodes('//sg:File', $nsMgr)) {
        $p = $fileNode.GetAttribute('path')
        if (-not $p.StartsWith('C:\Windows\Setup\Scripts\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $rel = $p.Substring('C:\Windows\Setup\Scripts\'.Length)
        $dest = Join-Path $scriptsRoot $rel
        New-Item -Path (Split-Path $dest -Parent) -ItemType Directory -Force | Out-Null
        $enc = switch ([System.IO.Path]::GetExtension($dest)) {
            { $_ -in '.ps1', '.xml' } { [System.Text.Encoding]::UTF8; break }
            { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new($false, $true); break }
            default { [System.Text.Encoding]::Default }
        }
        $bytes = $enc.GetPreamble() + $enc.GetBytes($fileNode.InnerText.Trim())
        [System.IO.File]::WriteAllBytes($dest, $bytes)
        $count++
    }
    Write-ToolLog "Scripts auxiliares de instalação preparados ($count arquivo(s))." "INFO"
}

function Generate-AutoUnattendXml {
    param(
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [string]$BaseTemplateXml = "",
        [int]$EditionIndex = 1
    )

    if (-not [string]::IsNullOrWhiteSpace($BaseTemplateXml)) {
        try {
            $prepared = Add-IsoSetupCustomizations -XmlContent $BaseTemplateXml -InstallImageIndex $EditionIndex
            [System.IO.File]::WriteAllText($DestinationPath, $prepared, (New-Object System.Text.UTF8Encoding($false)))
            $contentRoot = Split-Path $DestinationPath -Parent
            Stage-IsoSetupScriptsFallback -ContentRoot $contentRoot -XmlContent $prepared
            Write-ToolLog "Arquivo autounattend.xml completo injetado em: $DestinationPath" "SUCCESS"
            return
        } catch {
            Write-ToolLog "Aviso ao personalizar template XML completo ($($_.Exception.Message)). Usando template OOBE padrão." "WARN"
        }
    }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
"@
    [System.IO.File]::WriteAllText($DestinationPath, $xml, (New-Object System.Text.UTF8Encoding($false)))
    Write-ToolLog "Arquivo autounattend.xml gerado em: $DestinationPath" "SUCCESS"
}

function Build-CustomOptimizedIsoPipeline {
    param(
        [Parameter(Mandatory=$true)][string]$SourceIsoPath,
        [Parameter(Mandatory=$true)][string]$OutputIsoDir,
        [string]$OutputIsoName = "Windows_Custom_Otimizado.iso",
        [int]$EditionIndex = 1,
        [string]$EditionId = "",
        [string]$AutoUnattendXmlTemplate = "",
        [bool]$BypassHardwareChecks = $true,
        [bool]$BypassMicrosoftAccount = $true,
        [bool]$DisableBitLocker = $true,
        [bool]$RemoveBloatware = $true,
        [bool]$InjectUnattendXml = $true,
        [bool]$InjectDrivers = $false
    )

    Write-ToolLog "=== INICIANDO CRIAÇÃO DE ISO CUSTOMIZADA ===" "INFO"
    $workDir = Join-Path $OutputIsoDir "_WinRepair_ISO_Work"
    $extractedDir = Join-Path $workDir "extracted"
    $mountDir = Join-Path $workDir "mount"
    $drvDir = Join-Path $workDir "drivers"

    try {
        if (Test-Path $workDir) {
            Write-ToolLog "Limpando área de trabalho anterior ($workDir)..." "INFO"
            Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
            Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -ItemType Directory -Path $extractedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

        Write-ToolLog "Montando ISO de origem..." "INFO"
        $diskImg = Mount-DiskImage -ImagePath $SourceIsoPath -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 1
        $driveLetter = ($diskImg | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            $driveLetter = (Get-DiskImage -ImagePath $SourceIsoPath | Get-Volume).DriveLetter
        }
        $driveRoot = "${driveLetter}:\"

        Write-ToolLog "Copiando conteúdo da ISO de $driveRoot para $extractedDir..." "INFO"
        & robocopy $driveRoot $extractedDir /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            Dismount-DiskImage -ImagePath $SourceIsoPath -ErrorAction SilentlyContinue | Out-Null
            throw "robocopy falhou ao copiar mídia da ISO (código $LASTEXITCODE)."
        }
        Dismount-DiskImage -ImagePath $SourceIsoPath | Out-Null
        # Remover atributo somente leitura de arquivos copiados da ISO
        Get-ChildItem -Path $extractedDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.IsReadOnly) { $_.IsReadOnly = $false }
        }
        Write-ToolLog "Arquivos da ISO copiados com sucesso!" "SUCCESS"

        $wimPath = Join-Path $extractedDir "sources\install.wim"
        $esdPath = Join-Path $extractedDir "sources\install.esd"
        $targetIndex = $EditionIndex

        if ((-not (Test-Path $wimPath)) -and (Test-Path $esdPath)) {
            Write-ToolLog "install.esd detectado. Exportando índice $EditionIndex para install.wim..." "INFO"
            Export-WindowsImage -SourceImagePath $esdPath -SourceIndex $EditionIndex -DestinationImagePath $wimPath -CompressionType max -ErrorAction Stop
            Remove-Item -Path $esdPath -Force -ErrorAction SilentlyContinue
            $targetIndex = 1
        }

        if (Test-Path $wimPath) {
            Write-ToolLog "Montando imagem install.wim (Índice $targetIndex)..." "INFO"
            Mount-WindowsImage -ImagePath $wimPath -Index $targetIndex -Path $mountDir -ErrorAction Stop

            if ($RemoveBloatware) {
                Write-ToolLog "Removendo pacotes AppX provisionados (bloatware)..." "INFO"
                $bloatPatterns = @(
                    "*BingNews*", "*BingWeather*", "*Solitaire*", "*GetHelp*", "*Getstarted*",
                    "*People*", "*Todos*", "*PowerAutomate*", "*ZuneMusic*", "*ZuneVideo*",
                    "*Clipchamp*", "*XboxGamingOverlay*", "*XboxSpeechToTextOverlay*"
                )
                $provPackages = Get-AppxProvisionedPackage -Path $mountDir
                $removedCount = 0
                foreach ($pkg in $provPackages) {
                    foreach ($pattern in $bloatPatterns) {
                        if ($pkg.DisplayName -like $pattern) {
                            Remove-AppxProvisionedPackage -Path $mountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
                            $removedCount++
                            break
                        }
                    }
                }
                Write-ToolLog "AppX bloatwares removidos da imagem: $removedCount." "SUCCESS"
            }

            if ($InjectDrivers) {
                Write-ToolLog "Exportando drivers do sistema atual para injeção na imagem..." "INFO"
                New-Item -ItemType Directory -Path $drvDir -Force | Out-Null
                Export-WindowsDriver -Online -Destination $drvDir -ErrorAction SilentlyContinue | Out-Null
                Write-ToolLog "Injetando drivers em install.wim..." "INFO"
                Add-WindowsDriver -Path $mountDir -Driver $drvDir -Recurse -ErrorAction SilentlyContinue | Out-Null
                Write-ToolLog "Drivers injetados em install.wim." "SUCCESS"
            }

            $offlineSysHive = Join-Path $mountDir "Windows\System32\config\SYSTEM"
            if (Test-Path $offlineSysHive) {
                Write-ToolLog "Ajustando registro offline da imagem..." "INFO"
                reg load HKLM\OFFLINE_SYS "$offlineSysHive" | Out-Null

                if ($BypassHardwareChecks) {
                    $labConfig = "HKLM\OFFLINE_SYS\Setup\LabConfig"
                    if (-not (Test-Path $labConfig)) { New-Item -Path $labConfig -Force | Out-Null }
                    foreach ($n in @("BypassTPMCheck", "BypassSecureBootCheck", "BypassRAMCheck", "BypassCPUCheck", "BypassStorageCheck")) {
                        Set-ItemProperty -Path $labConfig -Name $n -Value 1 -Type DWord -Force
                    }
                    Write-ToolLog "Bypass Hardware Win11 (TPM/SecureBoot/RAM/CPU) gravado." "INFO"
                }

                if ($BypassMicrosoftAccount) {
                    $oobeKey = "HKLM\OFFLINE_SYS\Setup\OOBE"
                    if (-not (Test-Path $oobeKey)) { New-Item -Path $oobeKey -Force | Out-Null }
                    Set-ItemProperty -Path $oobeKey -Name "BypassNRO" -Value 1 -Type DWord -Force
                    Write-ToolLog "Bypass Conta Microsoft (BypassNRO) gravado." "INFO"
                }

                if ($DisableBitLocker) {
                    $bitlockerKey = "HKLM\OFFLINE_SYS\ControlSet001\Control\BitLocker"
                    if (-not (Test-Path $bitlockerKey)) { New-Item -Path $bitlockerKey -Force | Out-Null }
                    Set-ItemProperty -Path $bitlockerKey -Name "PreventDeviceEncryption" -Value 1 -Type DWord -Force
                    Write-ToolLog "BitLocker automático desativado." "INFO"
                }

                [gc]::Collect()
                reg unload HKLM\OFFLINE_SYS | Out-Null
            }

            Write-ToolLog "Salvando e desmontando install.wim..." "INFO"
            Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop
        }

        if ($InjectDrivers -and (Test-Path $drvDir)) {
            $bootWim = Join-Path $extractedDir "sources\boot.wim"
            if (Test-Path $bootWim) {
                $storageDrvs = Get-ChildItem -Path $drvDir -Filter "*.inf" -Recurse | Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match '(?im)^\s*Class\s*=\s*(SCSIAdapter|HDC)\s*'
                }
                if ($storageDrvs) {
                    Write-ToolLog "Injetando $($storageDrvs.Count) driver(s) de armazenamento no boot.wim (Índice 2)..." "INFO"
                    Mount-WindowsImage -ImagePath $bootWim -Index 2 -Path $mountDir -ErrorAction Stop
                    foreach ($sInf in $storageDrvs) {
                        Add-WindowsDriver -Path $mountDir -Driver $sInf.FullName -ErrorAction SilentlyContinue | Out-Null
                    }
                    Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop
                }
            }
        }

        if ($InjectUnattendXml) {
            $unattendDest = Join-Path $extractedDir "autounattend.xml"
            Generate-AutoUnattendXml -DestinationPath $unattendDest -BaseTemplateXml $AutoUnattendXmlTemplate -EditionIndex $targetIndex
        }

        if (-not [string]::IsNullOrWhiteSpace($EditionId)) {
            $eiPath = Join-Path $extractedDir "sources\ei.cfg"
            $eiText = "[EditionID]`r`n$EditionId`r`n[Channel]`r`nRetail`r`n[VL]`r`n0`r`n"
            [System.IO.File]::WriteAllText($eiPath, $eiText, (New-Object System.Text.UTF8Encoding($false)))
            Write-ToolLog "Gravado sources\ei.cfg para EditionID '$EditionId'." "INFO"
        }

        $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
        if ($sync) { $sync.LastPreparedIsoDir = $extractedDir }

        $finalIsoPath = Join-Path $OutputIsoDir $OutputIsoName
        $oscdimg = Get-Command "oscdimg.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
        if (-not $oscdimg) {
            $adkPaths = @(
                "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
                "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
            )
            $oscdimg = $adkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if ($oscdimg) {
            Write-ToolLog "Gerando ISO bootável via oscdimg: $finalIsoPath..." "INFO"
            $bootData = "2#p0,e,b`"$extractedDir\boot\etfsboot.com`"#pEF,e,b`"$extractedDir\efi\microsoft\boot\efisys.bin`""
            & "$oscdimg" -m -o -u2 -udfver102 -bootdata:$bootData "$extractedDir" "$finalIsoPath" | Out-Null
            Write-ToolLog "ISO customizada criada com sucesso: $finalIsoPath" "SUCCESS"
        } else {
            Write-ToolLog "Arquivos customizados prontos em: $extractedDir" "SUCCESS"
            Write-ToolLog "Você pode gravar direto em Pendrive USB aqui na aba ao lado ou gerar a ISO com oscdimg (Windows ADK)." "INFO"
        }

        Write-ToolLog "=== PIPELINE DE ISO FINALIZADO COM SUCESSO! ===" "SUCCESS"
    } catch {
        Write-ToolLog "Erro no pipeline de ISO: $($_.Exception.Message)" "ERROR"
        Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-RemovableUsbDisks {
    try {
        $disks = @(Get-Disk | Where-Object { $_.BusType -eq "USB" } | Sort-Object Number)
        return $disks
    } catch {
        Write-ToolLog "Erro ao listar unidades USB: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

function Write-PreparedIsoToUsb {
    param(
        [Parameter(Mandatory=$true)][string]$SourceDir,
        [Parameter(Mandatory=$true)][int]$DiskNumber
    )

    if (-not $SourceDir -or -not (Test-Path $SourceDir)) {
        Write-ToolLog "Nenhuma mídia customizada preparada encontrada. Gere/prepare a ISO primeiro." "ERROR"
        return
    }

    Write-ToolLog "=== INICIANDO GRAVAÇÃO EM PENDRIVE USB (DISCO $DiskNumber) ===" "INFO"
    try {
        $wimPath = Join-Path $SourceDir "sources\install.wim"
        if (Test-Path $wimPath) {
            $len = (Get-Item $wimPath).Length
            if ($len -ge 4GB) {
                $swmPath = Join-Path $SourceDir "sources\install.swm"
                Write-ToolLog "install.wim excede 4 GB ($([math]::Round($len/1GB, 2)) GB). Dividindo em arquivos install.swm (FAT32 UEFI compatível)..." "INFO"
                Split-WindowsImage -ImagePath $wimPath -SplitImagePath $swmPath -FileSize 3800 -ErrorAction Stop | Out-Null
                Remove-Item $wimPath -Force -ErrorAction Stop
                Write-ToolLog "Divisão em install.swm concluída!" "SUCCESS"
            }
        }

        $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
        $freeLetter = $null
        foreach ($c in [char[]](68..90)) {
            if ($usedLetters -notcontains [string]$c) { $freeLetter = [string]$c; break }
        }
        if (-not $freeLetter) { throw "Nenhuma letra de unidade disponível." }

        Write-ToolLog "Formatando Disco $DiskNumber (MBR/FAT32 bootável)..." "WARN"
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        Initialize-Disk -Number $DiskNumber -PartitionStyle MBR -ErrorAction Stop | Out-Null
        $part = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -IsActive -DriveLetter $freeLetter -ErrorAction Stop
        Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel "WINREPAIR" -Confirm:$false -ErrorAction Stop | Out-Null

        $destRoot = "${freeLetter}:\"
        Write-ToolLog "Copiando arquivos para $destRoot via robocopy..." "INFO"
        & robocopy $SourceDir $destRoot /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy falhou ao gravar no pendrive (código $LASTEXITCODE)."
        }

        Write-ToolLog "=== PENDRIVE BOOTÁVEL GRAVADO COM SUCESSO NA UNIDADE ${destRoot}! ===" "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao gravar pendrive USB: $($_.Exception.Message)" "ERROR"
    }
}
