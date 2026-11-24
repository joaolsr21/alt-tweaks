# ==============================================================================
# Validador Local (Compatível com PowerShell 5.1+ sem dependências externas)
# ==============================================================================
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcDir   = Join-Path $repoRoot "src"
$cfgDir   = Join-Path $srcDir "config"
$buildPs1 = Join-Path $repoRoot "build.ps1"

$script:Passed = 0
$script:Failed = 0

function Invoke-Check {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Test
    )

    try {
        & $Test
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    } catch {
        Write-Host "[FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host "=== Iniciando Validação Local do Alt Tweaks ===" -ForegroundColor Cyan

# Carregar módulos não-UI para testes funcionais
. (Join-Path $srcDir "core\logger.ps1")
. (Join-Path $srcDir "modules\tweak_engine.ps1")
. (Join-Path $srcDir "modules\hardware_optimizer.ps1")
. (Join-Path $srcDir "modules\tweaks_system.ps1")
. (Join-Path $srcDir "modules\appx_manager.ps1")

Invoke-Check "Sintaxe de todos os scripts .ps1 (src/ e build.ps1)" {
    $files = @($buildPs1) + @(Get-ChildItem -Path $srcDir -Recurse -Filter *.ps1 | Select-Object -ExpandProperty FullName)
    foreach ($f in $files) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw "Erros de sintaxe em $f : $($errors[0].Message)"
        }
    }
}

