# ==============================================================================
# Script Principal: Alt Tweaks
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Identificar diretório base
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptRoot) {
    $scriptRoot = Get-Location
}

$srcCore    = Join-Path $scriptRoot "core"
$srcModules = Join-Path $scriptRoot "modules"
$srcConfig  = Join-Path $scriptRoot "config"
$uiDir      = Join-Path $scriptRoot "ui"
$uiPath     = Join-Path $uiDir "app.xaml"
$ctrlPath   = Join-Path $uiDir "controller.ps1"

# Importar módulos base e controlador de UI
if (Test-Path $srcCore) {
    . (Join-Path $srcCore "elevation.ps1")
    . (Join-Path $srcCore "logger.ps1")
    . (Join-Path $srcModules "network.ps1")
    . (Join-Path $srcModules "tweak_engine.ps1")
    . (Join-Path $srcModules "hardware_optimizer.ps1")
    . (Join-Path $srcModules "optimizer.ps1")
    . (Join-Path $srcModules "tweaks_system.ps1")
    . (Join-Path $srcModules "windows_features.ps1")
    . (Join-Path $srcModules "windows_update.ps1")
    . (Join-Path $srcModules "system_repair.ps1")
    . (Join-Path $srcModules "iso_builder.ps1")
    . (Join-Path $srcModules "software_installer.ps1")
    . (Join-Path $srcModules "appx_manager.ps1")
    . $ctrlPath
}

# 1. Garantir privilégios de Administrador
if (-not (Test-IsAdmin)) {
    Ensure-AdminPrivileges
    return
}

# 2. Carregar configurações declarativas (JSON) e template autounattend
$configs = @{
    Applications = [System.IO.File]::ReadAllText((Join-Path $srcConfig "applications.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Appx         = [System.IO.File]::ReadAllText((Join-Path $srcConfig "appx.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Dns          = [System.IO.File]::ReadAllText((Join-Path $srcConfig "dns.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Features     = [System.IO.File]::ReadAllText((Join-Path $srcConfig "features.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Presets      = [System.IO.File]::ReadAllText((Join-Path $srcConfig "presets.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    Tweaks       = [System.IO.File]::ReadAllText((Join-Path $srcConfig "tweaks.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
$unattendPath = Join-Path $srcConfig "autounattend.xml"
$autoUnattendXml = if (Test-Path $unattendPath) { [System.IO.File]::ReadAllText($unattendPath, [System.Text.Encoding]::UTF8) } else { "" }

# 3. Iniciar HUD
if (-not (Test-Path $uiPath)) {
    Write-Error "Arquivo XAML não encontrado em: $uiPath"
    return
}
$xamlText = [System.IO.File]::ReadAllText($uiPath, [System.Text.Encoding]::UTF8)
Start-WinRepairUI -XamlText $xamlText -Configs $configs -AutoUnattendXml $autoUnattendXml
