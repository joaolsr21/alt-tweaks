# ==============================================================================
# Script de Build: Empacotador Standalone para Execução Única via irm | iex
# ==============================================================================
param(
    [string]$OutputDir = "$PSScriptRoot\dist",
    [string]$OutputFile = "winrepair.ps1"
)

Write-Host "[*] Iniciando compilação do WinRepair & Tweaks Pro v3.0..." -ForegroundColor Cyan

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$destination = Join-Path $OutputDir $OutputFile

function ConvertTo-AsciiXml([string]$rawText) {
    $xsb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $rawText.Length; $i++) {
        $ch = $rawText[$i]
        if ([int]$ch -le 127) {
            [void]$xsb.Append($ch)
        } elseif ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $rawText.Length -and [char]::IsLowSurrogate($rawText[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $rawText[$i + 1])
            [void]$xsb.Append(("&#x{0:X};" -f $cp))
            $i++
        } else {
            [void]$xsb.Append(("&#x{0:X};" -f [int]$ch))
        }
    }
    return $xsb.ToString()
}

function ConvertTo-AsciiJson([string]$rawJson) {
    $compressed = ($rawJson | ConvertFrom-Json) | ConvertTo-Json -Depth 12 -Compress
    return [regex]::Replace($compressed, '[^\x00-\x7F]', {
        param($m)
        '\u{0:x4}' -f [int][char]$m.Value[0]
    })
}

$banner = @"
# ==============================================================================
# WinRepair & Tweaks Pro v3.0 (Standalone All-in-One)
# Utilitário Completo: Tweaks, Softwares, AppX, Rede (14 Ferramentas), ISO & USB
# Execução direta via: irm <URL> | iex
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

"@

$filesToBundle = @(
    "$PSScriptRoot\src\core\elevation.ps1",
    "$PSScriptRoot\src\core\logger.ps1",
    "$PSScriptRoot\src\modules\network.ps1",
    "$PSScriptRoot\src\modules\tweak_engine.ps1",
    "$PSScriptRoot\src\modules\optimizer.ps1",
    "$PSScriptRoot\src\modules\tweaks_system.ps1",
    "$PSScriptRoot\src\modules\windows_features.ps1",
    "$PSScriptRoot\src\modules\windows_update.ps1",
    "$PSScriptRoot\src\modules\system_repair.ps1",
    "$PSScriptRoot\src\modules\iso_builder.ps1",
    "$PSScriptRoot\src\modules\software_installer.ps1",
    "$PSScriptRoot\src\modules\appx_manager.ps1",
    "$PSScriptRoot\src\ui\controller.ps1"
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine($banner)

foreach ($f in $filesToBundle) {
    if (-not (Test-Path $f)) {
        throw "Arquivo obrigatório ausente: $f"
    }
    Write-Host " -> Agregando $(Split-Path $f -Leaf)..." -ForegroundColor Gray
    $content = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    [void]$sb.AppendLine($content)
    [void]$sb.AppendLine()
}

# Converter e embutir configs JSON em formato ASCII-safe
Write-Host " -> Embutindo configurações JSON (ASCII-safe)..." -ForegroundColor Gray
$cfgDir = "$PSScriptRoot\src\config"
$appsJson     = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "applications.json"), [System.Text.Encoding]::UTF8))
$appxJson     = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "appx.json"), [System.Text.Encoding]::UTF8))
$dnsJson      = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "dns.json"), [System.Text.Encoding]::UTF8))
$featuresJson = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "features.json"), [System.Text.Encoding]::UTF8))
$presetsJson  = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "presets.json"), [System.Text.Encoding]::UTF8))
$tweaksJson   = ConvertTo-AsciiJson ([System.IO.File]::ReadAllText((Join-Path $cfgDir "tweaks.json"), [System.Text.Encoding]::UTF8))

# Converter XAML e autounattend.xml em entidades XML puras (ASCII-safe)
Write-Host " -> Embutindo XAML e autounattend.xml..." -ForegroundColor Gray
$xamlContent     = ConvertTo-AsciiXml ([System.IO.File]::ReadAllText("$PSScriptRoot\src\ui\app.xaml", [System.Text.Encoding]::UTF8))
$unattendContent = ConvertTo-AsciiXml ([System.IO.File]::ReadAllText((Join-Path $cfgDir "autounattend.xml"), [System.Text.Encoding]::UTF8))

$runtimeScript = @"
# 1. Garantir privilégios de Administrador
if (-not (Test-IsAdmin)) {
    Ensure-AdminPrivileges
    return
}

# 2. Carregar configurações e templates embutidos
`$embeddedConfigs = @{
    Applications = @'
$appsJson
'@ | ConvertFrom-Json
    Appx         = @'
$appxJson
'@ | ConvertFrom-Json
    Dns          = @'
$dnsJson
'@ | ConvertFrom-Json
    Features     = @'
$featuresJson
'@ | ConvertFrom-Json
    Presets      = @'
$presetsJson
'@ | ConvertFrom-Json
    Tweaks       = @'
$tweaksJson
'@ | ConvertFrom-Json
}

`$embeddedUnattendXml = @'
$unattendContent
'@

`$embeddedXaml = @'
$xamlContent
'@

# 3. Iniciar Interface Gráfica (HUD v3.0)
Start-WinRepairUI -XamlText `$embeddedXaml -Configs `$embeddedConfigs -AutoUnattendXml `$embeddedUnattendXml
"@

[void]$sb.AppendLine($runtimeScript)

# Salvar em UTF-8 SEM BOM para compatibilidade total com irm | iex e ParseFile
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($destination, $sb.ToString(), $utf8NoBom)

Write-Host "[+] Compilação concluída com sucesso (UTF-8 sem BOM): $destination" -ForegroundColor Green
