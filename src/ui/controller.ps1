# ==============================================================================
# Módulo de Interface: Controlador Unificado WPF + Hover Info + Runspaces
# ==============================================================================

function Start-AsyncAction {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [hashtable]$Vars = @{},
        [string]$Label = "Executando tarefa...",
        [scriptblock]$OnCompleted = $null
    )

    $sync = $global:WinRepairSync
    $jobId = [guid]::NewGuid().ToString()

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($global:BaseInitialSessionState)
    $rs.Open()
    foreach ($k in $Vars.Keys) {
        $rs.SessionStateProxy.SetVariable($k, $Vars[$k])
    }
    $rs.SessionStateProxy.SetVariable("__JobId", $jobId)

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    $wrappedCode = @"
Set-TaskStatus -Text "$($Label -replace '"','')" -IsRunning `$true
try {
$($Action.ToString())
} catch {
    Write-ToolLog "Erro na execução: `$_" "ERROR"
}
"@
    [void]$ps.AddScript($wrappedCode)
    $handle = $ps.BeginInvoke()

    [void]$sync.ActiveJobs.Add([pscustomobject]@{
        Id          = $jobId
        PowerShell  = $ps
        Runspace    = $rs
        Handle      = $handle
        OnCompleted = $OnCompleted
    })
}

function Register-HoverHelp {
    param(
        [Parameter(Mandatory=$true)]$Control,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [string]$Badge = "Dica",
        [switch]$NoToolTip
    )

    if ($null -eq $Control) { return }

    $Control.Resources["HoverHelpInfo"] = [pscustomobject]@{
        Title       = $Title
        Description = $Description
        Badge       = $Badge
    }

    if (-not $NoToolTip) {
        $tipPanel = New-Object System.Windows.Controls.StackPanel
        $tTitle = New-Object System.Windows.Controls.TextBlock
        $tTitle.Text = $Title
        $tTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $tTitle.FontSize = 12
        $tTitle.Margin = New-Object System.Windows.Thickness(0, 0, 0, 3)
        $tTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextSecondary")
        [void]$tipPanel.Children.Add($tTitle)

        $tDesc = New-Object System.Windows.Controls.TextBlock
        $tDesc.Text = $Description
        $tDesc.FontSize = 11.5
        $tDesc.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tDesc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextPrimary")
        [void]$tipPanel.Children.Add($tDesc)

        $Control.ToolTip = $tipPanel
    }

    $Control.Add_MouseEnter({
        param($sender, $e)
        $ui = $global:WinRepairUi
        if (-not $ui -or -not $ui.Window) { return }
        $info = $sender.Resources["HoverHelpInfo"]
        if ($null -eq $info) { return }

        $ui.Window.FindName("txtHoverBadge").Text = $info.Badge
        $ui.Window.FindName("txtHoverTitle").Text = "$($info.Title):"
        $ui.Window.FindName("txtHoverDesc").Text  = $info.Description
    })
}

function Set-HudTheme {
    param([ValidateSet("Dark", "Light", "Auto")][string]$Mode = "Dark")

    $ui = $global:WinRepairUi
    if (-not $ui -or -not $ui.Window) { return }

    if ($Mode -eq "Auto") {
        try {
            $lightVal = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
            $target = if ($lightVal -eq 1) { "Light" } else { "Dark" }
        } catch { $target = "Dark" }
    } else {
        $target = $Mode
    }

    # Paleta Crimson Noir (#0B0B0D, #1F1F24, #C1121F, #FF4D4D, #F2F2F2)
    $palette = if ($target -eq "Light") {
        @{
            BrushBgApp         = "#F2F2F2"
            BrushBgSidebar     = "#E8E8EC"
            BrushBgSurface     = "#FFFFFF"
            BrushBgCard        = "#FFFFFF"
            BrushBgCardAlt     = "#ECECF0"
            BrushBgCardHover   = "#FCE8EA"
            BrushBgInput       = "#F7F7F9"
            BrushBrandStart    = "#1F1F24"
            BrushBrandEnd      = "#C1121F"
            BrushBorder        = "#D4D4DC"
            BrushBorderStrong  = "#C1121F"
            BrushBorderHover   = "#FF4D4D"
            BrushTextPrimary   = "#0B0B0D"
            BrushTextSecondary = "#C1121F"
            BrushTextMuted     = "#52525E"
            BrushAccent        = "#C1121F"
            BrushAccentHover   = "#FF4D4D"
            BrushAccentDeep    = "#FCE8EA"
            BrushAccentText    = "#F2F2F2"
            BrushSuccess       = "#15803D"
            BrushWarning       = "#B45309"
            BrushDanger        = "#C1121F"
            BrushConsoleBg     = "#0B0B0D"
            BrushConsoleFg     = "#F2F2F2"
        }
    } else {
        @{
            BrushBgApp         = "#0B0B0D"
            BrushBgSidebar     = "#101014"
            BrushBgSurface     = "#16161A"
            BrushBgCard        = "#1F1F24"
            BrushBgCardAlt     = "#28282F"
            BrushBgCardHover   = "#322024"
            BrushBgInput       = "#121216"
            BrushBrandStart    = "#1F1F24"
            BrushBrandEnd      = "#C1121F"
            BrushBorder        = "#2F2F38"
            BrushBorderStrong  = "#C1121F"
            BrushBorderHover   = "#FF4D4D"
            BrushTextPrimary   = "#F2F2F2"
            BrushTextSecondary = "#FF4D4D"
            BrushTextMuted     = "#A3A3AE"
            BrushAccent        = "#C1121F"
            BrushAccentHover   = "#FF4D4D"
            BrushAccentDeep    = "#4A0D13"
            BrushAccentText    = "#F2F2F2"
            BrushSuccess       = "#4ADE80"
            BrushWarning       = "#FBBF24"
            BrushDanger        = "#FF4D4D"
            BrushConsoleBg     = "#08080A"
            BrushConsoleFg     = "#F2F2F2"
        }
    }

    foreach ($k in $palette.Keys) {
        $hex = $palette[$k]
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $ui.Window.Resources[$k] = [System.Windows.Media.SolidColorBrush]::new($color)
    }

    $ui.CurrentTheme = $target
    if ($global:WinRepairSync) { $global:WinRepairSync.ThemeMode = $Mode }
}

function Update-PresetCardVisuals {
    param([string]$ActivePreset = "Nenhum")

    $ui = $global:WinRepairUi
    if (-not $ui -or -not $ui.Window) { return }

    $map = @{
        Desktop  = $ui.Window.FindName("btnPresetDesktop")
        Notebook = $ui.Window.FindName("btnPresetNotebook")
        All      = $ui.Window.FindName("btnPresetAll")
    }

    foreach ($k in $map.Keys) {
        $btn = $map[$k]
        if (-not $btn) { continue }
        if ($k -eq $ActivePreset) {
            $btn.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushAccentDeep")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushTextSecondary")
        } else {
            $btn.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushBgCardAlt")
            $btn.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushBorderStrong")
        }
    }
}

function Update-TweaksSelectionPreview {
    $ui = $global:WinRepairUi
    if (-not $ui) { return }

    $ui.Window.FindName("txtActivePresetBadge").Text = "Perfil: $($ui.ActivePreset)"
    Update-PresetCardVisuals -ActivePreset $ui.ActivePreset

    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($k in $ui.TweakCheckBoxes.Keys) {
        $cb = $ui.TweakCheckBoxes[$k]
        if ($cb.IsChecked) {
            [void]$selected.Add([pscustomobject]@{ Key = $k; Label = [string]$cb.Content })
        }
    }

    $count = $selected.Count
    $ui.Window.FindName("txtTweaksSelectedCount").Text = if ($count -eq 1) { "1 opção selecionada" } else { "$count opções selecionadas" }

    $chipsPanel = $ui.Window.FindName("panelSelectedTweaksChips")
    $chipsPanel.Children.Clear()

    if ($count -eq 0) {
        $hint = New-Object System.Windows.Controls.TextBlock
        $hint.Text = "Nenhuma opção marcada. Clique em Desktop, Notebook, All ou marque manualmente abaixo."
        $hint.FontSize = 11.5
        $hint.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextMuted")
        $hint.Margin = New-Object System.Windows.Thickness(2, 4, 2, 4)
        [void]$chipsPanel.Children.Add($hint)
        return
    }

    foreach ($item in $selected) {
        $chip = New-Object System.Windows.Controls.Border
        $chip.CornerRadius = New-Object System.Windows.CornerRadius(11)
        $chip.Padding = New-Object System.Windows.Thickness(9, 3, 9, 3)
        $chip.Margin = New-Object System.Windows.Thickness(2)
        $chip.BorderThickness = New-Object System.Windows.Thickness(1)
        $chip.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushBgCardAlt")
        $chip.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushAccent")

        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = $item.Label
        $txt.FontSize = 11
        $txt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextPrimary")
        $chip.Child = $txt
        [void]$chipsPanel.Children.Add($chip)
    }
}

function Select-TweakPreset {
    param([ValidateSet("Desktop", "Notebook", "All")][string]$PresetName)

    $ui = $global:WinRepairUi
    $configs = $global:WinRepairSync.Configs
    if (-not $ui -or -not $configs -or -not $configs.Presets) { return }

    $targetKeys = @($configs.Presets.$PresetName)
    $ui.SuppressPresetReset = $true
    try {
        foreach ($k in $ui.TweakCheckBoxes.Keys) {
            $ui.TweakCheckBoxes[$k].IsChecked = ($targetKeys -contains $k)
        }
    } finally {
        $ui.SuppressPresetReset = $false
    }

    $ui.ActivePreset = $PresetName
    Update-TweaksSelectionPreview

    $checkedCount = @($ui.TweakCheckBoxes.Values | Where-Object { $_.IsChecked }).Count
    Write-ToolLog "Perfil [$PresetName] selecionado ($checkedCount opções marcadas). Revise no painel superior e clique em 'Aplicar Tweaks Selecionados' para executar." "INFO"
}

function Update-AppsSelectionCounter {
    $ui = $global:WinRepairUi
    if (-not $ui) { return }
    $count = @($ui.AppCheckBoxes.Values | Where-Object { $_.IsChecked }).Count
    $ui.Window.FindName("txtAppsSelectedCount").Text = "Selecionados: $count"
}

