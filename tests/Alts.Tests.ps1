BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:SrcDir   = Join-Path $script:RepoRoot "src"
    $script:CfgDir   = Join-Path $script:SrcDir "config"
    $script:BuildPs1 = Join-Path $script:RepoRoot "build.ps1"

    . (Join-Path $script:SrcDir "core\logger.ps1")
    . (Join-Path $script:SrcDir "modules\tweak_engine.ps1")
    . (Join-Path $script:SrcDir "modules\hardware_optimizer.ps1")
    . (Join-Path $script:SrcDir "modules\tweaks_system.ps1")
    . (Join-Path $script:SrcDir "modules\appx_manager.ps1")
}

Describe "Integridade de Scripts PowerShell" {
    It "Todos os arquivos .ps1 em src/ e build.ps1 têm sintaxe válida" {
        $files = @($script:BuildPs1) + @(Get-ChildItem -Path $script:SrcDir -Recurse -Filter *.ps1 | Select-Object -ExpandProperty FullName)
        $files.Count | Should -BeGreaterThan 0

        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0 -Because "o arquivo $file não deve conter erros de sintaxe"
        }
    }
}

Describe "Configurações JSON e XML/XAML" {
    It "Todos os arquivos JSON em src/config são válidos" {
        $jsonFiles = Get-ChildItem -Path $script:CfgDir -Filter *.json
        $jsonFiles.Count | Should -BeGreaterThan 0

        foreach ($jf in $jsonFiles) {
            { [System.IO.File]::ReadAllText($jf.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    It "Todas as chaves de presets.json existem em tweaks.json" {
        $presets = [System.IO.File]::ReadAllText((Join-Path $script:CfgDir "presets.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $tweaks  = [System.IO.File]::ReadAllText((Join-Path $script:CfgDir "tweaks.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $tweakKeys = @($tweaks.PSObject.Properties.Name)

        foreach ($prop in $presets.PSObject.Properties) {
            foreach ($key in @($prop.Value)) {
                ($tweakKeys -contains $key) | Should -BeTrue -Because "a chave '$key' do preset '$($prop.Name)' deve existir em tweaks.json"
            }
        }
    }

    It "app.xaml e autounattend.xml são XMLs válidos e todos os controles FindName existem no XAML" {
        $xamlRaw = [System.IO.File]::ReadAllText((Join-Path $script:SrcDir "ui\app.xaml"), [System.Text.Encoding]::UTF8)
        $unattendRaw = [System.IO.File]::ReadAllText((Join-Path $script:CfgDir "autounattend.xml"), [System.Text.Encoding]::UTF8)
        { [void][xml]$xamlRaw } | Should -Not -Throw
        { [void][xml]$unattendRaw } | Should -Not -Throw

        $ctrlRaw = [System.IO.File]::ReadAllText((Join-Path $script:SrcDir "ui\controller.ps1"), [System.Text.Encoding]::UTF8)
        $xamlNames = [regex]::Matches($xamlRaw, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $findNames = [regex]::Matches($ctrlRaw, 'FindName\("([^"]+)"\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

        foreach ($fn in $findNames) {
            ($xamlNames -contains $fn) | Should -BeTrue -Because "o controle '$fn' referenciado em controller.ps1 deve existir em app.xaml"
        }
    }
}

Describe "Empacotamento Standalone (build.ps1)" {
    It "Compila bundle válido em UTF-8 sem BOM e com 0 erros de sintaxe" {
        $tempOut = Join-Path $env:TEMP ("alts_pester_build_" + [guid]::NewGuid().ToString("N"))
        try {
            & $script:BuildPs1 -OutputDir $tempOut -OutputFile "alt-tweaks.ps1"
            $bundlePath = Join-Path $tempOut "alt-tweaks.ps1"
            (Test-Path $bundlePath) | Should -BeTrue

            $bytes = [System.IO.File]::ReadAllBytes($bundlePath)
            ($bytes.Length -gt 1000) | Should -BeTrue
            $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasUtf8Bom | Should -BeFalse

            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($bundlePath, [ref]$tokens, [ref]$errors)
            $errors.Count | Should -Be 0

            $bundleText = [System.IO.File]::ReadAllText($bundlePath, [System.Text.Encoding]::UTF8)
            $bundleText | Should -Match '\$embeddedConfigs\s*='
            $bundleText | Should -Match '\$embeddedXaml\s*='
            $bundleText | Should -Match 'Start-WinRepairUI'
        } finally {
            if (Test-Path $tempOut) {
                Remove-Item -Path $tempOut -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Modo Dry-Run e Pré-visualização" {
    It "Get-TweakChangesPreview e Format-TweakChangesPreviewText listam alterações de registro, serviço e script" {
        $tweaks = [System.IO.File]::ReadAllText((Join-Path $script:CfgDir "tweaks.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $sample = @(
            [pscustomobject]@{ Key = "WPFTweaksActivity"; Obj = $tweaks.WPFTweaksActivity },
            [pscustomobject]@{ Key = "WPFTweaksHiber";    Obj = $tweaks.WPFTweaksHiber }
        )

        $changes = Get-TweakChangesPreview -SelectedTweaks $sample
        $changes.Count | Should -BeGreaterThan 0
        (@($changes | Where-Object { $_.Kind -eq "Registro" }).Count) | Should -BeGreaterThan 0
        (@($changes | Where-Object { $_.Kind -eq "Script" }).Count) | Should -BeGreaterThan 0

        $text = Format-TweakChangesPreviewText -SelectedTweaks $sample
        $text | Should -Match "PRÉ-VISUALIZAÇÃO DE ALTERAÇÕES"
        $text | Should -Match "WPFTweaksActivity"
    }

    It "Invoke-DeclarativeTweak -DryRun não executa InvokeScript nem lança exceções" {
        $markerFile = Join-Path $env:TEMP ("alts_dryrun_marker_" + [guid]::NewGuid().ToString("N") + ".txt")
        $syntheticTweak = [pscustomobject]@{
            Content      = "Tweak Sintético de Teste"
            service      = @([pscustomobject]@{ Name = "DiagTrack"; StartupType = "Disabled"; OriginalType = "Automatic" })
            registry     = @([pscustomobject]@{ Path = "HKCU:\Software\AltsNonExistentTestKey"; Name = "TestVal"; Type = "DWord"; Value = 1; OriginalValue = "<RemoveEntry>" })
            InvokeScript = @("Set-Content -Path '$markerFile' -Value 'EXECUTED'")
            UndoScript   = @("Set-Content -Path '$markerFile' -Value 'UNDONE'")
        }

        { Invoke-DeclarativeTweak -TweakKey "SyntheticTest" -TweakObj $syntheticTweak -DryRun } | Should -Not -Throw
        { Invoke-DeclarativeTweak -TweakKey "SyntheticTest" -TweakObj $syntheticTweak -Undo -DryRun } | Should -Not -Throw
        (Test-Path $markerFile) | Should -BeFalse
    }

    It "Set-RestorePoint -DryRun retorna true sem criar ponto real" {
        $res = Set-RestorePoint -Description "Alts_DryRunTest" -DryRun
        $res | Should -BeTrue
    }

    It "Helpers de AppX (Preview e Dry-Run) funcionam sem modificar pacotes" {
        $appxCfg = [System.IO.File]::ReadAllText((Join-Path $script:CfgDir "appx.json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $firstKey = @($appxCfg.PSObject.Properties.Name) | Select-Object -First 1
        $entries = @($appxCfg.$firstKey)

        $preview = Get-AppxChangesPreview -Entries $entries -Action "Remove"
        $preview.Count | Should -Be 1
        $text = Format-AppxChangesPreviewText -Entries $entries -Action "Remove"
        $text | Should -Match "REMOÇÃO DE PACOTES APPX"

        { Remove-SelectedAppxPackages -Entries $entries -DryRun } | Should -Not -Throw
        { Install-SelectedAppxPackages -Entries $entries -DryRun } | Should -Not -Throw
    }

    It "Hardware Optimizer detecta perfil, lista 16 ajustes, gera preview e simula Dry-Run sem falhas" {
        $profile = Get-HardwareOptimizationProfile
        $profile.CpuVendor | Should -Not -BeNullOrEmpty
        $profile.PrimaryGpuName | Should -Not -BeNullOrEmpty

        $catalog = Get-HardwareOptimizationCatalog
        $catalog.Count | Should -Be 16
        $allKeys = @($catalog | Select-Object -ExpandProperty Key)
        ($allKeys | Select-Object -Unique).Count | Should -Be 16

        $prev = Get-HardwareChangesPreview -Keys $allKeys
        $prev.Count | Should -Be 16
        $txt = Format-HardwareChangesPreviewText -Keys $allKeys
        $txt | Should -Match "PRÉ-VISUALIZAÇÃO DE HARDWARE"

        foreach ($k in $allKeys) {
            { Invoke-HardwareOptimization -Key $k -DryRun } | Should -Not -Throw
            { Invoke-HardwareOptimization -Key $k -Undo -DryRun } | Should -Not -Throw
        }

        { Invoke-HardwareExternalTool -ToolKey "NVCleanstall" -DryRun } | Should -Not -Throw
        { Invoke-HardwareExternalTool -ToolKey "NvidiaDrivers" -DryRun } | Should -Not -Throw
    }
}