Invoke-Check "Validade de todos os arquivos JSON em src/config/" {
    $jsonFiles = Get-ChildItem -Path $cfgDir -Filter *.json
    if ($jsonFiles.Count -eq 0) { throw "Nenhum JSON encontrado em $cfgDir" }
    foreach ($jf in $jsonFiles) {
        $null = [System.IO.File]::ReadAllText($jf.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
}

Invoke-Check "Integridade referencial: presets.json -> tweaks.json" {
    $presets = [System.IO.File]::ReadAllText((Join-Path $cfgDir "presets.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $tweaks  = [System.IO.File]::ReadAllText((Join-Path $cfgDir "tweaks.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $tweakKeys = @($tweaks.PSObject.Properties.Name)
    foreach ($prop in $presets.PSObject.Properties) {
        foreach ($key in @($prop.Value)) {
            if ($tweakKeys -notcontains $key) {
                throw "Chave '$key' do preset '$($prop.Name)' ausente em tweaks.json"
            }
        }
    }
}

Invoke-Check "Validade XML (app.xaml e autounattend.xml) e vínculos FindName" {
    $xamlRaw = [System.IO.File]::ReadAllText((Join-Path $srcDir "ui\app.xaml"), [System.Text.Encoding]::UTF8)
    $unattendRaw = [System.IO.File]::ReadAllText((Join-Path $cfgDir "autounattend.xml"), [System.Text.Encoding]::UTF8)
    [void][xml]$xamlRaw
    [void][xml]$unattendRaw

    $ctrlRaw = [System.IO.File]::ReadAllText((Join-Path $srcDir "ui\controller.ps1"), [System.Text.Encoding]::UTF8)
    $xamlNames = [regex]::Matches($xamlRaw, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $findNames = [regex]::Matches($ctrlRaw, 'FindName\("([^"]+)"\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    foreach ($fn in $findNames) {
        if ($xamlNames -notcontains $fn) {
            throw "Controle '$fn' referenciado em controller.ps1 não encontrado em app.xaml"
        }
    }
}

Invoke-Check "Build standalone em diretório temporário (UTF-8 sem BOM + 0 erros)" {
    $tempOut = Join-Path $env:TEMP ("alts_val_build_" + [guid]::NewGuid().ToString("N"))
    try {
        & $buildPs1 -OutputDir $tempOut -OutputFile "alts.ps1" | Out-Null
        $bundlePath = Join-Path $tempOut "alts.ps1"
        if (-not (Test-Path $bundlePath)) { throw "Bundle não gerado em $bundlePath" }

        $bytes = [System.IO.File]::ReadAllBytes($bundlePath)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            throw "Bundle contém BOM UTF-8 inesperado"
        }

        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($bundlePath, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw "Erros de sintaxe no bundle gerado: $($errors[0].Message)"
        }
    } finally {
        if (Test-Path $tempOut) {
            Remove-Item -Path $tempOut -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Check "Preview e Dry-Run de Tweaks + Set-RestorePoint" {
    $tweaks = [System.IO.File]::ReadAllText((Join-Path $cfgDir "tweaks.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $sample = @(
        [pscustomobject]@{ Key = "WPFTweaksActivity"; Obj = $tweaks.WPFTweaksActivity },
        [pscustomobject]@{ Key = "WPFTweaksHiber";    Obj = $tweaks.WPFTweaksHiber }
    )
    $changes = Get-TweakChangesPreview -SelectedTweaks $sample
    if ($changes.Count -eq 0) { throw "Get-TweakChangesPreview retornou 0 itens" }

    $text = Format-TweakChangesPreviewText -SelectedTweaks $sample
    if ($text -notmatch "PRÉ-VISUALIZAÇÃO DE ALTERAÇÕES") { throw "Texto de pré-visualização inválido" }

    $markerFile = Join-Path $env:TEMP ("alts_val_marker_" + [guid]::NewGuid().ToString("N") + ".txt")
    $syntheticTweak = [pscustomobject]@{
        Content      = "Tweak Sintético"
        service      = @([pscustomobject]@{ Name = "DiagTrack"; StartupType = "Disabled"; OriginalType = "Automatic" })
        registry     = @([pscustomobject]@{ Path = "HKCU:\Software\AltsNonExistentTestKey"; Name = "TestVal"; Type = "DWord"; Value = 1; OriginalValue = "<RemoveEntry>" })
        InvokeScript = @("Set-Content -Path '$markerFile' -Value 'EXECUTED'")
        UndoScript   = @("Set-Content -Path '$markerFile' -Value 'UNDONE'")
    }
    Invoke-DeclarativeTweak -TweakKey "SyntheticTest" -TweakObj $syntheticTweak -DryRun
    Invoke-DeclarativeTweak -TweakKey "SyntheticTest" -TweakObj $syntheticTweak -Undo -DryRun
    if (Test-Path $markerFile) {
        Remove-Item $markerFile -Force -ErrorAction SilentlyContinue
        throw "InvokeScript foi executado mesmo com -DryRun!"
    }

    if (-not (Set-RestorePoint -Description "Alts_DryRun" -DryRun)) {
        throw "Set-RestorePoint -DryRun não retornou true"
    }
}

Invoke-Check "Preview e Dry-Run de AppX" {
    $appxCfg = [System.IO.File]::ReadAllText((Join-Path $cfgDir "appx.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $firstKey = @($appxCfg.PSObject.Properties.Name) | Select-Object -First 1
    $entries = @($appxCfg.$firstKey)

    $preview = Get-AppxChangesPreview -Entries $entries -Action "Remove"
    if ($preview.Count -ne 1) { throw "Get-AppxChangesPreview retornou contagem inesperada: $($preview.Count)" }

    $text = Format-AppxChangesPreviewText -Entries $entries -Action "Remove"
    if ($text -notmatch "REMOÇÃO DE PACOTES APPX") { throw "Format-AppxChangesPreviewText retornou texto inválido" }

    Remove-SelectedAppxPackages -Entries $entries -DryRun
    Install-SelectedAppxPackages -Entries $entries -DryRun
}

Invoke-Check "Hardware Optimizer: Detecção, Catálogo, Preview e Dry-Run (GPU & CPU)" {
    $profile = Get-HardwareOptimizationProfile
    if (-not $profile -or -not $profile.CpuVendor -or -not $profile.PrimaryGpuName) {
        throw "Get-HardwareOptimizationProfile retornou perfil incompleto"
    }

    $catalog = Get-HardwareOptimizationCatalog
    if ($catalog.Count -ne 16) {
        throw "Esperado 16 itens no catálogo de hardware, encontrado $($catalog.Count)"
    }
    $uniqueKeys = @($catalog | Select-Object -ExpandProperty Key -Unique)
    if ($uniqueKeys.Count -ne 16) {
        throw "Chaves duplicadas detectadas no catálogo de hardware"
    }

    $allKeys = @($catalog | Select-Object -ExpandProperty Key)
    $prevApply = Get-HardwareChangesPreview -Keys $allKeys
    $prevUndo  = Get-HardwareChangesPreview -Keys $allKeys -Undo
    if ($prevApply.Count -ne 16 -or $prevUndo.Count -ne 16) {
        throw "Preview de hardware retornou contagem inesperada"
    }

    $txt = Format-HardwareChangesPreviewText -Keys $allKeys
    if ($txt -notmatch "PRÉ-VISUALIZAÇÃO DE HARDWARE") {
        throw "Format-HardwareChangesPreviewText retornou formato inválido"
    }

    foreach ($k in $allKeys) {
        Invoke-HardwareOptimization -Key $k -DryRun
        Invoke-HardwareOptimization -Key $k -Undo -DryRun
    }

    Invoke-HardwareExternalTool -ToolKey "NVCleanstall" -DryRun
    Invoke-HardwareExternalTool -ToolKey "NvidiaDrivers" -DryRun
}

Write-Host ""
Write-Host "Resultado: $($script:Passed) passaram, $($script:Failed) falharam." -ForegroundColor Cyan
if ($script:Failed -gt 0) {
    exit 1
}
exit 0