function Update-AppxSelectionCounter {
    $ui = $global:WinRepairUi
    if (-not $ui) { return }
    $count = @($ui.AppxCheckBoxes.Values | Where-Object { $_.IsChecked }).Count
    $ui.Window.FindName("txtAppxSelectedCount").Text = "Selecionados: $count"
}

function Apply-GlobalSearchFilter {
    $ui = $global:WinRepairUi
    if (-not $ui) { return }
    $rawText = $ui.Window.FindName("txtGlobalSearch").Text
    $ui.Window.FindName("txtSearchPlaceholder").Visibility = if ([string]::IsNullOrEmpty($rawText)) {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }

    $q = $rawText.Trim().ToLowerInvariant()

    foreach ($catInfo in $ui.AppCategoryExpanders) {
        $anyVisible = $false
        $catMatchesFilter = ($ui.SelectedAppCategory -eq "Todas" -or $catInfo.Category -eq $ui.SelectedAppCategory)
        foreach ($cb in $catInfo.CheckBoxes) {
            $descTxt = if ($cb.Resources["HoverHelpInfo"]) { $cb.Resources["HoverHelpInfo"].Description } else { "" }
            $match = ([string]::IsNullOrEmpty($q)) -or (([string]$cb.Content).ToLowerInvariant().Contains($q)) -or ($descTxt.ToLowerInvariant().Contains($q))
            if ($catMatchesFilter -and $match) {
                $cb.Visibility = [System.Windows.Visibility]::Visible
                $anyVisible = $true
            } else {
                $cb.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }
        $catInfo.Expander.Visibility = if ($catMatchesFilter -and $anyVisible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }

    foreach ($map in @($ui.TweakCheckBoxes, $ui.ToggleBoxes, $ui.AppxCheckBoxes, $ui.FeatureCheckBoxes)) {
        foreach ($cb in $map.Values) {
            $descTxt = if ($cb.Resources["HoverHelpInfo"]) { $cb.Resources["HoverHelpInfo"].Description } else { "" }
            $match = ([string]::IsNullOrEmpty($q)) -or (([string]$cb.Content).ToLowerInvariant().Contains($q)) -or ($descTxt.ToLowerInvariant().Contains($q))
            $cb.Visibility = if ($match) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    }
}

function Set-ActiveHudView {
    param([string]$ViewKey)

    $ui = $global:WinRepairUi
    if (-not $ui) { return }

    $meta = @{
        Install = @{ Title = "Catálogo de Softwares"; Sub = "Passe o mouse em qualquer software para ver descrição e instale via WinGet ou Chocolatey" }
        Tweaks  = @{ Title = "Tweaks & Perfis Recomendados"; Sub = "Escolha Desktop, Notebook ou All para pré-selecionar e revisar antes de aplicar" }
        Appx    = @{ Title = "Gerenciador de AppX & Bloatware"; Sub = "Remova aplicativos pré-instalados do Windows ou reinstale via Microsoft Store" }
        Network = @{ Title = "Rede, Diagnóstico & DNS"; Sub = "14 ferramentas integradas de diagnóstico, varredura de rede local, TCP e Benchmark DNS" }
        Config  = @{ Title = "Recursos, Correções & Painéis do Sistema"; Sub = "Recursos opcionais, reparo DISM/SFC/Update, 14 painéis clássicos e OpenSSH" }
        Updates = @{ Title = "Políticas do Windows Update"; Sub = "Controle completo sobre atualizações automáticas, drivers e adiamento" }
        Iso     = @{ Title = "Criador de ISO Customizada & Pendrive USB"; Sub = "Injete bypasses, autounattend, drivers locais e grave direto no pendrive" }
    }

    foreach ($k in $ui.Views.Keys) {
        $ui.Views[$k].Visibility = if ($k -eq $ViewKey) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }

    if ($meta.ContainsKey($ViewKey)) {
        $ui.Window.FindName("txtSectionTitle").Text = $meta[$ViewKey].Title
        $ui.Window.FindName("txtSectionSubtitle").Text = $meta[$ViewKey].Sub
    }
    $ui.ActiveView = $ViewKey
}

function Initialize-StaticHoverHelp {
    $ui = $global:WinRepairUi
    $w = $ui.Window

    $entries = @(
        @("navTweaks", "Tweaks & Perfis", "Abre os perfis recomendados (Desktop, Notebook, All), otimizações do sistema e preferências instantâneas.", "Navegação"),
        @("navInstall", "Catálogo de Softwares", "Instale, desinstale ou atualize 239 programas populares silenciosamente via WinGet ou Chocolatey.", "Navegação"),
        @("navAppx", "AppX & Bloatware", "Remova ou reinstale aplicativos universais pré-instalados da Microsoft Store.", "Navegação"),
        @("navNetwork", "Rede & Diagnóstico", "Diagnóstico de rede em 14 ferramentas, varredura de IPs locais, otimização TCP e Benchmark DNS.", "Navegação"),
        @("navConfig", "Recursos & Reparos", "Recursos opcionais (WSL 2, Sandbox, Hyper-V), SFC/DISM, OpenSSH e 14 painéis clássicos.", "Navegação"),
        @("navUpdates", "Windows Update", "Escolha entre Padrão Microsoft, Recomendado (Estável), Pausa até 2042 ou Desativar.", "Navegação"),
        @("navIso", "Criador de ISO & USB", "Gere ISOs do Windows 10/11 sem TPM/Conta Microsoft e grave em pendrive FAT32 bootável.", "Navegação"),

        @("btnImportConfig", "Importar Seleção (.json)", "Carrega um arquivo .json e apenas marca os itens correspondentes para você revisar.", "Arquivo"),
        @("btnExportConfig", "Exportar Seleção (.json)", "Salva todas as opções marcadas atualmente em um arquivo .json reutilizável.", "Arquivo"),
        @("btnEnvReport", "Relatório do Ambiente", "Gera arquivo .txt na Área de Trabalho com hardware, versões de gerenciadores e status atual.", "Relatório"),
        @("btnToggleTheme", "Alternar Tema", "Alterna entre a paleta Crimson Noir (Escuro) e Crimson Light (Claro).", "Aparência"),
        @("btnFontDown", "Diminuir Fonte", "Reduz o tamanho do texto da interface para exibir mais itens por tela.", "Aparência"),
        @("btnFontUp", "Aumentar Fonte", "Amplia o tamanho do texto da interface para facilitar a leitura.", "Aparência"),

        @("btnPresetDesktop", "Perfil Desktop (Pré-Seleção)", "Marca 21 otimizações ideais para PCs de mesa (inclui desativar hibernação, TCP Gaming e TRIM). Não executa sozinho.", "Perfil"),
        @("btnPresetNotebook", "Perfil Notebook (Pré-Seleção)", "Marca 19 otimizações seguras para laptops, preservando hibernação e economia de energia Wi-Fi. Não executa sozinho.", "Perfil"),
        @("btnPresetAll", "Perfil All (Marcar Tudo)", "Marca todas as 48 opções de Tweaks Essenciais e Avançados no painel para revisão antes de executar.", "Perfil"),
        @("btnCreateRestorePoint", "Criar Ponto de Restauração", "Cria um ponto de segurança nativo do Windows para reverter alterações caso precise.", "Segurança"),
        @("btnApplyTweaks", "Aplicar Tweaks Selecionados", "Executa em segundo plano apenas as opções marcadas na lista abaixo.", "Execução"),
        @("btnUndoTweaks", "Desfazer Selecionados", "Reverte as modificações de registro/serviços das opções marcadas atualmente.", "Reverter"),
        @("btnClearTweaks", "Limpar Seleção", "Desmarca todas as caixas de Tweaks e limpa a lista de pré-visualização.", "Seleção"),
        @("btnEnableUltPerf", "Plano Desempenho Máximo", "Desbloqueia e ativa o esquema oculto Ultimate Performance (maior resposta de CPU).", "Energia"),
        @("btnDisableUltPerf", "Restaurar Planos de Energia", "Restaura os esquemas de energia padrão de fábrica do Windows.", "Energia"),
        @("btnRunOOSU", "Executar O&O ShutUp10++", "Baixa e abre a ferramenta portátil oficial O&O ShutUp10++ para ajustes extras de privacidade.", "Privacidade"),

        @("btnInstallApps", "Instalar / Atualizar Selecionados", "Instala ou atualiza todos os programas marcados usando WinGet ou Chocolatey.", "Softwares"),
        @("btnUninstallApps", "Desinstalar Selecionados", "Remove silenciosamente do sistema todos os programas marcados no catálogo.", "Softwares"),
        @("btnUpgradeAllApps", "Atualizar Todos os Apps", "Executa atualização geral de todos os programas instalados no computador.", "Softwares"),
        @("btnDetectInstalledApps", "Mostrar Instalados", "Destaca os softwares do catálogo que já estão instalados neste PC.", "Softwares"),
        @("btnClearApps", "Limpar Seleção de Apps", "Desmarca todos os checkboxes da lista de softwares.", "Seleção"),

        @("btnAppxDefault", "Marcar Bloatwares Padrão", "Marca automaticamente os 18 aplicativos pré-instalados mais comuns para remoção (apenas seleciona).", "AppX"),
        @("btnAppxSelectAll", "Marcar Todos AppX", "Marca todos os 34 pacotes AppX listados abaixo.", "AppX"),
        @("btnAppxClear", "Limpar Seleção AppX", "Desmarca todos os checkboxes de AppX.", "AppX"),
        @("btnAppxDetectInstalled", "Destacar AppX Instalados", "Verifica no sistema e destaca em destaque os AppX atualmente instalados.", "AppX"),
        @("btnAppxRemove", "Remover Selecionados", "Remove os pacotes AppX selecionados para todos os usuários e da imagem provisionada.", "Cuidado"),
        @("btnAppxInstall", "Reinstalar Selecionados (Store)", "Baixa e reinstala os pacotes selecionados diretamente da Microsoft Store via WinGet.", "Restaurar"),

        @("btnNetQuickDiag", "[1] Diagnóstico Rápido Integrado", "Testa placa local (127.0.0.1), Gateway/roteador, saída IP direta e resolução DNS em sequência.", "Rede"),
        @("btnNetDetailed", "[2] Teste Detalhado (Ping + HTTPS + DNS)", "Mede latência média/perda ICMP, valida acesso Web HTTPS porta 443 e resolução de domínios.", "Rede"),
        @("btnNetSpeedtest", "[3] Teste Velocidade Download", "Baixa bloco de 5 MB via CDN Cloudflare para medir a taxa real de download em Mbps.", "Rede"),
        @("btnNetWifi", "[4] Diagnóstico Wi-Fi", "Exibe interface sem fio atual, força do sinal em %, canal, SSID e redes próximas.", "Rede"),
        @("btnNetWifiReport", "[4b] Gerar Relatório Wi-Fi (HTML)", "Gera relatório oficial netsh wlanreport detalhado com histórico de quedas de Wi-Fi.", "Rede"),
        @("btnNetTestPort", "[5] Testar Porta TCP Alvo", "Verifica se o Host/IP e Porta informados acima estão acessíveis e abertos.", "Rede"),
        @("btnNetPathping", "[6] Perda de Pacotes (Pathping)", "Analisa perda de pacotes em cada salto até o destino informado.", "Rede"),
        @("btnNetTracert", "[7] Rastrear Rota (Tracert)", "Lista todos os roteadores (hops) entre seu PC e o destino para achar gargalos.", "Rede"),
        @("btnNetPingCont", "[8] Ping Contínuo (-t)", "Abre janela separada executando ping -t contínuo no alvo para monitorar estabilidade.", "Rede"),
        @("btnNetstatEst", "[9a] Netstat: Conexões Ativas", "Lista conexões TCP ativas (ESTABLISHED) com portas e PID do processo.", "Monitor"),
        @("btnNetstatList", "[9b] Netstat: Portas Escutando", "Lista serviços e portas abertas aguardando conexões (LISTENING) no sistema.", "Monitor"),
        @("btnNetstatAll", "[9c] Netstat: Tudo Detalhado", "Exibe todas as conexões e sockets ativos com PIDs.", "Monitor"),
        @("btnNetSubnetScan", "[10] Varredura Rede Local", "Escaneia IPs ativos na sub-rede local, coleta MAC/ARP, lista blocos de IPs livres e salva no Desktop.", "Rede Local"),
        @("btnNetIpConfig", "[11] Exibir ipconfig /all", "Mostra detalhes completos de IPv4, IPv6, DHCP, Gateway e servidores DNS atuais.", "Rede"),
        @("btnNetSimpleRepair", "[12] Reparar Conexão", "Executa Flush DNS, renova IP via DHCP (release/renew) e recarrega tabela NetBIOS.", "Reparo"),
        @("btnNetResetDeep", "[13] Reset Completo Pilha TCP/IP", "Reseta Winsock, IPv4, IPv6, WinHTTP Proxy, cache ARP e regras do Firewall do Windows.", "Cuidado"),
        @("btnNetForensicReport", "[14] Relatório Forense Completo (.TXT)", "Coleta 8 diagnósticos completos de rede e salva arquivo .txt na Área de Trabalho.", "Relatório"),
        @("btnRestartAdapters", "Reiniciar Placas de Rede", "Desativa e reativa adaptadores físicos Ethernet/Wi-Fi conectados.", "Rede"),
        @("btnOptimizeTcpTab", "Otimizar TCP Baixa Latência", "Ativa AutoTuning normal, RSS, ECN e remove limite multimídia NetworkThrottlingIndex.", "Gaming"),
        @("btnDnsBenchmark", "Benchmark DNS (Latência)", "Testa tempo de resposta TCP/53 em todos os provedores DNS para encontrar o mais rápido na sua rede.", "DNS"),
        @("btnApplyDns", "Aplicar DNS Selecionado", "Aplica IPv4, IPv6 e DNS-over-HTTPS (DoH) do provedor escolhido no ComboBox.", "DNS"),

        @("btnInstallFeatures", "Instalar Recursos Selecionados", "Habilita os recursos opcionais marcados acima usando DISM / Recursos do Windows.", "Sistema"),
        @("btnFixFullCorruption", "Verificação Completa (DISM + SFC)", "Executa DISM /RestoreHealth seguido de SFC /scannow para reparar arquivos corrompidos do Windows.", "Reparo"),
        @("btnSfcScan", "SFC /scannow", "Verifica e corrige arquivos protegidos do Windows corrompidos.", "Reparo"),
        @("btnDismRepair", "DISM /RestoreHealth", "Repara a imagem base do sistema Windows via Windows Update.", "Reparo"),
        @("btnDismCleanup", "Limpar WinSxS", "Remove versões antigas obsoletas de componentes da pasta WinSxS (/ResetBase).", "Limpeza"),
        @("btnFixWuReset", "Resetar Windows Update", "Limpa cache SoftwareDistribution, re-registra DLLs e reinicia serviços de atualização.", "Update"),
        @("btnFixWuResetAggressive", "Resetar WU (Agressivo)", "Além do reset padrão, executa DISM+SFC e redefine permissões SDSET de segurança dos serviços.", "Cuidado"),
        @("btnFixNetwork", "Resetar Rede Completa", "Reseta Winsock, TCP/IP, Proxy e Firewall para corrigir internet sem conexão.", "Rede"),
        @("btnFixWinget", "Reinstalar / Reparar WinGet", "Usa Microsoft.WinGet.Client para instalar ou consertar o gerenciador WinGet.", "Reparo"),
        @("btnFixNtpPool", "Sincronizar NTP (pool.ntp.org)", "Substitui o servidor de horário padrão por pool.ntp.org para maior precisão.", "Sistema"),
        @("btnFixAutologon", "Executar Autologon (Sysinternals)", "Baixa e abre o utilitário oficial Sysinternals para configurar login automático seguro.", "Sistema"),
        @("btnRestartSpooler", "Destravar Spooler Impressão", "Limpa documentos travados da fila de impressão e reinicia o serviço Spooler.", "Reparo"),
        @("btnScheduleChkdsk", "Agendar CHKDSK (Disco C:)", "Agenda verificação e reparo de erros no sistema de arquivos do disco C: na próxima reinicialização.", "Disco"),
        @("btnEnableSshServer", "Habilitar Servidor OpenSSH", "Instala OpenSSH Server, libera porta TCP 22 no Firewall e configura chaves administrativas.", "Remoto"),
        @("btnInstallPsProfile", "Instalar Perfil PowerShell 7", "Configura histórico preditivo PSReadLine e atalhos úteis no perfil do PowerShell 7.", "Terminal"),
        @("btnUninstallPsProfile", "Remover Perfil PowerShell 7", "Remove o perfil personalizado e restaura o backup anterior (.bak) se existir.", "Terminal"),

        @("btnWuDefault", "Restaurar Windows Update Padrão", "Remove todas as políticas de adiamento e devolve o controle automático padrão da Microsoft.", "Update"),
        @("btnWuRecommended", "Aplicar Modo Recomendado", "Evita drivers automáticos e adia recursos grandes por 365 dias mantendo segurança em dia.", "Recomendado"),
        @("btnWuPause", "Pausar Atualizações até 2042", "Estende o limite oficial de pausa do Windows Update até o ano de 2042.", "Update"),
        @("btnWuDisable", "Desativar Windows Update", "Para e desativa serviços/tarefas de atualização. Requer confirmação explícita.", "Cuidado"),

        @("btnBrowseIso", "Procurar ISO", "Seleciona o arquivo .iso oficial do Windows 10 ou Windows 11 no computador.", "ISO"),
        @("btnInspectIso", "Analisar Edições", "Monta a ISO temporariamente para listar todas as edições disponíveis (Home, Pro, etc.).", "ISO"),
        @("btnBuildCustomIso", "Preparar e Gerar ISO Otimizada", "Injeta bypasses, debloat, autounattend.xml, drivers locais e prepara a ISO/mídia.", "ISO"),
        @("btnRefreshUsb", "Atualizar USBs", "Lista pendrives USB removíveis conectados prontos para receber a instalação bootável.", "USB"),
        @("btnWriteUsb", "Formatar e Gravar Pendrive", "Formata o pendrive em FAT32 UEFI (dividindo install.wim >4GB se necessário) e grava os arquivos.", "Cuidado")
    )

    foreach ($item in $entries) {
        $ctrl = $w.FindName($item[0])
        if ($ctrl) {
            $noTip = ($item[0] -like "nav*")
            Register-HoverHelp -Control $ctrl -Title $item[1] -Description $item[2] -Badge $item[3] -NoToolTip:$noTip
        }
    }
}

function Start-WinRepairUI {
    param(
        [Parameter(Mandatory=$true)][string]$XamlText,
        [Parameter(Mandatory=$true)][hashtable]$Configs,
        [string]$AutoUnattendXml = ""
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$XamlText)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $global:txtLogControl = $window.FindName("txtLog")
    $global:WinRepairSync = [hashtable]::Synchronized(@{
        LogQueue           = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        ActiveJobs         = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Results            = [hashtable]::Synchronized(@{})
        Configs            = $Configs
        AutoUnattendXml    = $AutoUnattendXml
        TaskStatus         = "Pronto"
        IsRunning          = $false
        ThemeMode          = "Dark"
        PendingThemeSync   = $null
        LastPreparedIsoDir = $null
        RecentLogs         = @()
    })

    $global:WinRepairUi = @{
        Window               = $window
        Views                = @{
            Install = $window.FindName("viewInstall")
            Tweaks  = $window.FindName("viewTweaks")
            Appx    = $window.FindName("viewAppx")
            Network = $window.FindName("viewNetwork")
            Config  = $window.FindName("viewConfig")
            Updates = $window.FindName("viewUpdates")
            Iso     = $window.FindName("viewIso")
        }
        AppCheckBoxes        = [ordered]@{}
        AppCategoryExpanders = New-Object System.Collections.Generic.List[object]
        SelectedAppCategory  = "Todas"
        TweakCheckBoxes      = [ordered]@{}
        ToggleBoxes          = [ordered]@{}
        ComboControls        = [ordered]@{}
        AppxCheckBoxes       = [ordered]@{}
        FeatureCheckBoxes    = [ordered]@{}
        ActivePreset         = "Nenhum"
        SuppressPresetReset  = $false
        Initializing         = $true
        CurrentTheme         = "Dark"
        ConsoleCollapsed     = $false
        IsoEditions          = @()
        UsbDisks             = @()
    }

    # Preparar InitialSessionState para tarefas assíncronas em Runspaces
    $global:BaseInitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $global:BaseInitialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry("WinRepairSync", $global:WinRepairSync, $null)))
    foreach ($fn in (Get-ChildItem Function:\ | Where-Object { -not $_.ModuleName -and $_.Name.Length -gt 2 -and $_.Name -notmatch ':' })) {
        try {
            $global:BaseInitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn.Name, $fn.Definition)))
        } catch {}
    }

    # Hardware info no header
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $window.FindName("txtSystemInfo").Text = "$($os.Caption -replace 'Microsoft ','') ($($os.OSArchitecture)) | $ramGb GB | $($env:COMPUTERNAME)"
    } catch {
        $window.FindName("txtSystemInfo").Text = "Windows | $($env:COMPUTERNAME)"
    }

    # Tradução PT-BR das categorias de Softwares
    $appCatNames = @{
        "Browsers"         = "Navegadores"
        "Communications"   = "Comunicação"
        "Development"      = "Desenvolvimento"
        "Document"         = "Documentos & PDF"
        "Games"            = "Jogos & Launchers"
        "Microsoft Tools"  = "Ferramentas Microsoft"
        "Multimedia Tools" = "Multimídia & Vídeo"
        "Pro Tools"        = "Ferramentas Pro"
        "Selfhosted Tools" = "Selfhosted & Rede"
        "Utilities"        = "Utilitários Essenciais"
    }

    # ==========================================================================
    # POPULAR CONTROLES DINÂMICOS + HOVER HELP INSTANTÂNEO
    # ==========================================================================

    # 1. SOFTWARES (239 Apps)
    $appsByCategory = [ordered]@{}
    foreach ($p in $Configs.Applications.PSObject.Properties) {
        $rawCat = if ($p.Value.category) { $p.Value.category } else { "Utilities" }
        $cat = if ($appCatNames.ContainsKey($rawCat)) { $appCatNames[$rawCat] } else { $rawCat }
        if (-not $appsByCategory.Contains($cat)) {
            $appsByCategory[$cat] = New-Object System.Collections.Generic.List[object]
        }
        [void]$appsByCategory[$cat].Add([pscustomobject]@{ Key = $p.Name; Data = $p.Value; CatLabel = $cat })
    }

    $chipsWrap = $window.FindName("panelAppCategoryChips")
    $allChip = New-Object System.Windows.Controls.Button
    $allChip.Content = "Todas ($($Configs.Applications.PSObject.Properties.Count))"
    $allChip.Style = $window.FindResource("PillButtonStyle")
    $allChip.Add_Click({
        $global:WinRepairUi.SelectedAppCategory = "Todas"
        Apply-GlobalSearchFilter
    })
    Register-HoverHelp -Control $allChip -Title "Mostrar Todas" -Description "Exibe todas as categorias do catálogo de softwares." -Badge "Filtro" -NoToolTip
    [void]$chipsWrap.Children.Add($allChip)

    $appCols = @($window.FindName("panelAppsCol0"), $window.FindName("panelAppsCol1"), $window.FindName("panelAppsCol2"))
    $colIdx = 0
    foreach ($catName in ($appsByCategory.Keys | Sort-Object)) {
        $items = $appsByCategory[$catName] | Sort-Object { $_.Data.content }

        $chip = New-Object System.Windows.Controls.Button
        $chip.Content = "$catName ($($items.Count))"
        $chip.Tag = $catName
        $chip.Style = $window.FindResource("PillButtonStyle")
        $chip.Add_Click({
            param($s, $e)
            $global:WinRepairUi.SelectedAppCategory = [string]$s.Tag
            Apply-GlobalSearchFilter
        })
        Register-HoverHelp -Control $chip -Title "Categoria: $catName" -Description "Filtra apenas os $($items.Count) aplicativo(s) de $catName." -Badge "Filtro" -NoToolTip
        [void]$chipsWrap.Children.Add($chip)

        $exp = New-Object System.Windows.Controls.Expander
        $exp.Header = "$catName ($($items.Count))"
        $exp.IsExpanded = $true
        $exp.FontWeight = [System.Windows.FontWeights]::Bold

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Margin = New-Object System.Windows.Thickness(6, 6, 6, 8)
        $catCheckBoxes = New-Object System.Collections.Generic.List[object]

        foreach ($appEntry in $items) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $fossTag = if ($appEntry.Data.foss -eq $true) { " [FOSS]" } else { "" }
            $cb.Content = "$($appEntry.Data.content)$fossTag"
            $cb.Tag = $appEntry.Key
            $cb.FontWeight = [System.Windows.FontWeights]::Normal

            $wgTxt = if ($appEntry.Data.winget -and $appEntry.Data.winget -ne "na") { $appEntry.Data.winget } else { "-" }
            $desc = if ($appEntry.Data.description) { "$($appEntry.Data.description) (WinGet: $wgTxt)" } else { "WinGet: $wgTxt" }
            $badge = if ($appEntry.Data.foss -eq $true) { "FOSS • $catName" } else { $catName }
            Register-HoverHelp -Control $cb -Title $appEntry.Data.content -Description $desc -Badge $badge

            $cb.Add_Checked({ Update-AppsSelectionCounter })
            $cb.Add_Unchecked({ Update-AppsSelectionCounter })
            [void]$stack.Children.Add($cb)
            [void]$catCheckBoxes.Add($cb)
            $global:WinRepairUi.AppCheckBoxes[$appEntry.Key] = $cb
        }

        $exp.Content = $stack
        [void]$appCols[$colIdx % 3].Children.Add($exp)
        [void]$global:WinRepairUi.AppCategoryExpanders.Add([pscustomobject]@{
            Category   = $catName
            Expander   = $exp
            CheckBoxes = $catCheckBoxes
        })
        $colIdx++
    }

    # 2. TWEAKS, AVANÇADOS & PREFERÊNCIAS TOGGLES
    $pEssential = $window.FindName("panelTweaksEssential")
    $pAdvanced  = $window.FindName("panelTweaksAdvanced")
    $pPrefs     = $window.FindName("panelTweaksPrefs")

    foreach ($p in $Configs.Tweaks.PSObject.Properties) {
        $key = $p.Name
        $item = $p.Value
        $cat = $item.category
        $typ = if ($item.Type) { $item.Type } else { "CheckBox" }

        if ($key -in @("WPFOOSUbutton", "WPFchangedns", "WPFAddUltPerf", "WPFRemoveUltPerf")) { continue }

        $descText = if ($item.Description) { $item.Description } else { $item.Content }

        if ($typ -eq "Toggle") {
            $tg = New-Object System.Windows.Controls.CheckBox
            $tg.Content = $item.Content
            $tg.Tag = $key
            $tg.Style = $window.FindResource("ToggleSwitchStyle")
            try { $tg.IsChecked = (Get-ToggleCurrentState -TweakObj $item) } catch { $tg.IsChecked = $false }

            Register-HoverHelp -Control $tg -Title $item.Content -Description $descText -Badge "Instantâneo"

            $tg.Add_Click({
                param($sender, $e)
                $tKey = [string]$sender.Tag
                $obj = $global:WinRepairSync.Configs.Tweaks.$tKey
                $undo = -not ([bool]$sender.IsChecked)
                Start-AsyncAction -Label "Preferência: $($obj.Content)" -Vars @{ tKey = $tKey; obj = $obj; undo = $undo } -Action {
                    Invoke-DeclarativeTweak -TweakKey $tKey -TweakObj $obj -Undo:$undo
                }
            })
            [void]$pPrefs.Children.Add($tg)
            $global:WinRepairUi.ToggleBoxes[$key] = $tg
        } elseif ($typ -eq "Combobox" -and $item.ComboItems) {
            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = "$($item.Content):"
            $lbl.FontSize = 11.5
            $lbl.FontWeight = [System.Windows.FontWeights]::SemiBold
            $lbl.Margin = New-Object System.Windows.Thickness(7, 10, 0, 3)
            $lbl.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextMuted")
            [void]$pPrefs.Children.Add($lbl)

            $cmb = New-Object System.Windows.Controls.ComboBox
            $cmb.Tag = $key
            $cmb.Margin = New-Object System.Windows.Thickness(7, 0, 7, 4)
            Register-HoverHelp -Control $cmb -Title $item.Content -Description $descText -Badge "GPU / Vídeo"

            $comboOpts = @($item.ComboItems -split '\|')
            foreach ($opt in $comboOpts) { [void]$cmb.Items.Add($opt) }
            try {
                $curState = Get-RegistryComboState -Registry $item.registry -ComboItems $comboOpts
                if ($curState) { $cmb.SelectedItem = $curState }
            } catch {
                if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
            }
            $cmb.Add_SelectionChanged({
                param($sender, $e)
                if ($global:WinRepairUi.Initializing) { return }
                $cKey = [string]$sender.Tag
                $selState = [string]$sender.SelectedItem
                $regDef = $global:WinRepairSync.Configs.Tweaks.$cKey.registry
                if ($selState -and $regDef) {
                    Start-AsyncAction -Label "Ajustando $cKey -> $selState" -Vars @{ regDef = $regDef; selState = $selState } -Action {
                        Set-RegistryComboState -Registry $regDef -State $selState
                    }
                }
            })
            [void]$pPrefs.Children.Add($cmb)
            $global:WinRepairUi.ComboControls[$key] = $cmb
        } elseif ($typ -eq "CheckBox") {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $item.Content
            $cb.Tag = $key
            $badgeLbl = if ($cat -eq "Avancados") { "Avançado (Cuidado)" } else { "Essencial" }
            Register-HoverHelp -Control $cb -Title $item.Content -Description $descText -Badge $badgeLbl

            $cb.Add_Checked({
                if (-not $global:WinRepairUi.SuppressPresetReset) { $global:WinRepairUi.ActivePreset = "Personalizado" }
                Update-TweaksSelectionPreview
            })
            $cb.Add_Unchecked({
                if (-not $global:WinRepairUi.SuppressPresetReset) { $global:WinRepairUi.ActivePreset = "Personalizado" }
                Update-TweaksSelectionPreview
            })

            if ($cat -eq "Avancados") {
                [void]$pAdvanced.Children.Add($cb)
            } else {
                [void]$pEssential.Children.Add($cb)
            }
            $global:WinRepairUi.TweakCheckBoxes[$key] = $cb
        }
    }
    Update-TweaksSelectionPreview

    # 3. APPX & BLOATWARE (34 Pacotes)
    $appxByCat = [ordered]@{}
    foreach ($p in $Configs.Appx.PSObject.Properties) {
        $cat = if ($p.Value.Category) { $p.Value.Category } else { "Outros" }
        if (-not $appxByCat.Contains($cat)) {
            $appxByCat[$cat] = New-Object System.Collections.Generic.List[object]
        }
        [void]$appxByCat[$cat].Add([pscustomobject]@{ Key = $p.Name; Data = $p.Value })
    }
    $appxCols = @($window.FindName("panelAppxCol0"), $window.FindName("panelAppxCol1"), $window.FindName("panelAppxCol2"))
    $axIdx = 0
    foreach ($catName in ($appxByCat.Keys | Sort-Object)) {
        $card = New-Object System.Windows.Controls.Border
        $card.Style = $window.FindResource("CardBorderStyle")
        $sp = New-Object System.Windows.Controls.StackPanel

        $hdrTxt = New-Object System.Windows.Controls.TextBlock
        $hdrTxt.Text = $catName
        $hdrTxt.FontSize = 13.5
        $hdrTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $hdrTxt.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        $hdrTxt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextSecondary")
        [void]$sp.Children.Add($hdrTxt)

        foreach ($ax in ($appxByCat[$catName] | Sort-Object { $_.Data.Content })) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $ax.Data.Content
            $cb.Tag = $ax.Key
            $axDesc = if ($ax.Data.Description) { $ax.Data.Description } else { $ax.Data.PackageId }
            $axBadge = if ($ax.Data.DefaultDebloat -eq $true) { "Bloatware Padrão" } else { $catName }
            Register-HoverHelp -Control $cb -Title $ax.Data.Content -Description $axDesc -Badge $axBadge

            $cb.Add_Checked({ Update-AppxSelectionCounter })
            $cb.Add_Unchecked({ Update-AppxSelectionCounter })
            [void]$sp.Children.Add($cb)
            $global:WinRepairUi.AppxCheckBoxes[$ax.Key] = $cb
        }

        $card.Child = $sp
        [void]$appxCols[$axIdx % 3].Children.Add($card)
        $axIdx++
    }

    # 4. DNS COMBOBOX
    $cmbDns = $window.FindName("cmbDnsProvider")
    [void]$cmbDns.Items.Add("Mais Rápido (Benchmark)")
    foreach ($p in $Configs.Dns.PSObject.Properties) {
        [void]$cmbDns.Items.Add($p.Name)
    }
    [void]$cmbDns.Items.Add("Automático (DHCP)")
    $cmbDns.SelectedIndex = 0
    Register-HoverHelp -Control $cmbDns -Title "Seletor de Provedor DNS" -Description "Escolha Cloudflare, Google, Quad9, OpenDNS, AdGuard ou deixe no modo Benchmark automático." -Badge "DNS"

    # 5. RECURSOS OPCIONAIS & 14 PAINÉIS CLÁSSICOS
    $pFeat = $window.FindName("panelFeaturesContainer")
    $pLegacy = $window.FindName("panelLegacyPanelsContainer")

    foreach ($p in $Configs.Features.PSObject.Properties) {
        $key = $p.Name
        $f = $p.Value
        $fDesc = if ($f.Description) { $f.Description } else { $f.Content }
        if ($f.category -eq "Features" -and $key -ne "WPFFeatureInstall") {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $f.Content
            $cb.Tag = $key
            Register-HoverHelp -Control $cb -Title $f.Content -Description $fDesc -Badge "Recurso Windows"
            [void]$pFeat.Children.Add($cb)
            $global:WinRepairUi.FeatureCheckBoxes[$key] = $cb
        } elseif ($f.category -eq "Legacy Windows Panels") {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $f.Content
            $btn.Tag = $key
            $btn.MinWidth = 178
            Register-HoverHelp -Control $btn -Title $f.Content -Description $fDesc -Badge "Painel Clássico"
            $btn.Add_Click({
                param($sender, $e)
                $lKey = [string]$sender.Tag
                $fObj = $global:WinRepairSync.Configs.Features.$lKey
                if ($fObj.InvokeScript) {
                    foreach ($cmdLine in @($fObj.InvokeScript)) {
                        try { & ([scriptblock]::Create($cmdLine)) } catch { Write-ToolLog "Erro ao abrir painel: $_" "ERROR" }
                    }
                }
            })
            [void]$pLegacy.Children.Add($btn)
        }
    }

    # Hover help em todos os botões e elementos estáticos
    Initialize-StaticHoverHelp

    # ==========================================================================
    # VINCULAÇÃO DE EVENTOS PRINCIPAIS
    # ==========================================================================

    $window.FindName("navInstall").Add_Checked({ Set-ActiveHudView "Install" })
    $window.FindName("navTweaks").Add_Checked({ Set-ActiveHudView "Tweaks" })
    $window.FindName("navAppx").Add_Checked({ Set-ActiveHudView "Appx" })
    $window.FindName("navNetwork").Add_Checked({ Set-ActiveHudView "Network" })
    $window.FindName("navConfig").Add_Checked({ Set-ActiveHudView "Config" })
    $window.FindName("navUpdates").Add_Checked({ Set-ActiveHudView "Updates" })
    $window.FindName("navIso").Add_Checked({ Set-ActiveHudView "Iso" })

    $window.FindName("txtGlobalSearch").Add_TextChanged({ Apply-GlobalSearchFilter })
    $window.FindName("btnClearSearch").Add_Click({
        $global:WinRepairUi.Window.FindName("txtGlobalSearch").Text = ""
    })

    $window.FindName("btnToggleTheme").Add_Click({
        $next = if ($global:WinRepairUi.CurrentTheme -eq "Dark") { "Light" } else { "Dark" }
        Set-HudTheme -Mode $next
    })
    $window.FindName("btnFontUp").Add_Click({
        $w = $global:WinRepairUi.Window
        if ($w.FontSize -lt 17) { $w.FontSize += 1 }
    })
    $window.FindName("btnFontDown").Add_Click({
        $w = $global:WinRepairUi.Window
        if ($w.FontSize -gt 11) { $w.FontSize -= 1 }
    })

    $window.FindName("btnExportConfig").Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "Configuração JSON (*.json)|*.json"
        $dlg.FileName = "winrepair_config.json"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $keys = New-Object System.Collections.Generic.List[string]
            foreach ($map in @($global:WinRepairUi.TweakCheckBoxes, $global:WinRepairUi.AppCheckBoxes, $global:WinRepairUi.AppxCheckBoxes, $global:WinRepairUi.FeatureCheckBoxes)) {
                foreach ($k in $map.Keys) {
                    if ($map[$k].IsChecked) { [void]$keys.Add($k) }
                }
            }
            $json = ConvertTo-Json @($keys)
            [System.IO.File]::WriteAllText($dlg.FileName, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-ToolLog "Configuração exportada ($($keys.Count) seleções) para: $($dlg.FileName)" "SUCCESS"
        }
    })

    $window.FindName("btnImportConfig").Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Configuração JSON (*.json)|*.json"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $raw = [System.IO.File]::ReadAllText($dlg.FileName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                $flat = New-Object System.Collections.Generic.HashSet[string]
                if ($raw -is [array] -or $raw -is [System.Collections.IList]) {
                    foreach ($s in $raw) { [void]$flat.Add([string]$s) }
                } elseif ($raw -is [psobject]) {
                    foreach ($pr in $raw.PSObject.Properties) {
                        foreach ($v in @($pr.Value)) { [void]$flat.Add([string]$v) }
                    }
                }

                $global:WinRepairUi.SuppressPresetReset = $true
                try {
                    foreach ($map in @($global:WinRepairUi.TweakCheckBoxes, $global:WinRepairUi.AppCheckBoxes, $global:WinRepairUi.AppxCheckBoxes, $global:WinRepairUi.FeatureCheckBoxes)) {
                        foreach ($k in $map.Keys) { $map[$k].IsChecked = $flat.Contains($k) }
                    }
                } finally {
                    $global:WinRepairUi.SuppressPresetReset = $false
                }

                $global:WinRepairUi.ActivePreset = "Importado"
                Update-TweaksSelectionPreview
                Update-AppsSelectionCounter
                Update-AppxSelectionCounter
                Write-ToolLog "Configuração importada ($($flat.Count) chaves). Revise as seleções antes de aplicar." "SUCCESS"
            } catch {
                Write-ToolLog "Falha ao importar JSON: $_" "ERROR"
            }
        }
    })

    $window.FindName("btnEnvReport").Add_Click({
        $lines = $global:txtLogControl.Text -split "`r?`n" | Select-Object -Last 80
        $global:WinRepairSync.RecentLogs = @($lines)
        Start-AsyncAction -Label "Gerando Relatório do Ambiente..." -Action { Export-EnvironmentReport }
    })

    $window.FindName("btnToggleConsole").Add_Click({
        $ui = $global:WinRepairUi
        $row = $ui.Window.FindName("rowConsole")
        $btn = $ui.Window.FindName("btnToggleConsole")
        if ($ui.ConsoleCollapsed) {
            $row.Height = New-Object System.Windows.GridLength(155)
            $btn.Content = "$([char]0x25BC) Minimizar"
            $ui.ConsoleCollapsed = $false
        } else {
            $row.Height = New-Object System.Windows.GridLength(38)
            $btn.Content = "$([char]0x25B2) Expandir"
            $ui.ConsoleCollapsed = $true
        }
    })
    $window.FindName("btnCopyLogs").Add_Click({
        if ($global:txtLogControl.Text) {
            [System.Windows.Clipboard]::SetText($global:txtLogControl.Text)
            Write-ToolLog "Console copiado para a Área de Transferência." "INFO"
        }
    })
    $window.FindName("btnSaveLogs").Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "Arquivo de Texto (*.txt)|*.txt|Log (*.log)|*.log"
        $dlg.FileName = "winrepair_logs_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            [System.IO.File]::WriteAllText($dlg.FileName, $global:txtLogControl.Text, (New-Object System.Text.UTF8Encoding($false)))
            Write-ToolLog "Logs salvos em: $($dlg.FileName)" "SUCCESS"
        }
    })
    $window.FindName("btnClearLogs").Add_Click({ $global:txtLogControl.Text = "" })

    # --- VIEW 1: SOFTWARES ---
    $window.FindName("btnClearApps").Add_Click({
        foreach ($cb in $global:WinRepairUi.AppCheckBoxes.Values) { $cb.IsChecked = $false }
        Update-AppsSelectionCounter
    })
    $window.FindName("btnExpandAllApps").Add_Click({
        foreach ($ce in $global:WinRepairUi.AppCategoryExpanders) { $ce.Expander.IsExpanded = $true }
    })
    $window.FindName("btnCollapseAllApps").Add_Click({
        foreach ($ce in $global:WinRepairUi.AppCategoryExpanders) { $ce.Expander.IsExpanded = $false }
    })

    $window.FindName("btnInstallApps").Add_Click({
        $ui = $global:WinRepairUi
        $mgr = if ($ui.Window.FindName("rbManagerChoco").IsChecked) { "Choco" } else { "WinGet" }
        $selected = @(foreach ($k in $ui.AppCheckBoxes.Keys) {
            if ($ui.AppCheckBoxes[$k].IsChecked) {
                $d = $global:WinRepairSync.Configs.Applications.$k
                [pscustomobject]@{ Content = $d.content; Winget = $d.winget; Choco = $d.choco }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Selecione ao menos um aplicativo para instalar." "WARN"; return }
        Start-AsyncAction -Label "Instalando $($selected.Count) app(s) via $mgr..." -Vars @{ selected = $selected; mgr = $mgr } -Action {
            Install-PackagesBatch -Apps $selected -Manager $mgr
        }
    })

    $window.FindName("btnUninstallApps").Add_Click({
        $ui = $global:WinRepairUi
        $mgr = if ($ui.Window.FindName("rbManagerChoco").IsChecked) { "Choco" } else { "WinGet" }
        $selected = @(foreach ($k in $ui.AppCheckBoxes.Keys) {
            if ($ui.AppCheckBoxes[$k].IsChecked) {
                $d = $global:WinRepairSync.Configs.Applications.$k
                [pscustomobject]@{ Content = $d.content; Winget = $d.winget; Choco = $d.choco }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Selecione ao menos um aplicativo para desinstalar." "WARN"; return }
        Start-AsyncAction -Label "Desinstalando $($selected.Count) app(s) via $mgr..." -Vars @{ selected = $selected; mgr = $mgr } -Action {
            Uninstall-PackagesBatch -Apps $selected -Manager $mgr
        }
    })

    $window.FindName("btnUpgradeAllApps").Add_Click({
        $mgr = if ($global:WinRepairUi.Window.FindName("rbManagerChoco").IsChecked) { "Choco" } else { "WinGet" }
        Start-AsyncAction -Label "Atualizando todos os aplicativos ($mgr)..." -Vars @{ mgr = $mgr } -Action {
            Upgrade-AllPackages -Manager $mgr
        }
    })

    $window.FindName("btnDetectInstalledApps").Add_Click({
        $mgr = if ($global:WinRepairUi.Window.FindName("rbManagerChoco").IsChecked) { "Choco" } else { "WinGet" }
        Start-AsyncAction -Label "Verificando softwares instalados..." -Vars @{ mgr = $mgr } -Action {
            $global:WinRepairSync.Results[$__JobId] = Get-InstalledPackagesIds -Manager $mgr
        } -OnCompleted {
            param($rawList)
            if (-not $rawList) { return }
            $ui = $global:WinRepairUi
            $found = 0
            foreach ($k in $ui.AppCheckBoxes.Keys) {
                $d = $global:WinRepairSync.Configs.Applications.$k
                $ids = @($d.winget -split ';') + @($d.choco -split ';') | Where-Object { $_ -and $_ -ne "na" }
                $isInst = $false
                foreach ($id in $ids) {
                    if ($rawList -match [regex]::Escape($id)) { $isInst = $true; break }
                }
                $cb = $ui.AppCheckBoxes[$k]
                if ($isInst) {
                    $cb.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, "BrushSuccess")
                    $found++
                } else {
                    $cb.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, "BrushTextPrimary")
                }
            }
            Write-ToolLog "Verificação concluída: $found aplicativo(s) do catálogo detectado(s)." "SUCCESS"
        }
    })

    # --- VIEW 2: TWEAKS & PERFIS ---
    $window.FindName("btnPresetDesktop").Add_Click({ Select-TweakPreset -PresetName "Desktop" })
    $window.FindName("btnPresetNotebook").Add_Click({ Select-TweakPreset -PresetName "Notebook" })
    $window.FindName("btnPresetAll").Add_Click({ Select-TweakPreset -PresetName "All" })

    $window.FindName("btnClearTweaks").Add_Click({
        $ui = $global:WinRepairUi
        $ui.SuppressPresetReset = $true
        try {
            foreach ($cb in $ui.TweakCheckBoxes.Values) { $cb.IsChecked = $false }
        } finally { $ui.SuppressPresetReset = $false }
        $ui.ActivePreset = "Nenhum"
        Update-TweaksSelectionPreview
    })

    $window.FindName("btnApplyTweaks").Add_Click({
        $ui = $global:WinRepairUi
        $selected = @(foreach ($k in $ui.TweakCheckBoxes.Keys) {
            if ($ui.TweakCheckBoxes[$k].IsChecked) {
                [pscustomobject]@{ Key = $k; Obj = $global:WinRepairSync.Configs.Tweaks.$k }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Nenhuma opção marcada para aplicar." "WARN"; return }
        Start-AsyncAction -Label "Aplicando $($selected.Count) tweak(s)..." -Vars @{ selected = $selected } -Action {
            Write-ToolLog "=== INICIANDO APLICAÇÃO DE $($selected.Count) TWEAK(S) SELECIONADO(S) ===" "INFO"
            foreach ($s in $selected) {
                Invoke-DeclarativeTweak -TweakKey $s.Key -TweakObj $s.Obj -Undo:$false
            }
            Write-ToolLog "=== TODOS OS TWEAKS SELECIONADOS FORAM APLICADOS! ===" "SUCCESS"
        }
    })

    $window.FindName("btnUndoTweaks").Add_Click({
        $ui = $global:WinRepairUi
        $selected = @(foreach ($k in $ui.TweakCheckBoxes.Keys) {
            if ($ui.TweakCheckBoxes[$k].IsChecked) {
                [pscustomobject]@{ Key = $k; Obj = $global:WinRepairSync.Configs.Tweaks.$k }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Nenhuma opção marcada para desfazer." "WARN"; return }
        Start-AsyncAction -Label "Desfazendo $($selected.Count) tweak(s)..." -Vars @{ selected = $selected } -Action {
            Write-ToolLog "=== DESFAZENDO $($selected.Count) TWEAK(S) SELECIONADO(S) ===" "INFO"
            foreach ($s in $selected) {
                Invoke-DeclarativeTweak -TweakKey $s.Key -TweakObj $s.Obj -Undo:$true
            }
            Write-ToolLog "=== REVERSÃO CONCLUÍDA! ===" "SUCCESS"
        }
    })

    $window.FindName("btnCreateRestorePoint").Add_Click({ Start-AsyncAction -Label "Criando Ponto de Restauração..." -Action { Set-RestorePoint } })
    $window.FindName("btnEnableUltPerf").Add_Click({ Start-AsyncAction -Label "Ativando Plano Desempenho Máximo..." -Action { Set-UltimatePowerPlan -Enable } })
    $window.FindName("btnDisableUltPerf").Add_Click({ Start-AsyncAction -Label "Restaurando planos de energia..." -Action { Set-UltimatePowerPlan } })
    $window.FindName("btnRunOOSU").Add_Click({ Start-AsyncAction -Label "Baixando e iniciando O&O ShutUp10++..." -Action { Invoke-OOSU10 } })

    # --- VIEW 3: APPX & BLOATWARE ---
    $window.FindName("btnAppxDefault").Add_Click({
        $ui = $global:WinRepairUi
        foreach ($k in $ui.AppxCheckBoxes.Keys) {
            $ui.AppxCheckBoxes[$k].IsChecked = ($global:WinRepairSync.Configs.Appx.$k.DefaultDebloat -eq $true)
        }
        Update-AppxSelectionCounter
        Write-ToolLog "18 bloatwares padrão marcados para revisão. Clique em 'Remover Selecionados' para executar." "INFO"
    })
    $window.FindName("btnAppxSelectAll").Add_Click({
        foreach ($cb in $global:WinRepairUi.AppxCheckBoxes.Values) { $cb.IsChecked = $true }
        Update-AppxSelectionCounter
    })
    $window.FindName("btnAppxClear").Add_Click({
        foreach ($cb in $global:WinRepairUi.AppxCheckBoxes.Values) { $cb.IsChecked = $false }
        Update-AppxSelectionCounter
    })
    $window.FindName("btnAppxDetectInstalled").Add_Click({
        Start-AsyncAction -Label "Consultando pacotes AppX..." -Action {
            $global:WinRepairSync.Results[$__JobId] = Get-InstalledAppxPackageIds
        } -OnCompleted {
            param($installed)
            if (-not $installed) { return }
            $ui = $global:WinRepairUi
            $found = 0
            foreach ($k in $ui.AppxCheckBoxes.Keys) {
                $pkgId = $global:WinRepairSync.Configs.Appx.$k.PackageId
                $isInst = @($installed | Where-Object { $_ -like "*$pkgId*" }).Count -gt 0
                $cb = $ui.AppxCheckBoxes[$k]
                if ($isInst) {
                    $cb.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, "BrushSuccess")
                    $found++
                } else {
                    $cb.SetResourceReference([System.Windows.Controls.CheckBox]::ForegroundProperty, "BrushTextMuted")
                }
            }
            Write-ToolLog "$found pacote(s) AppX do catálogo estão instalados atualmente (destacados)." "SUCCESS"
        }
    })
    $window.FindName("btnAppxRemove").Add_Click({
        $ui = $global:WinRepairUi
        $entries = @(foreach ($k in $ui.AppxCheckBoxes.Keys) {
            if ($ui.AppxCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Appx.$k }
        })
        if ($entries.Count -eq 0) { Write-ToolLog "Nenhum pacote AppX selecionado para remover." "WARN"; return }
        Start-AsyncAction -Label "Removendo $($entries.Count) AppX..." -Vars @{ entries = $entries } -Action {
            Remove-SelectedAppxPackages -Entries $entries
        }
    })
    $window.FindName("btnAppxInstall").Add_Click({
        $ui = $global:WinRepairUi
        $entries = @(foreach ($k in $ui.AppxCheckBoxes.Keys) {
            if ($ui.AppxCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Appx.$k }
        })
        if ($entries.Count -eq 0) { Write-ToolLog "Nenhum pacote AppX selecionado para reinstalar." "WARN"; return }
        Start-AsyncAction -Label "Reinstalando $($entries.Count) AppX via Store..." -Vars @{ entries = $entries } -Action {
            Install-SelectedAppxPackages -Entries $entries
        }
    })

    # --- VIEW 4: REDE, DIAGNÓSTICO COMPLETO & DNS ---
    $window.FindName("btnNetQuickDiag").Add_Click({ Start-AsyncAction -Label "Diagnóstico rápido de rede..." -Action { Invoke-QuickIntegratedNetworkDiag } })
    $window.FindName("btnNetDetailed").Add_Click({ Start-AsyncAction -Label "Teste detalhado de rede..." -Action { Invoke-DetailedInternetTest } })
    $window.FindName("btnNetSpeedtest").Add_Click({ Start-AsyncAction -Label "Teste de velocidade..." -Action { Invoke-DownloadSpeedTest } })
    $window.FindName("btnNetWifi").Add_Click({ Start-AsyncAction -Label "Diagnóstico Wi-Fi..." -Action { Invoke-WifiDiagnostics -GenerateHtmlReport $false } })
    $window.FindName("btnNetWifiReport").Add_Click({ Start-AsyncAction -Label "Gerando relatório Wi-Fi HTML..." -Action { Invoke-WifiDiagnostics -GenerateHtmlReport $true } })

    $window.FindName("btnNetTestPort").Add_Click({
        $w = $global:WinRepairUi.Window
        $target = $w.FindName("txtNetTarget").Text
        $portVal = 443
        if (-not [int]::TryParse($w.FindName("txtNetPort").Text, [ref]$portVal)) {
            Write-ToolLog "Informe uma porta TCP válida." "WARN"; return
        }
        if (-not $target) { $target = "google.com" }
        Start-AsyncAction -Label "Testando porta ${target}:${portVal}..." -Vars @{ target = $target; portVal = $portVal } -Action {
            Test-SpecificTcpPort -TargetHost $target -Port $portVal
        }
    })
    $window.FindName("btnNetPathping").Add_Click({
        $target = $global:WinRepairUi.Window.FindName("txtNetTarget").Text
        Start-AsyncAction -Label "Executando Pathping..." -Vars @{ target = $target } -Action { Invoke-PathpingAnalysis -TargetHost $target }
    })
    $window.FindName("btnNetTracert").Add_Click({
        $target = $global:WinRepairUi.Window.FindName("txtNetTarget").Text
        Start-AsyncAction -Label "Rastreando rota (Tracert)..." -Vars @{ target = $target } -Action { Invoke-TracertAnalysis -TargetHost $target }
    })
    $window.FindName("btnNetPingCont").Add_Click({
        $target = $global:WinRepairUi.Window.FindName("txtNetTarget").Text
        Start-ContinuousPingWindow -TargetHost $target
    })
    $window.FindName("btnNetstatEst").Add_Click({ Start-AsyncAction -Label "Listando conexões ativas..." -Action { Get-ActiveConnectionsNetstat -Mode "Established" } })
    $window.FindName("btnNetstatList").Add_Click({ Start-AsyncAction -Label "Listando portas em escuta..." -Action { Get-ActiveConnectionsNetstat -Mode "Listening" } })
    $window.FindName("btnNetstatAll").Add_Click({ Start-AsyncAction -Label "Listando Netstat completo..." -Action { Get-ActiveConnectionsNetstat -Mode "All" } })
    $window.FindName("btnNetSubnetScan").Add_Click({ Start-AsyncAction -Label "Varrendo sub-rede local..." -Action { Invoke-LocalSubnetScan -SaveAndOpenReport $true } })
    $window.FindName("btnNetIpConfig").Add_Click({ Start-AsyncAction -Label "Coletando ipconfig /all..." -Action { Get-IpConfigAllDetails } })
    $window.FindName("btnNetSimpleRepair").Add_Click({ Start-AsyncAction -Label "Reparando conexão..." -Action { Invoke-SimpleNetworkRepair } })
    $window.FindName("btnNetResetDeep").Add_Click({ Start-AsyncAction -Label "Executando reset completo TCP/IP..." -Action { Invoke-ResetNetworkStack } })
    $window.FindName("btnNetForensicReport").Add_Click({ Start-AsyncAction -Label "Gerando relatório forense de rede..." -Action { Export-ForensicNetworkReport } })
    $window.FindName("btnRestartAdapters").Add_Click({ Start-AsyncAction -Label "Reiniciando adaptadores..." -Action { Restart-NetworkAdapters } })
    $window.FindName("btnOptimizeTcpTab").Add_Click({ Start-AsyncAction -Label "Otimizando pilha TCP/IP..." -Action { Optimize-TcpLatencyAndThroughput } })

    $window.FindName("btnApplyDns").Add_Click({
        $sel = [string]$global:WinRepairUi.Window.FindName("cmbDnsProvider").SelectedItem
        $key = switch ($sel) {
            "Mais Rápido (Benchmark)" { "Fastest" }
            "Automático (DHCP)"       { "DHCP" }
            default                   { $sel }
        }
        if (-not $key) { return }
        Start-AsyncAction -Label "Aplicando DNS ($key)..." -Vars @{ key = $key } -Action { Set-DnsFromConfig -ProviderKey $key }
    })
    $window.FindName("btnDnsBenchmark").Add_Click({ Start-AsyncAction -Label "Executando Benchmark DNS..." -Action { $null = Invoke-DnsLatencyBenchmark } })
    $window.FindName("btnDnsCloudflare").Add_Click({ Start-AsyncAction -Label "Aplicando DNS Cloudflare..." -Action { Set-QuickDnsProvider -Provider "Cloudflare" } })
    $window.FindName("btnDnsGoogle").Add_Click({ Start-AsyncAction -Label "Aplicando DNS Google..." -Action { Set-QuickDnsProvider -Provider "Google" } })
    $window.FindName("btnDnsQuad9").Add_Click({ Start-AsyncAction -Label "Aplicando DNS Quad9..." -Action { Set-QuickDnsProvider -Provider "Quad9" } })
    $window.FindName("btnDnsAdGuard").Add_Click({ Start-AsyncAction -Label "Aplicando DNS AdGuard..." -Action { Set-QuickDnsProvider -Provider "AdGuard" } })
    $window.FindName("btnDnsDhcp").Add_Click({ Start-AsyncAction -Label "Restaurando DNS DHCP..." -Action { Set-QuickDnsProvider -Provider "DHCP" } })

    # --- VIEW 5: RECURSOS, CORREÇÕES & REPAROS ---
    $window.FindName("btnInstallFeatures").Add_Click({
        $ui = $global:WinRepairUi
        $selected = @(foreach ($k in $ui.FeatureCheckBoxes.Keys) {
            if ($ui.FeatureCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Features.$k }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Nenhum recurso opcional selecionado." "WARN"; return }
        Start-AsyncAction -Label "Instalando $($selected.Count) recurso(s)..." -Vars @{ selected = $selected } -Action {
            Install-SelectedWindowsFeatures -FeatureEntries $selected
        }
    })

    $window.FindName("btnFixFullCorruption").Add_Click({ Start-AsyncAction -Label "Executando DISM + SFC..." -Action { Invoke-FullCorruptionRepair } })
    $window.FindName("btnSfcScan").Add_Click({ Start-AsyncAction -Label "Executando SFC /scannow..." -Action { Invoke-SfcScan } })
    $window.FindName("btnDismRepair").Add_Click({ Start-AsyncAction -Label "Executando DISM /RestoreHealth..." -Action { Invoke-DismRepair } })
    $window.FindName("btnDismCleanup").Add_Click({ Start-AsyncAction -Label "Limpando WinSxS..." -Action { Invoke-DismCleanup } })
    $window.FindName("btnFixWuReset").Add_Click({ Start-AsyncAction -Label "Resetando Windows Update..." -Action { Invoke-ResetWindowsUpdateFull -Aggressive $false } })
    $window.FindName("btnFixWuResetAggressive").Add_Click({ Start-AsyncAction -Label "Reset agressivo do Windows Update..." -Action { Invoke-ResetWindowsUpdateFull -Aggressive $true } })
    $window.FindName("btnFixNetwork").Add_Click({ Start-AsyncAction -Label "Resetando pilha de rede..." -Action { Invoke-ResetNetworkStack } })
    $window.FindName("btnFixWinget").Add_Click({ Start-AsyncAction -Label "Reparando WinGet..." -Action { Ensure-WinGetInstalled -Force } })
    $window.FindName("btnFixNtpPool").Add_Click({ Start-AsyncAction -Label "Sincronizando NTP (pool.ntp.org)..." -Action { Set-NtpPoolTimeSync } })
    $window.FindName("btnFixAutologon").Add_Click({ Start-AsyncAction -Label "Abrindo Sysinternals Autologon..." -Action { Invoke-SysinternalsAutologon } })
    $window.FindName("btnRestartSpooler").Add_Click({ Start-AsyncAction -Label "Destravando Spooler..." -Action { Restart-PrintSpooler } })
    $window.FindName("btnScheduleChkdsk").Add_Click({ Start-AsyncAction -Label "Agendando CHKDSK..." -Action { Schedule-ChkdskOnReboot } })

    $window.FindName("btnEnableSshServer").Add_Click({ Start-AsyncAction -Label "Configurando Servidor OpenSSH..." -Action { Enable-OpenSshServer } })
    $window.FindName("btnInstallPsProfile").Add_Click({ Start-AsyncAction -Label "Instalando perfil PowerShell 7..." -Action { Install-EnhancedPowerShellProfile } })
    $window.FindName("btnUninstallPsProfile").Add_Click({ Start-AsyncAction -Label "Removendo perfil PowerShell 7..." -Action { Uninstall-EnhancedPowerShellProfile } })

    # --- VIEW 6: WINDOWS UPDATE ---
    $window.FindName("btnWuDefault").Add_Click({ Start-AsyncAction -Label "Restaurando Windows Update padrão..." -Action { Reset-WindowsUpdateDefault } })
    $window.FindName("btnWuRecommended").Add_Click({ Start-AsyncAction -Label "Aplicando política recomendada de Update..." -Action { Set-WindowsUpdateRecommended } })
    $window.FindName("btnWuPause").Add_Click({ Start-AsyncAction -Label "Pausando atualizações até 2042..." -Action { Pause-WindowsUpdateExtended } })
    $window.FindName("btnWuDisable").Add_Click({
        $ans = [System.Windows.MessageBox]::Show(
            "Desativar o Windows Update para serviços essenciais e impede atualizações de segurança até que você restaure o padrão. Deseja continuar?",
            "Confirmar Desativação do Windows Update",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
            Start-AsyncAction -Label "Desativando Windows Update..." -Action { Disable-WindowsUpdateAll }
        }
    })

    # --- VIEW 7: CRIADOR DE ISO & PENDRIVE USB ---
    $window.FindName("btnBrowseIso").Add_Click({
        $selected = Select-IsoFileDialog
        if ($selected) {
            $global:WinRepairUi.Window.FindName("txtIsoPath").Text = $selected
            Write-ToolLog "ISO selecionada: $selected" "INFO"
        }
    })
    $window.FindName("btnBrowseOutputDir").Add_Click({
        $selected = Select-OutputFolderDialog
        if ($selected) {
            $global:WinRepairUi.Window.FindName("txtOutputIsoDir").Text = $selected
            Write-ToolLog "Pasta de saída: $selected" "INFO"
        }
    })
    $window.FindName("btnInspectIso").Add_Click({
        $isoPath = $global:WinRepairUi.Window.FindName("txtIsoPath").Text
        if (-not $isoPath -or -not (Test-Path $isoPath)) {
            Write-ToolLog "Selecione primeiro um arquivo ISO válido." "WARN"; return
        }
        Start-AsyncAction -Label "Analisando edições da ISO..." -Vars @{ isoPath = $isoPath } -Action {
            $global:WinRepairSync.Results[$__JobId] = Inspect-IsoEditions -IsoPath $isoPath
        } -OnCompleted {
            param($editions)
            $cmb = $global:WinRepairUi.Window.FindName("cmbIsoEdition")
            $cmb.Items.Clear()
            $global:WinRepairUi.IsoEditions = @($editions)
            foreach ($ed in @($editions)) {
                [void]$cmb.Items.Add("[$($ed.ImageIndex)] $($ed.ImageName)")
            }
            if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
        }
    })
    $window.FindName("btnBuildCustomIso").Add_Click({
        $w = $global:WinRepairUi.Window
        $isoPath = $w.FindName("txtIsoPath").Text
        $outputDir = $w.FindName("txtOutputIsoDir").Text
        $outputName = $w.FindName("txtOutputIsoName").Text

        if (-not $isoPath -or -not (Test-Path $isoPath)) {
            Write-ToolLog "Arquivo ISO de origem inválido." "ERROR"; return
        }

        $cmbEd = $w.FindName("cmbIsoEdition")
        $edIdx = 1
        $edId = ""
        if ($cmbEd.SelectedIndex -ge 0 -and $cmbEd.SelectedIndex -lt $global:WinRepairUi.IsoEditions.Count) {
            $picked = $global:WinRepairUi.IsoEditions[$cmbEd.SelectedIndex]
            $edIdx = [int]$picked.ImageIndex
            $edId  = [string]$picked.EditionId
        }

        $vars = @{
            isoPath    = $isoPath
            outputDir  = $outputDir
            outputName = $outputName
            edIdx      = $edIdx
            edId       = $edId
            tplXml     = $global:WinRepairSync.AutoUnattendXml
            bpHw       = [bool]$w.FindName("chkIsoBypassHw").IsChecked
            bpAcc      = [bool]$w.FindName("chkIsoBypassAcc").IsChecked
            disBit     = [bool]$w.FindName("chkIsoDisableBitLocker").IsChecked
            debloat    = [bool]$w.FindName("chkIsoDebloat").IsChecked
            unattend   = [bool]$w.FindName("chkIsoUnattend").IsChecked
            drv        = [bool]$w.FindName("chkIsoInjectDrivers").IsChecked
        }

        Start-AsyncAction -Label "Construindo ISO customizada (aguarde)..." -Vars $vars -Action {
            Build-CustomOptimizedIsoPipeline `
                -SourceIsoPath $isoPath `
                -OutputIsoDir $outputDir `
                -OutputIsoName $outputName `
                -EditionIndex $edIdx `
                -EditionId $edId `
                -AutoUnattendXmlTemplate $tplXml `
                -BypassHardwareChecks $bpHw `
                -BypassMicrosoftAccount $bpAcc `
                -DisableBitLocker $disBit `
                -RemoveBloatware $debloat `
                -InjectUnattendXml $unattend `
                -InjectDrivers $drv
        }
    })

    $window.FindName("btnRefreshUsb").Add_Click({
        Start-AsyncAction -Label "Atualizando unidades USB..." -Action {
            $global:WinRepairSync.Results[$__JobId] = Get-RemovableUsbDisks
        } -OnCompleted {
            param($disks)
            $cmb = $global:WinRepairUi.Window.FindName("cmbUsbDrive")
            $cmb.Items.Clear()
            $global:WinRepairUi.UsbDisks = @($disks)
            if ($global:WinRepairUi.UsbDisks.Count -eq 0) {
                [void]$cmb.Items.Add("Nenhum pendrive USB detectado")
            } else {
                foreach ($d in $global:WinRepairUi.UsbDisks) {
                    $gb = [math]::Round($d.Size / 1GB, 1)
                    [void]$cmb.Items.Add("Disco $($d.Number): $($d.FriendlyName) [$gb GB]")
                }
            }
            $cmb.SelectedIndex = 0
        }
    })
    $window.FindName("btnWriteUsb").Add_Click({
        $ui = $global:WinRepairUi
        $srcDir = $global:WinRepairSync.LastPreparedIsoDir
        if (-not $srcDir -or -not (Test-Path $srcDir)) {
            Write-ToolLog "Prepare primeiro os arquivos na seção acima antes de gravar no USB." "WARN"; return
        }
        $idx = $ui.Window.FindName("cmbUsbDrive").SelectedIndex
        if ($idx -lt 0 -or $idx -ge $ui.UsbDisks.Count) {
            Write-ToolLog "Selecione um pendrive USB válido e clique em Atualizar USBs." "WARN"; return
        }
        $disk = $ui.UsbDisks[$idx]
        $gb = [math]::Round($disk.Size / 1GB, 1)
        $ans = [System.Windows.MessageBox]::Show(
            "ATENÇÃO: TODOS os dados do Disco $($disk.Number) ($($disk.FriendlyName) - $gb GB) serão PERMANENTEMENTE apagados! Continuar?",
            "Confirmar Formatação do Pendrive USB",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
            $dNum = [int]$disk.Number
            Start-AsyncAction -Label "Gravando pendrive bootável..." -Vars @{ srcDir = $srcDir; dNum = $dNum } -Action {
                Write-PreparedIsoToUsb -SourceDir $srcDir -DiskNumber $dNum
            }
        }
    })

    $uiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $uiTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $uiTimer.Add_Tick({
        $sync = $global:WinRepairSync
        $ui   = $global:WinRepairUi
        $line = $null
        $updated = $false
        while ($sync.LogQueue.TryDequeue([ref]$line)) {
            $global:txtLogControl.AppendText("$line`r`n")
            $updated = $true
        }
        if ($updated) { $global:txtLogControl.ScrollToEnd() }

        if ($sync.PendingThemeSync) {
            $mode = $sync.PendingThemeSync
            $sync.PendingThemeSync = $null
            Set-HudTheme -Mode $mode
        }

        for ($i = $sync.ActiveJobs.Count - 1; $i -ge 0; $i--) {
            $job = $sync.ActiveJobs[$i]
            if ($job.Handle.IsCompleted) {
                try { $job.PowerShell.EndInvoke($job.Handle) | Out-Null } catch {}
                $res = $null
                if ($sync.Results.ContainsKey($job.Id)) {
                    $res = $sync.Results[$job.Id]
                    $sync.Results.Remove($job.Id)
                }
                $cb = $job.OnCompleted
                $job.PowerShell.Dispose()
                $job.Runspace.Close()
                $job.Runspace.Dispose()
                $sync.ActiveJobs.RemoveAt($i)
                if ($cb) {
                    try { & $cb $res } catch { Write-ToolLog "Erro no callback UI: $_" "ERROR" }
                }
            }
        }

        $pb = $ui.Window.FindName("pbTaskProgress")
        $stTxt = $ui.Window.FindName("txtTaskStatus")
        if ($sync.ActiveJobs.Count -gt 0) {
            $pb.Visibility = [System.Windows.Visibility]::Visible
            $stTxt.Text = "$([char]0x25CF) $($sync.TaskStatus)"
            $stTxt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushWarning")
        } else {
            $sync.IsRunning = $false
            $sync.TaskStatus = "Pronto"
            $pb.Visibility = [System.Windows.Visibility]::Collapsed
            $stTxt.Text = "$([char]0x25CF) Pronto"
            $stTxt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushSuccess")
        }
    })
    $uiTimer.Start()

    $global:WinRepairUi.Initializing = $false

    Write-ToolLog "WinRepair & Tweaks Pro v3.1 carregado com sucesso!" "SUCCESS"
    Write-ToolLog "Passe o mouse em qualquer opção para ler o resumo instantâneo antes de executar." "INFO"

    $window.Add_Closed({ $uiTimer.Stop() })
    $window.ShowDialog() | Out-Null
}
