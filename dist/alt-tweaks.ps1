# ==============================================================================
# Alt Tweaks v3.1 (Standalone All-in-One)
# Utilitário Completo: Tweaks, Softwares, AppX, Rede (14 Ferramentas), ISO & USB
# Execução direta via: irm <URL> | iex
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# ==============================================================================
# Módulo: Elevação e Privilégios Administrativos
# ==============================================================================

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-AdminPrivileges {
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host " [!] PRIVILÉGIOS DE ADMINISTRADOR NECESSÁRIOS" -ForegroundColor Red
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host "Este utilitário precisa ser executado como Administrador para realizar reparos e otimizações." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "[*] Solicitando elevação de privilégios via UAC..." -ForegroundColor Cyan

        $scriptPath = $PSCommandPath
        if ($scriptPath -and (Test-Path $scriptPath)) {
            # Se executado a partir de arquivo local
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        } else {
            # Se executado diretamente em memória via irm | iex:
            # Salva um inicializador limpo em arquivo temporário para evitar falsos positivos de heurística de linha de comando
            $tempLauncher = Join-Path $env:TEMP "alt_tweaks_launcher.ps1"
            $launcherCode = @'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
irm https://raw.githubusercontent.com/joaolsr21/alt-tweaks/main/dist/alt-tweaks.ps1 | iex
'@
            [System.IO.File]::WriteAllText($tempLauncher, $launcherCode, [System.Text.Encoding]::UTF8)
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempLauncher`""
        }
        exit
    }
}


# ==============================================================================
# Módulo: Sistema de Logging e Status Assíncrono (Thread-Safe entre Runspaces e UI)
# ==============================================================================

function Write-ToolLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
    }

    Write-Host $logLine -ForegroundColor $color

    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync -and $sync.LogQueue) {
        $sync.LogQueue.Enqueue($logLine)
    }
}

function Set-TaskStatus {
    param (
        [string]$Text = "Pronto",
        [bool]$IsRunning = $false
    )

    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync) {
        $sync.TaskStatus = $Text
        $sync.IsRunning = $IsRunning
    }
}


# ==============================================================================
# Módulo Avançado: Diagnóstico Completo, Varredura, Otimizações e Reparo de Rede
# ==============================================================================

function Invoke-OemTool {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string]$Arguments = "",
        [switch]$StreamToLog
    )

    $oemCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding($oemCodePage)
    $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding($oemCodePage)

    $proc = [System.Diagnostics.Process]::Start($psi)
    $lines = New-Object System.Collections.Generic.List[string]

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        [void]$lines.Add($line)
        if ($StreamToLog -and -not [string]::IsNullOrWhiteSpace($line)) {
            Write-ToolLog $line "INFO"
        }
    }

    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if (-not [string]::IsNullOrWhiteSpace($err)) {
        foreach ($el in ($err -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($el)) {
                [void]$lines.Add($el)
                if ($StreamToLog) { Write-ToolLog $el "WARN" }
            }
        }
    }

    return ($lines -join "`r`n")
}

# --- [1] Diagnóstico Rápido Integrado ---
function Invoke-QuickIntegratedNetworkDiag {
    Write-ToolLog "=== [1] DIAGN$([char]0xD3)STICO RÁPIDO INTEGRADO ===" "INFO"

    Write-ToolLog "1. Testando placa de rede interna [Loopback 127.0.0.1]..." "INFO"
    if (Test-Connection -ComputerName "127.0.0.1" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Hardware de rede local respondendo perfeitamente." "SUCCESS"
    } else {
        Write-ToolLog "  [FALHA CRÍTICA] Placa de rede local ou pilha TCP/IP com defeito." "ERROR"
    }

    Write-ToolLog "2. Identificando Gateway Padrão [Roteador Local]..." "INFO"
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        Write-ToolLog "  Gateway identificado: $gw" "INFO"
        if (Test-Connection -ComputerName $gw -Count 2 -Quiet) {
            Write-ToolLog "  [OK] Comunicação com o Roteador Local: 100% operacional." "SUCCESS"
        } else {
            Write-ToolLog "  [FALHA] Roteador não respondeu aos pacotes de teste." "ERROR"
        }
    } else {
        Write-ToolLog "  [FALHA] Nenhum Gateway Padrão localizado. Cabo desconectado ou sem DHCP." "ERROR"
    }

    Write-ToolLog "3. Testando conexão direta com a Internet [8.8.8.8 e 1.1.1.1]..." "INFO"
    if (Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Acesso à Internet funcional - Google DNS [8.8.8.8] respondeu." "SUCCESS"
    } elseif (Test-Connection -ComputerName "1.1.1.1" -Count 2 -Quiet) {
        Write-ToolLog "  [OK] Acesso à Internet funcional - Cloudflare [1.1.1.1] respondeu." "SUCCESS"
    } else {
        Write-ToolLog "  [FALHA] Sem comunicação direta com a Internet via pacotes IP." "ERROR"
    }

    Write-ToolLog "4. Testando Resolução de Nomes [DNS - google.com]..." "INFO"
    try {
        $null = [System.Net.Dns]::GetHostAddresses("google.com")
        Write-ToolLog "  [OK] Servidores DNS resolvendo nomes perfeitamente." "SUCCESS"
    } catch {
        Write-ToolLog "  [FALHA] Servidor DNS falhou ao traduzir nomes de domínio." "ERROR"
    }
    Write-ToolLog "=== DIAGN$([char]0xD3)STICO RÁPIDO CONCLUÍDO ===" "SUCCESS"
}

# --- [2] Teste Detalhado de Conexão com a Internet ---
function Invoke-DetailedInternetTest {
    Write-ToolLog "=== [2] TESTE DETALHADO DE CONECTIVIDADE ===" "INFO"

    Write-ToolLog "1. Testando pacotes ICMP [Ping]..." "INFO"
    foreach ($ip in @("8.8.8.8", "1.1.1.1")) {
        $pings = Test-Connection -ComputerName $ip -Count 3 -ErrorAction SilentlyContinue
        if ($pings) {
            $avg = [math]::Round(($pings | Measure-Object ResponseTime -Average).Average, 1)
            $loss = [math]::Round(((3 - $pings.Count) / 3) * 100, 1)
            Write-ToolLog "  Host $ip -> Latência Média: ${avg} ms | Perda: ${loss}%" "SUCCESS"
        } else {
            Write-ToolLog "  Host $ip -> Sem resposta (100% perda)." "ERROR"
        }
    }

    Write-ToolLog "2. Testando comunicação Web Segura [HTTPS Porta 443]..." "INFO"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $wc.DownloadString("https://www.google.com")
        $sw.Stop()
        Write-ToolLog "  [OK] Conexão HTTPS ativa e respondendo em $($sw.ElapsedMilliseconds) ms." "SUCCESS"
    } catch {
        Write-ToolLog "  [FALHA] Não foi possível carregar conteúdo Web seguro: $_" "ERROR"
    }

    Write-ToolLog "3. Testando Resolução de Servidores DNS..." "INFO"
    foreach ($dom in @("google.com", "registro.br")) {
        try {
            $ips = [System.Net.Dns]::GetHostAddresses($dom) | Select-Object -First 2
            Write-ToolLog "  [OK] Domínio [$dom] resolvido ($($ips.IPAddressToString -join ', '))." "SUCCESS"
        } catch {
            Write-ToolLog "  [FALHA] Falha na resolução de [$dom]." "WARN"
        }
    }
}

# --- [3] Teste Rápido de Velocidade de Download ---
function Invoke-DownloadSpeedTest {
    Write-ToolLog "=== [3] TESTE DE VELOCIDADE DE DOWNLOAD (CLOUDFLARE CDN) ===" "INFO"
    Write-ToolLog "Baixando bloco de medição de 5 MB direto do Cloudflare... Aguarde..." "INFO"
    $tempFile = Join-Path $env:TEMP "alts_speedtest.bin"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc.DownloadFile("https://speed.cloudflare.com/__down?bytes=5000000", $tempFile)
        $sw.Stop()
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

        $sec = $sw.ElapsedMilliseconds / 1000.0
        if ($sec -le 0) { $sec = 0.001 }
        $mbps = [math]::Round((5 * 8) / $sec, 2)
        Write-ToolLog "  [OK] Taxa estimada de Download: $mbps Mbps (tempo: $([math]::Round($sec, 2))s)" "SUCCESS"
    } catch {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Write-ToolLog "  [FALHA] Não foi possível concluir o teste de velocidade: $_" "ERROR"
    }
}

# --- [4] Diagnóstico de Wi-Fi ---
function Invoke-WifiDiagnostics {
    param([bool]$GenerateHtmlReport = $false)
    Write-ToolLog "=== [4] DIAGN$([char]0xD3)STICO DE REDE SEM FIO (WI-FI) ===" "INFO"

    Write-ToolLog "--- Status da Interface Wi-Fi Atual ---" "INFO"
    Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show interfaces" -StreamToLog | Out-Null

    Write-ToolLog "--- Redes Disponíveis ao Redor (Canais e Sinal) ---" "INFO"
    Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show networks mode=bssid" -StreamToLog | Out-Null

    if ($GenerateHtmlReport) {
        Write-ToolLog "Gerando relatório histórico de eventos WLAN da Microsoft (HTML)..." "INFO"
        Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show wlanreport" -StreamToLog | Out-Null
        $reportHtml = "C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html"
        if (Test-Path $reportHtml) {
            Write-ToolLog "Relatório HTML gerado em: $reportHtml" "SUCCESS"
            Start-Process $reportHtml
        }
    }
}

# --- [5] Testar Porta TCP Específica ---
function Test-SpecificTcpPort {
    param(
        [Parameter(Mandatory=$true)][string]$TargetHost,
        [Parameter(Mandatory=$true)][int]$Port
    )

    Write-ToolLog "=== [5] TESTE DE PORTA TCP ===" "INFO"
    Write-ToolLog "Testando comunicação com [$TargetHost] na porta TCP [$Port]..." "INFO"

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(3000, $false) -and $client.Connected) {
            $client.EndConnect($async)
            Write-ToolLog "  [SUCESSO] Porta $Port em $TargetHost está ABERTA e acessível!" "SUCCESS"
        } else {
            Write-ToolLog "  [FALHA] Porta $Port em $TargetHost está FECHADA ou bloqueada por Firewall!" "WARN"
        }
    } catch {
        Write-ToolLog "  [FALHA] Erro ao conectar na porta $Port em $TargetHost`: $_" "ERROR"
    } finally {
        $client.Close()
    }
}

# --- [6] Análise de Perda de Pacotes (Pathping) ---
function Invoke-PathpingAnalysis {
    param([string]$TargetHost = "8.8.8.8")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "8.8.8.8" }
    Write-ToolLog "=== [6] ANÁLISE DE PERDA DE PACOTES (PATHPING) ===" "INFO"
    Write-ToolLog "Iniciando pathping em $TargetHost (pode levar 30-90s)... Aguarde..." "INFO"
    Invoke-OemTool -FilePath "pathping.exe" -Arguments "-n -q 10 $TargetHost" -StreamToLog | Out-Null
    Write-ToolLog "Análise Pathping concluída." "SUCCESS"
}

# --- [7] Rastrear Rota (Tracert) ---
function Invoke-TracertAnalysis {
    param([string]$TargetHost = "1.1.1.1")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "1.1.1.1" }
    Write-ToolLog "=== [7] RASTREAMENTO DE ROTA (TRACERT) ===" "INFO"
    Write-ToolLog "Rastreando rota até $TargetHost (limite 15 saltos)..." "INFO"
    Invoke-OemTool -FilePath "tracert.exe" -Arguments "-d -h 15 $TargetHost" -StreamToLog | Out-Null
    Write-ToolLog "Rastreamento Tracert concluído." "SUCCESS"
}

# --- [8] Teste Contínuo de Estabilidade (Ping -t) ---
function Start-ContinuousPingWindow {
    param([string]$TargetHost = "8.8.8.8")
    if ([string]::IsNullOrWhiteSpace($TargetHost)) { $TargetHost = "8.8.8.8" }
    Write-ToolLog "Abrindo janela dedicada de Ping contínuo (-t) para $TargetHost..." "INFO"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k title Ping Continuo: $TargetHost && color 0F && echo Pressione CTRL+C para interromper o teste. && ping $TargetHost -t"
}

# --- [9] Conexões Ativas e Portas Escutando (Netstat) ---
function Get-ActiveConnectionsNetstat {
    param(
        [ValidateSet("Established", "Listening", "All")]
        [string]$Mode = "Established"
    )

    Write-ToolLog "=== [9] CONEXÕES ATIVAS E PORTAS ($Mode) ===" "INFO"
    $args = switch ($Mode) {
        "Established" { "-f" }
        "Listening"   { "-ano" }
        "All"         { "-ano" }
    }

    $output = Invoke-OemTool -FilePath "netstat.exe" -Arguments $args
    $lines = $output -split "`r?`n"
    foreach ($l in $lines) {
        if ($Mode -eq "Established" -and $l -match "ESTABLISHED") {
            Write-ToolLog $l "INFO"
        } elseif ($Mode -eq "Listening" -and $l -match "LISTENING") {
            Write-ToolLog $l "INFO"
        } elseif ($Mode -eq "All" -and -not [string]::IsNullOrWhiteSpace($l)) {
            Write-ToolLog $l "INFO"
        }
    }
    Write-ToolLog "Consulta Netstat concluída." "SUCCESS"
}

# --- [10] Varredura Completa da Rede Local (IPs Ocupados e Livres) ---
function Invoke-LocalSubnetScan {
    param([bool]$SaveAndOpenReport = $true)

    Write-ToolLog "=== [10] VARREDURA COMPLETA DA REDE LOCAL (SUB-REDE IPv4) ===" "INFO"
    Write-ToolLog "Identificando sub-rede e disparando varredura paralela..." "INFO"

    try {
        $ipObj = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1
        if (-not $ipObj) {
            Write-ToolLog "Nenhum endereço IPv4 local válido encontrado." "ERROR"
            return
        }

        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
        $localIP = $ipObj.IPAddress
        $ipBytes = [System.Net.IPAddress]::Parse($localIP).GetAddressBytes()
        if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($ipBytes) }
        $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
        $prefixLen = $ipObj.PrefixLength

        # Limitar varredura paralela a /22 (1022 hosts) para evitar travamento em máscaras muito grandes
        if ($prefixLen -lt 22) {
            Write-ToolLog "Máscara /$prefixLen detectada (muito ampla). Limitando varredura à faixa /24 local para segurança." "WARN"
            $prefixLen = 24
        }

        $maskInt = [uint32]([Convert]::ToUInt64(('1' * $prefixLen + '0' * (32 - $prefixLen)), 2))
        $netInt = $ipInt -band $maskInt
        $bcastInt = $netInt -bor (-bnot $maskInt)
        $firstHostInt = $netInt + 1
        $lastHostInt = $bcastInt - 1

        function Convert-UInt32ToIP([uint32]$val) {
            $b = [BitConverter]::GetBytes($val)
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($b) }
            return [System.Net.IPAddress]::new($b).ToString()
        }

        $firstIP = Convert-UInt32ToIP $firstHostInt
        $lastIP = Convert-UInt32ToIP $lastHostInt
        $totalHosts = $lastHostInt - $firstHostInt + 1

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $allIPs = for ($i = $firstHostInt; $i -le $lastHostInt; $i++) { Convert-UInt32ToIP $i }
        $tasks = foreach ($target in $allIPs) {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $ping.SendPingAsync($target, 350)
        }
        [Threading.Tasks.Task]::WaitAll($tasks)
        $sw.Stop()

        $arpOutput = Invoke-OemTool -FilePath "arp.exe" -Arguments "-a"
        $arpLines = $arpOutput -split "`r?`n"
        $usedSet = New-Object 'System.Collections.Generic.HashSet[uint32]'
        $devices = @()

        foreach ($line in $arpLines) {
            $p = ($line.Trim() -split '\s+')
            if ($p.Count -ge 3 -and $p[0] -match '^\d+\.\d+\.\d+\.\d+$') {
                try {
                    $b = [System.Net.IPAddress]::Parse($p[0]).GetAddressBytes()
                    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($b) }
                    $val = [BitConverter]::ToUInt32($b, 0)
                    if ($val -ge $firstHostInt -and $val -le $lastHostInt) {
                        $mac = $p[1]
                        if ($mac -notlike 'ff*' -and $mac -notlike '01-00-5e*' -and $mac -notlike '224*' -and $mac -notlike '239*') {
                            if ($usedSet.Add($val)) {
                                $tag = 'Ativo'
                                if ($p[0] -eq $gw) { $tag = 'Gateway/Roteador' }
                                if ($p[0] -eq $localIP) { $tag = 'Este Computador' }
                                $cleanTipo = if ($p[2] -match 'din') { 'Dinamico' } elseif ($p[2] -match 'est') { 'Estatico' } else { $p[2] }
                                $devices += [PSCustomObject]@{ Val = $val; Row = ("{0,-18} {1,-20} {2,-12} {3}" -f $p[0], $mac.ToUpper(), $cleanTipo, $tag) }
                            }
                        }
                    }
                } catch {}
            }
        }

        try {
            $locBytes = [System.Net.IPAddress]::Parse($localIP).GetAddressBytes()
            if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($locBytes) }
            $null = $usedSet.Add([BitConverter]::ToUInt32($locBytes, 0))
        } catch {}

        $totalUsed = $usedSet.Count
        $totalFree = $totalHosts - $totalUsed
        $pctUsed = [math]::Round(($totalUsed / $totalHosts) * 100, 1)
        $pctFree = [math]::Round(($totalFree / $totalHosts) * 100, 1)

        $freeRanges = @()
        $freeIndividual = @()
        $rangeStart = $null
        $rangeCount = 0

        for ($i = $firstHostInt; $i -le $lastHostInt; $i++) {
            if (-not $usedSet.Contains($i)) {
                $freeIndividual += Convert-UInt32ToIP $i
                if ($null -eq $rangeStart) { $rangeStart = $i; $rangeCount = 1 } else { $rangeCount++ }
            } else {
                if ($null -ne $rangeStart) {
                    $sIP = Convert-UInt32ToIP $rangeStart
                    $eIP = Convert-UInt32ToIP ($rangeStart + $rangeCount - 1)
                    $desc = if ($rangeCount -eq 1) { "$sIP" } else { "$sIP até $eIP" }
                    $freeRanges += ("{0,-38} {1,-15}" -f $desc, "$rangeCount IP(s) livres")
                    $rangeStart = $null; $rangeCount = 0
                }
            }
        }
        if ($null -ne $rangeStart) {
            $sIP = Convert-UInt32ToIP $rangeStart
            $eIP = Convert-UInt32ToIP ($rangeStart + $rangeCount - 1)
            $desc = if ($rangeCount -eq 1) { "$sIP" } else { "$sIP até $eIP" }
            $freeRanges += ("{0,-38} {1,-15}" -f $desc, "$rangeCount IP(s) livres")
        }

        $hdr = "==============================================================================="
        $sumLines = @(
            $hdr,
            "               RESUMO DE OCUPAÇÃO DA SUB-REDE (IPv4)",
            $hdr,
            "  Máscara Detectada:        /$prefixLen",
            "  Faixa Total da Rede:      $firstIP até $lastIP",
            "  Total de IPs Usáveis:     $totalHosts endereços",
            "  IPs Ocupados (Em Uso):    $totalUsed ($pctUsed%)",
            "  IPs Livres (Disponíveis): $totalFree ($pctFree%)",
            "  Tempo de Varredura:       $([math]::Round($sw.ElapsedMilliseconds/1000, 2)) segundos",
            $hdr
        )

        foreach ($sl in $sumLines) { Write-ToolLog $sl "INFO" }

        $colUsed = "{0,-18} {1,-20} {2,-12} {3}" -f "ENDEREÇO IP", "ENDEREÇO MAC", "TIPO", "STATUS"
        $sorted = $devices | Sort-Object Val
        $usedOut = @($hdr, "DISPOSITIVOS OCUPADOS / EM USO ($totalUsed encontrados)", $hdr, $colUsed, $hdr) + ($sorted | ForEach-Object { $_.Row }) + @($hdr)

        Write-ToolLog "--- Dispositivos Ocupados ---" "INFO"
        foreach ($u in $sorted) { Write-ToolLog ("  " + $u.Row) "SUCCESS" }

        Write-ToolLog "--- Faixas de IPs Livres ---" "INFO"
        foreach ($fr in $freeRanges) { Write-ToolLog ("  " + $fr) "INFO" }

        if ($SaveAndOpenReport) {
            $colFree = "{0,-38} {1,-15}" -f "FAIXA / BLOCO DISPONÍVEL", "QUANTIDADE"
            $rangesOut = @($hdr, "FAIXAS E BLOCOS DE IPs LIVRES ($($freeRanges.Count) blocos - $totalFree IPs livres)", $hdr, $colFree, $hdr) + $freeRanges + @($hdr)
            $allFreeOut = @($hdr, "LISTA COMPLETA DE IPs LIVRES INDIVIDUAIS ($totalFree IPs disponíveis)", $hdr) + $freeIndividual + @($hdr)
            $fullReport = $sumLines + @("", "") + $rangesOut + @("", "") + $usedOut + @("", "") + $allFreeOut

            $desktopPath = [Environment]::GetFolderPath("Desktop")
            $reportFile = Join-Path $desktopPath "Relatorio_IPs_Rede_Local.txt"
            [System.IO.File]::WriteAllLines($reportFile, $fullReport, [System.Text.Encoding]::UTF8)
            Write-ToolLog "Relatório completo de IPs salvo na Área de Trabalho: $reportFile" "SUCCESS"
            Start-Process notepad.exe -ArgumentList "`"$reportFile`""
        }
    } catch {
        Write-ToolLog "Erro durante varredura da rede local: $_" "ERROR"
    }
}

# --- [11] Exibir Configurações de IP e DNS (ipconfig /all) ---
function Get-IpConfigAllDetails {
    Write-ToolLog "=== [11] CONFIGURAÇÕES DE IP E DNS (ipconfig /all) ===" "INFO"
    Invoke-OemTool -FilePath "ipconfig.exe" -Arguments "/all" -StreamToLog | Out-Null
    Write-ToolLog "=== FIM DO IPCONFIG ===" "SUCCESS"
}

# --- [12] Reparar Conexão (FlushDNS, Renew IP e NetBIOS) ---
function Invoke-SimpleNetworkRepair {
    Write-ToolLog "=== [12] REPARO SIMPLES DE CONEXÃO ===" "INFO"
    try {
        Write-ToolLog "1. Limpando cache do Resolvedor de DNS..." "INFO"
        Clear-DnsClientCache
        ipconfig /flushdns | Out-Null

        Write-ToolLog "2. Liberando e renovando concessão DHCP..." "INFO"
        ipconfig /release | Out-Null
        Start-Sleep -Milliseconds 800
        ipconfig /renew | Out-Null

        Write-ToolLog "3. Limpando cache NetBIOS (nbtstat -R)..." "INFO"
        nbtstat -R | Out-Null

        Write-ToolLog "Cache limpo e endereço IP renovado com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao reparar conexão: $_" "ERROR"
    }
}

# --- [13] Reset Completo da Pilha de Rede (Winsock, TCP/IP, Proxy, ARP e Firewall) ---
function Invoke-ResetNetworkStack {
    Write-ToolLog "=== [13] RESET COMPLETO DA PILHA DE REDE ===" "INFO"
    try {
        Write-ToolLog "1. Redefinindo Catálogo Winsock..." "INFO"
        netsh winsock reset | Out-Null
        Write-ToolLog "2. Redefinindo Pilha TCP/IP (IPv4 e IPv6)..." "INFO"
        netsh int ip reset | Out-Null
        netsh int ipv6 reset | Out-Null
        Write-ToolLog "3. Redefinindo Configurações de Proxy WinHTTP..." "INFO"
        netsh winhttp reset proxy | Out-Null
        Write-ToolLog "4. Limpando tabela ARP..." "INFO"
        netsh interface ip delete arpcache | Out-Null
        Write-ToolLog "5. Redefinindo Firewall do Windows..." "INFO"
        netsh advfirewall reset | Out-Null

        Write-ToolLog "Pilha de rede reinicializada de fábrica. Recomenda-se reiniciar o computador." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir pilha de rede: $_" "ERROR"
    }
}

# --- [14] Gerar Relatório Forense Completo de Rede (.TXT) ---
function Export-ForensicNetworkReport {
    Write-ToolLog "=== [14] GERANDO RELAT$([char]0xD3)RIO FORENSE COMPLETO DE REDE ===" "INFO"
    Write-ToolLog "Coletando dados de adaptadores, rotas, Wi-Fi, ARP, conexões, ping, DNS e tracert..." "INFO"

    try {
        $dt = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $reportFile = Join-Path $desktopPath "Relatorio_Rede_${env:COMPUTERNAME}_${dt}.txt"

        $sb = New-Object System.Text.StringBuilder
        $sep = "==============================================================================="

        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine("                    RELAT$([char]0xD3)RIO COMPLETO DE DIAGN$([char]0xD3)STICO DE REDE")
        [void]$sb.AppendLine("Data e Hora: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))")
        [void]$sb.AppendLine("Estação: $($env:COMPUTERNAME) | Usuário: $($env:USERNAME)")
        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine("")

        Write-ToolLog "[1/8] Coletando adaptadores e configurações de IP..." "INFO"
        [void]$sb.AppendLine("--- 1. CONFIGURAÇÕES DE IP / ADAPTADORES ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ipconfig.exe" -Arguments "/all"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[2/8] Coletando tabela de roteamento IPv4..." "INFO"
        [void]$sb.AppendLine("--- 2. TABELA DE ROTEAMENTO IPV4 ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "route.exe" -Arguments "print -4"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[3/8] Coletando status das interfaces Wi-Fi..." "INFO"
        [void]$sb.AppendLine("--- 3. STATUS DAS INTERFACES WI-FI ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "netsh.exe" -Arguments "wlan show interfaces"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[4/8] Coletando tabela ARP local..." "INFO"
        [void]$sb.AppendLine("--- 4. TABELA ARP LOCAL ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "arp.exe" -Arguments "-a"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[5/8] Coletando conexões ativas..." "INFO"
        [void]$sb.AppendLine("--- 5. CONEXÕES DE REDE ATIVAS (ESTABLISHED) ---")
        $netOut = (Invoke-OemTool -FilePath "netstat.exe" -Arguments "-ano") -split "`r?`n" | Where-Object { $_ -match "ESTABLISHED" }
        [void]$sb.AppendLine(($netOut -join "`r`n"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[6/8] Testando conectividade (Google e Cloudflare)..." "INFO"
        [void]$sb.AppendLine("--- 6. TESTE DE CONECTIVIDADE GOOGLE (8.8.8.8) ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ping.exe" -Arguments "-n 4 8.8.8.8"))
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("--- 7. TESTE DE CONECTIVIDADE CLOUDFLARE (1.1.1.1) ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "ping.exe" -Arguments "-n 4 1.1.1.1"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[7/8] Testando resolução DNS..." "INFO"
        [void]$sb.AppendLine("--- 8. TESTE DE RESOLUÇÃO DE DNS ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "nslookup.exe" -Arguments "google.com"))
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "nslookup.exe" -Arguments "microsoft.com"))
        [void]$sb.AppendLine("")

        Write-ToolLog "[8/8] Rastreando rota até a internet (8.8.8.8)..." "INFO"
        [void]$sb.AppendLine("--- 9. ROTA COMPLETA ATÉ A INTERNET ---")
        [void]$sb.AppendLine((Invoke-OemTool -FilePath "tracert.exe" -Arguments "-d -h 12 8.8.8.8"))

        [System.IO.File]::WriteAllText($reportFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
        Write-ToolLog "Relatório forense salvo na Área de Trabalho: $reportFile" "SUCCESS"
        Start-Process notepad.exe -ArgumentList "`"$reportFile`""
    } catch {
        Write-ToolLog "Erro ao gerar relatório forense: $_" "ERROR"
    }
}

# --- Auxiliares extras de Rede & Gaming ---
function Invoke-FlushDns {
    Write-ToolLog "Limpando o cache do resolvedor DNS..." "INFO"
    try {
        Clear-DnsClientCache
        Write-ToolLog "Cache DNS limpo com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao limpar cache DNS: $_" "ERROR"
    }
}

function Invoke-RenewDhcp {
    Write-ToolLog "Liberando e renovando endereço IP via DHCP..." "INFO"
    try {
        ipconfig /release | Out-Null
        Start-Sleep -Milliseconds 800
        ipconfig /renew | Out-Null
        Write-ToolLog "Concessão de IP renovada com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao renovar concessão DHCP: $_" "ERROR"
    }
}

function Invoke-DnsLatencyBenchmark {
    param(
        $DnsConfigs,
        [int]$TimeoutMs = 1500
    )

    if (-not $DnsConfigs) {
        $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
        if ($sync -and $sync.Configs) { $DnsConfigs = $sync.Configs.Dns }
    }

    if (-not $DnsConfigs) {
        Write-ToolLog "Tabela de servidores DNS não carregada." "ERROR"
        return @()
    }

    Write-ToolLog "=== BENCHMARK DE LATÊNCIA DNS (TCP PORTA 53) ===" "INFO"
    $results = New-Object System.Collections.Generic.List[object]

    foreach ($prop in $DnsConfigs.PSObject.Properties) {
        $name = $prop.Name
        $ip = $prop.Value.Primary
        if (-not $ip) { continue }

        $ms = 9999
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $ar = $client.BeginConnect($ip, 53, $null, $null)
            $ok = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            $sw.Stop()
            if ($ok) {
                $client.EndConnect($ar)
                $ms = [int]$sw.ElapsedMilliseconds
            }
        } catch {
            $ms = 9999
        } finally {
            if ($client) { $client.Dispose() }
        }

        $eligible = ($prop.Value.BenchmarkEligible -eq $true)
        $results.Add([pscustomobject]@{
            Provider = $name
            Primary  = $ip
            LatencyMs = $ms
            Eligible = $eligible
        })
    }

    $sorted = $results | Sort-Object LatencyMs
    foreach ($r in $sorted) {
        $tag = if ($r.LatencyMs -ge 9999) { "Timeout" } else { "$($r.LatencyMs) ms" }
        Write-ToolLog ("  {0,-34} ({1,-15}) -> {2}" -f $r.Provider, $r.Primary, $tag) "INFO"
    }

    $best = $sorted | Where-Object { $_.LatencyMs -lt 9999 } | Select-Object -First 1
    if ($best) {
        Write-ToolLog "Mais rápido detectado: $($best.Provider) ($($best.Primary)) com $($best.LatencyMs) ms." "SUCCESS"
    }
    return $sorted
}

function Set-DnsFromConfig {
    param(
        [Parameter(Mandatory=$true)][string]$ProviderKey,
        $DnsConfigs
    )

    if (-not $DnsConfigs) {
        $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
        if ($sync -and $sync.Configs) { $DnsConfigs = $sync.Configs.Dns }
    }

    if ($ProviderKey -eq "Fastest") {
        $bench = Invoke-DnsLatencyBenchmark -DnsConfigs $DnsConfigs
        $eligibleBest = $bench | Where-Object { $_.Eligible -and $_.LatencyMs -lt 9999 } | Select-Object -First 1
        if (-not $eligibleBest) {
            $eligibleBest = $bench | Where-Object { $_.LatencyMs -lt 9999 } | Select-Object -First 1
        }
        if (-not $eligibleBest) {
            Write-ToolLog "Nenhum servidor DNS respondeu ao benchmark." "ERROR"
            return
        }
        $ProviderKey = $eligibleBest.Provider
        Write-ToolLog "Aplicando servidor DNS mais rápido: $ProviderKey ($($eligibleBest.LatencyMs) ms)..." "INFO"
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    }
    if (-not $adapters) {
        Write-ToolLog "Nenhum adaptador de rede ativo encontrado." "WARN"
        return
    }

    if ($ProviderKey -eq "DHCP") {
        foreach ($adapter in $adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
                Write-ToolLog "[$($adapter.Name)] DNS restaurado para automático (DHCP)." "SUCCESS"
            } catch {
                Write-ToolLog "Falha ao restaurar DHCP em $($adapter.Name): $_" "ERROR"
            }
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        return
    }

    $cfg = $null
    if ($DnsConfigs) {
        $cfg = $DnsConfigs.$ProviderKey
    }
    if (-not $cfg) {
        Write-ToolLog "Provedor DNS '$ProviderKey' não encontrado." "ERROR"
        return
    }

    $v4 = @($cfg.Primary, $cfg.Secondary | Where-Object { $_ })
    $v6 = @($cfg.Primary6, $cfg.Secondary6 | Where-Object { $_ })
    $dohCmd = Get-Command "Add-DnsClientDohServerAddress" -ErrorAction SilentlyContinue

    foreach ($adapter in $adapters) {
        try {
            if ($v4.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $v4 -ErrorAction Stop
            }
            if ($v6.Count -gt 0) {
                try { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $v6 -ErrorAction SilentlyContinue } catch {}
            }
            if ($dohCmd -and $cfg.DohTemplate) {
                foreach ($srv in $v4) {
                    try {
                        Add-DnsClientDohServerAddress -ServerAddress $srv -DohTemplate $cfg.DohTemplate -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction SilentlyContinue | Out-Null
                    } catch {}
                }
            }
            Write-ToolLog "[$($adapter.Name)] DNS $ProviderKey aplicado (IPv4: $($v4 -join ', '))." "SUCCESS"
        } catch {
            Write-ToolLog "Falha ao definir DNS em $($adapter.Name): $_" "ERROR"
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Set-QuickDnsProvider {
    param(
        [string]$Provider = "Cloudflare"
    )

    $mapped = if ($Provider -eq "AdGuard") { "AdGuard_Ads_Trackers" } else { $Provider }
    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync -and $sync.Configs -and $sync.Configs.Dns -and ($mapped -eq "DHCP" -or $mapped -eq "Fastest" -or $sync.Configs.Dns.$mapped)) {
        Set-DnsFromConfig -ProviderKey $mapped -DnsConfigs $sync.Configs.Dns
        return
    }

    $dnsServers = switch ($Provider) {
        "Cloudflare" { @("1.1.1.1", "1.0.0.1") }
        "Google"     { @("8.8.8.8", "8.8.4.4") }
        "Quad9"      { @("9.9.9.9", "149.112.112.112") }
        "AdGuard"    { @("94.140.14.14", "94.140.15.15") }
        "DHCP"       { $null }
    }

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    if (-not $adapters) {
        Write-ToolLog "Nenhum adaptador físico ativo encontrado." "WARN"
        return
    }

    foreach ($adapter in $adapters) {
        try {
            if ($Provider -eq "DHCP") {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Write-ToolLog "[$($adapter.Name)] DNS restaurado para automático (DHCP)." "SUCCESS"
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers
                Write-ToolLog "[$($adapter.Name)] DNS $Provider aplicado: $($dnsServers -join ', ')." "SUCCESS"
            }
        } catch {
            Write-ToolLog "Falha ao definir DNS em $($adapter.Name): $_" "ERROR"
        }
    }
}

function Optimize-TcpLatencyAndThroughput {
    Write-ToolLog "Aplicando otimizações avançadas na pilha TCP/IP (Baixa Latência & Alto Rendimento)..." "INFO"
    try {
        netsh int tcp set global autotuninglevel=normal | Out-Null
        netsh int tcp set global rss=enabled | Out-Null
        netsh int tcp set global ecncapability=enabled | Out-Null
        try { netsh int tcp set supplemental template=custom congestionprovider=ctcp | Out-Null } catch {}

        $gamingNetKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $gamingNetKey) {
            Set-ItemProperty -Path $gamingNetKey -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force
            Set-ItemProperty -Path $gamingNetKey -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Otimizações de latência e taxa de transferência TCP aplicadas com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao otimizar TCP/IP: $_" "ERROR"
    }
}

function Restart-NetworkAdapters {
    Write-ToolLog "Reiniciando adaptadores de rede físicos..." "INFO"
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false }
    foreach ($adapter in $adapters) {
        try {
            Restart-NetAdapter -Name $adapter.Name -Confirm:$false
            Write-ToolLog "Adaptador $($adapter.Name) reiniciado." "SUCCESS"
        } catch {
            Write-ToolLog "Falha ao reiniciar $($adapter.Name): $_" "ERROR"
        }
    }
}


# ==============================================================================
# Módulo: Motor Declarativo de Tweaks, Preferências, Energia e Relatórios
# ==============================================================================

function Set-RegistryEntry {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Type = "DWord",
        $Value,
        [switch]$DryRun
    )

    try {
        if (-not (Get-PSDrive -Name "HKU" -ErrorAction SilentlyContinue)) {
            New-PSDrive -PSProvider Registry -Name "HKU" -Root "HKEY_USERS" -ErrorAction SilentlyContinue | Out-Null
        }

        if ($DryRun) {
            $curText = "(inexistente)"
            if (Test-Path $Path) {
                $props = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
                if ($null -ne $props -and ($props.PSObject.Properties.Name -contains $Name)) {
                    $curText = [string]$props.$Name
                }
            }
            if ($Value -eq "<RemoveEntry>") {
                Write-ToolLog "[DRY-RUN] Registro: $Path\$Name | Atual: $curText -> Remover propriedade" "INFO"
            } else {
                Write-ToolLog "[DRY-RUN] Registro: $Path\$Name | Atual: $curText -> Definir = $Value ($Type)" "INFO"
            }
            return
        }

        if ($Value -eq "<RemoveEntry>") {
            $exists = $true
            try {
                Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop | Out-Null
            } catch {
                $exists = $false
            }
            if (-not $exists) {
                Write-ToolLog "Registro $Path\$Name já está ausente." "INFO"
                return
            }
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
            Write-ToolLog "Removido registro: $Path\$Name" "INFO"
            return
        }

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        $typedVal = switch ($Type) {
            "DWord" { [int]$Value }
            "QWord" { [long]$Value }
            default { [string]$Value }
        }
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $typedVal -Force -ErrorAction Stop | Out-Null
        Write-ToolLog "Registro definido: $Path\$Name = $typedVal ($Type)" "INFO"
    } catch {
        Write-ToolLog "Erro no registro ($Path\$Name): $($_.Exception.Message)" "WARN"
    }
}

function Set-ServiceStartupSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$StartupType,
        [switch]$DryRun
    )

    if ($DryRun) {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        $currentDisplay = if ($svc -and ($svc.PSObject.Properties.Name -contains "StartType")) {
            [string]$svc.StartType
        } elseif ($svc) {
            "Desconhecido"
        } else {
            "Não encontrado"
        }
        Write-ToolLog "[DRY-RUN] Serviço [$Name] | Atual: $currentDisplay -> Novo: $StartupType" "INFO"
        return
    }

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        $current = if ($svc.PSObject.Properties.Name -contains "StartType") { [string]$svc.StartType } else { "" }
        if ($current -eq $StartupType) {
            return
        }

        if (($PSVersionTable.PSVersion.Major -lt 7) -and ($StartupType -eq "AutomaticDelayedStart")) {
            sc.exe config $Name start= delayed-auto | Out-Null
        } else {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
        Write-ToolLog "Serviço [$Name] ajustado para: $StartupType" "INFO"
    } catch {
        if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
            Write-ToolLog "Serviço [$Name] não encontrado neste sistema (ignorado)." "INFO"
        } else {
            Write-ToolLog "Não foi possível alterar o serviço [$Name]: $($_.Exception.Message)" "WARN"
        }
    }
}

function Invoke-ExplorerRefresh {
    param([string]$Action = "refresh")

    try {
        if ($Action -eq "restart") {
            $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
            Get-Process -Name "explorer" -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -eq $sessionId } |
                ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 300
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })) {
                Start-Process "explorer.exe"
            }
            Write-ToolLog "Windows Explorer reiniciado para aplicar alterações visuais." "INFO"
        } else {
            if (-not ([System.Management.Automation.PSTypeName]"WinRepairNativeWin32").Type) {
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinRepairNativeWin32 {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@
            }
            $result = [IntPtr]::Zero
            [void][WinRepairNativeWin32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, "ImmersiveColorSet", 0x2, 200, [ref]$result)
        }
    } catch {
        Write-ToolLog "Aviso ao atualizar Explorer: $($_.Exception.Message)" "WARN"
    }
}

function Invoke-ThemeRefresh {
    param([string]$Theme = "Auto")
    $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
    if ($sync) {
        $sync.PendingThemeSync = $Theme
    }
}

function Set-ClassicContextMenu {
    param([switch]$Undo)

    $clsidPath = "HKCU:\Software\Classes\CLSID"
    $legacyPath = "$clsidPath\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $inprocLegacy = "$legacyPath\InprocServer32"

    try {
        if ($Undo) {
            if (Test-Path -LiteralPath $legacyPath) {
                Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction Stop
            }
            Write-ToolLog "Menu de contexto moderno do Windows 11 restaurado." "SUCCESS"
        } else {
            New-Item -Path $inprocLegacy -Force -ErrorAction Stop | Out-Null
            Set-Item -LiteralPath $inprocLegacy -Value "" -Force -ErrorAction Stop
            Write-ToolLog "Menu de contexto clássico ativado." "SUCCESS"
        }
        Invoke-ExplorerRefresh -Action "restart"
    } catch {
        Write-ToolLog "Erro ao alternar menu de contexto clássico: $($_.Exception.Message)" "ERROR"
    }
}

function Get-ToggleCurrentState {
    param($TweakObj)

    if (-not $TweakObj -or -not $TweakObj.registry) { return $false }

    if (-not (Get-PSDrive -Name "HKU" -ErrorAction SilentlyContinue)) {
        New-PSDrive -PSProvider Registry -Name "HKU" -Root "HKEY_USERS" -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($reg in $TweakObj.registry) {
        $currentVal = $null
        if (Test-Path $reg.Path) {
            $props = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $props) {
                $currentVal = $props.($reg.Name)
            }
        }

        if ($null -eq $currentVal) {
            if ($reg.DefaultState -eq "true") {
                $currentVal = $reg.Value
            } elseif ($reg.DefaultState -eq "false") {
                $currentVal = $reg.OriginalValue
            }
        }

        if ($null -eq $currentVal) {
            if ($reg.Value -ne "<RemoveEntry>") { return $false }
        } elseif ([string]$currentVal -ne [string]$reg.Value) {
            return $false
        }
    }

    return $true
}

function ConvertFrom-ComboValuesMap {
    param($ValuesData)

    $map = [ordered]@{}
    if ($null -eq $ValuesData) { return $map }

    if ($ValuesData -is [string] -and $ValuesData -match '@\{(.*)\}') {
        $pairs = $Matches[1] -split ';'
        foreach ($pair in $pairs) {
            if ($pair -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
                $map[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    } elseif ($ValuesData -is [psobject]) {
        foreach ($p in $ValuesData.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    return $map
}

function Get-RegistryComboState {
    param(
        $Registry,
        [string[]]$ComboItems
    )

    if (-not $Registry) { return $null }
    $items = if ($ComboItems) { $ComboItems } else { @() }
    if ($items.Count -eq 0) {
        $firstMap = ConvertFrom-ComboValuesMap $Registry[0].Values
        $items = @($firstMap.Keys)
    }

    foreach ($stateName in $items) {
        $allMatch = $true
        foreach ($setting in @($Registry)) {
            $valMap = ConvertFrom-ComboValuesMap $setting.Values
            $targetVal = $valMap[$stateName]
            $expected = if ($targetVal -eq "<RemoveEntry>" -or $null -eq $targetVal) { [string]$setting.DefaultValue } else { [string]$targetVal }

            $actual = [string]$setting.DefaultValue
            if (Test-Path $setting.Path) {
                $p = Get-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
                if ($null -ne $p -and $null -ne $p.($setting.Name)) {
                    $actual = [string]$p.($setting.Name)
                }
            }
            if ($actual -ne $expected) {
                $allMatch = $false
                break
            }
        }
        if ($allMatch) { return $stateName }
    }

    return ($items | Select-Object -First 1)
}

function Set-RegistryComboState {
    param(
        $Registry,
        [Parameter(Mandatory=$true)][string]$State,
        [switch]$DryRun
    )

    if (-not $Registry) { return }
    foreach ($setting in @($Registry)) {
        $valMap = ConvertFrom-ComboValuesMap $setting.Values
        if ($valMap.Contains($State)) {
            Set-RegistryEntry -Path $setting.Path -Name $setting.Name -Type $setting.Type -Value $valMap[$State] -DryRun:$DryRun
        }
    }
    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    Write-ToolLog "${prefix}Estado do ajuste aplicado: $State" "SUCCESS"
}

function Invoke-DeclarativeTweak {
    param(
        [Parameter(Mandatory=$true)][string]$TweakKey,
        [Parameter(Mandatory=$true)]$TweakObj,
        [switch]$Undo,
        [switch]$DryRun
    )

    $label = if ($TweakObj.Content) { $TweakObj.Content } else { $TweakKey }
    $actionText = if ($Undo) { "Desfazendo" } else { "Aplicando" }
    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    Write-ToolLog "${prefix}$actionText [$label]..." "INFO"

    # 1. Serviços
    if ($TweakObj.service) {
        foreach ($svcItem in @($TweakObj.service)) {
            $targetType = if ($Undo) { $svcItem.OriginalType } else { $svcItem.StartupType }
            if ($targetType) {
                Set-ServiceStartupSafe -Name $svcItem.Name -StartupType $targetType -DryRun:$DryRun
            }
        }
    }

    # 2. Registros
    if ($TweakObj.registry) {
        foreach ($regItem in @($TweakObj.registry)) {
            $targetVal = if ($Undo) { $regItem.OriginalValue } else { $regItem.Value }
            if ($null -ne $targetVal) {
                Set-RegistryEntry -Path $regItem.Path -Name $regItem.Name -Type $regItem.Type -Value $targetVal -DryRun:$DryRun
            }
        }
    }

    # 3. Scripts customizados
    $scriptKind = if ($Undo) { "UndoScript" } else { "InvokeScript" }
    $scripts = if ($Undo) { $TweakObj.UndoScript } else { $TweakObj.InvokeScript }
    if ($scripts) {
        foreach ($scriptText in @($scripts)) {
            if ([string]::IsNullOrWhiteSpace($scriptText)) { continue }
            if ($DryRun) {
                $firstLine = ($scriptText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") } | Select-Object -First 1)
                if (-not $firstLine) { $firstLine = $scriptText.Trim() }
                if ($firstLine.Length -gt 120) { $firstLine = $firstLine.Substring(0, 117) + "..." }
                Write-ToolLog "[DRY-RUN] Executaria script customizado ($scriptKind): $firstLine" "INFO"
                continue
            }
            try {
                $sb = [scriptblock]::Create($scriptText)
                $out = & $sb *>&1
                foreach ($line in @($out)) {
                    $txt = [string]$line
                    if (-not [string]::IsNullOrWhiteSpace($txt)) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            Write-ToolLog "  -> $txt" "WARN"
                        } elseif ($line -is [System.Management.Automation.WarningRecord]) {
                            Write-ToolLog "  -> $txt" "WARN"
                        } else {
                            Write-ToolLog "  -> $txt" "INFO"
                        }
                    }
                }
            } catch {
                Write-ToolLog "Aviso ao executar script de [$label]: $($_.Exception.Message)" "WARN"
            }
        }
    }

    Write-ToolLog "${prefix}Concluído: $label" "SUCCESS"
}

function Get-TweakChangesPreview {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedTweaks,
        [switch]$Undo
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $SelectedTweaks) {
        if ($null -eq $entry) { continue }
        $tKey = [string]$entry.Key
        $tObj = $entry.Obj
        if ($null -eq $tObj) { continue }

        $label = if ($tObj.Content) { [string]$tObj.Content } else { $tKey }

        if ($tObj.service) {
            foreach ($svcItem in @($tObj.service)) {
                $targetType = if ($Undo) { $svcItem.OriginalType } else { $svcItem.StartupType }
                if (-not $targetType) { continue }
                [void]$items.Add([pscustomobject]@{
                    TweakKey = $tKey
                    Label    = $label
                    Kind     = "Serviço"
                    Target   = [string]$svcItem.Name
                    Action   = "StartupType -> $targetType"
                    Detail   = "Serviço [$($svcItem.Name)] => $targetType"
                })
            }
        }

        if ($tObj.registry) {
            foreach ($regItem in @($tObj.registry)) {
                $targetVal = if ($Undo) { $regItem.OriginalValue } else { $regItem.Value }
                if ($null -eq $targetVal) { continue }
                $actionDesc = if ($targetVal -eq "<RemoveEntry>") {
                    "Remover entrada"
                } else {
                    "Definir $targetVal ($($regItem.Type))"
                }
                [void]$items.Add([pscustomobject]@{
                    TweakKey = $tKey
                    Label    = $label
                    Kind     = "Registro"
                    Target   = "$($regItem.Path)\$($regItem.Name)"
                    Action   = $actionDesc
                    Detail   = "$($regItem.Path)\$($regItem.Name) = $actionDesc"
                })
            }
        }

        $scriptKind = if ($Undo) { "UndoScript" } else { "InvokeScript" }
        $scripts = if ($Undo) { $tObj.UndoScript } else { $tObj.InvokeScript }
        if ($scripts) {
            foreach ($scriptText in @($scripts)) {
                if ([string]::IsNullOrWhiteSpace($scriptText)) { continue }
                $firstLine = ($scriptText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") } | Select-Object -First 1)
                if (-not $firstLine) { $firstLine = $scriptText.Trim() }
                if ($firstLine.Length -gt 120) { $firstLine = $firstLine.Substring(0, 117) + "..." }
                [void]$items.Add([pscustomobject]@{
                    TweakKey = $tKey
                    Label    = $label
                    Kind     = "Script"
                    Target   = $scriptKind
                    Action   = $firstLine
                    Detail   = "${scriptKind}: $firstLine"
                })
            }
        }
    }

    return ,$items.ToArray()
}

function Format-TweakChangesPreviewText {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedTweaks,
        [switch]$Undo
    )

    $changes = Get-TweakChangesPreview -SelectedTweaks $SelectedTweaks -Undo:$Undo
    $modeLabel = if ($Undo) { "REVERSÃO (DESFAZER)" } else { "APLICAÇÃO" }
    $regCount = @($changes | Where-Object { $_.Kind -eq "Registro" }).Count
    $svcCount = @($changes | Where-Object { $_.Kind -eq "Serviço" }).Count
    $scrCount = @($changes | Where-Object { $_.Kind -eq "Script" }).Count

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("  PRÉ-VISUALIZAÇÃO DE ALTERAÇÕES - $modeLabel")
    [void]$sb.AppendLine("  Tweaks selecionados : $($SelectedTweaks.Count)")
    [void]$sb.AppendLine("  Chaves de Registro  : $regCount")
    [void]$sb.AppendLine("  Serviços do Windows : $svcCount")
    [void]$sb.AppendLine("  Scripts Customizados: $scrCount")
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("")

    if ($changes.Count -eq 0) {
        [void]$sb.AppendLine("Nenhuma alteração declarativa encontrada para os itens selecionados.")
        return $sb.ToString().TrimEnd()
    }

    $grouped = $changes | Group-Object -Property TweakKey
    foreach ($grp in $grouped) {
        $first = $grp.Group[0]
        [void]$sb.AppendLine("* $($first.Label) [$($first.TweakKey)]")
        foreach ($c in $grp.Group) {
            [void]$sb.AppendLine("    [$($c.Kind)] $($c.Detail)")
        }
        [void]$sb.AppendLine("")
    }

    return $sb.ToString().TrimEnd()
}

function Set-UltimatePowerPlan {
    param([switch]$Enable)

    try {
        if ($Enable) {
            Write-ToolLog "Duplicando e ativando plano 'Desempenho Máximo' (Ultimate Performance)..." "INFO"
            $dup = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
            $guid = ($dup | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value | Select-Object -First 1
            if ($guid) {
                powercfg /setactive $guid | Out-Null
                Write-ToolLog "Plano Desempenho Máximo ativado ($guid)." "SUCCESS"
            } else {
                powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
                Write-ToolLog "Comando de ativação do plano de energia executado." "SUCCESS"
            }
        } else {
            Write-ToolLog "Restaurando esquemas de energia padrão do Windows..." "INFO"
            powercfg /restoredefaultschemes | Out-Null
            Write-ToolLog "Planos de energia restaurados para o padrão de fábrica." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao configurar plano de energia: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-OOSU10 {
    Write-ToolLog "Preparando O&O ShutUp10++..." "INFO"
    $dir = Join-Path $env:LOCALAPPDATA "Alts"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $exePath = Join-Path $dir "OOSU10.exe"

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        Write-ToolLog "Baixando versão oficial de dl5.oo-software.com..." "INFO"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.DownloadFile("https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe", $exePath)
        Write-ToolLog "Iniciando O&O ShutUp10++ ($exePath)..." "SUCCESS"
        Start-Process -FilePath $exePath
    } catch {
        Write-ToolLog "Falha ao baixar/iniciar O&O ShutUp10++: $($_.Exception.Message)" "ERROR"
    }
}

function Export-EnvironmentReport {
    Write-ToolLog "Gerando Relatório Completo do Ambiente..." "INFO"
    $desktop = [Environment]::GetFolderPath("Desktop")
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $outFile = Join-Path $desktop "Relatorio_Ambiente_${env:COMPUTERNAME}_${stamp}.txt"

    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("  RELAT$([char]0xD3)RIO DO AMBIENTE - ALT TWEAKS")
        [void]$sb.AppendLine("  Data: $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) | Host: $($env:COMPUTERNAME)")
        [void]$sb.AppendLine("======================================================================")
        [void]$sb.AppendLine("")

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        [void]$sb.AppendLine("[SISTEMA OPERACIONAL & HARDWARE]")
        if ($os) { [void]$sb.AppendLine("OS: $($os.Caption) | Versão: $($os.Version) Build $($os.BuildNumber) | Arq: $($os.OSArchitecture)") }
        if ($cpu) { [void]$sb.AppendLine("CPU: $($cpu.Name) ($($cpu.NumberOfLogicalProcessors) threads)") }
        if ($cs) { [void]$sb.AppendLine("RAM: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB | Fabricante: $($cs.Manufacturer) $($cs.Model)") }
        [void]$sb.AppendLine("PowerShell: $($PSVersionTable.PSVersion)")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("[GERENCIADORES DE PACOTES]")
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        $ch = Get-Command choco.exe -ErrorAction SilentlyContinue
        [void]$sb.AppendLine("WinGet: $(if ($wg) { (& winget --version 2>$null) } else { 'Não instalado' })")
        [void]$sb.AppendLine("Chocolatey: $(if ($ch) { (& choco --version 2>$null) } else { 'Não instalado' })")
        [void]$sb.AppendLine("")

        $sync = if ($WinRepairSync) { $WinRepairSync } else { $global:WinRepairSync }
        if ($sync -and $sync.Configs -and $sync.Configs.Tweaks) {
            [void]$sb.AppendLine("[ESTADO ATUAL DE PREFERÊNCIAS & TOGGLES]")
            foreach ($p in $sync.Configs.Tweaks.PSObject.Properties) {
                if ($p.Value.Type -eq "Toggle") {
                    $st = Get-ToggleCurrentState -TweakObj $p.Value
                    [void]$sb.AppendLine("  [$($st)] $($p.Value.Content) ($($p.Name))")
                }
            }
            [void]$sb.AppendLine("")
        }

        if ($sync -and $sync.RecentLogs) {
            [void]$sb.AppendLine("[LOGS DA SESSÃO ATUAL]")
            foreach ($l in @($sync.RecentLogs)) {
                [void]$sb.AppendLine($l)
            }
        }

        [System.IO.File]::WriteAllText($outFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
        Write-ToolLog "Relatório de Ambiente salvo em: $outFile" "SUCCESS"
        Start-Process notepad.exe -ArgumentList "`"$outFile`""
    } catch {
        Write-ToolLog "Erro ao gerar relatório do ambiente: $($_.Exception.Message)" "ERROR"
    }
}


# ==============================================================================
# Módulo: Otimização de Hardware (GPU NVIDIA/AMD & CPU AMD/Intel)
# ==============================================================================

function Get-HardwareOptimizationProfile {
    $cpuName = "CPU Desconhecida"
    $cpuVendor = "Other"
    $cpuCores = 0
    $cpuThreads = 0

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            if ($cpu.Name) { $cpuName = ([string]$cpu.Name).Trim() }
            $mfr = [string]$cpu.Manufacturer
            if ($cpuName -match 'AMD|Ryzen|EPYC|Athlon' -or $mfr -match 'AMD') {
                $cpuVendor = "AMD"
            } elseif ($cpuName -match 'Intel|Core|Xeon|Pentium|Celeron' -or $mfr -match 'Intel') {
                $cpuVendor = "Intel"
            }
            if ($cpu.NumberOfCores) { $cpuCores = [int]$cpu.NumberOfCores }
            if ($cpu.NumberOfLogicalProcessors) { $cpuThreads = [int]$cpu.NumberOfLogicalProcessors }
        }
    } catch {}

    $isRyzenX3D = ($cpuVendor -eq "AMD") -and ($cpuName -match 'X3D')
    $isIntelHybrid = ($cpuVendor -eq "Intel") -and ($cpuName -match '1[2-5]\d{2}|Ultra|Core\(TM\) [3579] 1\d{2}')

    $gpuList = New-Object System.Collections.Generic.List[string]
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        foreach ($g in $gpus) {
            $gName = ([string]$g.Name).Trim()
            if ($gName -and ($gName -notmatch 'Microsoft Basic|Remote|Parsec|Virtual|Meta')) {
                [void]$gpuList.Add($gName)
            }
        }
        if ($gpuList.Count -eq 0) {
            foreach ($g in $gpus) {
                $gName = ([string]$g.Name).Trim()
                if ($gName) { [void]$gpuList.Add($gName) }
            }
        }
    } catch {}

    $gpuArray = $gpuList.ToArray()
    $joinedGpu = $gpuArray -join " | "
    $hasNvidia = ($joinedGpu -match 'NVIDIA|GeForce|Quadro|RTX|GTX')
    $hasAmdGpu = ($joinedGpu -match 'AMD|Radeon')
    $hasIntelGpu = ($joinedGpu -match 'Intel')

    $primaryGpu = "GPU não detectada"
    $discrete = $gpuArray | Where-Object { $_ -match 'NVIDIA|GeForce|Quadro|RTX|GTX|Radeon RX|Radeon Pro|Arc' } | Select-Object -First 1
    if ($discrete) {
        $primaryGpu = $discrete
    } elseif ($gpuArray.Count -gt 0) {
        $primaryGpu = $gpuArray[0]
    }

    $tips = New-Object System.Collections.Generic.List[string]
    if ($hasNvidia) { [void]$tips.Add("NVIDIA detectada (MSI Mode e Telemetria disponíveis)") }
    if ($hasAmdGpu) { [void]$tips.Add("AMD Radeon detectada (Desativar ULPS e MSI Mode disponíveis)") }
    if ($cpuVendor -eq "AMD") {
        if ($isRyzenX3D) {
            [void]$tips.Add("Ryzen X3D detectado (mantenha o Modo de Jogo ativado para agendamento 3D V-Cache)")
        } else {
            [void]$tips.Add("CPU AMD Ryzen detectada (Core Parking e Boost AC recomendados)")
        }
    } elseif ($cpuVendor -eq "Intel") {
        if ($isIntelHybrid) {
            [void]$tips.Add("CPU Intel Híbrida detectada (agendamento prioritário de P-Cores recomendado)")
        } else {
            [void]$tips.Add("CPU Intel detectada (Core Parking e Speed Shift EPP disponíveis)")
        }
    }
    if ($tips.Count -eq 0) {
        [void]$tips.Add("Use os ajustes gerais de GPU e CPU ou clique em Auto-Selecionar Recomendados.")
    }

    return [pscustomobject]@{
        CpuName       = $cpuName
        CpuVendor     = $cpuVendor
        CpuCores      = $cpuCores
        CpuThreads    = $cpuThreads
        IsRyzenX3D    = $isRyzenX3D
        IsIntelHybrid = $isIntelHybrid
        GpuNames      = $gpuArray
        PrimaryGpuName = $primaryGpu
        HasNvidia     = $hasNvidia
        HasAmdGpu     = $hasAmdGpu
        HasIntelGpu   = $hasIntelGpu
        SummaryTips   = ($tips.ToArray() -join " | ")
    }
}

function Get-HardwareOptimizationCatalog {
    $items = New-Object System.Collections.Generic.List[object]

    $defs = @(
        @{
            Key = "HwGpuHags"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Agendamento de GPU por Hardware (HAGS)"
            Description = "Ativa Hardware-Accelerated GPU Scheduling (HwSchMode=2) para reduzir latência de renderização e overhead de CPU em jogos compatíveis."
            ApplySummary = "HKLM:\...\GraphicsDrivers\HwSchMode = 2 (Requer reinício)"
            UndoSummary  = "HKLM:\...\GraphicsDrivers\HwSchMode = 1 (Padrão)"
        },
        @{
            Key = "HwGpuMmcss"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Prioridade MMCSS para Jogos (CPU/GPU/SFIO)"
            Description = "Ajusta Multimedia Class Scheduler (SystemResponsiveness=10, GPU Priority=8, Priority=6, Scheduling Category=High) para menor stuttering."
            ApplySummary = "HKLM:\...\Multimedia\SystemProfile + Tasks\Games -> Prioridade Alta"
            UndoSummary  = "HKLM:\...\Multimedia\SystemProfile + Tasks\Games -> Padrão Windows"
        },
        @{
            Key = "HwGpuPcieLspm"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Economia PCIe (ASPM / Link State)"
            Description = "Define Link State Power Management (SUB_PCIEXPRESS ASPM) para Desligado na tomada (AC), evitando quedas de largura de banda na GPU."
            ApplySummary = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0"
            UndoSummary  = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 2"
        },
        @{
            Key = "HwGpuShaderCache"; Group = "GpuGeneral"; Vendor = "All"; Recommended = $false; Risk = "Seguro"
            Content = "Limpar Cache de Shaders (DirectX / NVIDIA / AMD)"
            Description = "Remove caches antigos de shaders (D3DSCache, DXCache, GLCache, VkCache) que podem causar travamentos após troca de driver ou updates."
            ApplySummary = "Limpar pastas de Shader Cache em LocalAppData / LocalLow"
            UndoSummary  = "Limpeza de cache é pontual (os shaders são recriados automaticamente)"
        },
        @{
            Key = "HwNvidiaMsiMode"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $true; Risk = "Seguro"
            Content = "Ativar MSI Mode na GPU NVIDIA (VEN_10DE)"
            Description = "Habilita Message Signaled Interrupts (MSISupported=1) no dispositivo PCI de vídeo NVIDIA para reduzir latência de interrupções DPC."
            ApplySummary = "HKLM:\...\PCI\VEN_10DE*\...\Interrupt Management\MSISupported = 1"
            UndoSummary  = "HKLM:\...\PCI\VEN_10DE*\...\Interrupt Management\MSISupported = 0"
        },
        @{
            Key = "HwNvidiaTelemetry"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Telemetria NVIDIA (NvTelemetryContainer)"
            Description = "Desativa o serviço NvTelemetryContainer e tarefas agendadas NvTmRep/NvTmMon que coletam métricas em segundo plano."
            ApplySummary = "Serviço NvTelemetryContainer -> Disabled + tarefas NvTm* desativadas"
            UndoSummary  = "Serviço NvTelemetryContainer -> Automatic + tarefas NvTm* reativadas"
        },
        @{
            Key = "HwNvidiaPowerMizer"; Group = "GpuNvidia"; Vendor = "NVIDIA"; Recommended = $false; Risk = "Avançado"
            Content = "Desativar PowerMizer Dinâmico (Clock Fixo Desktop)"
            Description = "Força PerfLevelSrc/PowerMizerLevel=1 na chave de vídeo NVIDIA para impedir redução agressiva de clock. Aumenta consumo em idle."
            ApplySummary = "Chave Class\{4d36e968...} NVIDIA: PowerMizerLevelAC=1, PerfLevelSrc=8738"
            UndoSummary  = "Remover entradas PowerMizer customizadas (retorna ao driver padrão)"
        },
        @{
            Key = "HwAmdUlps"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar ULPS (Ultra Low Power State - AMD)"
            Description = "Define EnableUlps=0 no driver AMD Radeon para evitar quedas bruscas de clock, tela preta ao acordar e microstuttering."
            ApplySummary = "Chave Class\{4d36e968...} AMD: EnableUlps = 0"
            UndoSummary  = "Chave Class\{4d36e968...} AMD: EnableUlps = 1"
        },
        @{
            Key = "HwAmdMsiMode"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Ativar MSI Mode na GPU AMD (VEN_1002)"
            Description = "Habilita Message Signaled Interrupts (MSISupported=1) na GPU PCI AMD Radeon para menor latência de interrupções."
            ApplySummary = "HKLM:\...\PCI\VEN_1002*\...\Interrupt Management\MSISupported = 1"
            UndoSummary  = "HKLM:\...\PCI\VEN_1002*\...\Interrupt Management\MSISupported = 0"
        },
        @{
            Key = "HwAmdCrashDefender"; Group = "GpuAmd"; Vendor = "AMD_GPU"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Telemetria / Crash Defender AMD"
            Description = "Desativa os serviços AMD Crash Defender Service e AUEPLauncher, preservando AMD External Events Utility (FreeSync)."
            ApplySummary = "Serviços AMD Crash Defender / AUEPLauncher -> Disabled"
            UndoSummary  = "Serviços AMD Crash Defender / AUEPLauncher -> Manual"
        },
        @{
            Key = "HwCpuCoreParking"; Group = "CpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Core Parking na Tomada (CPMINCORES=100%)"
            Description = "Mantém 100% dos núcleos ativos no plano de energia atual na tomada (AC), reduzindo latência ao alternar cargas em jogos."
            ApplySummary = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100"
            UndoSummary  = "powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 10"
        },
        @{
            Key = "HwCpuPowerThrottling"; Group = "CpuGeneral"; Vendor = "All"; Recommended = $true; Risk = "Seguro"
            Content = "Desativar Power Throttling do Windows"
            Description = "Define PowerThrottlingOff=1 no registro para evitar que o Windows limite clocks de processos e jogos em segundo plano."
            ApplySummary = "HKLM:\...\Control\Power\PowerThrottling\PowerThrottlingOff = 1"
            UndoSummary  = "Remover PowerThrottlingOff (comportamento padrão)"
        },
        @{
            Key = "HwCpuAmdRyzenBoost"; Group = "CpuAmd"; Vendor = "AMD_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Otimizar Boost & EPP para AMD Ryzen (AC)"
            Description = "Define PERFBOOSTMODE=2 (Aggressive) e PERFEPP=0 na tomada para resposta rápida de Precision Boost em CPUs Ryzen."
            ApplySummary = "powercfg AC: PERFBOOSTMODE=2, PERFEPP=0"
            UndoSummary  = "powercfg AC: PERFEPP=50"
        },
        @{
            Key = "HwCpuAmdX3DGameMode"; Group = "CpuAmd"; Vendor = "AMD_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Otimizar Agendamento Ryzen X3D (Modo de Jogo Ativo)"
            Description = "Garante AllowAutoGameMode=1 e AutoGameModeEnabled=1 para que o driver AMD 3D V-Cache direcione jogos ao CCD com V-Cache."
            ApplySummary = "HKCU:\Software\Microsoft\GameBar -> AutoGameModeEnabled = 1"
            UndoSummary  = "HKCU:\Software\Microsoft\GameBar -> AutoGameModeEnabled = 0"
        },
        @{
            Key = "HwCpuIntelHybridPolicy"; Group = "CpuIntel"; Vendor = "Intel_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Priorizar P-Cores em CPUs Intel Híbridas"
            Description = "Ajusta SCHEDPOLICY=2 e SHORTSCHEDPOLICY=2 (Performant processors) para priorizar núcleos de performance (P-Cores) em jogos."
            ApplySummary = "powercfg AC: SCHEDPOLICY=2, SHORTSCHEDPOLICY=2"
            UndoSummary  = "powercfg AC: SCHEDPOLICY=5, SHORTSCHEDPOLICY=5"
        },
        @{
            Key = "HwCpuIntelEpp"; Group = "CpuIntel"; Vendor = "Intel_CPU"; Recommended = $true; Risk = "Seguro"
            Content = "Intel Speed Shift / EPP Desempenho Máximo (AC)"
            Description = "Define Energy Performance Preference (PERFEPP=0) na tomada para atingir clocks turbo mais rápido sem atraso de rampa."
            ApplySummary = "powercfg AC: PERFEPP=0"
            UndoSummary  = "powercfg AC: PERFEPP=50"
        }
    )

    foreach ($d in $defs) {
        [void]$items.Add([pscustomobject]$d)
    }
    return ,$items.ToArray()
}

function Get-DisplayPciDeviceRegPaths {
    param([Parameter(Mandatory=$true)][string]$VendorId)

    $results = New-Object System.Collections.Generic.List[string]
    $pciRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    if (-not (Test-Path $pciRoot)) { return ,$results.ToArray() }

    try {
        $venDirs = Get-ChildItem -Path $pciRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like "${VendorId}*" }
        foreach ($vd in $venDirs) {
            $instDirs = Get-ChildItem -Path $vd.PSPath -ErrorAction SilentlyContinue
            foreach ($inst in $instDirs) {
                $props = Get-ItemProperty -Path $inst.PSPath -ErrorAction SilentlyContinue
                if ($props -and ($props.ClassGUID -eq "{4d36e968-e325-11ce-bfc1-08002be10318}")) {
                    $msiPath = Join-Path $inst.PSPath "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
                    $msiPath = $msiPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\'
                    [void]$results.Add($msiPath)
                }
            }
        }
    } catch {}
    return ,$results.ToArray()
}

function Get-DisplayClassRegPaths {
    param([Parameter(Mandatory=$true)][string]$ProviderPattern)

    $results = New-Object System.Collections.Generic.List[string]
    $classRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    if (-not (Test-Path $classRoot)) { return ,$results.ToArray() }

    try {
        $subKeys = Get-ChildItem -Path $classRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' }
        foreach ($sk in $subKeys) {
            $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
            if ($props -and ($props.ProviderName -match $ProviderPattern -or $props.DriverDesc -match $ProviderPattern)) {
                $cleanPath = $sk.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\'
                [void]$results.Add($cleanPath)
            }
        }
    } catch {}
    return ,$results.ToArray()
}

function Invoke-PowerCfgSetting {
    param(
        [Parameter(Mandatory=$true)][string]$Subgroup,
        [Parameter(Mandatory=$true)][string]$Setting,
        [Parameter(Mandatory=$true)][int]$Value,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] powercfg /setacvalueindex SCHEME_CURRENT $Subgroup $Setting $Value" "INFO"
        return
    }

    try {
        $p = Start-Process -FilePath "powercfg.exe" -ArgumentList "/setacvalueindex SCHEME_CURRENT $Subgroup $Setting $Value" -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            $null = Start-Process -FilePath "powercfg.exe" -ArgumentList "/setactive SCHEME_CURRENT" -NoNewWindow -Wait -PassThru
            Write-ToolLog "Energia (powercfg): $Subgroup/$Setting = $Value aplicado." "INFO"
        } else {
            Write-ToolLog "powercfg retornou código $($p.ExitCode) para $Subgroup/$Setting (pode não ser suportado nesta CPU/plano)." "WARN"
        }
    } catch {
        Write-ToolLog "Aviso ao executar powercfg ($Subgroup/$Setting): $($_.Exception.Message)" "WARN"
    }
}

function Clear-GpuShaderCaches {
    param([switch]$DryRun)

    $cacheDirs = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
        (Join-Path (Split-Path $env:LOCALAPPDATA) "LocalLow\NVIDIA\PerDriverVersion\DXCache")
    )

    $totalRemoved = 0
    foreach ($dir in $cacheDirs) {
        if (-not (Test-Path $dir)) { continue }
        $files = @(Get-ChildItem -Path $dir -Recurse -File -Force -ErrorAction SilentlyContinue)
        if ($DryRun) {
            Write-ToolLog "[DRY-RUN] Limparia $($files.Count) arquivo(s) em $dir" "INFO"
            continue
        }
        foreach ($f in $files) {
            try {
                Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                $totalRemoved++
            } catch {}
        }
    }

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] Limpeza de Shader Cache simulada." "SUCCESS"
    } else {
        Write-ToolLog "Limpeza de Shader Cache concluída ($totalRemoved arquivo(s) removidos; arquivos em uso foram preservados)." "SUCCESS"
    }
}

function Set-ScheduledTasksByPrefix {
    param(
        [Parameter(Mandatory=$true)][string]$Pattern,
        [bool]$Enable = $false,
        [switch]$DryRun
    )

    $actionLabel = if ($Enable) { "Habilitar" } else { "Desabilitar" }
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like $Pattern })
        if ($tasks.Count -eq 0) {
            $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "${prefix}Nenhuma tarefa agendada encontrada para [$Pattern]." "INFO"
            return
        }
        foreach ($t in $tasks) {
            if ($DryRun) {
                Write-ToolLog "[DRY-RUN] $actionLabel tarefa agendada: $($t.TaskPath)$($t.TaskName)" "INFO"
            } else {
                if ($Enable) {
                    Enable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                }
                Write-ToolLog "Tarefa [$($t.TaskName)] -> $actionLabel." "INFO"
            }
        }
    } catch {}
}

function Invoke-HardwareOptimization {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [switch]$Undo,
        [switch]$DryRun
    )

    $catalog = Get-HardwareOptimizationCatalog
    $item = $catalog | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    $label = if ($item) { $item.Content } else { $Key }
    $prefix = if ($DryRun) { "[DRY-RUN] " } else { "" }
    $verb = if ($Undo) { "Desfazendo" } else { "Aplicando" }

    Write-ToolLog "${prefix}$verb [$label]..." "INFO"

    switch ($Key) {
        "HwGpuHags" {
            $val = if ($Undo) { 1 } else { 2 }
            Set-RegistryEntry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwGpuMmcss" {
            $sysResp = if ($Undo) { 20 } else { 10 }
            $gpuPrio = if ($Undo) { 2 } else { 8 }
            $prio    = if ($Undo) { 2 } else { 6 }
            $sched   = if ($Undo) { "Medium" } else { "High" }
            $sfio    = if ($Undo) { "Normal" } else { "High" }

            $mmRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            $games  = "$mmRoot\Tasks\Games"
            Set-RegistryEntry -Path $mmRoot -Name "SystemResponsiveness" -Type "DWord" -Value $sysResp -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "GPU Priority" -Type "DWord" -Value $gpuPrio -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "Priority" -Type "DWord" -Value $prio -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "Scheduling Category" -Type "String" -Value $sched -DryRun:$DryRun
            Set-RegistryEntry -Path $games -Name "SFIO Priority" -Type "String" -Value $sfio -DryRun:$DryRun
        }
        "HwGpuPcieLspm" {
            $val = if ($Undo) { 2 } else { 0 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PCIEXPRESS" -Setting "ASPM" -Value $val -DryRun:$DryRun
        }
        "HwGpuShaderCache" {
            if ($Undo) {
                Write-ToolLog "${prefix}Limpeza de Shader Cache não requer reversão (caches são recriados pelos jogos)." "INFO"
            } else {
                Clear-GpuShaderCaches -DryRun:$DryRun
            }
        }
        "HwNvidiaMsiMode" {
            $paths = Get-DisplayPciDeviceRegPaths -VendorId "VEN_10DE"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma GPU PCI NVIDIA (VEN_10DE) encontrada neste sistema." "INFO"
            } else {
                $val = if ($Undo) { 0 } else { 1 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "MSISupported" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwNvidiaTelemetry" {
            $svcMode = if ($Undo) { "Automatic" } else { "Disabled" }
            Set-ServiceStartupSafe -Name "NvTelemetryContainer" -StartupType $svcMode -DryRun:$DryRun
            Set-ScheduledTasksByPrefix -Pattern "NvTmRep*" -Enable:$Undo -DryRun:$DryRun
            Set-ScheduledTasksByPrefix -Pattern "NvTmMon*" -Enable:$Undo -DryRun:$DryRun
        }
        "HwNvidiaPowerMizer" {
            $paths = Get-DisplayClassRegPaths -ProviderPattern "NVIDIA"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma chave de classe de vídeo NVIDIA encontrada." "INFO"
            } else {
                foreach ($p in $paths) {
                    if ($Undo) {
                        foreach ($n in @("PerfLevelSrc", "PowerMizerEnable", "PowerMizerLevel", "PowerMizerLevelAC")) {
                            Set-RegistryEntry -Path $p -Name $n -Type "DWord" -Value "<RemoveEntry>" -DryRun:$DryRun
                        }
                    } else {
                        Set-RegistryEntry -Path $p -Name "PerfLevelSrc" -Type "DWord" -Value 8738 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerEnable" -Type "DWord" -Value 1 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerLevel" -Type "DWord" -Value 1 -DryRun:$DryRun
                        Set-RegistryEntry -Path $p -Name "PowerMizerLevelAC" -Type "DWord" -Value 1 -DryRun:$DryRun
                    }
                }
            }
        }
        "HwAmdUlps" {
            $paths = Get-DisplayClassRegPaths -ProviderPattern "AMD|ATI|Radeon"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma chave de classe de vídeo AMD encontrada." "INFO"
            } else {
                $val = if ($Undo) { 1 } else { 0 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "EnableUlps" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwAmdMsiMode" {
            $paths = Get-DisplayPciDeviceRegPaths -VendorId "VEN_1002"
            if ($paths.Count -eq 0) {
                Write-ToolLog "${prefix}Nenhuma GPU PCI AMD (VEN_1002) encontrada neste sistema." "INFO"
            } else {
                $val = if ($Undo) { 0 } else { 1 }
                foreach ($p in $paths) {
                    Set-RegistryEntry -Path $p -Name "MSISupported" -Type "DWord" -Value $val -DryRun:$DryRun
                }
            }
        }
        "HwAmdCrashDefender" {
            $svcMode = if ($Undo) { "Manual" } else { "Disabled" }
            Set-ServiceStartupSafe -Name "AMD Crash Defender Service" -StartupType $svcMode -DryRun:$DryRun
            Set-ServiceStartupSafe -Name "AUEPLauncher" -StartupType $svcMode -DryRun:$DryRun
        }
        "HwCpuCoreParking" {
            $val = if ($Undo) { 10 } else { 100 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "CPMINCORES" -Value $val -DryRun:$DryRun
        }
        "HwCpuPowerThrottling" {
            $ptPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
            $val = if ($Undo) { "<RemoveEntry>" } else { 1 }
            Set-RegistryEntry -Path $ptPath -Name "PowerThrottlingOff" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwCpuAmdRyzenBoost" {
            if ($Undo) {
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value 50 -DryRun:$DryRun
            } else {
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFBOOSTMODE" -Value 2 -DryRun:$DryRun
                Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value 0 -DryRun:$DryRun
            }
        }
        "HwCpuAmdX3DGameMode" {
            $gbPath = "HKCU:\Software\Microsoft\GameBar"
            $val = if ($Undo) { 0 } else { 1 }
            Set-RegistryEntry -Path $gbPath -Name "AllowAutoGameMode" -Type "DWord" -Value $val -DryRun:$DryRun
            Set-RegistryEntry -Path $gbPath -Name "AutoGameModeEnabled" -Type "DWord" -Value $val -DryRun:$DryRun
        }
        "HwCpuIntelHybridPolicy" {
            $val = if ($Undo) { 5 } else { 2 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "SCHEDPOLICY" -Value $val -DryRun:$DryRun
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "SHORTSCHEDPOLICY" -Value $val -DryRun:$DryRun
        }
        "HwCpuIntelEpp" {
            $val = if ($Undo) { 50 } else { 0 }
            Invoke-PowerCfgSetting -Subgroup "SUB_PROCESSOR" -Setting "PERFEPP" -Value $val -DryRun:$DryRun
        }
        default {
            Write-ToolLog "Otimização de hardware desconhecida: $Key" "WARN"
            return
        }
    }

    Write-ToolLog "${prefix}Concluído: $label" "SUCCESS"
}

function Get-HardwareChangesPreview {
    param(
        [Parameter(Mandatory=$true)][string[]]$Keys,
        [switch]$Undo
    )

    $catalog = Get-HardwareOptimizationCatalog
    $byKey = @{}
    foreach ($c in $catalog) { $byKey[$c.Key] = $c }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($k in $Keys) {
        if (-not $byKey.ContainsKey($k)) { continue }
        $c = $byKey[$k]
        $detail = if ($Undo) { $c.UndoSummary } else { $c.ApplySummary }
        [void]$items.Add([pscustomobject]@{
            Key     = $c.Key
            Content = $c.Content
            Group   = $c.Group
            Vendor  = $c.Vendor
            Risk    = $c.Risk
            Action  = if ($Undo) { "Desfazer" } else { "Aplicar" }
            Detail  = $detail
        })
    }
    return ,$items.ToArray()
}

function Format-HardwareChangesPreviewText {
    param(
        [Parameter(Mandatory=$true)][string[]]$Keys,
        [switch]$Undo
    )

    $preview = Get-HardwareChangesPreview -Keys $Keys -Undo:$Undo
    $modeLabel = if ($Undo) { "REVERSÃO (DESFAZER)" } else { "APLICAÇÃO" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("  PRÉ-VISUALIZAÇÃO DE HARDWARE (GPU & CPU) - $modeLabel")
    [void]$sb.AppendLine("  Ajustes selecionados: $($preview.Count)")
    [void]$sb.AppendLine("======================================================================")
    [void]$sb.AppendLine("")

    foreach ($p in $preview) {
        [void]$sb.AppendLine("* $($p.Content) [$($p.Key)] ($($p.Risk))")
        [void]$sb.AppendLine("    Alvo/Ação: $($p.Detail)")
        [void]$sb.AppendLine("")
    }

    return $sb.ToString().TrimEnd()
}

function Invoke-HardwareExternalTool {
    param(
        [Parameter(Mandatory=$true)][string]$ToolKey,
        [switch]$DryRun
    )

    $tools = @{
        NVCleanstall   = @{ Name = "NVCleanstall";            Winget = "TechPowerUp.NVCleanstall";                 Url = "https://www.techpowerup.com/nvcleanstall/" }
        DDU            = @{ Name = "Display Driver Uninstaller (DDU)"; Winget = "Wagnardsoft.DisplayDriverUninstaller"; Url = "https://www.wagnardsoft.com/display-driver-uninstaller-ddu-" }
        MSIAfterburner = @{ Name = "MSI Afterburner";         Winget = "Guru3D.Afterburner";                       Url = "https://www.msi.com/Landing/afterburner/graphics-cards" }
        GPUZ           = @{ Name = "TechPowerUp GPU-Z";       Winget = "TechPowerUp.GPU-Z";                        Url = "https://www.techpowerup.com/gpuz/" }
        CPUZ           = @{ Name = "CPUID CPU-Z";             Winget = "CPUID.CPU-Z";                              Url = "https://www.cpuid.com/softwares/cpu-z.html" }
        HWiNFO         = @{ Name = "HWiNFO";                  Winget = "REALiX.HWiNFO";                            Url = "https://www.hwinfo.com/download/" }
        NvidiaDrivers  = @{ Name = "Drivers Oficiais NVIDIA"; Winget = "";                                         Url = "https://www.nvidia.com/Download/index.aspx" }
        AmdDrivers     = @{ Name = "Drivers Oficiais AMD";    Winget = "";                                         Url = "https://www.amd.com/en/support" }
        IntelDrivers   = @{ Name = "Drivers Oficiais Intel";  Winget = "";                                         Url = "https://www.intel.com/content/www/us/en/support/detect.html" }
    }

    if (-not $tools.ContainsKey($ToolKey)) {
        Write-ToolLog "Ferramenta externa desconhecida: $ToolKey" "WARN"
        return
    }

    $t = $tools[$ToolKey]
    if ($DryRun) {
        if ($t.Winget) {
            Write-ToolLog "[DRY-RUN] Instalaria $($t.Name) via WinGet ($($t.Winget)) ou abriria $($t.Url)." "INFO"
        } else {
            Write-ToolLog "[DRY-RUN] Abriria página oficial $($t.Name): $($t.Url)" "INFO"
        }
        return
    }

    if ($t.Winget -and (Get-Command "winget.exe" -ErrorAction SilentlyContinue) -and (Get-Command "Install-PackagesBatch" -ErrorAction SilentlyContinue)) {
        Install-PackagesBatch -Apps @([pscustomobject]@{ Content = $t.Name; Winget = $t.Winget; Choco = "na" }) -Manager "WinGet"
    } else {
        Write-ToolLog "Abrindo página oficial de $($t.Name): $($t.Url)" "INFO"
        try {
            Start-Process $t.Url
        } catch {
            Write-ToolLog "Erro ao abrir URL $($t.Url): $($_.Exception.Message)" "ERROR"
        }
    }
}


# ==============================================================================
# Módulo Avançado: Otimizações de Desempenho, Debloat, Serviços e Perfis Prontos
# ==============================================================================

function Clear-TempFiles {
    Write-ToolLog "Iniciando limpeza profunda de arquivos temporários e caches..." "INFO"

    $targets = @(
        "$env:TEMP\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "$env:LOCALAPPDATA\CrashDumps\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$env:LOCALAPPDATA\Temp\*"
    )

    $deletedCount = 0
    foreach ($target in $targets) {
        if (Test-Path (Split-Path $target)) {
            try {
                $items = Get-ChildItem -Path $target -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $deletedCount++
                }
            } catch {}
        }
    }

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Lixeira esvaziada." "SUCCESS"
    } catch {}

    Write-ToolLog "Limpeza temporária finalizada. $deletedCount arquivos processados/removidos." "SUCCESS"
}

function Clear-WindowsUpdateCache {
    Write-ToolLog "Parando serviços do Windows Update..." "INFO"
    try {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "cryptSvc" -Force -ErrorAction SilentlyContinue

        $wuCachePath = "C:\Windows\SoftwareDistribution\Download\*"
        if (Test-Path (Split-Path $wuCachePath)) {
            Write-ToolLog "Removendo arquivos temporários de atualização corrompidos..." "INFO"
            Remove-Item -Path $wuCachePath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-ToolLog "Reiniciando serviços essenciais..." "INFO"
        Start-Service -Name "cryptSvc" -ErrorAction SilentlyContinue
        Start-Service -Name "bits" -ErrorAction SilentlyContinue
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue

        Write-ToolLog "Cache do Windows Update redefinido com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao redefinir cache do Windows Update: $_" "ERROR"
    }
}

function Enable-UltimatePerformancePowerPlan {
    Write-ToolLog "Desbloqueando e ativando o Plano de Energia 'Desempenho Máximo' (Ultimate Performance)..." "INFO"
    try {
        $guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $output = powercfg -duplicatescheme $guid 2>&1
        powercfg -setactive $guid
        Write-ToolLog "Plano 'Desempenho Máximo' ativado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao ativar plano de energia: $_" "ERROR"
    }
}

function Optimize-WindowsTelemetryAndPrivacy {
    Write-ToolLog "Desativando telemetria, diagnóstico e coleta de dados..." "INFO"
    try {
        $dataCollectionKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dataCollectionKey)) { New-Item -Path $dataCollectionKey -Force | Out-Null }
        Set-ItemProperty -Path $dataCollectionKey -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $dataCollectionKey -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force

        $advertisingKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $advertisingKey)) { New-Item -Path $advertisingKey -Force | Out-Null }
        Set-ItemProperty -Path $advertisingKey -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force

        # Desativar Histórico de Atividades
        $activityKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $activityKey)) { New-Item -Path $activityKey -Force | Out-Null }
        Set-ItemProperty -Path $activityKey -Name "EnableActivityFeed" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "PublishUserActivities" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $activityKey -Name "UploadUserActivities" -Value 0 -Type DWord -Force

        # Desativar Tarefas Agendadas de Telemetria / CEIP
        $telemetryTasks = @(
            "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
            "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
            "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
        )
        foreach ($task in $telemetryTasks) {
            Disable-ScheduledTask -TaskPath (Split-Path $task) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue | Out-Null
        }

        Write-ToolLog "Telemetria e tarefas agendadas de rastreamento desativadas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar telemetria: $_" "ERROR"
    }
}

function Optimize-WindowsServicesManual {
    Write-ToolLog "Configurando serviços secundários pesados para Manual ou Desativado..." "INFO"
    
    $servicesToDisable = @(
        "DiagTrack",
        "dmwappushservice",
        "RetailDemo",
        "RemoteRegistry",
        "diagnosticshub.standardcollector.service"
    )

    $servicesToManual = @(
        "MapsBroker",
        "lfsvc",
        "SensorService",
        "SensrSvc",
        "WbioSrvc",
        "Fax",
        "wisvc",
        "SharedAccess",
        "WMPNetworkSvc",
        "WerSvc"
    )

    foreach ($s in $servicesToDisable) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Desativado." "INFO"
        }
    }

    foreach ($s in $servicesToManual) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$s] -> Manual." "INFO"
        }
    }

    Write-ToolLog "Otimização de serviços do Windows concluída." "SUCCESS"
}

function Disable-GameDvrAndBackgroundRecording {
    Write-ToolLog "Desativando gravação em segundo plano do GameDVR (Reduz input lag em jogos)..." "INFO"
    try {
        $gameConfigKey = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gameConfigKey)) { New-Item -Path $gameConfigKey -Force | Out-Null }
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $gameConfigKey -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force

        $gamePolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $gamePolicyKey)) { New-Item -Path $gamePolicyKey -Force | Out-Null }
        Set-ItemProperty -Path $gamePolicyKey -Name "AllowGameDVR" -Value 0 -Type DWord -Force

        Write-ToolLog "GameDVR e gravação de fundo desativados. Desempenho de jogos otimizado." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao desativar GameDVR: $_" "ERROR"
    }
}

function Disable-StartMenuAdsAndBingSearch {
    Write-ToolLog "Desativando pesquisas da Web (Bing) e anúncios patrocinados no Menu Iniciar..." "INFO"
    try {
        $searchKey = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
        Set-ItemProperty -Path $searchKey -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force

        $userSearchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $userSearchKey)) { New-Item -Path $userSearchKey -Force | Out-Null }
        Set-ItemProperty -Path $userSearchKey -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchKey -Name "CortanaConsent" -Value 0 -Type DWord -Force

        $contentDeliveryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (Test-Path $contentDeliveryKey) {
            Set-ItemProperty -Path $contentDeliveryKey -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338388Enabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $contentDeliveryKey -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "Pesquisas Bing no menu Iniciar e anúncios de aplicativos desativados." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao remover anúncios do Menu Iniciar: $_" "ERROR"
    }
}

function Optimize-SystemResponsivenessAndVisuals {
    Write-ToolLog "Ajustando tempo de resposta de menus e prioridade de CPU..." "INFO"
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "10" -Force
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force
        Write-ToolLog "Prioridade de processos em foco e velocidade de menus aceleradas." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao aplicar ajustes visuais: $_" "ERROR"
    }
}

function Optimize-SsdTrim {
    Write-ToolLog "Verificando unidades SSD para execução de TRIM (ReTrim)..." "INFO"
    try {
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
        foreach ($vol in $volumes) {
            Write-ToolLog "Otimizando unidade $($vol.DriveLetter): ..." "INFO"
            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction SilentlyContinue | Out-Null
        }
        Write-ToolLog "Comando TRIM executado com sucesso nas unidades elegíveis." "SUCCESS"
    } catch {
        Write-ToolLog "Falha ao executar TRIM: $_" "ERROR"
    }
}

function Set-HibernationState {
    param([Parameter(Mandatory=$true)][bool]$Enable)
    try {
        if ($Enable) {
            powercfg.exe -h on
            Write-ToolLog "Hibernação reativada." "SUCCESS"
        } else {
            powercfg.exe -h off
            Write-ToolLog "Hibernação desativada. Espaço equivalente à memória RAM liberado no disco C:." "SUCCESS"
        }
    } catch {
        Write-ToolLog "Erro ao alterar estado de hibernação: $_" "ERROR"
    }
}

function Invoke-SystemDebloatAppx {
    Write-ToolLog "Removendo bloatwares e aplicativos pré-instalados desnecessários do Windows..." "INFO"
    $appsToRemove = @(
        "*Microsoft.BingNews*",
        "*Microsoft.BingWeather*",
        "*Microsoft.BingSearch*",
        "*Microsoft.GetHelp*",
        "*Microsoft.Getstarted*",
        "*Microsoft.MicrosoftOfficeHub*",
        "*Microsoft.MicrosoftSolitaireCollection*",
        "*Microsoft.People*",
        "*Microsoft.PowerAutomateDesktop*",
        "*Microsoft.Todos*",
        "*Microsoft.WindowsFeedbackHub*",
        "*Microsoft.YourPhone*",
        "*Microsoft.ZuneMusic*",
        "*Microsoft.ZuneVideo*",
        "*Clipchamp.Clipchamp*",
        "*SpotifyAB.SpotifyMusic*",
        "*Disney.37853FC22B2CE*",
        "*Netflix*",
        "*Facebook*",
        "*TikTok*"
    )

    $removed = 0
    foreach ($app in $appsToRemove) {
        try {
            $pkgs = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            foreach ($pkg in $pkgs) {
                Write-ToolLog "Removendo app: $($pkg.Name)..." "INFO"
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removed++
            }
        } catch {}
    }

    Write-ToolLog "Debloat de aplicativos concluído. Pacotes removidos: $removed." "SUCCESS"
}


# ==============================================================================
# Módulo: Ajustes de Usabilidade e Interface
# ==============================================================================

function Set-RestorePoint {
    param(
        [string]$Description = "AltTweaks_RestorePoint",
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-ToolLog "[DRY-RUN] Criaria Ponto de Restauração do Sistema ($Description) via Checkpoint-Computer." "INFO"
        return $true
    }

    Write-ToolLog "Criando Ponto de Restauração do Sistema ($Description)..." "INFO"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-ToolLog "Ponto de Restauração criado com sucesso!" "SUCCESS"
        return $true
    } catch {
        Write-ToolLog "Não foi possível criar o Ponto de Restauração: $_ (Verifique se a Proteção do Sistema está ativada)." "WARN"
        return $false
    }
}

function Set-ShowFileExtensions {
    param([bool]$Enable = $true)
    Write-ToolLog "Configurando exibição de extensões de arquivo conhecidas..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $val = if ($Enable) { 0 } else { 1 }
        Set-ItemProperty -Path $key -Name "HideFileExt" -Value $val -Type DWord -Force
        Write-ToolLog "Extensões de arquivos visíveis: $Enable." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar exibição de extensões: $_" "ERROR"
    }
}

function Set-ShowHiddenFiles {
    param([bool]$Enable = $true)
    Write-ToolLog "Configurando exibição de arquivos e pastas ocultas..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $val = if ($Enable) { 1 } else { 2 }
        Set-ItemProperty -Path $key -Name "Hidden" -Value $val -Type DWord -Force
        Write-ToolLog "Arquivos ocultos visíveis: $Enable." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar arquivos ocultos: $_" "ERROR"
    }
}

function Set-ExplorerOpenToThisPC {
    Write-ToolLog "Configurando o Windows Explorer para abrir em 'Este Computador' em vez do Acesso Rápido..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $key -Name "LaunchTo" -Value 1 -Type DWord -Force
        Write-ToolLog "Explorer agora abre diretamente em 'Este Computador'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar abertura do Explorer: $_" "ERROR"
    }
}

function Set-SystemDarkMode {
    param([bool]$Enable = $true)
    Write-ToolLog "Aplicando Tema Escuro (Dark Mode) global no sistema e aplicativos..." "INFO"
    try {
        $key = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        $val = if ($Enable) { 0 } else { 1 }
        Set-ItemProperty -Path $key -Name "AppsUseLightTheme" -Value $val -Type DWord -Force
        Set-ItemProperty -Path $key -Name "SystemUsesLightTheme" -Value $val -Type DWord -Force
        Write-ToolLog "Tema Escuro aplicado com sucesso." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar Dark Mode: $_" "ERROR"
    }
}

function Disable-MouseAcceleration {
    Write-ToolLog "Desativando Aceleração do Mouse (Aprimorar Precisão do Ponteiro) para precisão 1:1 em jogos..." "INFO"
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force
        Write-ToolLog "Aceleração do mouse desativada (precisão pura do sensor)." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desativar aceleração do mouse: $_" "ERROR"
    }
}

function Disable-Win11TaskbarJunk {
    Write-ToolLog "Limpando itens inúteis da barra de tarefas do Windows 11 (Widgets, Copilot, Chat/Teams, TaskView)..." "INFO"
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $key -Name "TaskbarDa" -Value 0 -Type DWord -Force          # Desativa Widgets
        Set-ItemProperty -Path $key -Name "ShowCopilotButton" -Value 0 -Type DWord -Force  # Desativa Botão Copilot
        Set-ItemProperty -Path $key -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force # Desativa Visão de Tarefas

        $chatKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
        if (Test-Path $chatKey) {
            Set-ItemProperty -Path $chatKey -Name "PeopleBand" -Value 0 -Type DWord -Force
        }

        # Reiniciar explorer para refletir alterações
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Write-ToolLog "Barra de tarefas limpa e sem distrações." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao ajustar barra de tarefas: $_" "ERROR"
    }
}

function Add-TakeOwnershipContextMenu {
    Write-ToolLog "Adicionando 'Obter Permissões' (Take Ownership) ao menu de contexto de arquivos e pastas..." "INFO"
    try {
        # Para arquivos
        $fileKey = "HKCR:\*\shell\runas"
        New-Item -Path $fileKey -Force | Out-Null
        Set-ItemProperty -Path $fileKey -Name "(Default)" -Value "Obter Acesso Total (Take Ownership)" -Force
        Set-ItemProperty -Path $fileKey -Name "NoWorkingDirectory" -Value "" -Force
        $fileCmd = "$fileKey\command"
        New-Item -Path $fileCmd -Force | Out-Null
        Set-ItemProperty -Path $fileCmd -Name "(Default)" -Value "cmd.exe /c takeown /f `"%1`" && icacls `"%1`" /grant administrators:F" -Force
        Set-ItemProperty -Path $fileCmd -Name "IsolatedCommand" -Value "cmd.exe /c takeown /f `"%1`" && icacls `"%1`" /grant administrators:F" -Force

        # Para pastas
        $dirKey = "HKCR:\Directory\shell\runas"
        New-Item -Path $dirKey -Force | Out-Null
        Set-ItemProperty -Path $dirKey -Name "(Default)" -Value "Obter Acesso Total (Take Ownership)" -Force
        Set-ItemProperty -Path $dirKey -Name "NoWorkingDirectory" -Value "" -Force
        $dirCmd = "$dirKey\command"
        New-Item -Path $dirCmd -Force | Out-Null
        Set-ItemProperty -Path $dirCmd -Name "(Default)" -Value "cmd.exe /c takeown /f `"%1`" /r /d y && icacls `"%1`" /grant administrators:F /t" -Force
        Set-ItemProperty -Path $dirCmd -Name "IsolatedCommand" -Value "cmd.exe /c takeown /f `"%1`" /r /d y && icacls `"%1`" /grant administrators:F /t" -Force

        Write-ToolLog "Atalho 'Take Ownership' adicionado ao menu do botão direito." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao adicionar Take Ownership: $_" "ERROR"
    }
}

function Uninstall-OneDrivePurge {
    Write-ToolLog "Iniciando desinstalação completa e remoção de resíduos do OneDrive..." "INFO"
    try {
        Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue

        $oneDriveSetup = @(
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe",
            "$env:LOCALAPPDATA\Microsoft\OneDrive\Update\OneDriveSetup.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($oneDriveSetup) {
            Start-Process -FilePath $oneDriveSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
            Write-ToolLog "Desinstalador do OneDrive executado." "INFO"
        }

        # Remover pastas residuais
        $dirs = @(
            "$env:USERPROFILE\OneDrive",
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive"
        )
        foreach ($d in $dirs) {
            if (Test-Path $d) {
                Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Remover OneDrive do painel lateral do Windows Explorer
        $clsid = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        if (Test-Path $clsid) {
            Set-ItemProperty -Path $clsid -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord -Force
        }

        Write-ToolLog "OneDrive desinstalado e removido do sistema com sucesso!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desinstalar OneDrive: $_" "ERROR"
    }
}


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
# Perfil Aprimorado Alt Tweaks - PowerShell 7+
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


# ==============================================================================
# Módulo: Gerenciamento Completo do Windows Update
# ==============================================================================

function Clear-WindowsUpdateSystemDenyAcl {
    foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc", "WaaSMedicSvc")) {
        $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        try {
            if (-not (Test-Path $serviceKeyPath)) { continue }
            $acl = Get-Acl -Path $serviceKeyPath -ErrorAction Stop
            $denyRules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.AccessControlType -eq "Deny" -and $_.IdentityReference.Value -eq "S-1-5-18"
            })
            if ($denyRules.Count -gt 0) {
                foreach ($r in $denyRules) { [void]$acl.RemoveAccessRule($r) }
                Set-Acl -Path $serviceKeyPath -AclObject $acl -ErrorAction Stop
                Write-ToolLog "Removida restrição Deny de SYSTEM em [$serviceName]." "INFO"
            }
        } catch {}
    }
}

function Enable-WindowsUpdateScheduledTasks {
    $tasks = @(
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'
    )
    foreach ($t in $tasks) {
        Get-ScheduledTask -TaskPath $t -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }
}

function Set-WindowsUpdateRecommended {
    Write-ToolLog "Configurando Windows Update para o Modo Recomendado (Segurança Estável)..." "INFO"
    Write-ToolLog "Desativa drivers via Update, adia recursos por 365 dias e qualidade por 4 dias." "INFO"
    try {
        Clear-WindowsUpdateSystemDenyAcl

        $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        $auPath = "$wuPath\AU"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }

        Remove-ItemProperty -Path $auPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $wuPath -Name "DisableWindowsUpdateAccess" -ErrorAction SilentlyContinue

        Set-Service -Name "BITS" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "UsoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "UsoSvc" -ErrorAction SilentlyContinue
        Enable-WindowsUpdateScheduledTasks

        foreach ($p in @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
            if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Value 0 -Type DWord -Force

        Set-ItemProperty -Path $wuPath -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdates" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPath -Name "DeferQualityUpdatesPeriodInDays" -Value 4 -Type DWord -Force

        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 3 -Type DWord -Force
        Set-ItemProperty -Path $auPath -Name "AUPowerManagement" -Value 0 -Type DWord -Force

        Write-ToolLog "Windows Update configurado no modo 'Segurança e Estabilidade Recomendada'." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao configurar Windows Update: $_" "ERROR"
    }
}

function Reset-WindowsUpdateDefault {
    Write-ToolLog "Restaurando Windows Update para as configurações originais de fábrica..." "INFO"
    try {
        $registryCleanup = @(
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"; Names = @("NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; Names = @("ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays", "DisableWindowsUpdateAccess") },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"; Names = @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays", "PauseUpdatesExpiryTime", "PauseFeatureUpdatesStartTime", "PauseQualityUpdatesStartTime") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"; Names = @("PreventDeviceMetadataFromNetwork") },
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"; Names = @("DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled") },
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"; Names = @("DODownloadMode") }
        )
        foreach ($entry in $registryCleanup) {
            foreach ($n in $entry.Names) {
                Remove-ItemProperty -Path $entry.Path -Name $n -ErrorAction SilentlyContinue
            }
        }

        Clear-WindowsUpdateSystemDenyAcl

        Set-Service -Name "BITS" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
        Set-Service -Name "UsoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "UsoSvc" -ErrorAction SilentlyContinue
        try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Type DWord -Value 3 -ErrorAction SilentlyContinue } catch {}
        Enable-WindowsUpdateScheduledTasks

        Write-ToolLog "Windows Update restaurado para o padrão original da Microsoft." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao restaurar Windows Update: $_" "ERROR"
    }
}

function Disable-WindowsUpdateAll {
    Write-ToolLog "Desativando completamente serviços e políticas do Windows Update..." "INFO"
    try {
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
        Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Type DWord -Value 1 -Force
        Set-ItemProperty -Path $auPath -Name "AUOptions" -Type DWord -Value 1 -Force

        $doPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
        if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
        Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Type DWord -Value 0 -Force

        foreach ($svc in @("BITS", "wuauserv", "UsoSvc")) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-ToolLog "Serviço [$svc] parado e desativado." "INFO"
        }

        Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue

        $tasks = @(
            '\Microsoft\Windows\InstallService\*',
            '\Microsoft\Windows\UpdateOrchestrator\*',
            '\Microsoft\Windows\UpdateAssistant\*',
            '\Microsoft\Windows\WaaSMedic\*',
            '\Microsoft\Windows\WindowsUpdate\*',
            '\Microsoft\WindowsUpdate\*'
        )
        foreach ($t in $tasks) {
            Get-ScheduledTask -TaskPath $t -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }

        Write-ToolLog "Windows Update desativado. Reinicie o computador para consolidar." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao desativar Windows Update: $_" "ERROR"
    }
}

function Pause-WindowsUpdateExtended {
    Write-ToolLog "Pausando atualizações do Windows Update até 2042..." "INFO"
    try {
        $wuPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }

        Set-ItemProperty -Path $wuPath -Name "PauseUpdatesExpiryTime" -Value "2042-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseFeatureUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force
        Set-ItemProperty -Path $wuPath -Name "PauseQualityUpdatesStartTime" -Value "2026-01-01T00:00:00Z" -Type String -Force

        Write-ToolLog "Atualizações do Windows pausadas até 2042." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao pausar atualizações: $_" "ERROR"
    }
}


# ==============================================================================
# Módulo: Diagnóstico e Reparo do Sistema Operacional e Windows Update
# ==============================================================================

function Invoke-SfcScan {
    Write-ToolLog "Iniciando verificação de integridade dos arquivos de sistema (SFC /scannow)..." "INFO"
    try {
        $process = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "SFC: Nenhuma violação de integridade encontrada." "SUCCESS"
        } elseif ($process.ExitCode -eq 1) {
            Write-ToolLog "SFC: Arquivos corrompidos foram encontrados e corrigidos!" "SUCCESS"
        } else {
            Write-ToolLog "SFC finalizado com código $($process.ExitCode). Verifique C:\Windows\Logs\CBS\CBS.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar SFC: $_" "ERROR"
    }
}

function Invoke-DismRepair {
    Write-ToolLog "Iniciando reparo da imagem do Windows com DISM (/RestoreHealth)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "DISM: Restauração de imagem concluída com êxito." "SUCCESS"
        } else {
            Write-ToolLog "DISM finalizado com código $($process.ExitCode). Verifique C:\Windows\Logs\DISM\dism.log" "WARN"
        }
    } catch {
        Write-ToolLog "Falha ao executar DISM: $_" "ERROR"
    }
}

function Invoke-FullCorruptionRepair {
    Write-ToolLog "=== REPARO COMPLETO DE INTEGRIDADE (DISM + SFC) ===" "INFO"
    Invoke-DismRepair
    Invoke-SfcScan
    Write-ToolLog "=== REPARO COMPLETO DE INTEGRIDADE CONCLUÍDO ===" "SUCCESS"
}

function Invoke-DismCleanup {
    Write-ToolLog "Executando limpeza profunda do repositório WinSxS (/StartComponentCleanup /ResetBase)..." "INFO"
    try {
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-ToolLog "Limpeza WinSxS concluída." "SUCCESS"
        } else {
            Write-ToolLog "DISM Component Cleanup retornou código $($process.ExitCode)." "WARN"
        }
    } catch {
        Write-ToolLog "Falha na limpeza de componentes: $_" "ERROR"
    }
}

function Restart-PrintSpooler {
    Write-ToolLog "Reiniciando o Spooler de Impressão e limpando filas travadas..." "INFO"
    try {
        Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
        $spoolPath = "C:\Windows\System32\spool\PRINTERS\*"
        if (Test-Path (Split-Path $spoolPath)) {
            Remove-Item -Path $spoolPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        Start-Service -Name "Spooler" -ErrorAction SilentlyContinue
        Write-ToolLog "Fila de impressão limpa e Spooler reiniciado!" "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao reiniciar Spooler: $_" "ERROR"
    }
}

function Schedule-ChkdskOnReboot {
    Write-ToolLog "Agendando verificação de disco (CHKDSK /F) para a próxima reinicialização..." "INFO"
    try {
        $null = echo "Y" | chkdsk C: /f
        Write-ToolLog "CHKDSK agendado na unidade C:. Será executado no próximo boot." "SUCCESS"
    } catch {
        Write-ToolLog "Erro ao agendar CHKDSK: $_" "ERROR"
    }
}

function Invoke-ResetWindowsUpdateFull {
    param([bool]$Aggressive = $false)

    $modeLabel = if ($Aggressive) { "AGRESSIVO" } else { "PADRÃO" }
    Write-ToolLog "=== INICIANDO REPARO COMPLETO DO WINDOWS UPDATE ($modeLabel) ===" "INFO"

    try {
        if ($Aggressive) { Invoke-FullCorruptionRepair }

        foreach ($svc in @("BITS", "wuauserv", "appidsvc", "cryptsvc")) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }

        Remove-Item "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -Force -ErrorAction SilentlyContinue
        if ($Aggressive) {
            Rename-Item "$env:systemroot\SoftwareDistribution\DataStore" "DataStore.bak" -ErrorAction SilentlyContinue
            Rename-Item "$env:systemroot\System32\Catroot2" "catroot2.bak" -ErrorAction SilentlyContinue
        }
        Rename-Item "$env:systemroot\SoftwareDistribution\Download" "Download.bak" -ErrorAction SilentlyContinue
        Remove-Item "$env:systemroot\WindowsUpdate.log" -Force -ErrorAction SilentlyContinue

        if ($Aggressive) {
            Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "bits", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait
            Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "wuauserv", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" -Wait
        }

        $dlls = @(
            "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
            "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",
            "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll",
            "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",
            "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll",
            "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
            "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
        )
        Write-ToolLog "Re-registrando $($dlls.Count) DLLs do BITS e Windows Update..." "INFO"
        foreach ($dll in $dlls) {
            Start-Process -NoNewWindow -FilePath "regsvr32.exe" -ArgumentList "/s", (Join-Path "$env:systemroot\system32" $dll) -Wait -ErrorAction SilentlyContinue
        }

        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate") {
            foreach ($v in @("AccountDomainSid", "PingID", "SusClientId")) {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" -Name $v -ErrorAction SilentlyContinue
            }
        }

        if (Get-Command "Reset-WindowsUpdateDefault" -ErrorAction SilentlyContinue) {
            Reset-WindowsUpdateDefault
        }

        Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset" -Wait
        Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy" -Wait
        Get-BitsTransfer -ErrorAction SilentlyContinue | Remove-BitsTransfer -ErrorAction SilentlyContinue

        Set-Service -Name "BITS" -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name "BITS" -ErrorAction SilentlyContinue
        Set-Service -Name "wuauserv" -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value 3 -ErrorAction SilentlyContinue } catch {}
        Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
        Set-Service -Name "CryptSvc" -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name "CryptSvc" -ErrorAction SilentlyContinue

        try { (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow() } catch {}
        Start-Process -NoNewWindow -FilePath "wuauclt" -ArgumentList "/resetauthorization", "/detectnow" -ErrorAction SilentlyContinue

        Write-ToolLog "=== REPARO DO WINDOWS UPDATE FINALIZADO! Recomenda-se reiniciar o PC ===" "SUCCESS"
    } catch {
        Write-ToolLog "Erro no reparo do Windows Update: $($_.Exception.Message)" "ERROR"
    }
}


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
Start-Transcript -Path 'C:\Windows\Setup\Scripts\Alts-PostInstall.log' -Append -ErrorAction SilentlyContinue
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
        $postFile.SetAttribute('path', 'C:\Windows\Setup\Scripts\Alts-PostInstall.ps1')
        $postFile.InnerText = $postInstallScript
        [void]$extensions.AppendChild($postFile)
        $firstLogon.InnerText = "& 'C:\Windows\Setup\Scripts\Alts-PostInstall.ps1';`r`n`r`n$($firstLogon.InnerText.Trim())"
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
    $workDir = Join-Path $OutputIsoDir "_Alts_ISO_Work"
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
        Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel "ALTS" -Confirm:$false -ErrorAction Stop | Out-Null

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

function Update-HardwareSelectionCounter {
    $ui = $global:WinRepairUi
    if (-not $ui) { return }
    $count = @($ui.HwCheckBoxes.Values | Where-Object { $_.IsChecked }).Count
    $ui.Window.FindName("txtHwSelectedCount").Text = "Selecionados: $count"
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

    foreach ($map in @($ui.TweakCheckBoxes, $ui.ToggleBoxes, $ui.AppxCheckBoxes, $ui.FeatureCheckBoxes, $ui.HwCheckBoxes)) {
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
        Install  = @{ Title = "Catálogo de Softwares"; Sub = "Passe o mouse em qualquer software para ver descrição e instale via WinGet ou Chocolatey" }
        Tweaks   = @{ Title = "Tweaks & Perfis Recomendados"; Sub = "Escolha Desktop, Notebook ou All para pré-selecionar e revisar antes de aplicar" }
        Hardware = @{ Title = "Hardware (GPU NVIDIA/AMD & CPU AMD/Intel)"; Sub = "Detecção automática de GPU/CPU com otimizações reversíveis de latência, estabilidade e energia" }
        Appx     = @{ Title = "Gerenciador de AppX & Bloatware"; Sub = "Remova aplicativos pré-instalados do Windows ou reinstale via Microsoft Store" }
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
        @("navHardware", "Hardware (GPU & CPU)", "Otimizações específicas e reversíveis para GPUs NVIDIA/AMD e CPUs AMD/Intel com detecção automática.", "Navegação"),
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
        @("btnPreviewTweaks", "Pré-visualizar Alterações", "Exibe todas as chaves de registro, serviços e scripts que serão alterados pelos tweaks marcados.", "Simulação"),
        @("chkAutoRestorePoint", "Ponto de Restauração Automático", "Cria automaticamente um Ponto de Restauração do Windows antes de aplicar ou desfazer tweaks.", "Segurança"),
        @("chkDryRunTweaks", "Modo Simulação (Dry-Run)", "Simula a execução no console sem modificar o registro, serviços ou arquivos do sistema.", "Simulação"),
        @("btnApplyTweaks", "Aplicar Tweaks Selecionados", "Executa em segundo plano apenas as opções marcadas na lista abaixo.", "Execução"),
        @("btnUndoTweaks", "Desfazer Selecionados", "Reverte as modificações de registro/serviços das opções marcadas atualmente.", "Reverter"),
        @("btnClearTweaks", "Limpar Seleção", "Desmarca todas as caixas de Tweaks e limpa a lista de pré-visualização.", "Seleção"),
        @("btnEnableUltPerf", "Plano Desempenho Máximo", "Desbloqueia e ativa o esquema oculto Ultimate Performance (maior resposta de CPU).", "Energia"),
        @("btnDisableUltPerf", "Restaurar Planos de Energia", "Restaura os esquemas de energia padrão de fábrica do Windows.", "Energia"),
        @("btnRunOOSU", "Executar O&O ShutUp10++", "Baixa e abre a ferramenta portátil oficial O&O ShutUp10++ para ajustes extras de privacidade.", "Privacidade"),

        @("btnHwAutoSelect", "Auto-Selecionar Recomendados", "Marca automaticamente apenas as otimizações seguras compatíveis com a GPU e CPU detectadas neste computador.", "Hardware"),
        @("btnHwApply", "Aplicar Selecionados (Hardware)", "Executa as otimizações de GPU/CPU marcadas abaixo (com Ponto de Restauração automático ou Dry-Run se habilitado).", "Execução"),
        @("btnHwUndo", "Desfazer Selecionados (Hardware)", "Reverte as otimizações de GPU/CPU marcadas para os padrões do sistema/driver.", "Reverter"),
        @("btnHwClear", "Limpar Seleção (Hardware)", "Desmarca todas as opções de otimização de GPU e CPU.", "Seleção"),
        @("btnHwPreview", "Pré-visualizar Alterações (Hardware)", "Mostra as chaves de registro, serviços e comandos powercfg que serão aplicados ou revertidos.", "Simulação"),
        @("chkHwAutoRestorePoint", "Ponto de Restauração Automático (Hardware)", "Cria automaticamente um Ponto de Restauração antes de aplicar ou desfazer otimizações de hardware.", "Segurança"),
        @("chkHwDryRun", "Modo Simulação (Dry-Run - Hardware)", "Simula as otimizações de GPU/CPU e ferramentas no console sem alterar nada no sistema.", "Simulação"),
        @("btnHwToolNvCleanstall", "NVCleanstall", "Instala via WinGet (ou abre o site oficial) o NVCleanstall para instalar drivers NVIDIA sem telemetria/bloat.", "NVIDIA"),
        @("btnHwToolDdu", "Display Driver Uninstaller (DDU)", "Instala via WinGet (ou abre o site oficial) o DDU para remoção limpa de drivers de vídeo em Modo de Segurança.", "Ferramenta"),
        @("btnHwToolAfterburner", "MSI Afterburner", "Instala via WinGet (ou abre o site oficial) para controle de curva de fan, monitoramento OSD e ajuste de GPU.", "Ferramenta"),
        @("btnHwToolGpuZ", "TechPowerUp GPU-Z", "Instala via WinGet (ou abre o site oficial) para inspeção detalhada de GPU, clocks, VRAM e barramento PCIe.", "Diagnóstico"),
        @("btnHwToolCpuZ", "CPUID CPU-Z", "Instala via WinGet (ou abre o site oficial) para inspeção de CPU, cache, placa-mãe e memória RAM.", "Diagnóstico"),
        @("btnHwToolHwInfo", "HWiNFO", "Instala via WinGet (ou abre o site oficial) para monitoramento completo de temperaturas, tensões e clocks.", "Diagnóstico"),
        @("btnHwUrlNvidia", "Drivers Oficiais NVIDIA", "Abre a página oficial de download de drivers NVIDIA GeForce/RTX.", "Driver"),
        @("btnHwUrlAmd", "Drivers Oficiais AMD", "Abre a página oficial de suporte e drivers AMD Radeon e Chipset Ryzen.", "Driver"),
        @("btnHwUrlIntel", "Drivers Oficiais Intel", "Abre a página oficial de drivers e Assistente Intel (Arc / UHD / Chipset).", "Driver"),

        @("btnInstallApps", "Instalar / Atualizar Selecionados", "Instala ou atualiza todos os programas marcados usando WinGet ou Chocolatey.", "Softwares"),
        @("btnUninstallApps", "Desinstalar Selecionados", "Remove silenciosamente do sistema todos os programas marcados no catálogo.", "Softwares"),
        @("btnUpgradeAllApps", "Atualizar Todos os Apps", "Executa atualização geral de todos os programas instalados no computador.", "Softwares"),
        @("btnDetectInstalledApps", "Mostrar Instalados", "Destaca os softwares do catálogo que já estão instalados neste PC.", "Softwares"),
        @("btnClearApps", "Limpar Seleção de Apps", "Desmarca todos os checkboxes da lista de softwares.", "Seleção"),

        @("btnAppxDefault", "Marcar Bloatwares Padrão", "Marca automaticamente os 18 aplicativos pré-instalados mais comuns para remoção (apenas seleciona).", "AppX"),
        @("btnAppxSelectAll", "Marcar Todos AppX", "Marca todos os 34 pacotes AppX listados abaixo.", "AppX"),
        @("btnAppxClear", "Limpar Seleção AppX", "Desmarca todos os checkboxes de AppX.", "AppX"),
        @("btnAppxDetectInstalled", "Destacar AppX Instalados", "Verifica no sistema e destaca em destaque os AppX atualmente instalados.", "AppX"),
        @("btnAppxPreview", "Pré-visualizar Seleção AppX", "Lista todos os pacotes AppX selecionados e seus PackageId/StoreId antes de remover.", "Simulação"),
        @("chkAppxAutoRestorePoint", "Ponto de Restauração Automático (AppX)", "Cria automaticamente um Ponto de Restauração antes de remover aplicativos nativos AppX.", "Segurança"),
        @("chkDryRunAppx", "Modo Simulação AppX (Dry-Run)", "Simula remoção ou reinstalação de AppX sem modificar nenhum pacote no sistema.", "Simulação"),
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

function Show-PreviewDialog {
    param(
        [string]$Title = "Pré-visualização de Alterações",
        [string]$Subtitle = "",
        [string]$BodyText = ""
    )

    $ui = $global:WinRepairUi
    $owner = if ($ui -and $ui.Window) { $ui.Window } else { $null }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = $Title
    $dlg.Width = 780
    $dlg.Height = 540
    $dlg.MinWidth = 560
    $dlg.MinHeight = 380
    $dlg.WindowStartupLocation = if ($owner) { [System.Windows.WindowStartupLocation]::CenterOwner } else { [System.Windows.WindowStartupLocation]::CenterScreen }
    if ($owner) {
        $dlg.Owner = $owner
        foreach ($resKey in @("BrushBgApp", "BrushBgSurface", "BrushBgCardAlt", "BrushBorder", "BrushBorderStrong", "BrushTextPrimary", "BrushTextSecondary", "BrushTextMuted", "BrushAccent", "BrushAccentHover", "BrushAccentText", "BrushConsoleBg", "BrushConsoleFg")) {
            if ($owner.Resources.Contains($resKey)) {
                $dlg.Resources[$resKey] = $owner.Resources[$resKey]
            }
        }
    }
    $dlg.SetResourceReference([System.Windows.Window]::BackgroundProperty, "BrushBgApp")
    $dlg.SetResourceReference([System.Windows.Window]::ForegroundProperty, "BrushTextPrimary")

    $root = New-Object System.Windows.Controls.Grid
    $root.Margin = New-Object System.Windows.Thickness(14)
    $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
    $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = [System.Windows.GridLength]::Auto
    [void]$root.RowDefinitions.Add($r0)
    [void]$root.RowDefinitions.Add($r1)
    [void]$root.RowDefinitions.Add($r2)

    $hdr = New-Object System.Windows.Controls.StackPanel
    $hdr.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $tTitle = New-Object System.Windows.Controls.TextBlock
    $tTitle.Text = $Title
    $tTitle.FontSize = 15.5
    $tTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $tTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextSecondary")
    [void]$hdr.Children.Add($tTitle)

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $tSub = New-Object System.Windows.Controls.TextBlock
        $tSub.Text = $Subtitle
        $tSub.FontSize = 11.5
        $tSub.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        $tSub.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextMuted")
        [void]$hdr.Children.Add($tSub)
    }
    [System.Windows.Controls.Grid]::SetRow($hdr, 0)
    [void]$root.Children.Add($hdr)

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $border.BorderThickness = New-Object System.Windows.Thickness(1)
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushConsoleBg")
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderProperty, "BrushBorderStrong")

    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $BodyText
    $tb.IsReadOnly = $true
    $tb.AcceptsReturn = $true
    $tb.TextWrapping = [System.Windows.TextWrapping]::NoWrap
    $tb.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $tb.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas, Courier New")
    $tb.FontSize = 12
    $tb.Padding = New-Object System.Windows.Thickness(10)
    $tb.BorderThickness = New-Object System.Windows.Thickness(0)
    $tb.SetResourceReference([System.Windows.Controls.TextBox]::BackgroundProperty, "BrushConsoleBg")
    $tb.SetResourceReference([System.Windows.Controls.TextBox]::ForegroundProperty, "BrushConsoleFg")
    $border.Child = $tb
    [System.Windows.Controls.Grid]::SetRow($border, 1)
    [void]$root.Children.Add($border)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $btnPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnPanel.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)

    $btnCopy = New-Object System.Windows.Controls.Button
    $btnCopy.Content = "Copiar"
    $btnCopy.Padding = New-Object System.Windows.Thickness(14, 6, 14, 6)
    $btnCopy.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $btnCopy.Add_Click({
        if ($tb.Text) { [System.Windows.Clipboard]::SetText($tb.Text) }
    })

    $btnClose = New-Object System.Windows.Controls.Button
    $btnClose.Content = "Fechar"
    $btnClose.Padding = New-Object System.Windows.Thickness(16, 6, 16, 6)
    $btnClose.Add_Click({ $dlg.Close() })

    [void]$btnPanel.Children.Add($btnCopy)
    [void]$btnPanel.Children.Add($btnClose)
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 2)
    [void]$root.Children.Add($btnPanel)

    $dlg.Content = $root
    $dlg.ShowDialog() | Out-Null
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
            Install  = $window.FindName("viewInstall")
            Tweaks   = $window.FindName("viewTweaks")
            Hardware = $window.FindName("viewHardware")
            Appx     = $window.FindName("viewAppx")
            Network  = $window.FindName("viewNetwork")
            Config   = $window.FindName("viewConfig")
            Updates  = $window.FindName("viewUpdates")
            Iso      = $window.FindName("viewIso")
        }
        AppCheckBoxes        = [ordered]@{}
        AppCategoryExpanders = New-Object System.Collections.Generic.List[object]
        SelectedAppCategory  = "Todas"
        TweakCheckBoxes      = [ordered]@{}
        HwCheckBoxes         = [ordered]@{}
        HwProfile            = $null
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

    # 6. HARDWARE (GPU NVIDIA/AMD & CPU AMD/INTEL)
    $hwProfile = Get-HardwareOptimizationProfile
    $global:WinRepairUi.HwProfile = $hwProfile
    $window.FindName("txtHwDetectedGpu").Text = "GPU: $($hwProfile.PrimaryGpuName)"
    $window.FindName("txtHwDetectedCpu").Text = "CPU: $($hwProfile.CpuName) ($($hwProfile.CpuCores)C/$($hwProfile.CpuThreads)T)"
    $window.FindName("txtHwDetectedTips").Text = $hwProfile.SummaryTips

    $badgeConfig = @(
        @{ Badge = "txtHwNvidiaBadge";   Border = "borderHwNvidia";   Detected = $hwProfile.HasNvidia },
        @{ Badge = "txtHwAmdGpuBadge";   Border = "borderHwAmdGpu";   Detected = $hwProfile.HasAmdGpu },
        @{ Badge = "txtHwAmdCpuBadge";   Border = "borderHwAmdCpu";   Detected = ($hwProfile.CpuVendor -eq "AMD") },
        @{ Badge = "txtHwIntelCpuBadge"; Border = "borderHwIntelCpu"; Detected = ($hwProfile.CpuVendor -eq "Intel") }
    )
    foreach ($bc in $badgeConfig) {
        $bTxt = $window.FindName($bc.Badge)
        $bBrd = $window.FindName($bc.Border)
        if ($bc.Detected) {
            if ($bTxt) {
                $bTxt.Text = "Detectado"
                $bTxt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushSuccess")
            }
            if ($bBrd) {
                $bBrd.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushBorderStrong")
            }
        } else {
            if ($bTxt) {
                $bTxt.Text = "Não detectado"
                $bTxt.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushTextMuted")
            }
        }
    }

    $hwGroupPanels = @{
        GpuGeneral = $window.FindName("panelHwGpuGeneral")
        GpuNvidia  = $window.FindName("panelHwGpuNvidia")
        GpuAmd     = $window.FindName("panelHwGpuAmd")
        CpuGeneral = $window.FindName("panelHwCpuGeneral")
        CpuAmd     = $window.FindName("panelHwCpuAmd")
        CpuIntel   = $window.FindName("panelHwCpuIntel")
    }
    foreach ($hwItem in (Get-HardwareOptimizationCatalog)) {
        $targetPanel = $hwGroupPanels[$hwItem.Group]
        if (-not $targetPanel) { continue }
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $hwItem.Content
        $cb.Tag = $hwItem.Key
        Register-HoverHelp -Control $cb -Title $hwItem.Content -Description $hwItem.Description -Badge $hwItem.Risk
        $cb.Add_Checked({ Update-HardwareSelectionCounter })
        $cb.Add_Unchecked({ Update-HardwareSelectionCounter })
        [void]$targetPanel.Children.Add($cb)
        $global:WinRepairUi.HwCheckBoxes[$hwItem.Key] = $cb
    }
    Update-HardwareSelectionCounter

    # Hover help em todos os botões e elementos estáticos
    Initialize-StaticHoverHelp

    # ==========================================================================
    # VINCULAÇÃO DE EVENTOS PRINCIPAIS
    # ==========================================================================

    $window.FindName("navInstall").Add_Checked({ Set-ActiveHudView "Install" })
    $window.FindName("navTweaks").Add_Checked({ Set-ActiveHudView "Tweaks" })
    $window.FindName("navHardware").Add_Checked({ Set-ActiveHudView "Hardware" })
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
        $dlg.FileName = "alt_tweaks_config.json"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $keys = New-Object System.Collections.Generic.List[string]
            foreach ($map in @($global:WinRepairUi.TweakCheckBoxes, $global:WinRepairUi.HwCheckBoxes, $global:WinRepairUi.AppCheckBoxes, $global:WinRepairUi.AppxCheckBoxes, $global:WinRepairUi.FeatureCheckBoxes)) {
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
                    foreach ($map in @($global:WinRepairUi.TweakCheckBoxes, $global:WinRepairUi.HwCheckBoxes, $global:WinRepairUi.AppCheckBoxes, $global:WinRepairUi.AppxCheckBoxes, $global:WinRepairUi.FeatureCheckBoxes)) {
                        foreach ($k in $map.Keys) { $map[$k].IsChecked = $flat.Contains($k) }
                    }
                } finally {
                    $global:WinRepairUi.SuppressPresetReset = $false
                }

                $global:WinRepairUi.ActivePreset = "Importado"
                Update-TweaksSelectionPreview
                Update-HardwareSelectionCounter
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
        $dlg.FileName = "alt_tweaks_logs_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"
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

    $window.FindName("btnPreviewTweaks").Add_Click({
        $ui = $global:WinRepairUi
        $selected = @(foreach ($k in $ui.TweakCheckBoxes.Keys) {
            if ($ui.TweakCheckBoxes[$k].IsChecked) {
                [pscustomobject]@{ Key = $k; Obj = $global:WinRepairSync.Configs.Tweaks.$k }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Nenhuma opção marcada para pré-visualizar." "WARN"; return }
        $previewText = Format-TweakChangesPreviewText -SelectedTweaks $selected
        Write-ToolLog "Pré-visualização gerada para $($selected.Count) tweak(s) selecionado(s)." "INFO"
        Show-PreviewDialog -Title "Pré-visualização de Tweaks ($($selected.Count))" -Subtitle "Revise abaixo as chaves de registro, serviços e scripts antes de aplicar." -BodyText $previewText
    })

    $window.FindName("btnApplyTweaks").Add_Click({
        $ui = $global:WinRepairUi
        $selected = @(foreach ($k in $ui.TweakCheckBoxes.Keys) {
            if ($ui.TweakCheckBoxes[$k].IsChecked) {
                [pscustomobject]@{ Key = $k; Obj = $global:WinRepairSync.Configs.Tweaks.$k }
            }
        })
        if ($selected.Count -eq 0) { Write-ToolLog "Nenhuma opção marcada para aplicar." "WARN"; return }

        $dryRun = [bool]$ui.Window.FindName("chkDryRunTweaks").IsChecked
        $autoRestore = [bool]$ui.Window.FindName("chkAutoRestorePoint").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }

        Start-AsyncAction -Label "${modeTag}Aplicando $($selected.Count) tweak(s)..." -Vars @{ selected = $selected; dryRun = $dryRun; autoRestore = $autoRestore } -Action {
            $prefix = if ($dryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "=== ${prefix}INICIANDO APLICAÇÃO DE $($selected.Count) TWEAK(S) SELECIONADO(S) ===" "INFO"
            if ($autoRestore) {
                $hasRestoreTweak = @($selected | Where-Object { $_.Key -eq "WPFTweaksRestorePoint" }).Count -gt 0
                if ($hasRestoreTweak) {
                    Write-ToolLog "${prefix}Ponto de Restauração já incluído na seleção atual." "INFO"
                } else {
                    $null = Set-RestorePoint -Description "AltTweaks_PreTweaks" -DryRun:$dryRun
                }
            }
            foreach ($s in $selected) {
                Invoke-DeclarativeTweak -TweakKey $s.Key -TweakObj $s.Obj -Undo:$false -DryRun:$dryRun
            }
            if ($dryRun) {
                Write-ToolLog "=== [DRY-RUN] SIMULAÇÃO CONCLUÍDA! Nenhuma alteração foi feita no sistema. ===" "SUCCESS"
            } else {
                Write-ToolLog "=== TODOS OS TWEAKS SELECIONADOS FORAM APLICADOS! ===" "SUCCESS"
            }
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

        $dryRun = [bool]$ui.Window.FindName("chkDryRunTweaks").IsChecked
        $autoRestore = [bool]$ui.Window.FindName("chkAutoRestorePoint").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }

        Start-AsyncAction -Label "${modeTag}Desfazendo $($selected.Count) tweak(s)..." -Vars @{ selected = $selected; dryRun = $dryRun; autoRestore = $autoRestore } -Action {
            $prefix = if ($dryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "=== ${prefix}DESFAZENDO $($selected.Count) TWEAK(S) SELECIONADO(S) ===" "INFO"
            if ($autoRestore) {
                $null = Set-RestorePoint -Description "AltTweaks_PreUndoTweaks" -DryRun:$dryRun
            }
            foreach ($s in $selected) {
                Invoke-DeclarativeTweak -TweakKey $s.Key -TweakObj $s.Obj -Undo:$true -DryRun:$dryRun
            }
            if ($dryRun) {
                Write-ToolLog "=== [DRY-RUN] SIMULAÇÃO DE REVERSÃO CONCLUÍDA! ===" "SUCCESS"
            } else {
                Write-ToolLog "=== REVERSÃO CONCLUÍDA! ===" "SUCCESS"
            }
        }
    })

    $window.FindName("btnCreateRestorePoint").Add_Click({ Start-AsyncAction -Label "Criando Ponto de Restauração..." -Action { Set-RestorePoint } })
    $window.FindName("btnEnableUltPerf").Add_Click({ Start-AsyncAction -Label "Ativando Plano Desempenho Máximo..." -Action { Set-UltimatePowerPlan -Enable } })
    $window.FindName("btnDisableUltPerf").Add_Click({ Start-AsyncAction -Label "Restaurando planos de energia..." -Action { Set-UltimatePowerPlan } })
    $window.FindName("btnRunOOSU").Add_Click({ Start-AsyncAction -Label "Baixando e iniciando O&O ShutUp10++..." -Action { Invoke-OOSU10 } })

    # --- VIEW 8: HARDWARE (GPU & CPU) ---
    $window.FindName("btnHwAutoSelect").Add_Click({
        $ui = $global:WinRepairUi
        $hw = $ui.HwProfile
        $selectedCount = 0
        foreach ($item in (Get-HardwareOptimizationCatalog)) {
            $cb = $ui.HwCheckBoxes[$item.Key]
            if (-not $cb) { continue }
            $matchVendor = switch ($item.Vendor) {
                "All"       { $true }
                "NVIDIA"    { [bool]$hw.HasNvidia }
                "AMD_GPU"   { [bool]$hw.HasAmdGpu }
                "AMD_CPU"   { $hw.CpuVendor -eq "AMD" }
                "Intel_CPU" { $hw.CpuVendor -eq "Intel" }
                default     { $false }
            }
            $isMatch = ($item.Recommended -eq $true) -and $matchVendor
            $cb.IsChecked = $isMatch
            if ($isMatch) { $selectedCount++ }
        }
        Update-HardwareSelectionCounter
        Write-ToolLog "Auto-seleção de Hardware: $selectedCount otimização(ões) recomendadas marcadas para $($hw.PrimaryGpuName) / $($hw.CpuName)." "INFO"
    })

    $window.FindName("btnHwClear").Add_Click({
        foreach ($cb in $global:WinRepairUi.HwCheckBoxes.Values) { $cb.IsChecked = $false }
        Update-HardwareSelectionCounter
    })

    $window.FindName("btnHwPreview").Add_Click({
        $ui = $global:WinRepairUi
        $keys = @(foreach ($k in $ui.HwCheckBoxes.Keys) { if ($ui.HwCheckBoxes[$k].IsChecked) { $k } })
        if ($keys.Count -eq 0) { Write-ToolLog "Nenhuma otimização de hardware selecionada para pré-visualizar." "WARN"; return }
        $previewText = Format-HardwareChangesPreviewText -Keys $keys
        Write-ToolLog "Pré-visualização de hardware gerada para $($keys.Count) item(ns)." "INFO"
        Show-PreviewDialog -Title "Pré-visualização de Hardware ($($keys.Count))" -Subtitle "Revise os ajustes de GPU e CPU antes de aplicar." -BodyText $previewText
    })

    $window.FindName("btnHwApply").Add_Click({
        $ui = $global:WinRepairUi
        $keys = @(foreach ($k in $ui.HwCheckBoxes.Keys) { if ($ui.HwCheckBoxes[$k].IsChecked) { $k } })
        if ($keys.Count -eq 0) { Write-ToolLog "Nenhuma otimização de hardware selecionada para aplicar." "WARN"; return }

        $dryRun = [bool]$ui.Window.FindName("chkHwDryRun").IsChecked
        $autoRestore = [bool]$ui.Window.FindName("chkHwAutoRestorePoint").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }

        Start-AsyncAction -Label "${modeTag}Aplicando $($keys.Count) otimização(ões) de hardware..." -Vars @{ keys = $keys; dryRun = $dryRun; autoRestore = $autoRestore } -Action {
            $prefix = if ($dryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "=== ${prefix}INICIANDO OTIMIZAÇÕES DE HARDWARE ($($keys.Count)) ===" "INFO"
            if ($autoRestore) {
                $null = Set-RestorePoint -Description "AltTweaks_PreHardware" -DryRun:$dryRun
            }
            foreach ($k in $keys) {
                Invoke-HardwareOptimization -Key $k -Undo:$false -DryRun:$dryRun
            }
            if ($dryRun) {
                Write-ToolLog "=== [DRY-RUN] SIMULAÇÃO DE HARDWARE CONCLUÍDA! ===" "SUCCESS"
            } else {
                Write-ToolLog "=== OTIMIZAÇÕES DE HARDWARE APLICADAS! Alguns ajustes exigem reinício. ===" "SUCCESS"
            }
        }
    })

    $window.FindName("btnHwUndo").Add_Click({
        $ui = $global:WinRepairUi
        $keys = @(foreach ($k in $ui.HwCheckBoxes.Keys) { if ($ui.HwCheckBoxes[$k].IsChecked) { $k } })
        if ($keys.Count -eq 0) { Write-ToolLog "Nenhuma otimização de hardware selecionada para desfazer." "WARN"; return }

        $dryRun = [bool]$ui.Window.FindName("chkHwDryRun").IsChecked
        $autoRestore = [bool]$ui.Window.FindName("chkHwAutoRestorePoint").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }

        Start-AsyncAction -Label "${modeTag}Desfazendo $($keys.Count) otimização(ões) de hardware..." -Vars @{ keys = $keys; dryRun = $dryRun; autoRestore = $autoRestore } -Action {
            $prefix = if ($dryRun) { "[DRY-RUN] " } else { "" }
            Write-ToolLog "=== ${prefix}REVERTENDO OTIMIZAÇÕES DE HARDWARE ($($keys.Count)) ===" "INFO"
            if ($autoRestore) {
                $null = Set-RestorePoint -Description "AltTweaks_PreUndoHardware" -DryRun:$dryRun
            }
            foreach ($k in $keys) {
                Invoke-HardwareOptimization -Key $k -Undo:$true -DryRun:$dryRun
            }
            Write-ToolLog "=== ${prefix}REVERSÃO DE HARDWARE CONCLUÍDA! ===" "SUCCESS"
        }
    })

    $hwToolButtons = @{
        btnHwToolNvCleanstall = "NVCleanstall"
        btnHwToolDdu          = "DDU"
        btnHwToolAfterburner  = "MSIAfterburner"
        btnHwToolGpuZ         = "GPUZ"
        btnHwToolCpuZ         = "CPUZ"
        btnHwToolHwInfo       = "HWiNFO"
        btnHwUrlNvidia        = "NvidiaDrivers"
        btnHwUrlAmd           = "AmdDrivers"
        btnHwUrlIntel         = "IntelDrivers"
    }
    foreach ($btnName in $hwToolButtons.Keys) {
        $btn = $window.FindName($btnName)
        if ($btn) {
            $btn.Tag = $hwToolButtons[$btnName]
            $btn.Add_Click({
                param($sender, $e)
                $tKey = [string]$sender.Tag
                $dryRun = [bool]$global:WinRepairUi.Window.FindName("chkHwDryRun").IsChecked
                Start-AsyncAction -Label "Ferramenta Hardware: $tKey..." -Vars @{ tKey = $tKey; dryRun = $dryRun } -Action {
                    Invoke-HardwareExternalTool -ToolKey $tKey -DryRun:$dryRun
                }
            })
        }
    }

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
    $window.FindName("btnAppxPreview").Add_Click({
        $ui = $global:WinRepairUi
        $entries = @(foreach ($k in $ui.AppxCheckBoxes.Keys) {
            if ($ui.AppxCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Appx.$k }
        })
        if ($entries.Count -eq 0) { Write-ToolLog "Nenhum pacote AppX selecionado para pré-visualizar." "WARN"; return }
        $previewText = Format-AppxChangesPreviewText -Entries $entries -Action "Remove"
        Write-ToolLog "Pré-visualização gerada para $($entries.Count) pacote(s) AppX." "INFO"
        Show-PreviewDialog -Title "Pré-visualização de AppX ($($entries.Count))" -Subtitle "Confira os pacotes que serão afetados antes de remover ou reinstalar." -BodyText $previewText
    })
    $window.FindName("btnAppxRemove").Add_Click({
        $ui = $global:WinRepairUi
        $entries = @(foreach ($k in $ui.AppxCheckBoxes.Keys) {
            if ($ui.AppxCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Appx.$k }
        })
        if ($entries.Count -eq 0) { Write-ToolLog "Nenhum pacote AppX selecionado para remover." "WARN"; return }
        $dryRun = [bool]$ui.Window.FindName("chkDryRunAppx").IsChecked
        $autoRestore = [bool]$ui.Window.FindName("chkAppxAutoRestorePoint").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }
        Start-AsyncAction -Label "${modeTag}Removendo $($entries.Count) AppX..." -Vars @{ entries = $entries; dryRun = $dryRun; autoRestore = $autoRestore } -Action {
            if ($autoRestore) {
                $null = Set-RestorePoint -Description "AltTweaks_PreAppxRemove" -DryRun:$dryRun
            }
            Remove-SelectedAppxPackages -Entries $entries -DryRun:$dryRun
        }
    })
    $window.FindName("btnAppxInstall").Add_Click({
        $ui = $global:WinRepairUi
        $entries = @(foreach ($k in $ui.AppxCheckBoxes.Keys) {
            if ($ui.AppxCheckBoxes[$k].IsChecked) { $global:WinRepairSync.Configs.Appx.$k }
        })
        if ($entries.Count -eq 0) { Write-ToolLog "Nenhum pacote AppX selecionado para reinstalar." "WARN"; return }
        $dryRun = [bool]$ui.Window.FindName("chkDryRunAppx").IsChecked
        $modeTag = if ($dryRun) { "[DRY-RUN] " } else { "" }
        Start-AsyncAction -Label "${modeTag}Reinstalando $($entries.Count) AppX via Store..." -Vars @{ entries = $entries; dryRun = $dryRun } -Action {
            Install-SelectedAppxPackages -Entries $entries -DryRun:$dryRun
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

    Write-ToolLog "Alt Tweaks v3.1 carregado com sucesso!" "SUCCESS"
    Write-ToolLog "Passe o mouse em qualquer opção para ler o resumo instantâneo antes de executar." "INFO"

    $window.Add_Closed({ $uiTimer.Stop() })
    $window.ShowDialog() | Out-Null
}


# 1. Garantir privilégios de Administrador
if (-not (Test-IsAdmin)) {
    Ensure-AdminPrivileges
    return
}

# 2. Carregar configurações e templates embutidos
$embeddedConfigs = @{
    Applications = @'
{"1password":{"category":"Utilities","choco":"1password","content":"1Password","description":"1Password is a password manager that allows you to store and manage your passwords securely.","link":"https://1password.com/","winget":"AgileBits.1Password","foss":false},"7zip":{"category":"Utilities","choco":"7zip","content":"7-Zip","description":"7-Zip is a free and open-source file archiver utility. It supports several compression formats and provides a high compression ratio, making it a popular choice for file compression.","link":"https://www.7-zip.org/","winget":"7zip.7zip","foss":true},"abdownloadmanager":{"category":"Utilities","choco":"ab-download-manager","content":"AB Download Manager","description":"AB Download Manager is an open-source download accelerator and manager with multi-threaded downloads, queue scheduling, speed limiting, and browser integration.","link":"https://abdownloadmanager.com/","winget":"amir1376.ABDownloadManager","foss":true},"adobe":{"category":"Document","choco":"adobereader","content":"Adobe Acrobat Reader","description":"Adobe Acrobat Reader is a free PDF viewer with essential features for viewing, printing, and annotating PDF documents.","link":"https://www.adobe.com/acrobat/pdf-reader.html","winget":"Adobe.Acrobat.Reader.64-bit","foss":false},"advancedip":{"category":"Pro Tools","choco":"advanced-ip-scanner","content":"Advanced IP Scanner","description":"Advanced IP Scanner is a fast and easy-to-use network scanner. It is designed to analyze LAN networks and provides information about connected devices.","link":"https://www.advanced-ip-scanner.com/","winget":"Famatech.AdvancedIPScanner","foss":false},"aimp":{"category":"Multimedia Tools","choco":"aimp","content":"AIMP (Music Player)","description":"AIMP is a feature-rich music player with support for various audio formats, playlists, and customizable user interface.","link":"https://www.aimp.ru/","winget":"AIMP.AIMP","foss":false},"angryipscanner":{"category":"Pro Tools","choco":"angryip","content":"Angry IP Scanner","description":"Angry IP Scanner is an open-source and cross-platform network scanner. It is used to scan IP addresses and ports, providing information about network connectivity.","link":"https://angryip.org/","winget":"angryziber.AngryIPScanner","foss":true},"anydesk":{"category":"Utilities","choco":"anydesk","content":"AnyDesk","description":"AnyDesk is a remote desktop software that enables users to access and control computers remotely. It is known for its fast connection and low latency.","link":"https://anydesk.com/","winget":"AnyDesk.AnyDesk","foss":false},"audacity":{"category":"Multimedia Tools","choco":"audacity","content":"Audacity","description":"Audacity is a free and open-source audio editing software known for its powerful recording and editing capabilities.","link":"https://www.audacityteam.org/","winget":"Audacity.Audacity","foss":true},"autoruns":{"category":"Microsoft Tools","choco":"autoruns","content":"Autoruns","description":"This utility shows you what programs are configured to run during system bootup or login.","link":"https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns","winget":"Microsoft.Sysinternals.Autoruns","foss":false},"rdcman":{"category":"Microsoft Tools","choco":"rdcman","content":"RDCMan","description":"RDCMan manages multiple remote desktop connections. It is useful for managing server labs where you need regular access to each machine such as automated checkin systems and data centers.","link":"https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman","winget":"Microsoft.Sysinternals.RDCMan","foss":false},"autohotkey":{"category":"Utilities","choco":"autohotkey","content":"AutoHotkey","description":"AutoHotkey is a scripting language for Windows that allows users to create custom automation scripts and macros. It is often used for automating repetitive tasks and customizing keyboard shortcuts.","link":"https://www.autohotkey.com/","winget":"AutoHotkey.AutoHotkey","foss":true},"battlenet":{"category":"Games","choco":"na","winget":"Blizzard.BattleNet","content":"Battle.net","description":"Battle.net is a launcher for games created and developed by Activision Blizzard","link":"https://battle.net","foss":false},"bitwarden":{"category":"Utilities","choco":"bitwarden","content":"Bitwarden","description":"Bitwarden is an open-source password management solution. It allows users to store and manage their passwords in a secure and encrypted vault, accessible across multiple devices.","link":"https://bitwarden.com/","winget":"Bitwarden.Bitwarden","foss":true},"blender":{"category":"Multimedia Tools","choco":"blender","content":"Blender (3D Graphics)","description":"Blender is a powerful open-source 3D creation suite, offering modeling, sculpting, animation, and rendering tools.","link":"https://www.blender.org/","winget":"BlenderFoundation.Blender","foss":true},"brave":{"category":"Browsers","choco":"brave","content":"Brave","description":"Brave is a privacy-focused web browser that blocks ads and trackers, offering a faster and safer browsing experience.","link":"https://www.brave.com","winget":"Brave.Brave","foss":true},"bruno":{"category":"Development","choco":"bruno","content":"Bruno","description":"Bruno is a local-first API client that stores collections as plain text files for version control and collaboration.","link":"https://www.usebruno.com/","winget":"Bruno.Bruno","foss":true},"bulkcrapuninstaller":{"category":"Utilities","choco":"bulk-crap-uninstaller","content":"Bulk Crap Uninstaller","description":"Bulk Crap Uninstaller is a free and open-source uninstaller utility for Windows. It helps users remove unwanted programs and clean up their system by uninstalling multiple applications at once.","link":"https://www.bcuninstaller.com/","winget":"Klocman.BulkCrapUninstaller","foss":true},"blurautoclicker":{"category":"Utilities","choco":"na","content":"BlurAutoClicker","description":"An Auto-clicker with a few advanced features and generally better performance than popular alternatives.","link":"https://blur009.vercel.app/projects/blur-autoclicker/","winget":"Blur009.BlurAutoClicker","foss":true},"calibre":{"category":"Multimedia Tools","choco":"calibre","content":"Calibre","description":"Calibre is a powerful and easy-to-use e-book manager, viewer, and converter.","link":"https://calibre-ebook.com/","winget":"calibre.calibre","foss":true},"cemu":{"category":"Games","choco":"cemu","content":"Cemu","description":"Cemu is a highly experimental software to emulate Wii U applications on PC.","link":"https://cemu.info/","winget":"Cemu.Cemu","foss":true},"chatgpt":{"category":"Development","choco":"na","content":"ChatGPT Desktop","description":"The official ChatGPT desktop app for Windows, distributed through the Microsoft Store.","link":"https://openai.com/chatgpt/download/","winget":"msstore:9NT1R1C2HH7J","foss":false},"chatterino":{"category":"Communications","choco":"chatterino","content":"Chatterino","description":"Chatterino is a chat client for Twitch chat that offers a clean and customizable interface for a better streaming experience.","link":"https://www.chatterino.com/","winget":"ChatterinoTeam.Chatterino","foss":true},"chrome":{"category":"Browsers","choco":"googlechrome","content":"Chrome","description":"Google Chrome is a widely used web browser known for its speed, simplicity, and seamless integration with Google services.","link":"https://www.google.com/chrome/","winget":"Google.Chrome","foss":false},"chromium":{"category":"Browsers","choco":"chromium","content":"Chromium","description":"Chromium is the open-source project that serves as the foundation for various web browsers, including Chrome.","link":"https://www.chromium.org/","winget":"Hibbiki.Chromium","foss":true},"cinebenchr23":{"category":"Pro Tools","choco":"na","content":"Cinebench R23","description":"Cinebench R23 is a benchmark tool for comparing CPU rendering performance across systems.","link":"https://www.maxon.net/en/cinebench","winget":"Maxon.CinebenchR23","foss":false},"claude":{"category":"Development","choco":"claude","content":"Claude Desktop","description":"Anthropic\u0027s Claude desktop application for focused AI-assisted work and chat.","link":"https://claude.ai/download","winget":"Anthropic.Claude","foss":false},"claude-code":{"category":"Development","choco":"claude-code","content":"Claude Code","description":"Anthropic\u0027s agentic coding tool for terminal and IDE development workflows.","link":"https://code.claude.com/","winget":"Anthropic.ClaudeCode","foss":false},"cmake":{"category":"Development","choco":"cmake","content":"CMake","description":"CMake is an open-source, cross-platform family of tools designed to build, test and package software.","link":"https://cmake.org/","winget":"Kitware.CMake","foss":true},"codex":{"category":"Development","choco":"codex","content":"Codex","description":"Codex CLI is an OpenAI coding agent that runs locally in your terminal.","link":"https://developers.openai.com/codex/cli","winget":"OpenAI.Codex","foss":true},"cpuz":{"category":"Pro Tools","choco":"cpu-z","content":"CPU-Z","description":"CPU-Z is a system monitoring and diagnostic tool for Windows. It provides detailed information about the computer\u0027s hardware components, including the CPU, memory, and motherboard.","link":"https://www.cpuid.com/softwares/cpu-z.html","winget":"CPUID.CPU-Z","foss":false},"crystaldiskinfo":{"category":"Utilities","choco":"crystaldiskinfo","content":"Crystal Disk Info","description":"Crystal Disk Info is a disk health monitoring tool that provides information about the status and performance of hard drives. It helps users anticipate potential issues and monitor drive health.","link":"https://crystalmark.info/en/software/crystaldiskinfo/","winget":"CrystalDewWorld.CrystalDiskInfo","foss":true},"crystaldiskmark":{"category":"Utilities","choco":"crystaldiskmark","content":"Crystal Disk Mark","description":"Crystal Disk Mark is a disk benchmarking tool that measures the read and write speeds of storage devices. It helps users assess the performance of their hard drives and SSDs.","link":"https://crystalmark.info/en/software/crystaldiskmark/","winget":"CrystalDewWorld.CrystalDiskMark","foss":true},"cursor":{"category":"Development","choco":"cursoride","content":"Cursor","description":"AI-powered code editor (VS Code-based) with agentic coding features and integrated AI assistance for development workflows.","link":"https://cursor.com/","winget":"Anysphere.Cursor","foss":false},"ddu":{"category":"Pro Tools","choco":"ddu","content":"Display Driver Uninstaller","description":"Display Driver Uninstaller (DDU) is a tool for completely uninstalling graphics drivers from NVIDIA, AMD, and Intel. It is useful for troubleshooting graphics driver-related issues.","link":"https://www.wagnardsoft.com/display-driver-uninstaller-DDU-","winget":"Wagnardsoft.DisplayDriverUninstaller","foss":true},"discord":{"category":"Communications","choco":"discord","content":"Discord","description":"Discord is a popular communication platform with voice, video, and text chat, designed for gamers but used by a wide range of communities.","link":"https://discord.com/","winget":"Discord.Discord","foss":false},"dismtools":{"category":"Microsoft Tools","choco":"dismtools","content":"DISMTools","description":"DISMTools is a fast, customizable GUI for the DISM utility, supporting Windows images from Windows 7 onward. It handles installations on any drive, offers project support, and lets users tweak settings like color modes, language, and DISM versions; powered by both native DISM and a managed DISM API.","link":"https://github.com/CodingWonders/DISMTools","winget":"CodingWondersSoftware.DISMTools.Stable","foss":true},"ntlite":{"category":"Microsoft Tools","choco":"ntlite-free","content":"NTLite","description":"Integrate updates, drivers, automate Windows and application setup, speedup Windows deployment process and have it all set for the next time.","link":"https://ntlite.com","winget":"Nlitesoft.NTLite","foss":false},"dorion":{"category":"Communications","choco":"dorion","content":"Dorion","description":"Tiny alternative Discord client with a smaller footprint, snappier startup, themes, plugins and more!","link":"https://spikehd.dev/projects/dorion/","winget":"SpikeHD.Dorion","foss":true},"dockerdesktop":{"category":"Development","choco":"docker-desktop","content":"Docker Desktop","description":"Docker Desktop provides a local environment for building, running, and testing containerized applications on Windows.","link":"https://www.docker.com/products/docker-desktop/","winget":"Docker.DockerDesktop","foss":false},"dotnet6":{"category":"Microsoft Tools","choco":"dotnet-6.0-runtime","content":".NET Desktop Runtime 6","description":".NET Desktop Runtime 6 is a runtime environment required for running applications developed with .NET 6.","link":"https://dotnet.microsoft.com/download/dotnet/6.0","winget":"Microsoft.DotNet.DesktopRuntime.6","foss":true},"dotnet8":{"category":"Microsoft Tools","choco":"dotnet-8.0-runtime","content":".NET Desktop Runtime 8","description":".NET Desktop Runtime 8 is a runtime environment required for running applications developed with .NET 8.","link":"https://dotnet.microsoft.com/download/dotnet/8.0","winget":"Microsoft.DotNet.DesktopRuntime.8","foss":true},"dotnet9":{"category":"Microsoft Tools","choco":"dotnet-9.0-runtime","content":".NET Desktop Runtime 9","description":".NET Desktop Runtime 9 is a runtime environment required for running applications developed with .NET 9.","link":"https://dotnet.microsoft.com/download/dotnet/9.0","winget":"Microsoft.DotNet.DesktopRuntime.9","foss":true},"dotnet10":{"category":"Microsoft Tools","choco":"dotnet-10.0-runtime","content":".NET Desktop Runtime 10","description":".NET Desktop Runtime 10 is a runtime environment required for running applications developed with .NET 10.","link":"https://dotnet.microsoft.com/download/dotnet/10.0","winget":"Microsoft.DotNet.DesktopRuntime.10","foss":true},"dropbox":{"category":"Utilities","choco":"dropbox","content":"Dropbox","description":"Dropbox is a cloud storage client for syncing files, sharing content, and keeping documents available across devices.","link":"https://www.dropbox.com/desktop","winget":"Dropbox.Dropbox","foss":false},"eaapp":{"category":"Games","choco":"ea-app","content":"EA App","description":"EA App is a platform for accessing and playing Electronic Arts games.","link":"https://www.ea.com/ea-app","winget":"ElectronicArts.EADesktop","foss":false},"eartrumpet":{"category":"Multimedia Tools","choco":"eartrumpet","content":"EarTrumpet (Audio)","description":"EarTrumpet is an audio control app for Windows, providing a simple and intuitive interface for managing sound settings.","link":"https://eartrumpet.app/","winget":"File-New-Project.EarTrumpet","foss":true},"edge":{"category":"Browsers","choco":"microsoft-edge","content":"Edge","description":"Microsoft Edge is a modern web browser built on Chromium, offering performance, security, and integration with Microsoft services.","link":"https://www.microsoft.com/edge","winget":"Microsoft.Edge","foss":false},"es-de":{"category":"Games","choco":"","content":"EmulationStation Desktop Edition","_comment":"This and emulationstation are two completely different things. ES-DE is your frontend for everything and has its own set of emulators. Emulationstation is a graphical frontend for RetroArch.","description":"EmulationStation Desktop Edition is a frontend for browsing and launching games from your multi-platform game collection.","link":"https://es-de.org/","winget":"ES-DE.EmulationStation-DE","foss":true},"enteauth":{"category":"Utilities","choco":"ente-auth","content":"Ente Auth","description":"Ente Auth is a free, cross-platform, end-to-end encrypted authenticator app.","link":"https://ente.io/auth/","winget":"ente-io.auth-desktop","foss":true},"epicgames":{"category":"Games","choco":"epicgameslauncher","content":"Epic Games Launcher","description":"Epic Games Launcher is the client for accessing and playing games from the Epic Games Store.","link":"https://www.epicgames.com/store/en-US/","winget":"EpicGames.EpicGamesLauncher","foss":false},"files":{"category":"Utilities","choco":"files","content":"Files","description":"Alternative file explorer.","link":"https://files.community","winget":"FilesCommunity.Files","foss":true},"fileconverter":{"category":"Multimedia Tools","choco":"file-converter","content":"File Converter","description":"File Converter converts and compresses files from the Windows Explorer context menu.","link":"https://file-converter.io/","winget":"AdrienAllard.FileConverter","foss":true},"firefox":{"category":"Browsers","choco":"firefox","content":"Firefox","description":"Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions.","link":"https://www.mozilla.org/en-US/firefox/new/","winget":"Mozilla.Firefox","foss":true},"firefoxesr":{"category":"Browsers","choco":"FirefoxESR","content":"Firefox ESR","description":"Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions. Firefox ESR (Extended Support Release) receives major updates every 42 weeks with minor updates such as crash fixes, security fixes and policy updates as needed, but at least every four weeks.","link":"https://www.mozilla.org/en-US/firefox/enterprise/","winget":"Mozilla.Firefox.ESR","foss":true},"floorp":{"category":"Browsers","choco":"floorp","content":"Floorp","description":"Floorp is an open-source web browser project that aims to provide a simple and fast browsing experience.","link":"https://floorp.app/","winget":"Ablaze.Floorp","foss":true},"flux":{"category":"Utilities","choco":"f.lux","content":"F.lux","description":"f.lux adjusts the color temperature of your screen to reduce eye strain during nighttime use.","link":"https://justgetflux.com/","winget":"flux.flux","foss":false},"foobar":{"category":"Multimedia Tools","choco":"foobar2000","content":"foobar2000 (Music Player)","description":"foobar2000 is a highly customizable and extensible music player for Windows, known for its modular design and advanced features.","link":"https://www.foobar2000.org/","winget":"PeterPawlowski.foobar2000","foss":false},"fnm":{"category":"Development","choco":"fnm","content":"Fast Node Manager","description":"Fast Node Manager (fnm) is a fast, cross-platform tool for installing and switching between Node.js versions.","link":"https://github.com/Schniz/fnm","winget":"Schniz.fnm","foss":true},"foxpdfreader":{"category":"Document","choco":"foxitreader","content":"Foxit PDF Reader","description":"Foxit PDF Reader is a free PDF viewer with a familiar ribbon-style interface.","link":"https://www.foxit.com/pdf-reader/","winget":"Foxit.FoxitReader","foss":false},"geforcenow":{"category":"Games","choco":"nvidia-geforce-now","content":"GeForce NOW","description":"GeForce NOW is a cloud gaming service that allows you to play high-quality PC games on your device.","link":"https://www.nvidia.com/en-us/geforce-now/","winget":"Nvidia.GeForceNow","foss":false},"gimp":{"category":"Multimedia Tools","choco":"gimp","content":"GIMP (Image Editor)","description":"GIMP is a versatile open-source raster graphics editor used for tasks such as photo retouching, image editing, and image composition.","link":"https://www.gimp.org/","winget":"GIMP.GIMP.3","foss":true},"git":{"category":"Development","choco":"git","content":"Git","description":"Git is a distributed version control system widely used for tracking changes in source code during software development.","link":"https://git-scm.com/","winget":"Git.Git","foss":true},"gitextensions":{"category":"Development","choco":"gitextensions","content":"Git Extensions","description":"Git Extensions is a graphical Git client for Windows with repository, history, and commit management tools.","link":"https://gitextensions.github.io/","winget":"GitExtensionsTeam.GitExtensions","foss":true},"githubcli":{"category":"Development","choco":"gh","content":"GitHub CLI","description":"GitHub CLI brings pull requests, issues, releases, and other GitHub workflows to the terminal.","link":"https://cli.github.com/","winget":"GitHub.cli","foss":true},"githubdesktop":{"category":"Development","choco":"git;github-desktop","content":"GitHub Desktop","description":"GitHub Desktop is a visual Git client that simplifies collaboration on GitHub repositories with an easy-to-use interface.","link":"https://desktop.github.com/","winget":"GitHub.GitHubDesktop","foss":true},"gog":{"category":"Games","choco":"goggalaxy","content":"GOG Galaxy","description":"GOG Galaxy is a gaming client that offers DRM-free games, additional content, and more.","link":"https://www.gog.com/galaxy","winget":"GOG.Galaxy","foss":false},"golang":{"category":"Development","choco":"golang","content":"Go","description":"Go (or Golang) is a statically typed, compiled programming language designed for simplicity, reliability, and efficiency.","link":"https://go.dev/","winget":"GoLang.Go","foss":true},"googledrive":{"category":"Utilities","choco":"googledrive","content":"Google Drive","description":"File syncing across devices all tied to your Google account.","link":"https://www.google.com/drive/","winget":"Google.GoogleDrive","foss":false},"gpuz":{"category":"Pro Tools","choco":"gpu-z","content":"GPU-Z","description":"GPU-Z provides detailed information about your graphics card and GPU.","link":"https://www.techpowerup.com/gpuz/","winget":"TechPowerUp.GPU-Z","foss":false},"gsudo":{"category":"Pro Tools","choco":"gsudo","content":"gsudo","description":"gsudo is a sudo equivalent for Windows. It allows you to run commands with elevated administrative privileges directly within the current console window.","link":"https://github.com/gerardog/gsudo","winget":"gerardog.gsudo","foss":true},"helium":{"category":"Browsers","choco":"helium","content":"Helium","description":"Private, fast, and honest web browser.","link":"https://helium.computer","winget":"ImputNet.Helium","foss":true},"hugo":{"category":"Development","choco":"hugo-extended","content":"Hugo","description":"The world\u0027s fastest framework for building websites.","link":"https://gohugo.io","winget":"Hugo.Hugo.Extended","foss":true},"handbrake":{"category":"Multimedia Tools","choco":"handbrake","content":"HandBrake","description":"HandBrake is an open-source video transcoder, allowing you to convert video from nearly any format to a selection of widely supported codecs.","link":"https://handbrake.fr/","winget":"HandBrake.HandBrake","foss":true},"heroiclauncher":{"category":"Games","choco":"heroic-games-launcher","content":"Heroic Games Launcher","description":"Heroic Games Launcher is an open-source alternative game launcher for Epic Games Store.","link":"https://heroicgameslauncher.com/","winget":"HeroicGamesLauncher.HeroicGamesLauncher","foss":true},"hwinfo":{"category":"Pro Tools","choco":"hwinfo","content":"HWiNFO","description":"HWiNFO provides comprehensive hardware information and diagnostics for Windows.","link":"https://www.hwinfo.com/","winget":"REALiX.HWiNFO","foss":false},"hwmonitor":{"category":"Pro Tools","choco":"hwmonitor","content":"HWMonitor","description":"HWMonitor is a hardware monitoring program that reads PC systems main health sensors.","link":"https://www.cpuid.com/softwares/hwmonitor.html","winget":"CPUID.HWMonitor","foss":false},"imhex":{"category":"Pro Tools","choco":"imhex","content":"ImHex","description":"ImHex is a free and open-source hex editor for reverse engineers and programmers, featuring a custom pattern language for decoding binary formats, a disassembler, and data analysis tools.","link":"https://imhex.werwolv.net/","winget":"WerWolv.ImHex","foss":true},"imageglass":{"category":"Multimedia Tools","choco":"imageglass","content":"ImageGlass (Image Viewer)","description":"ImageGlass is a versatile image viewer with support for various image formats and a focus on simplicity and speed.","link":"https://imageglass.org/","winget":"DuongDieuPhap.ImageGlass","foss":true},"internetdownloadmanager":{"category":"Utilities","choco":"internet-download-manager","content":"Internet Download Manager","description":"Internet Download Manager is a download manager for accelerating, resuming, and scheduling file downloads.","link":"https://www.internetdownloadmanager.com/","winget":"Tonec.InternetDownloadManager","foss":false},"irfanview":{"category":"Multimedia Tools","choco":"irfanview","content":"IrfanView","description":"IrfanView is a lightweight, fast, and free image viewer and editor. Supports multiple formats, batch processing, and powerful plugins.","link":"https://irfanview.com/","winget":"IrfanSkiljan.IrfanView","foss":false},"itch":{"category":"Games","choco":"itch","content":"Itch.io","description":"Itch.io is a digital distribution platform for indie games and creative projects.","link":"https://itch.io/","winget":"ItchIo.Itch","foss":true},"itunes":{"category":"Multimedia Tools","choco":"itunes","content":"iTunes","description":"iTunes is a media player, media library, and online radio broadcaster application developed by Apple Inc.","link":"https://www.apple.com/itunes/","winget":"Apple.iTunes","foss":false},"java8":{"category":"Development","choco":"corretto8jdk","content":"Amazon Corretto 8 (LTS)","description":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","link":"https://aws.amazon.com/corretto","winget":"Amazon.Corretto.8.JDK","foss":true},"java21":{"category":"Development","choco":"corretto21jdk","content":"Amazon Corretto 21 (LTS)","description":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","link":"https://aws.amazon.com/corretto","winget":"Amazon.Corretto.21.JDK","foss":true},"java25":{"category":"Development","choco":"corretto25jdk","content":"Amazon Corretto 25 (LTS)","description":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","link":"https://aws.amazon.com/corretto","winget":"Amazon.Corretto.25.JDK","foss":true},"jellyfinmediaplayer":{"category":"Selfhosted Tools","choco":"jellyfin-media-player","content":"Jellyfin Media Player","description":"Jellyfin Media Player is a client application for the Jellyfin media server, providing access to your media library.","link":"https://jellyfin.org/","winget":"Jellyfin.JellyfinMediaPlayer","foss":true},"jellyfinserver":{"category":"Selfhosted Tools","choco":"jellyfin","content":"Jellyfin Server","description":"Jellyfin Server is an open-source media server software, allowing you to organize and stream your media library.","link":"https://jellyfin.org/","winget":"Jellyfin.Server","foss":true},"jetbrains":{"category":"Development","choco":"jetbrainstoolbox","content":"Jetbrains Toolbox","description":"Jetbrains Toolbox is a platform for easy installation and management of JetBrains developer tools.","link":"https://www.jetbrains.com/toolbox/","winget":"JetBrains.Toolbox","foss":false},"jpegview":{"category":"Utilities","choco":"jpegview","content":"JPEG View","description":"JPEGView is a lean, fast and highly configurable viewer/editor for JPEG, BMP, PNG, WEBP, TGA, GIF, JXL, HEIC, HEIF, AVIF, and TIFF images with a minimal GUI.","link":"https://github.com/sylikc/jpegview","winget":"sylikc.JPEGView","foss":true},"joplin":{"category":"Document","choco":"joplin","content":"Joplin","description":"Joplin is an open-source note-taking and to-do application with synchronization capabilities.","link":"https://joplinapp.org/","winget":"Joplin.Joplin","foss":true},"keepassxc":{"category":"Utilities","choco":"keepassxc","content":"KeePassXC","description":"KeePassXC is a modern, secure, and open-source password manager that stores and manages your most sensitive information. You can run KeePassXC on Windows, macOS, and Linux systems. KeePassXC is for people with extremely high demands of secure personal data management. It saves many different types of information, such as usernames, passwords, URLs, attachments, and notes in an offline, encrypted file that can be stored in any location, including private and public cloud solutions. For easy identification and management, user-defined titles and icons can be specified for entries. In addition, entries are sorted into customizable groups. An integrated search function allows you to use advanced patterns to easily find any entry in your database. A customizable, fast, and easy-to-use password generator utility allows you to create passwords with any combination of characters or easy to remember passphrases.","link":"https://keepassxc.org/","winget":"KeePassXCTeam.KeePassXC","foss":true},"klite":{"category":"Multimedia Tools","choco":"k-litecodecpack-standard","content":"K-Lite Codec Standard","description":"K-Lite Codec Pack Standard is a collection of audio and video codecs and related tools, providing essential components for media playback.","link":"https://www.codecguide.com/","winget":"CodecGuide.K-LiteCodecPack.Standard","foss":false},"kodi":{"category":"Selfhosted Tools","choco":"kodi","content":"Kodi Media Center","description":"Kodi is an open-source media center application that allows you to play and view most videos, music, podcasts, and other digital media files.","link":"https://kodi.tv/","winget":"XBMCFoundation.Kodi","foss":true},"lazygit":{"category":"Development","choco":"lazygit","content":"Lazygit","description":"Simple terminal UI for git commands.","link":"https://github.com/jesseduffield/lazygit/","winget":"JesseDuffield.lazygit","foss":true},"libreoffice":{"category":"Document","choco":"libreoffice-fresh","content":"LibreOffice","description":"LibreOffice is a powerful and free office suite, compatible with other major office suites.","link":"https://www.libreoffice.org/","winget":"TheDocumentFoundation.LibreOffice","foss":true},"librewolf":{"category":"Browsers","choco":"librewolf","content":"LibreWolf","description":"LibreWolf is a privacy-focused web browser based on Firefox, with additional privacy and security enhancements.","link":"https://librewolf.net/","winget":"LibreWolf.LibreWolf","foss":true},"localsend":{"category":"Selfhosted Tools","choco":"localsend.install","content":"LocalSend","description":"An open-source cross-platform alternative to AirDrop.","link":"https://localsend.org/","winget":"LocalSend.LocalSend","foss":true},"mpc-qt":{"category":"Multimedia Tools","choco":"mpc-qt","content":"mpc-qt","description":"Media Player Classic Qute Theater","link":"https://mpc-qt.github.io","winget":"mpc-qt.mpc-qt","foss":true},"mpv":{"category":"Multimedia Tools","content":"mpv","description":"mpv is a free, open source, and cross-platform media player supporting a wide variety of media formats, codecs, and subtitle types.","link":"https://mpv.io/","winget":"shinchiro.mpv","foss":true},"matrix":{"category":"Communications","choco":"element-desktop","content":"Element","description":"Element is a client for Matrix; an open network for secure, decentralized communication.","link":"https://element.io/","winget":"Element.Element","foss":true},"minitoolpartitionwizard":{"category":"Utilities","choco":"partitionwizard","content":"MiniTool Partition Wizard","description":"Comprehensive free partition manager that performs advanced operations Windows natively cannot, such as merging partitions, converting file systems, and organizing disk capacity.","link":"https://www.partitionwizard.com/","winget":"MiniTool.PartitionWizard.Free","foss":false},"modrinth":{"category":"Games","choco":"modrinth-app","content":"Modrinth App","description":"Modrinth App is a desktop application for managing Minecraft mods and modpacks.","link":"https://modrinth.com/app","winget":"Modrinth.ModrinthApp","foss":true},"moonlight":{"category":"Selfhosted Tools","choco":"moonlight-qt","content":"Moonlight/GameStream Client","description":"Moonlight/GameStream Client allows you to stream PC games to other devices over your local network.","link":"https://moonlight-stream.org/","winget":"MoonlightGameStreamingProject.Moonlight","foss":true},"mpchc":{"category":"Multimedia Tools","choco":"mpc-hc-clsid2","content":"Media Player Classic - Home Cinema","description":"Media Player Classic - Home Cinema (MPC-HC) is a free and open-source video and audio player for Windows. MPC-HC is based on the original Guliverkli project and contains many additional features and bug fixes.","link":"https://mpc-hc.org/","winget":"clsid2.mpc-hc","foss":true},"msedgeredirect":{"category":"Utilities","choco":"msedgeredirect","content":"MSEdgeRedirect","description":"A Tool to Redirect News, Search, Widgets, Weather, and More to your default browser.","link":"https://github.com/rcmaehl/MSEdgeRedirect","winget":"rcmaehl.MSEdgeRedirect","foss":true},"msiafterburner":{"category":"Pro Tools","choco":"msiafterburner","content":"MSI Afterburner","description":"MSI Afterburner is a graphics card overclocking utility with advanced features.","link":"https://www.msi.com/Landing/afterburner","winget":"Guru3D.Afterburner","foss":false},"mullvadvpn":{"category":"Pro Tools","choco":"mullvad-app","content":"Mullvad VPN","description":"This is the VPN client software for the Mullvad VPN service.","link":"https://mullvad.net/","winget":"MullvadVPN.MullvadVPN","foss":true},"mullvadbrowser":{"category":"Browsers","choco":"na","content":"Mullvad Browser","description":"Mullvad Browser is a privacy-focused web browser, developed in partnership with the Tor Project.","link":"https://mullvad.net/browser","winget":"MullvadVPN.MullvadBrowser","foss":true},"nomacs":{"category":"Multimedia Tools","choco":"nomacs","content":"nomacs","description":"nomacs is a free, open-source image viewer, which supports multiple platforms. You can use it for viewing all common image formats, including RAW and .psd images.","link":"https://nomacs.org/","winget":"nomacs.nomacs","foss":true},"nanazip":{"category":"Utilities","choco":"nanazip","content":"NanaZip","description":"NanaZip is a fast and efficient file compression and decompression tool.","link":"https://nanazip.org","winget":"M2Team.NanaZip","foss":true},"netbird":{"category":"Selfhosted Tools","choco":"netbird","content":"NetBird","description":"NetBird is an open-source alternative comparable to TailScale that can be connected to a self-hosted server.","link":"https://netbird.io/","winget":"Netbird.Netbird","foss":true},"tailscale":{"category":"Pro Tools","choco":"tailscale","content":"Tailscale","description":"The Tailscale client allows you to connect all your devices using WireGuard\u00ae, without the hassle. Tailscale makes it as easy as installing an app and signing in.","link":"https://tailscale.com/","winget":"Tailscale.Tailscale","foss":false},"naps2":{"category":"Document","choco":"naps2","content":"NAPS2 (Scanner)","description":"NAPS2 is a document scanning application that simplifies the process of creating electronic documents.","link":"https://www.naps2.com/","winget":"Cyanfish.NAPS2","foss":true},"neovim":{"category":"Development","choco":"neovim","content":"Neovim","description":"Neovim is a highly extensible text editor and an improvement over the original Vim editor.","link":"https://neovim.io/","winget":"Neovim.Neovim","foss":true},"nextclouddesktop":{"category":"Selfhosted Tools","choco":"nextcloud-client","content":"Nextcloud Desktop","description":"Nextcloud Desktop is the official desktop client for the Nextcloud file synchronization and sharing platform.","link":"https://nextcloud.com/install/#install-clients","winget":"Nextcloud.NextcloudDesktop","foss":true},"nmap":{"category":"Pro Tools","choco":"nmap","content":"Nmap","description":"Nmap (Network Mapper) is an open-source tool for network exploration and security auditing. It discovers devices on a network and provides information about their ports and services.","link":"https://nmap.org/","winget":"Insecure.Nmap","foss":true},"nodejs":{"category":"Development","choco":"nodejs","content":"NodeJS","description":"NodeJS is a JavaScript runtime built on Chrome\u0027s V8 JavaScript engine for building server-side and networking applications.","link":"https://nodejs.org/","winget":"OpenJS.NodeJS","foss":true},"nodejslts":{"category":"Development","choco":"nodejs-lts","content":"NodeJS LTS","description":"NodeJS LTS provides Long-Term Support releases for stable and reliable server-side JavaScript development.","link":"https://nodejs.org/","winget":"OpenJS.NodeJS.LTS","foss":true},"pnpm":{"category":"Development","content":"pnpm","description":"pnpm is a fast and disk space efficient package manager for JavaScript and Node.js applications.","link":"https://pnpm.io/","winget":"pnpm.pnpm","foss":true},"notepadplus":{"category":"Development","choco":"notepadplusplus","content":"Notepad++","description":"Notepad++ is a free, open-source code editor and Notepad replacement with support for multiple languages.","link":"https://notepad-plus-plus.org/","winget":"Notepad++.Notepad++","foss":true},"nuget":{"category":"Microsoft Tools","choco":"nuget.commandline","content":"NuGet","description":"NuGet is a package manager for the .NET framework, enabling developers to manage and share libraries in their .NET applications.","link":"https://www.nuget.org/","winget":"Microsoft.NuGet","foss":true},"nvclean":{"category":"Utilities","choco":"na","content":"NVCleanstall","description":"NVCleanstall is a tool designed to customize NVIDIA driver installations, allowing advanced users to control more aspects of the installation process.","link":"https://www.techpowerup.com/nvcleanstall/","winget":"TechPowerUp.NVCleanstall","foss":false},"obs":{"category":"Multimedia Tools","choco":"obs-studio","content":"OBS Studio","description":"OBS Studio is a free and open-source software for video recording and live streaming. It supports real-time video/audio capturing and mixing, making it popular among content creators.","link":"https://obsproject.com/","winget":"OBSProject.OBSStudio","foss":true},"obsidian":{"category":"Document","choco":"obsidian","content":"Obsidian","description":"Obsidian is a powerful note-taking and knowledge management application.","link":"https://obsidian.md/","winget":"Obsidian.Obsidian","foss":false},"okular":{"category":"Document","choco":"okular","content":"Okular","description":"Okular is a versatile document viewer with advanced features.","link":"https://okular.kde.org/","winget":"KDE.Okular","foss":true},"onedrive":{"category":"Microsoft Tools","choco":"onedrive","content":"OneDrive","description":"OneDrive is a cloud storage service provided by Microsoft, allowing users to store and share files securely across devices.","link":"https://onedrive.live.com/","winget":"Microsoft.OneDrive","foss":false},"onlyoffice":{"category":"Document","choco":"onlyoffice","content":"ONLYOFFICE Desktop","description":"ONLYOFFICE Desktop is a comprehensive office suite for document editing and collaboration.","link":"https://www.onlyoffice.com/desktop.aspx","winget":"ONLYOFFICE.DesktopEditors","foss":true},"OPAutoClicker":{"category":"Utilities","choco":"autoclicker","content":"OPAutoClicker","description":"A full-fledged autoclicker with two modes of autoclicking, at your dynamic cursor location or at a prespecified location.","link":"https://www.opautoclicker.com","winget":"OPAutoClicker.OPAutoClicker","foss":false},"opencode":{"category":"Development","choco":"opencode","content":"OpenCode","description":"OpenCode is an open-source AI coding agent built for the terminal. It is provider-agnostic and supports local and hosted AI models.","link":"https://opencode.ai/","winget":"SST.opencode","foss":true},"openrgb":{"category":"Utilities","choco":"openrgb","content":"OpenRGB","description":"OpenRGB is an open-source RGB lighting control software designed to manage and control RGB lighting for various components and peripherals.","link":"https://openrgb.org/","winget":"OpenRGB.OpenRGB","foss":true},"OpenVPN":{"category":"Pro Tools","choco":"openvpn-connect","content":"OpenVPN Connect","description":"OpenVPN Connect is a VPN client that allows you to connect securely to a VPN server. It provides a secure and encrypted connection for protecting your online privacy.","link":"https://openvpn.net/","winget":"OpenVPNTechnologies.OpenVPNConnect","foss":false},"OVirtualBox":{"category":"Utilities","choco":"virtualbox","content":"Oracle VirtualBox","description":"Oracle VirtualBox is a powerful and free open-source virtualization tool for x86 and AMD64/Intel64 architectures.","link":"https://www.virtualbox.org/","winget":"Oracle.VirtualBox","foss":true},"policyplus":{"category":"Utilities","choco":"na","content":"Policy Plus","description":"Local Group Policy Editor plus more, for all Windows editions.","link":"https://github.com/Fleex255/PolicyPlus","winget":"Fleex255.PolicyPlus","foss":true},"processexplorer":{"category":"Microsoft Tools","choco":"procexp","content":"Process Explorer","description":"Process Explorer is a task manager and system monitor.","link":"https://learn.microsoft.com/sysinternals/downloads/process-explorer","winget":"Microsoft.Sysinternals.ProcessExplorer","foss":false},"Paintdotnet":{"category":"Multimedia Tools","choco":"paint.net","content":"Paint.NET","description":"Paint.NET is a free image and photo editing software for Windows. It features an intuitive user interface and supports a wide range of powerful editing tools.","link":"https://www.getpaint.net/","winget":"dotPDN.PaintDotNet","foss":false},"parsec":{"category":"Utilities","choco":"parsec","content":"Parsec","description":"Parsec is a low-latency, high-quality remote desktop sharing application for collaborating and gaming across devices.","link":"https://parsec.app/","winget":"Parsec.Parsec","foss":false},"peazip":{"category":"Utilities","choco":"peazip","content":"PeaZip","description":"PeaZip is a free, open-source file archiver utility that supports multiple archive formats and provides encryption features.","link":"https://peazip.github.io/","winget":"Giorgiotani.Peazip","foss":true},"pdf-xchange":{"category":"Document","choco":"pdfxchangeeditor","content":"PDF-XChange Editor","description":"A comprehensive Windows-based software suite and editor for creating, viewing, editing, annotating, and signing PDF files.","link":"https://www.pdf-xchange.com/","winget":"TrackerSoftware.PDF-XChangeEditor","foss":false},"pdf24creator":{"category":"Document","choco":"pdf24","content":"PDF24 Creator","description":"Free and easy-to-use online/desktop PDF tools that make you more productive","link":"https://tools.pdf24.org/en/creator","winget":"geeksoftwareGmbH.PDF24Creator","foss":false},"pdfgear":{"category":"Document","choco":"pdfgear","content":"PDFgear","description":"PDFgear is a piece of full-featured PDF management software for Windows, macOS, and mobile, and it\u0027s completely free to use.","link":"https://www.pdfgear.com/","winget":"PDFgear.PDFgear","foss":false},"pdfsam":{"category":"Document","choco":"pdfsam","content":"PDFsam Basic","description":"PDFsam Basic is a free and open-source tool for splitting, merging, and rotating PDF files.","link":"https://pdfsam.org/","winget":"PDFsam.PDFsam","foss":true},"playnite":{"category":"Games","choco":"playnite","content":"Playnite","description":"Playnite is an open-source video game library manager with one simple goal: To provide a unified interface for all of your games.","link":"https://playnite.link/","winget":"Playnite.Playnite","foss":true},"plex":{"category":"Selfhosted Tools","choco":"plexmediaserver","content":"Plex Media Server","description":"Plex Media Server is a media server software that allows you to organize and stream your media library. It supports various media formats and offers a wide range of features.","link":"https://www.plex.tv/your-media/","winget":"Plex.PlexMediaServer","foss":false},"plexdesktop":{"category":"Selfhosted Tools","choco":"plex","content":"Plex Desktop","description":"Plex Desktop for Windows is the front end for Plex Media Server.","link":"https://www.plex.tv","winget":"Plex.Plex","foss":false},"posh":{"category":"Development","choco":"oh-my-posh","content":"Oh My Posh (Prompt)","description":"Oh My Posh is a cross-platform prompt theme engine for any shell.","link":"https://ohmyposh.dev/","winget":"JanDeDobbeleer.OhMyPosh","foss":true},"postman":{"category":"Development","choco":"postman","content":"Postman","description":"Postman is an API platform and desktop client for designing, testing, documenting, and collaborating on APIs.","link":"https://www.postman.com/downloads/","winget":"Postman.Postman","foss":false},"powershell":{"category":"Microsoft Tools","choco":"powershell-core","content":"PowerShell","description":"PowerShell is a task automation framework and scripting language designed for system administrators, offering powerful command-line capabilities.","link":"https://github.com/PowerShell/PowerShell","winget":"Microsoft.PowerShell","foss":true},"powertoys":{"category":"Microsoft Tools","choco":"powertoys","content":"PowerToys","description":"PowerToys is a set of utilities for power users to enhance productivity, featuring tools like FancyZones, PowerRename, and more.","link":"https://github.com/microsoft/PowerToys","winget":"Microsoft.PowerToys","foss":true},"prismlauncher":{"category":"Games","choco":"prismlauncher","content":"Prism Launcher","description":"Prism Launcher is an open-source Minecraft launcher with the ability to manage multiple instances, accounts, and mods.","link":"https://prismlauncher.org/","winget":"PrismLauncher.PrismLauncher","foss":true},"processlasso":{"category":"Utilities","choco":"plasso","content":"Process Lasso","description":"Process Lasso is a system optimization and automation tool that improves system responsiveness and stability by adjusting process priorities and CPU affinities.","link":"https://bitsum.com/","winget":"BitSum.ProcessLasso","foss":false},"protonauth":{"category":"Utilities","choco":"protonauth","content":"Proton Authenticator","description":"2FA app from Proton to securely sync and backup 2FA codes.","link":"https://proton.me/authenticator","winget":"Proton.ProtonAuthenticator","foss":true},"protonmail":{"category":"Communications","choco":"protonmail","content":"Proton Mail","description":"Proton Mail is an end-to-end encrypted email service by Proton, protecting your privacy with zero-access encryption.","link":"https://proton.me/mail","winget":"Proton.ProtonMail","foss":true},"protondrive":{"category":"Utilities","choco":"protondrive","content":"Proton Drive","description":"Proton Drive is an end-to-end encrypted Swiss vault for your files that protects your data.","link":"https://proton.me/drive","winget":"Proton.ProtonDrive","foss":true},"protonpass":{"category":"Utilities","choco":"protonpass","content":"Proton Pass","description":"Proton Pass is a cloud-based password manager with end-to-end encryption and unique email aliases.","link":"https://proton.me/pass","winget":"Proton.ProtonPass","foss":true},"protonvpn":{"category":"Pro Tools","choco":"protonvpn","content":"Proton VPN","description":"Proton VPN is a no-logs VPN service that protects your privacy online with features like Secure Core and Tor over VPN.","link":"https://protonvpn.com/","winget":"Proton.ProtonVPN","foss":true},"processmonitor":{"category":"Microsoft Tools","choco":"procmon","content":"Process Monitor","description":"SysInternals Process Monitor is an advanced monitoring tool that shows real-time file system, registry, and process/thread activity.","link":"https://docs.microsoft.com/en-us/sysinternals/downloads/procmon","winget":"Microsoft.Sysinternals.ProcessMonitor","foss":false},"pstools":{"category":"Microsoft Tools","choco":"pstools","content":"PsTools","description":"Microsoft Sysinternals PsTools provides utilities for managing local and remote Windows systems and monitoring processes. PsExec can run processes under the SYSTEM account when the user has local administrative rights on the target system.","link":"https://learn.microsoft.com/en-us/sysinternals/downloads/pstools","winget":"Microsoft.Sysinternals.PsTools","foss":false},"putty":{"category":"Pro Tools","choco":"putty","content":"PuTTY","description":"PuTTY is a free and open-source terminal emulator, serial console, and network file transfer application. It supports various network protocols such as SSH, Telnet, and SCP.","link":"https://www.chiark.greenend.org.uk/~sgtatham/putty/","winget":"PuTTY.PuTTY","foss":true},"python3":{"category":"Development","choco":"python","content":"Python3","description":"Python is a versatile programming language used for web development, data analysis, artificial intelligence, and more.","link":"https://www.python.org/","winget":"Python.Python.3.14","foss":true},"qbittorrent":{"category":"Utilities","choco":"qbittorrent","content":"qBittorrent","description":"qBittorrent is a free and open-source BitTorrent client that aims to provide a feature-rich and lightweight alternative to other torrent clients.","link":"https://www.qbittorrent.org/","winget":"qBittorrent.qBittorrent","foss":true},"qownnotes":{"category":"Document","choco":"qownnotes","content":"QOwnNotes","description":"QOwnNotes is a free open-source note-taking app with Nextcloud/ownCloud integration.","link":"https://www.qownnotes.org/","winget":"pbek.QOwnNotes","foss":true},"qtox":{"category":"Communications","choco":"qtox","content":"QTox","description":"QTox is a free and open-source messaging app that prioritizes user privacy and security in its design.","link":"https://qtox.github.io/","winget":"Tox.qTox","foss":true},"revo":{"category":"Utilities","choco":"revo-uninstaller","content":"Revo Uninstaller","description":"Revo Uninstaller is an advanced uninstaller tool that helps you remove unwanted software and clean up your system.","link":"https://www.revouninstaller.com/","winget":"RevoUninstaller.RevoUninstaller","foss":false},"WiseProgramUninstaller":{"category":"Utilities","choco":"na","content":"Wise Program Uninstaller (WiseCleaner)","description":"Wise Program Uninstaller is the perfect solution for uninstalling Windows programs, allowing you to uninstall applications quickly and completely using its simple and user-friendly interface.","link":"https://www.wisecleaner.com/wise-program-uninstaller.html","winget":"WiseCleaner.WiseProgramUninstaller","foss":false},"rufus":{"category":"Pro Tools","choco":"rufus","content":"Rufus Imager","description":"Rufus is a utility that helps format and create bootable USB drives, such as USB keys or pen drives.","link":"https://rufus.ie/","winget":"Rufus.Rufus","foss":true},"rustlang":{"category":"Development","choco":"rust","content":"Rust","description":"Rust is a programming language designed for safety and performance, particularly focused on systems programming.","link":"https://www.rust-lang.org/","winget":"Rustlang.Rust.MSVC","foss":true},"sdio":{"category":"Utilities","choco":"sdio","content":"Snappy Driver Installer Origin","description":"Snappy Driver Installer Origin is a free and open-source driver updater with a vast driver database for Windows.","link":"https://www.glenn.delahoy.com/snappy-driver-installer-origin/","winget":"GlennDelahoy.SnappyDriverInstallerOrigin","foss":true},"sharex":{"category":"Multimedia Tools","choco":"sharex","content":"ShareX (Screenshots)","description":"ShareX is a free and open-source screen capture and file sharing tool. It supports various capture methods and offers advanced features for editing and sharing screenshots.","link":"https://getsharex.com/","winget":"ShareX.ShareX","foss":true},"nilesoftShell":{"category":"Utilities","choco":"nilesoft-shell","content":"Nilesoft Shell","description":"Shell is an expanded context menu tool that adds extra functionality and customization options to the Windows context menu.","link":"https://nilesoft.org/","winget":"Nilesoft.Shell","foss":false},"systeminformer":{"category":"Pro Tools","choco":"systeminformer","content":"System Informer","description":"A free, powerful, multi-purpose tool that helps you monitor system resources, debug software and detect malware.","link":"https://systeminformer.com/","winget":"WinsiderSS.SystemInformer","foss":true},"signal":{"category":"Communications","choco":"signal","content":"Signal","description":"Signal is a privacy-focused messaging app that offers end-to-end encryption for secure and private communication.","link":"https://signal.org/","winget":"OpenWhisperSystems.Signal","foss":true},"signalrgb":{"category":"Utilities","choco":"na","content":"SignalRGB","description":"SignalRGB lets you control and sync your favorite RGB devices with one free application.","link":"https://www.signalrgb.com/","winget":"WhirlwindFX.SignalRgb","foss":false},"simplenote":{"category":"Document","choco":"simplenote","content":"Simplenote","description":"Simplenote is an easy way to keep notes, lists, ideas and more.","link":"https://simplenote.com/","winget":"Automattic.Simplenote","foss":true},"simplewall":{"category":"Pro Tools","choco":"simplewall","content":"Simplewall","description":"Simplewall is a free and open-source firewall application for Windows. It allows users to control and manage the inbound and outbound network traffic of applications.","link":"https://github.com/henrypp/simplewall","winget":"Henry++.simplewall","foss":true},"slack":{"category":"Communications","choco":"slack","content":"Slack","description":"Slack is a collaboration hub that connects teams and facilitates communication through channels, messaging, and file sharing.","link":"https://slack.com/","winget":"SlackTechnologies.Slack","foss":false},"startallback":{"category":"Utilities","choco":"StartAllBack","content":"StartAllBack","description":"StartAllBack restores and improves Windows taskbar, Start menu, File Explorer, and shell UI behavior.","link":"https://www.startallback.com/","winget":"StartIsBack.StartAllBack","foss":false},"starship":{"category":"Development","choco":"starship","content":"Starship (Shell Prompt)","description":"Starship is a fast, customizable, cross-platform prompt for PowerShell and other shells.","link":"https://starship.rs/","winget":"Starship.Starship","foss":true},"steam":{"category":"Games","choco":"steam-client","content":"Steam","description":"Steam is a digital distribution platform for purchasing and playing video games, offering multiplayer gaming, video streaming, and more.","link":"https://store.steampowered.com/about/","winget":"Valve.Steam","foss":false},"roblox":{"category":"Games","choco":"na","content":"Roblox","description":"Roblox is a platform and game creation system that allows users to create and play games developed by the community.","link":"https://www.roblox.com/","winget":"Roblox.Roblox","foss":false},"sublimetext":{"category":"Development","choco":"sublimetext4","content":"Sublime Text","description":"Sublime Text is a sophisticated text editor for code, markup, and prose.","link":"https://www.sublimetext.com/","winget":"SublimeHQ.SublimeText.4","foss":false},"sumatra":{"category":"Document","choco":"sumatrapdf","content":"Sumatra PDF","description":"Sumatra PDF is a lightweight and fast PDF viewer with minimalistic design.","link":"https://www.sumatrapdfreader.org/free-pdf-reader.html","winget":"SumatraPDF.SumatraPDF","foss":true},"sunshine":{"category":"Selfhosted Tools","choco":"sunshine","content":"Sunshine/GameStream Server","description":"Sunshine is a GameStream server that allows you to remotely play PC games on Android devices, offering low-latency streaming.","link":"https://app.lizardbyte.dev/Sunshine/","winget":"LizardByte.Sunshine","foss":true},"synctrayzor":{"category":"Selfhosted Tools","choco":"synctrayzor","content":"SyncTrayzor","description":"SyncTrayzor is a Windows tray utility that bundles and wraps Syncthing, making it behave like a native application to easily manage and monitor file synchronization.","link":"https://github.com/GermanCoding/SyncTrayzor","winget":"GermanCoding.SyncTrayzor"},"syncthing":{"category":"Selfhosted Tools","choco":"syncthing","content":"Syncthing (CLI / Web UI)","description":"Syncthing is a decentralized, peer-to-peer file synchronization tool that securely syncs files directly across devices without cloud servers, managed via a local web interface.","link":"https://syncthing.net/","winget":"Syncthing.Syncthing","foss":true},"tcpview":{"category":"Microsoft Tools","choco":"tcpview","content":"TCPView","description":"SysInternals TCPView is a network monitoring tool that displays a detailed list of all TCP and UDP endpoints on your system.","link":"https://docs.microsoft.com/en-us/sysinternals/downloads/tcpview","winget":"Microsoft.Sysinternals.TCPView","foss":false},"teams":{"category":"Communications","choco":"microsoft-teams","content":"Teams","description":"Microsoft Teams is a collaboration platform that integrates with Office 365 and offers chat, video conferencing, file sharing, and more.","link":"https://www.microsoft.com/en-us/microsoft-teams/group-chat-software","winget":"Microsoft.Teams","foss":false},"teamviewer":{"category":"Utilities","choco":"teamviewer","content":"TeamViewer","description":"TeamViewer is a popular remote access and support software that allows you to connect to and control remote devices.","link":"https://www.teamviewer.com/","winget":"TeamViewer.TeamViewer","foss":false},"teamspeak3":{"category":"Communications","choco":"teamspeak","content":"TeamSpeak 3","description":"TEAMSPEAK. YOUR TEAM. YOUR RULES. Use crystal clear sound to communicate with your teammates cross-platform with military-grade security, lag-free performance \u0026 unparalleled reliability and uptime.","link":"https://www.teamspeak.com/","winget":"TeamSpeakSystems.TeamSpeakClient","foss":false},"teamspeak6":{"category":"Communications","choco":"na","content":"TeamSpeak 6","description":"TEAMSPEAK. YOUR TEAM. YOUR RULES. Use crystal clear sound to communicate with your teammates cross-platform with military-grade security, lag-free performance \u0026 unparalleled reliability and uptime.","link":"https://www.teamspeak.com/","winget":"TeamSpeakSystems.TeamSpeakClient.Beta.6","foss":false},"telegram":{"category":"Communications","choco":"telegram","content":"Telegram","description":"Telegram is a cloud-based instant messaging app known for its security features, speed, and simplicity.","link":"https://telegram.org/","winget":"Telegram.TelegramDesktop","foss":true},"terminal":{"category":"Microsoft Tools","choco":"microsoft-windows-terminal","content":"Windows Terminal","description":"Windows Terminal is a modern, fast, and efficient terminal application for command-line users, supporting multiple tabs, panes, and more.","link":"https://aka.ms/terminal","winget":"Microsoft.WindowsTerminal","foss":true},"thunderbird":{"category":"Communications","choco":"thunderbird","content":"Thunderbird","description":"Mozilla Thunderbird is a free and open-source email client, news client, and chat client with advanced features.","link":"https://www.thunderbird.net/","winget":"Mozilla.Thunderbird","foss":true},"betterbird":{"category":"Communications","choco":"betterbird","content":"Betterbird","description":"Betterbird is a fork of Mozilla Thunderbird with additional features and bugfixes.","link":"https://www.betterbird.eu/","winget":"Betterbird.Betterbird","foss":true},"tor":{"category":"Browsers","choco":"tor-browser","content":"Tor Browser","description":"Tor Browser is designed for anonymous web browsing, utilizing the Tor network to protect user privacy and security.","link":"https://www.torproject.org/","winget":"TorProject.TorBrowser","foss":true},"totalcommander":{"category":"Utilities","choco":"TotalCommander","content":"Total Commander","description":"Total Commander is a file manager for Windows that provides a powerful and intuitive interface for file management.","link":"https://www.ghisler.com/","winget":"Ghisler.TotalCommander","foss":false},"treesize":{"category":"Utilities","choco":"treesizefree","content":"TreeSize Free","description":"TreeSize Free is a disk space manager that helps you analyze and visualize the space usage on your drives.","link":"https://www.jam-software.com/treesize_free/","winget":"JAMSoftware.TreeSize.Free","foss":false},"ttaskbar":{"category":"Utilities","choco":"translucenttb","content":"TranslucentTB","description":"TranslucentTB is a tool that allows you to customize the transparency of the Windows Taskbar.","link":"https://translucenttb.github.io","winget":"CharlesMilette.TranslucentTB","foss":true},"ubisoft":{"category":"Games","choco":"ubisoft-connect","content":"Ubisoft Connect","description":"Ubisoft Connect is Ubisoft\u0027s digital distribution and online gaming service, providing access to Ubisoft\u0027s games and services.","link":"https://ubisoftconnect.com/","winget":"Ubisoft.Connect","foss":false},"ungoogled":{"category":"Browsers","choco":"ungoogled-chromium","content":"Ungoogled Chromium","description":"Ungoogled Chromium is a version of Chromium without Google\u0027s integration for enhanced privacy and control.","link":"https://github.com/Eloston/ungoogled-chromium","winget":"eloston.ungoogled-chromium","foss":true},"unity":{"category":"Development","choco":"unity-hub","content":"Unity Game Engine","description":"Unity is a powerful game development platform for creating 2D, 3D, augmented reality, and virtual reality games.","link":"https://unity.com/","winget":"Unity.UnityHub","foss":false},"vagrant":{"category":"Development","choco":"vagrant","content":"Vagrant","description":"Vagrant builds and manages reproducible virtual machine development environments from declarative configuration.","link":"https://developer.hashicorp.com/vagrant","winget":"Hashicorp.Vagrant","foss":false},"everything":{"category":"Utilities","choco":"everything","content":"Everything","description":"Everything is a search engine that locates files and folders by filename instantly for Windows. Unlike Windows search Everything initially displays every file and folder on your computer (hence the name Everything). You type in a search filter to limit what files and folders are displayed.","link":"https://www.voidtools.com/","winget":"voidtools.Everything","foss":false},"vc2015_32":{"category":"Microsoft Tools","choco":"vcredist2015","content":"Visual C++ 2015-2022 32-bit","description":"Visual C++ 2015-2022 32-bit redistributable package installs runtime components of Visual C++ libraries required to run 32-bit applications.","link":"https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads","winget":"Microsoft.VCRedist.2015+.x86","foss":false},"vc2015_64":{"category":"Microsoft Tools","choco":"vcredist2015","content":"Visual C++ 2015-2022 64-bit","description":"Visual C++ 2015-2022 64-bit redistributable package installs runtime components of Visual C++ libraries required to run 64-bit applications.","link":"https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads","winget":"Microsoft.VCRedist.2015+.x64","foss":false},"ventoy":{"category":"Pro Tools","choco":"ventoy","content":"Ventoy","description":"Ventoy is an open-source tool for creating bootable USB drives. It supports multiple ISO files on a single USB drive, making it a versatile solution for installing operating systems.","link":"https://www.ventoy.net/","winget":"Ventoy.Ventoy","foss":true},"vesktop":{"category":"Communications","choco":"na","content":"Vesktop","description":"A cross-platform electron-based desktop app aiming to give you a snappier Discord experience with Vencord pre-installed.","link":"https://vesktop.dev","winget":"Vencord.Vesktop","foss":true},"viber":{"category":"Communications","choco":"viber","content":"Viber","description":"Viber is a free messaging and calling app with features like group chats, video calls, and more.","link":"https://www.viber.com/","winget":"Rakuten.Viber","foss":false},"visualstudio2022":{"category":"Development","choco":"visualstudio2022community","content":"Visual Studio 2022","description":"Visual Studio 2022 is an integrated development environment (IDE) for building, debugging, and deploying applications.","link":"https://visualstudio.microsoft.com/","winget":"Microsoft.VisualStudio.2022.Community","foss":false},"visualstudio2026":{"category":"Development","choco":"visualstudio2026community","content":"Visual Studio 2026","description":"Visual Studio 2026 is an integrated development environment (IDE) for building, debugging, and deploying applications.","link":"https://visualstudio.microsoft.com/","winget":"Microsoft.VisualStudio.Community","foss":false},"vivaldi":{"category":"Browsers","choco":"vivaldi","content":"Vivaldi","description":"Vivaldi is a highly customizable web browser with a focus on user personalization and productivity features.","link":"https://vivaldi.com/","winget":"Vivaldi.Vivaldi","foss":false},"vlc":{"category":"Multimedia Tools","choco":"vlc","content":"VLC (Video Player)","description":"VLC Media Player is a free and open-source multimedia player that supports a wide range of audio and video formats. It is known for its versatility and cross-platform compatibility.","link":"https://www.videolan.org/vlc/","winget":"VideoLAN.VLC","foss":true},"vrdesktopstreamer":{"category":"Games","choco":"na","content":"Virtual Desktop Streamer","description":"Virtual Desktop Streamer is a tool that allows you to stream your desktop screen to VR devices.","link":"https://www.vrdesktop.net/","winget":"VirtualDesktop.Streamer","foss":false},"vscode":{"category":"Development","choco":"vscode","content":"VS Code","description":"Visual Studio Code is a free, open-source code editor with support for multiple programming languages.","link":"https://code.visualstudio.com/","winget":"Microsoft.VisualStudioCode","foss":true},"vscodium":{"category":"Development","choco":"vscodium","content":"VS Codium","description":"VSCodium is a community-driven, freely-licensed binary distribution of Microsoft\u0027s VS Code.","link":"https://vscodium.com/","winget":"VSCodium.VSCodium","foss":true},"waterfox":{"category":"Browsers","choco":"waterfox","content":"Waterfox","description":"Waterfox is a fast, privacy-focused web browser based on Firefox, designed to preserve user choice and privacy.","link":"https://www.waterfox.net/","winget":"Waterfox.Waterfox","foss":true},"whatsapp":{"category":"Communications","choco":"na","content":"WhatsApp Desktop","description":"WhatsApp Desktop is the official Windows desktop messaging app from Meta, distributed through the Microsoft Store.","link":"https://www.whatsapp.com/download","winget":"msstore:9NKSQGP7F2NH","foss":false},"wingetui":{"category":"Utilities","choco":"wingetui","content":"UniGetUI","description":"UniGetUI is a GUI for WinGet, Chocolatey, and other Windows CLI package managers.","link":"https://devolutions.net/unigetui/","winget":"Devolutions.UniGetUI","foss":true},"winrar":{"category":"Utilities","choco":"winrar","content":"WinRAR","description":"WinRAR is a powerful archive manager that allows you to create, manage, and extract compressed files.","link":"https://www.win-rar.com/","winget":"RARLab.WinRAR","foss":false},"winscp":{"category":"Pro Tools","choco":"winscp","content":"WinSCP","description":"WinSCP is a popular open-source SFTP, FTP, and SCP client for Windows. It allows secure file transfers between a local and a remote computer.","link":"https://winscp.net/","winget":"WinSCP.WinSCP","foss":true},"wireguard":{"category":"Pro Tools","choco":"wireguard","content":"WireGuard","description":"WireGuard is a fast and modern VPN (Virtual Private Network) protocol. It aims to be simpler and more efficient than other VPN protocols, providing secure and reliable connections.","link":"https://www.wireguard.com/","winget":"WireGuard.WireGuard","foss":true},"wireshark":{"category":"Pro Tools","choco":"wireshark","content":"Wireshark","description":"Wireshark is a widely-used open-source network protocol analyzer. It allows users to capture and analyze network traffic in real-time, providing detailed insights into network activities.","link":"https://www.wireshark.org/","winget":"WiresharkFoundation.Wireshark","foss":true},"wiztree":{"category":"Utilities","choco":"wiztree","content":"WizTree","description":"WizTree is a fast disk space analyzer that helps you quickly find the files and folders consuming the most space on your hard drive.","link":"https://wiztreefree.com/","winget":"AntibodySoftware.WizTree","foss":false},"xeheditor":{"category":"Utilities","choco":"HxD","content":"HxD Hex Editor","description":"HxD is a free hex editor that allows you to edit, view, search, and analyze binary files.","link":"https://mh-nexus.de/en/hxd/","winget":"MHNexus.HxD","foss":false},"xournal":{"category":"Document","choco":"xournalplusplus","content":"Xournal++","description":"Xournal++ is an open-source handwriting notetaking software with PDF annotation capabilities.","link":"https://xournalpp.github.io/","winget":"Xournal++.Xournal++","foss":true},"yarn":{"category":"Development","choco":"yarn","content":"Yarn","description":"Yarn is a fast, reliable, and secure dependency management tool for JavaScript projects.","link":"https://yarnpkg.com/","winget":"Yarn.Yarn","foss":true},"zoom":{"category":"Communications","choco":"zoom","content":"Zoom","description":"Zoom is a popular video conferencing and web conferencing service for online meetings, webinars, and collaborative projects.","link":"https://zoom.us/","winget":"Zoom.Zoom","foss":false},"uv":{"category":"Development","choco":"uv","content":"uv","description":"uv is a fast Python package and project manager written in Rust.","link":"https://docs.astral.sh/uv/getting-started/installation/","winget":"astral-sh.uv","foss":true},"tightvnc":{"category":"Utilities","choco":"TightVNC","content":"TightVNC","description":"TightVNC is a free and open-source remote desktop software that lets you access and control a computer over the network. With its intuitive interface, you can interact with the remote screen as if you were sitting in front of it. You can open files, launch applications, and perform other actions on the remote desktop almost as if you were physically there.","link":"https://www.tightvnc.com/","winget":"GlavSoft.TightVNC","foss":true},"glazewm":{"category":"Utilities","choco":"glazewm","content":"GlazeWM","description":"GlazeWM is a tiling window manager for Windows inspired by i3 and Polybar.","link":"https://github.com/glzr-io/glazewm","winget":"glzr-io.glazewm","foss":true},"Overwolf":{"category":"Games","content":"CurseForge","description":"CurseForge is a desktop application for managing mods and modpacks across multiple games, powered by Overwolf.","link":"https://www.overwolf.com/app/overwolf-curseforge","winget":"Overwolf.CurseForge","foss":false},"OFGB":{"category":"Utilities","choco":"ofgb","content":"OFGB (Oh Frick Go Back)","description":"GUI Tool to remove ads from various places around Windows 11","link":"https://github.com/xM4ddy/OFGB","winget":"xM4ddy.OFGB","foss":true},"ZenBrowser":{"category":"Browsers","choco":"na","content":"Zen Browser","description":"The modern, privacy-focused, performance-driven browser built on Firefox.","link":"https://zen-browser.app/","winget":"Zen-Team.Zen-Browser","foss":true},"Zed":{"category":"Development","choco":"zed","content":"Zed","description":"Zed is a modern, high-performance code editor designed from the ground up for speed and collaboration.","link":"https://zed.dev/","winget":"ZedIndustries.Zed","foss":true},"zotero":{"category":"Document","choco":"zotero","content":"Zotero","description":"Zotero is a free, easy-to-use tool to help you collect, organize, cite, and share your research materials.","link":"https://www.zotero.org/","winget":"DigitalScholar.Zotero","foss":true},"deskflow":{"category":"Utilities","choco":"deskflow","content":"Deskflow","description":"Deskflow is a free and open-source software KVM that lets you share a single keyboard and mouse across multiple computers.","link":"https://github.com/deskflow/deskflow","winget":"Deskflow.Deskflow","foss":true},"Ruby":{"category":"Development","choco":"ruby","winget":"RubyInstallerTeam.Ruby.4.0","description":"A Ruby language execution environment with a MSYS2 installation.","content":"Ruby","link":"https://rubyinstaller.org/","foss":true},"Lua":{"category":"Development","choco":"lua","winget":"rjpcomputing.luaforwindows","description":"A \u0027batteries included environment\u0027 for the Lua scripting language on Windows.","content":"Lua","link":"https://github.com/rjpcomputing/luaforwindows","foss":true},"CloudflareWARP":{"category":"Utilities","choco":"warp","winget":"Cloudflare.Warp","description":"WARP is a freemium VPN service provided by Cloudflare. Includes usage of Cloudflare\u0027s DNS","content":"Cloudflare WARP","link":"https://one.one.one.one","foss":false}}
'@ | ConvertFrom-Json
    Appx         = @'
{"WPFAppxMicrosoft_WindowsFeedbackHub":{"Category":"Apps Microsoft","Content":"Hub de Feedback","Description":"App para enviar diagn\u00f3sticos e avalia\u00e7\u00f5es \u00e0 Microsoft.","Panel":"0","PackageId":"Microsoft.WindowsFeedbackHub","StoreId":"9NBLGGH4R32N","DefaultDebloat":true},"WPFAppxMicrosoft_GetHelp":{"Category":"Apps Microsoft","Content":"Obter Ajuda","Description":"Guias automatizados e suporte remoto Microsoft.","Panel":"0","PackageId":"Microsoft.GetHelp","StoreId":"9PKDZBMV1H3T","DefaultDebloat":true},"WPFAppxMicrosoft_OutlookForWindows":{"Category":"Apps Microsoft","Content":"Outlook para Windows","Description":"Cliente de e-mail e calend\u00e1rio padr\u00e3o baseado em Web.","Panel":"0","PackageId":"Microsoft.OutlookForWindows","StoreId":"9NRX63209R7B","DefaultDebloat":false},"WPFAppxMSTeams":{"Category":"Apps Microsoft","Content":"Microsoft Teams","Description":"Aplicativo de reuni\u00f5es e chat integrado ao Windows 11.","Panel":"0","PackageId":"MSTeams","StoreId":"XP8BT8DW290MPQ","DefaultDebloat":false},"WPFAppxClipchamp_Clipchamp":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Clipchamp","Description":"Editor de v\u00eddeos pr\u00e9-instalado com recursos em nuvem.","Panel":"0","PackageId":"Clipchamp.Clipchamp","StoreId":"9P1J8S7CCWWT","DefaultDebloat":true},"WPFAppxMicrosoft_MicrosoftOfficeHub":{"Category":"Apps Microsoft","Content":"Microsoft 365 (Hub)","Description":"Painel de atalhos e propagandas do Office/Microsoft 365.","Panel":"0","PackageId":"Microsoft.MicrosoftOfficeHub","StoreId":"9WZDNCRD29V9","DefaultDebloat":true},"WPFAppxMicrosoft_ZuneMusic":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Reprodutor Multim\u00eddia","Description":"Player de \u00e1udio e v\u00eddeo moderno do Windows.","Panel":"0","PackageId":"Microsoft.ZuneMusic","StoreId":"9WZDNCRFJ3PT","DefaultDebloat":false},"WPFAppxMicrosoft_BingSearch":{"Category":"Bing \u0026 Web","Content":"Pesquisa Bing","Description":"Integra\u00e7\u00e3o da busca web Bing no sistema.","Panel":"1","PackageId":"Microsoft.BingSearch","StoreId":"9NZBF4GT040C","DefaultDebloat":true},"WPFAppxMicrosoftCorporationII_QuickAssist":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Assist\u00eancia R\u00e1pida","Description":"Ferramenta nativa para acesso remoto assistido.","Panel":"0","PackageId":"MicrosoftCorporationII.QuickAssist","StoreId":"9P7BP5VNWKX5","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsDevHome":{"Category":"Ferramentas Dev","Content":"Dev Home","Description":"Painel de monitoramento e configura\u00e7\u00e3o para desenvolvedores.","Panel":"1","PackageId":"Microsoft.Windows.DevHome","StoreId":"9N8MHTPHNGVV","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsCrossDevice":{"Category":"Ecossistema Microsoft","Content":"Dispositivos M\u00f3veis","Description":"Sincroniza\u00e7\u00e3o em segundo plano entre PC e celular.","Panel":"0","PackageId":"MicrosoftWindows.CrossDevice","StoreId":"9NTXGKQ8P7N0","DefaultDebloat":false},"WPFAppxMicrosoft_Todos":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Microsoft To Do","Description":"Lista de tarefas sincronizada com conta Microsoft.","Panel":"0","PackageId":"Microsoft.Todos","StoreId":"9NBLGGH5R558","DefaultDebloat":true},"WPFAppxMicrosoft_PowerAutomateDesktop":{"Category":"Ferramentas Dev","Content":"Power Automate","Description":"Automa\u00e7\u00e3o de fluxos e rotinas de trabalho Microsoft.","Panel":"1","PackageId":"Microsoft.PowerAutomateDesktop","StoreId":"9NFTCH6J7FHV","DefaultDebloat":true},"WPFAppxMicrosoft_YourPhone":{"Category":"Ecossistema Microsoft","Content":"Vincular ao Celular (Phone Link)","Description":"Espelhamento de notifica\u00e7\u00f5es, SMS e chamadas Android/iOS.","Panel":"0","PackageId":"Microsoft.YourPhone","StoreId":"9NMPJ99VJBWV","DefaultDebloat":false},"WPFAppxMicrosoft_MicrosoftStickyNotes":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Notas Autoadesivas (Sticky Notes)","Description":"Blocos de anota\u00e7\u00f5es r\u00e1pidas na \u00e1rea de trabalho.","Panel":"0","PackageId":"Microsoft.MicrosoftStickyNotes","StoreId":"9NBLGGH4QGHW","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsSoundRecorder":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Gravador de Som","Description":"Gravador de \u00e1udio nativo pelo microfone.","Panel":"0","PackageId":"Microsoft.WindowsSoundRecorder","StoreId":"9WZDNCRFHWKN","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsAlarms":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Rel\u00f3gio \u0026 Alarmes","Description":"Alarmes, cron\u00f4metro, timer e sess\u00f5es de foco.","Panel":"0","PackageId":"Microsoft.WindowsAlarms","StoreId":"9WZDNCRFJ3PR","DefaultDebloat":true},"WPFAppxMicrosoft_Paint":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Microsoft Paint","Description":"Editor de desenhos e imagens cl\u00e1ssico/moderno do Windows.","Panel":"0","PackageId":"Microsoft.Paint","StoreId":"9PCFS5B6T72H","DefaultDebloat":false},"WPFAppxMicrosoft_WindowsNotepad":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Bloco de Notas (Store)","Description":"Vers\u00e3o UWP atualizada do Bloco de Notas.","Panel":"0","PackageId":"Microsoft.WindowsNotepad","StoreId":"9MSMLRH6LZF3","DefaultDebloat":false},"WPFAppxMicrosoft_ScreenSketch":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Ferramenta de Captura (Snipping Tool)","Description":"Captura de tela e grava\u00e7\u00e3o nativa (Win+Shift+S).","Panel":"0","PackageId":"Microsoft.ScreenSketch","StoreId":"9MZ95KL8MR0L","DefaultDebloat":false},"WPFAppxMicrosoft_Copilot":{"Category":"Bing \u0026 Web","Content":"Microsoft Copilot","Description":"Assistente de IA integrado ao sistema e barra lateral.","Panel":"1","PackageId":"Microsoft.Copilot","StoreId":"9NHT9RB2F4HD","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsCalculator":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Calculadora","Description":"Calculadora padr\u00e3o e cient\u00edfica nativa do Windows.","Panel":"0","PackageId":"Microsoft.WindowsCalculator","StoreId":"9WZDNCRFHVN5","DefaultDebloat":true},"WPFAppxMicrosoft_WindowsCamera":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"C\u00e2mera","Description":"Aplicativo nativo para webcam e c\u00e2mera do notebook.","Panel":"0","PackageId":"Microsoft.WindowsCamera","StoreId":"9WZDNCRFJBBG","DefaultDebloat":false},"WPFAppxMicrosoft_WindowsPhotos":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Fotos","Description":"Visualizador padr\u00e3o de imagens e galeria do Windows.","Panel":"0","PackageId":"Microsoft.Windows.Photos","StoreId":"9WZDNCRFJBH4","DefaultDebloat":false},"WPFAppxMicrosoft_BingNews":{"Category":"Bing \u0026 Web","Content":"Not\u00edcias (Bing News)","Description":"Feed de not\u00edcias e manchetes patrocinadas.","Panel":"1","PackageId":"Microsoft.BingNews","StoreId":"9WZDNCRFHVFW","DefaultDebloat":true},"WPFAppxMicrosoft_BingWeather":{"Category":"Bing \u0026 Web","Content":"Clima (Bing Weather)","Description":"Previs\u00e3o do tempo e alertas meteorol\u00f3gicos.","Panel":"1","PackageId":"Microsoft.BingWeather","StoreId":"9WZDNCRFJ3Q2","DefaultDebloat":true},"WPFAppxMicrosoft_GamingApp":{"Category":"Xbox \u0026 Jogos","Content":"App Xbox","Description":"Central Xbox PC Game Pass e jogos na loja Microsoft.","Panel":"1","PackageId":"Microsoft.GamingApp","StoreId":"9MV0B5HZVK9Z","DefaultDebloat":false},"WPFAppxMicrosoft_XboxGamingOverlay":{"Category":"Xbox \u0026 Jogos","Content":"Xbox Game Bar","Description":"Sobreposi\u00e7\u00e3o Win+G para capturas e widgets durante jogos.","Panel":"1","PackageId":"Microsoft.XboxGamingOverlay","StoreId":"9NZKPSTSNW4P","DefaultDebloat":false},"WPFAppxMicrosoft_XboxIdentityProvider":{"Category":"Xbox \u0026 Jogos","Content":"Provedor de Identidade Xbox","Description":"Autentica\u00e7\u00e3o Xbox Live exigida por jogos da Microsoft Store.","Panel":"1","PackageId":"Microsoft.XboxIdentityProvider","StoreId":"9WZDNCRD1HKW","DefaultDebloat":false},"WPFAppxMicrosoft_XboxSpeechToTextOverlay":{"Category":"Xbox \u0026 Jogos","Content":"Xbox Voz para Texto","Description":"Recurso de acessibilidade de transcri\u00e7\u00e3o em jogos Xbox.","Panel":"1","PackageId":"Microsoft.XboxSpeechToTextOverlay","DefaultDebloat":false},"WPFAppxMicrosoft_Xbox_TCUI":{"Category":"Xbox \u0026 Jogos","Content":"Interface Xbox TCUI","Description":"Componentes de interface necess\u00e1rios para login em jogos Xbox.","Panel":"1","PackageId":"Microsoft.Xbox.TCUI","DefaultDebloat":false},"WPFAppxMicrosoft_StartExperiencesApp":{"Category":"Bing \u0026 Web","Content":"Experi\u00eancias do Iniciar","Description":"M\u00f3dulo de widgets din\u00e2micos e feed web do Menu Iniciar.","Panel":"1","PackageId":"Microsoft.StartExperiencesApp","StoreId":"9PC1H9VN18CM","DefaultDebloat":true},"WPFAppxMicrosoft_MicrosoftSolitaireCollection":{"Category":"Xbox \u0026 Jogos","Content":"Cole\u00e7\u00e3o Paci\u00eancia","Description":"Pacote de jogos de cartas com an\u00fancios pr\u00e9-instalado.","Panel":"1","PackageId":"Microsoft.MicrosoftSolitaireCollection","DefaultDebloat":true},"WPFAppxMicrosoft_ZuneVideo":{"Category":"Utilit\u00e1rios \u0026 Produtividade","Content":"Filmes e TV","Description":"Reprodutor de v\u00eddeo cl\u00e1ssico da Microsoft Store.","Panel":"0","PackageId":"Microsoft.ZuneVideo","StoreId":"9WZDNCRFJ3P2","DefaultDebloat":false}}
'@ | ConvertFrom-Json
    Dns          = @'
{"Google":{"BenchmarkEligible":true,"Primary":"8.8.8.8","Secondary":"8.8.4.4","Primary6":"2001:4860:4860::8888","Secondary6":"2001:4860:4860::8844","DohTemplate":"https://dns.google/dns-query"},"Cloudflare":{"BenchmarkEligible":true,"Primary":"1.1.1.1","Secondary":"1.0.0.1","Primary6":"2606:4700:4700::1111","Secondary6":"2606:4700:4700::1001","DohTemplate":"https://cloudflare-dns.com/dns-query"},"Cloudflare_Malware":{"Primary":"1.1.1.2","Secondary":"1.0.0.2","Primary6":"2606:4700:4700::1112","Secondary6":"2606:4700:4700::1002","DohTemplate":"https://security.cloudflare-dns.com/dns-query"},"Cloudflare_Malware_Adult":{"Primary":"1.1.1.3","Secondary":"1.0.0.3","Primary6":"2606:4700:4700::1113","Secondary6":"2606:4700:4700::1003","DohTemplate":"https://family.cloudflare-dns.com/dns-query"},"Open_DNS":{"Primary":"208.67.222.222","Secondary":"208.67.220.220","Primary6":"2620:119:35::35","Secondary6":"2620:119:53::53","DohTemplate":"https://doh.opendns.com/dns-query"},"Quad9":{"Primary":"9.9.9.9","Secondary":"149.112.112.112","Primary6":"2620:fe::fe","Secondary6":"2620:fe::9","DohTemplate":"https://dns.quad9.net/dns-query"},"AdGuard_Ads_Trackers":{"Primary":"94.140.14.14","Secondary":"94.140.15.15","Primary6":"2a10:50c0::ad1:ff","Secondary6":"2a10:50c0::ad2:ff","DohTemplate":"https://dns.adguard-dns.com/dns-query"},"AdGuard_Ads_Trackers_Malware_Adult":{"Primary":"94.140.14.15","Secondary":"94.140.15.16","Primary6":"2a10:50c0::bad1:ff","Secondary6":"2a10:50c0::bad2:ff","DohTemplate":"https://family.adguard-dns.com/dns-query"}}
'@ | ConvertFrom-Json
    Features     = @'
{"WPFFeaturesdotnet":{"category":"Features","panel":"1","feature":["NetFx4-AdvSrvs","NetFx3"],"InvokeScript":[],"Content":".NET Framework 3.5 (Vers\u00f5es 2.0, 3.0 e 3.5)","Description":"Habilita suporte a programas legados e sistemas corporativos que exigem .NET antigo."},"WPFFixesNTPPool":{"Content":"NTP Server - Enable","Description":"Replaces the default Windows NTP server (time.windows.com) with pool.ntp.org for improved time synchronization accuracy and reliability.","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFFixesNTPPool"},"WPFFeatureshyperv":{"category":"Features","panel":"1","feature":["Microsoft-Hyper-V-All"],"Content":"Hyper-V (Virtualiza\u00e7\u00e3o Completa)","Description":"Habilita o hipervisor nativo da Microsoft para rodar m\u00e1quinas virtuais de alto desempenho."},"WPFFeatureslegacymedia":{"category":"Features","panel":"1","feature":["WindowsMediaPlayer","MediaPlayback","DirectPlay","LegacyComponents"],"InvokeScript":[],"Content":"Recursos de M\u00eddia Legados (WMP, DirectPlay)","Description":"Ativa Windows Media Player antigo e DirectPlay necess\u00e1rios para jogos cl\u00e1ssicos."},"WPFFeaturewsl":{"category":"Features","panel":"1","feature":["VirtualMachinePlatform","Microsoft-Windows-Subsystem-Linux"],"InvokeScript":[],"Content":"WSL 2 (Subsistema Windows para Linux)","Description":"Instala o kernel Linux nativo no Windows para rodar Ubuntu, Docker e ferramentas CLI."},"WPFFeaturenfs":{"category":"Features","panel":"1","feature":["ServicesForNFS-ClientOnly","ClientForNFS-Infrastructure","NFS-Administration"],"InvokeScript":["nfsadmin client stop","Set-ItemProperty -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default\u0027 -Name \u0027AnonymousUID\u0027 -Type DWord -Value 0","Set-ItemProperty -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default\u0027 -Name \u0027AnonymousGID\u0027 -Type DWord -Value 0","nfsadmin client start","nfsadmin client localhost config fileaccess=755 SecFlavors=+sys -krb5 -krb5i"],"Content":"Cliente NFS (Network File System)","Description":"Permite montar compartilhamentos de rede NFS de servidores Linux/NAS no Windows."},"WPFFeatureRegBackup":{"category":"Features","panel":"1","feature":[],"InvokeScript":["\n      New-ItemProperty -Path \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\u0027 -Name \u0027EnablePeriodicBackup\u0027 -Type DWord -Value 1 -Force\n      New-ItemProperty -Path \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\u0027 -Name \u0027BackupCount\u0027 -Type DWord -Value 2 -Force\n      $action = New-ScheduledTaskAction -Execute \u0027schtasks\u0027 -Argument \u0027/run /i /tn \"\\Microsoft\\Windows\\Registry\\RegIdleBackup\"\u0027\n      $trigger = New-ScheduledTaskTrigger -Daily -At 00:30\n      Register-ScheduledTask -Action $action -Trigger $trigger -TaskName \u0027AutoRegBackup\u0027 -Description \u0027Create System Registry Backups\u0027 -User \u0027System\u0027\n      "],"Content":"Backup Di\u00e1rio Autom\u00e1tico do Registro","Description":"Reativa a tarefa agendada di\u00e1ria de c\u00f3pia de seguran\u00e7a do Registro em System32\\config\\RegBack."},"WPFFeatureEnableLegacyRecovery":{"category":"Features","panel":"1","feature":[],"InvokeScript":["bcdedit /set bootmenupolicy legacy"],"Content":"Ativar Menu F8 Cl\u00e1ssico no Boot","Description":"Restaura a tela cl\u00e1ssica de Op\u00e7\u00f5es Avan\u00e7adas ao pressionar F8 durante a inicializa\u00e7\u00e3o."},"WPFFeatureDisableLegacyRecovery":{"category":"Features","panel":"1","feature":[],"InvokeScript":["bcdedit /set bootmenupolicy standard"],"Content":"Desativar Menu F8 Cl\u00e1ssico (Boot R\u00e1pido)","Description":"Retorna a pol\u00edtica moderna de boot r\u00e1pido do Windows 10/11."},"WPFFeaturesSandbox":{"category":"Features","panel":"1","feature":["Containers-DisposableClientVM"],"Content":"Windows Sandbox (\u00c1rea Restrita)","Description":"Cria uma m\u00e1quina virtual descart\u00e1vel e isolada com 1 clique para testar arquivos suspeitos com seguran\u00e7a."},"WPFFeatureInstall":{"Content":"Install Features","category":"Features","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFFeatureInstall"},"WPFPanelAutologin":{"Content":"AutoLogon - Run","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFPanelAutologin"},"WPFFixesUpdate":{"Content":"Windows Update - Reset","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFFixesUpdate"},"WPFFixesNetwork":{"Content":"Network - Reset","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFFixesNetwork"},"WPFPanelDISM":{"Content":"System Corruption Scan - Run","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFSystemRepair"},"WPFFixesWinget":{"Content":"WinGet - Reinstall","category":"Fixes","panel":"1","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFFixesWinget"},"WPFPanelComputer":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["compmgmt.msc"],"Content":"Gerenciamento do Computador","Description":"Abre compmgmt.msc (Discos, Usu\u00e1rios, Servi\u00e7os e Visualizador de Eventos)."},"WPFPanelControl":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["control"],"Content":"Painel de Controle Cl\u00e1ssico","Description":"Abre o Painel de Controle tradicional completo do Windows."},"WPFPanelMouse":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["main.cpl"],"Content":"Propriedades do Mouse","Description":"Abre configura\u00e7\u00f5es cl\u00e1ssicas de velocidade, ponteiro e bot\u00f5es (main.cpl)."},"WPFPanelNetwork":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["ncpa.cpl"],"Content":"Conex\u00f5es de Rede","Description":"Abre a lista de adaptadores Ethernet/Wi-Fi (ncpa.cpl) para alterar IP/DNS manualmente."},"WPFPanelPower":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["powercfg.cpl"],"Content":"Op\u00e7\u00f5es de Energia","Description":"Abre o painel cl\u00e1ssico de planos de energia e bot\u00f5es de suspens\u00e3o (powercfg.cpl)."},"WPFPanelPrinter":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["Start-Process \u0027shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}\u0027"],"Content":"Dispositivos e Impressoras","Description":"Abre o gerenciador cl\u00e1ssico completo de impressoras e portas locais."},"WPFPanelPrograms":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["appwiz.cpl"],"Content":"Programas e Recursos","Description":"Abre a janela cl\u00e1ssica de desinstala\u00e7\u00e3o de programas Win32 (appwiz.cpl)."},"WPFPanelRegion":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["intl.cpl"],"Content":"Regi\u00e3o e Formato","Description":"Abre formatos de data, moeda, hora e localidade do sistema (intl.cpl)."},"WPFPanelSecurity":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["wscui.cpl"],"Content":"Seguran\u00e7a e Manuten\u00e7\u00e3o","Description":"Abre o resumo de integridade e avisos de seguran\u00e7a cl\u00e1ssicos (wscui.cpl)."},"WPFPanelSound":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["mmsys.cpl"],"Content":"Configura\u00e7\u00f5es de Som Cl\u00e1ssicas","Description":"Abre mmsys.cpl para gerenciar dispositivos de reprodu\u00e7\u00e3o, grava\u00e7\u00e3o e taxa de amostragem."},"WPFPanelSystem":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["sysdm.cpl"],"Content":"Propriedades do Sistema","Description":"Abre sysdm.cpl (Nome do PC, Vari\u00e1veis de Ambiente, Efeitos Visuais e Mem\u00f3ria Virtual)."},"WPFPanelTimedate":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["timedate.cpl"],"Content":"Data e Hora","Description":"Abre ajustes cl\u00e1ssicos de rel\u00f3gio, fuso hor\u00e1rio e servidor NTP (timedate.cpl)."},"WPFPanelFirewall":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["firewall.cpl"],"Content":"Firewall do Windows Defender","Description":"Abre configura\u00e7\u00f5es e regras r\u00e1pidas do Firewall nativo (firewall.cpl)."},"WPFPanelRestore":{"category":"Legacy Windows Panels","panel":"2","Type":"Button","ButtonWidth":"300","InvokeScript":["rstrui.exe"],"Content":"Restaura\u00e7\u00e3o do Sistema","Description":"Abre o assistente rstrui.exe para restaurar o Windows a um ponto anterior."},"WPFInstallPSProfile":{"Content":"Alt Tweaks PowerShell Profile - Install","category":"Powershell Profile Powershell 7+ Only","panel":"2","Type":"Button","ButtonWidth":"300","function":"Install-EnhancedPowerShellProfile"},"WPFUninstallPSProfile":{"Content":"Alt Tweaks PowerShell Profile - Remove","category":"Powershell Profile Powershell 7+ Only","panel":"2","Type":"Button","ButtonWidth":"300","function":"Uninstall-EnhancedPowerShellProfile"},"WPFEnableSSHServer":{"Content":"OpenSSH Server - Enable","category":"Remote Access","panel":"2","Type":"Button","ButtonWidth":"300","function":"Invoke-WPFSSHServer"}}
'@ | ConvertFrom-Json
    Presets      = @'
{"Desktop":["WPFTweaksRestorePoint","WPFTweaksDeleteTempFiles","WPFTweaksDiskCleanup","WPFTweaksTelemetry","WPFTweaksActivity","WPFTweaksLocation","WPFTweaksConsumerFeatures","WPFTweaksDeliveryOptimization","WPFTweaksHiber","WPFTweaksServices","WPFTweaksEndTaskOnTaskbar","WPFTweaksDisableExplorerAutoDiscovery","WPFTweaksWPBT","WPFTweaksPreventDeviceMetadataFromNetwork","WPFTweaksDisableStoreSearch","WPFTweaksWidget","TweaksGameDvr","TweaksSsdTrim","TweaksFastMenus","TweaksTcpGaming","TweaksFlushDns"],"Notebook":["WPFTweaksRestorePoint","WPFTweaksDeleteTempFiles","WPFTweaksDiskCleanup","WPFTweaksTelemetry","WPFTweaksActivity","WPFTweaksLocation","WPFTweaksConsumerFeatures","WPFTweaksDeliveryOptimization","WPFTweaksServices","WPFTweaksEndTaskOnTaskbar","WPFTweaksDisableExplorerAutoDiscovery","WPFTweaksWPBT","WPFTweaksPreventDeviceMetadataFromNetwork","WPFTweaksDisableStoreSearch","WPFTweaksWidget","TweaksGameDvr","TweaksSsdTrim","TweaksFastMenus","TweaksFlushDns"],"All":["WPFTweaksActivity","WPFTweaksHiber","WPFTweaksWidget","WPFTweaksRevertStartMenu","WPFTweaksDisableStoreSearch","WPFTweaksLocation","WPFTweaksServices","WPFTweaksSvcHostSplitting","WPFTweaksBraveDebloat","WPFTweaksDisableWarningForUnsignedRdp","WPFTweaksEdgeDebloat","WPFTweaksConsumerFeatures","WPFTweaksTelemetry","WPFTweaksDeliveryOptimization","WPFTweaksRemoveEdge","WPFTweaksDisableBitLocker","WPFTweaksUTC","WPFTweaksRemoveOneDrive","WPFTweaksRemoveHomeAndGallery","WPFTweaksDisplay","WPFTweaksReservedStorage","WPFTweaksRestorePoint","WPFTweaksEndTaskOnTaskbar","WPFTweaksStorage","WPFTweaksWindowsAI","WPFTweaksWPBT","WPFTweaksPreventDeviceMetadataFromNetwork","WPFTweaksRazerBlock","WPFTweaksLogiBlock","WPFTweaksDisableNotifications","WPFTweaksBlockAdobeNet","WPFTweaksRightClickMenu","WPFTweaksDiskCleanup","WPFTweaksDeleteTempFiles","WPFTweaksIPv46","WPFTweaksTeredo","WPFTweaksDisableSearchIndexing","WPFTweaksDisableIPv6","WPFTweaksDisableBGapps","WPFTweaksDisableExplorerAutoDiscovery","TweaksGameDvr","TweaksSsdTrim","TweaksFastMenus","TweaksTakeOwnership","TweaksTcpGaming","TweaksFlushDns","TweaksRenewDhcp","TweaksResetNetStack"]}
'@ | ConvertFrom-Json
    Tweaks       = @'
{"WPFTweaksActivity":{"Content":"Hist\u00f3rico de Atividades - Desativar","Description":"Impede o Windows de enviar hist\u00f3rico de uso e atividades para a Microsoft, mantendo a \u00e1rea de transfer\u00eancia intacta.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"EnableActivityFeed","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"PublishUserActivities","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"UploadUserActivities","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksHiber":{"Content":"Hiberna\u00e7\u00e3o - Desativar (Desktop)","Description":"Desativa a hiberna\u00e7\u00e3o e remove o arquivo hiberfil.sys para liberar v\u00e1rios GB de espa\u00e7o no disco. N\u00e3o recomendado para notebooks.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power","Name":"HibernateEnabled","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FlyoutMenuSettings","Name":"ShowHibernateOption","Value":"0","Type":"DWord","OriginalValue":"1"}],"InvokeScript":["powercfg.exe /hibernate off"],"UndoScript":["powercfg.exe /hibernate on"]},"WPFTweaksWidget":{"Content":"Widgets da Barra de Tarefas - Remover","Description":"Remove o painel de Widgets e not\u00edcias da barra de tarefas do Windows 11, liberando mem\u00f3ria em segundo plano.","category":"Essenciais","panel":"1","InvokeScript":["\n      # Sometimes if you dont stop the Widgets process the removal may fail\n\n      Get-Process *Widget* | Stop-Process\n      Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers | Remove-AppxPackage -AllUsers\n      Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers | Remove-AppxPackage -AllUsers\n\n      Invoke-ExplorerRefresh -action \"restart\"\n      Write-Host \"Removed widgets\"\n      "]},"WPFTweaksRevertStartMenu":{"Content":"Menu Iniciar Layout Cl\u00e1ssico","Description":"Tenta restaurar o layout anterior do Menu Iniciar em vers\u00f5es compat\u00edveis do Windows 11.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\ControlSet001\\Control\\FeatureManagement\\Overrides\\8\\3036241548","Name":"EnabledState","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksDisableStoreSearch":{"Content":"Sugest\u00f5es da Store na Busca - Desativar","Description":"Impede que aplicativos promovidos da Microsoft Store apare\u00e7am nas pesquisas do Menu Iniciar.","category":"Essenciais","panel":"1","InvokeScript":["icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /deny *S-1-1-0:F"],"UndoScript":["icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /grant *S-1-1-0:F"]},"WPFTweaksLocation":{"Content":"Rastreamento de Localiza\u00e7\u00e3o - Desativar","Description":"Desativa os servi\u00e7os de geolocaliza\u00e7\u00e3o e rastreamento de localiza\u00e7\u00e3o pelo sistema e apps.","category":"Essenciais","panel":"1","service":[{"Name":"lfsvc","StartupType":"Disabled","OriginalType":"Manual"}],"registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location","Name":"Value","Value":"Deny","Type":"String","OriginalValue":"Allow"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Sensor\\Overrides\\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}","Name":"SensorPermissionState","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SYSTEM\\Maps","Name":"AutoUpdateEnabled","Value":"0","Type":"DWord","OriginalValue":"1"}]},"WPFTweaksServices":{"Content":"Servi\u00e7os Secund\u00e1rios em Manual","Description":"Define dezenas de servi\u00e7os n\u00e3o essenciais para inicializa\u00e7\u00e3o Manual, reduzindo uso de RAM e processos no boot.","category":"Essenciais","panel":"1","service":[{"Name":"CscService","StartupType":"Disabled","OriginalType":"Manual"},{"Name":"DiagTrack","StartupType":"Disabled","OriginalType":"Automatic"},{"Name":"MapsBroker","StartupType":"Manual","OriginalType":"Automatic"},{"Name":"StorSvc","StartupType":"Manual","OriginalType":"Automatic"},{"Name":"SharedAccess","StartupType":"Disabled","OriginalType":"Automatic"}]},"WPFTweaksSvcHostSplitting":{"Content":"Agrupamento svchost.exe - Otimizar RAM","Description":"Desativa a divis\u00e3o excessiva de processos svchost.exe para reduzir consumo de mem\u00f3ria em PCs com 12 GB de RAM ou menos. Requer rein\u00edcio.","category":"Avancados","panel":"1","InvokeScript":["\n      # A threshold above the physical memory disables svchost service splitting\n      $Memory = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB\n      Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name SvcHostSplitThresholdInKB -Value $Memory -Type DWord\n      "],"UndoScript":["\n      # Windows client default (0x380000): splitting back on\n      Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force\n      "]},"WPFTweaksBraveDebloat":{"Content":"Brave Browser - Remover Extras (Debloat)","Description":"Desativa Brave Rewards, Leo AI, Carteira Cripto e VPN integrada via pol\u00edticas do navegador.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveRewardsDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveWalletDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveVPNDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveAIChatEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveStatsPingEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveNewsDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveTalkDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"TorDisabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveP3AEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"UrlKeyedAnonymizedDataCollectionEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"SafeBrowsingExtendedReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"MetricsReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksDisableWarningForUnsignedRdp":{"Content":"Avisos RDP N\u00e3o Assinados - Desativar","Description":"Remove avisos extras ao abrir arquivos de \u00c1rea de Trabalho Remota (.rdp) n\u00e3o assinados.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services\\Client","Name":"RedirectionWarningDialogVersion","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Terminal Server Client","Name":"RdpLaunchConsentAccepted","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksEdgeDebloat":{"Content":"Microsoft Edge - Desativar Telemetria/Popups","Description":"Remove banners promocionais, sidebar, telemetria e recomenda\u00e7\u00f5es de compras no Microsoft Edge.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\EdgeUpdate","Name":"CreateDesktopShortcutDefault","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"PersonalizationReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\\ExtensionInstallBlocklist","Name":"1","Value":"ofefcgjbeghpigppfmkologfjadafddi","Type":"String","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ShowRecommendationsEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"HideFirstRunExperience","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"UserFeedbackAllowed","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ConfigureDoNotTrack","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"AlternateErrorPagesEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeCollectionsEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeShoppingAssistantEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"MicrosoftEdgeInsiderPromotionEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ShowMicrosoftRewards","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"WebWidgetAllowed","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"DiagnosticData","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeAssetDeliveryServiceEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"WalletDonationEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"DefaultBrowserSettingsCampaignEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksConsumerFeatures":{"Content":"Instala\u00e7\u00e3o Silenciosa de Apps/An\u00fancios - Desativar","Description":"Bloqueia a instala\u00e7\u00e3o autom\u00e1tica de jogos e aplicativos patrocinados (Candy Crush, etc.) pela Microsoft.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent","Name":"DisableWindowsConsumerFeatures","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksTelemetry":{"Content":"Telemetria \u0026 Coleta de Dados - Desativar","Description":"Desativa telemetria do sistema, tarefas CEIP e coleta de dados de diagn\u00f3stico em segundo plano.","category":"Essenciais","panel":"1","service":[{"Name":"diagtrack","StartupType":"Disabled","OriginalType":"Automatic"},{"Name":"WerSvc","StartupType":"Disabled","OriginalType":"Manual"}],"registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo","Name":"Enabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Privacy","Name":"TailoredExperiencesWithDiagnosticDataEnabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Speech_OneCore\\Settings\\OnlineSpeechPrivacy","Name":"HasAccepted","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Input\\TIPC","Name":"Enabled","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization","Name":"RestrictImplicitInkCollection","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization","Name":"RestrictImplicitTextCollection","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization\\TrainedDataStore","Name":"HarvestContacts","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Personalization\\Settings","Name":"AcceptedPrivacyPolicy","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection","Name":"AllowTelemetry","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"Start_TrackProgs","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"PublishUserActivities","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Siuf\\Rules","Name":"NumberOfSIUFInPeriod","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Siuf\\Rules","Name":"PeriodInNanoSeconds","Value":"\u003cRemoveEntry\u003e","Type":"QWord","OriginalValue":"\u003cRemoveEntry\u003e"}],"InvokeScript":["[Environment]::SetEnvironmentVariable(\u0027POWERSHELL_TELEMETRY_OPTOUT\u0027, \u00271\u0027, \u0027Machine\u0027)"],"UndoScript":["[Environment]::SetEnvironmentVariable(\u0027POWERSHELL_TELEMETRY_OPTOUT\u0027, \u0027\u0027, \u0027Machine\u0027)"]},"WPFTweaksDeliveryOptimization":{"Content":"Otimiza\u00e7\u00e3o de Entrega (P2P Updates) - Desativar","Description":"Impede o Windows de usar sua banda de internet para enviar atualiza\u00e7\u00f5es a outros computadores.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization","Name":"DODownloadMode","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksRemoveEdge":{"Content":"Microsoft Edge - Desinstalar Completamente","Description":"Executa a remo\u00e7\u00e3o completa do Microsoft Edge em n\u00edvel de sistema (Cuidado: requer outro navegador instalado).","category":"Avancados","panel":"1","InvokeScript":["\n      $EdgeAppDir = \"$Env:ProgramFiles (x86)\\Microsoft\\Edge\\Application\"\n      $Path = $null\n      if (Test-Path -LiteralPath $EdgeAppDir -ErrorAction Stop) {\n          $InstallerPattern = Join-Path $EdgeAppDir \"*\\Installer\\setup.exe\"\n          if (Test-Path -Path $InstallerPattern -ErrorAction Stop) {\n              $Path = Resolve-Path -Path $InstallerPattern -ErrorAction Stop | Select-Object -Last 1\n          }\n      }\n\n      if ($Path) {\n          New-Item -Path \"$Env:SystemRoot\\SystemApps\\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\\MicrosoftEdge.exe\" -Force\n          Start-Process -FilePath $Path -ArgumentList \"--uninstall --system-level --force-uninstall --delete-profile\" -Wait\n          Write-Host \"Microsoft Edge was removed\"\n      } else {\n          Write-Host \"Microsoft Edge is not installed\"\n      }\n      "],"UndoScript":["\n      Write-Host \"Installing Microsoft Edge...\"\n      winget install Microsoft.Edge --source winget\n      "]},"WPFTweaksDisableBitLocker":{"Content":"Criptografia Autom\u00e1tica BitLocker - Desativar","Description":"Impede a ativa\u00e7\u00e3o autom\u00e1tica da criptografia de disco BitLocker em contas locais/Microsoft.","category":"Essenciais","panel":"1","InvokeScript":["\n      $bitLockerVolume = Get-BitLockerVolume -MountPoint $Env:SystemDrive -ErrorAction Stop\n\n      if ($bitLockerVolume.VolumeStatus -eq \u0027FullyDecrypted\u0027) {\n          Write-Host \"BitLocker is already disabled on $($Env:SystemDrive).\"\n      } else {\n          Disable-BitLocker -MountPoint $Env:SystemDrive -ErrorAction Stop\n      }\n      "],"UndoScript":["Enable-BitLocker -MountPoint $Env:SystemDrive"]},"WPFTweaksUTC":{"Content":"Rel\u00f3gio do Sistema em UTC (Dual-Boot)","Description":"Define o rel\u00f3gio da BIOS/Windows para UTC, corrigindo atraso de hor\u00e1rio em m\u00e1quinas com Dual-Boot Windows/Linux.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation","Name":"RealTimeIsUniversal","Value":"1","Type":"QWord","OriginalValue":"0"}]},"WPFTweaksRemoveOneDrive":{"Content":"Microsoft OneDrive - Remover Completamente","Description":"Desinstala o OneDrive preservando arquivos do usu\u00e1rio, limpa pastas residuais e remove do Explorer.","category":"Avancados","panel":"1","InvokeScript":["\n      $OneDrivePath = $Env:OneDrive\n      $OneDriveFolderExists = -not [string]::IsNullOrWhiteSpace($OneDrivePath) -and (Test-Path -LiteralPath $OneDrivePath -PathType Container -ErrorAction Stop)\n\n      if ($OneDriveFolderExists) {\n          $OneDriveAcl = Get-Acl -LiteralPath $OneDrivePath -ErrorAction Stop\n      } else {\n          Write-Host \"OneDrive folder is already absent; skipping folder permissions and cleanup.\"\n      }\n\n      try {\n          if ($OneDriveFolderExists) {\n              # Protect user files while the uninstaller runs.\n              icacls $OneDrivePath /deny \"*S-1-5-32-544:(D,DC)\"\n              if ($LASTEXITCODE -ne 0) { throw \"Unable to protect the OneDrive folder (icacls exit code $LASTEXITCODE).\" }\n          }\n\n          Write-Host \"Uninstalling OneDrive...\"\n          Start-Process -FilePath (Join-Path $Env:SystemRoot \"System32\\OneDriveSetup.exe\") -ArgumentList \u0027/uninstall\u0027 -Wait -ErrorAction Stop\n\n          # Some of OneDrive files use explorer, and OneDrive uses FileCoAuth\n          Write-Host \"Removing leftover OneDrive Files...\"\n\n          Get-Process -ErrorAction Stop | Where-Object ProcessName -eq \u0027FileCoAuth\u0027 | Stop-Process -ErrorAction Stop\n          Get-Process -ErrorAction Stop | Where-Object ProcessName -eq \u0027Explorer\u0027 | Stop-Process -ErrorAction Stop\n\n          $OneDriveLeftovers = @(\"$Env:LocalAppData\\Microsoft\\OneDrive\", \"$Env:ProgramData\\Microsoft OneDrive\")\n          foreach ($LeftoverPath in $OneDriveLeftovers) {\n              if (Test-Path -LiteralPath $LeftoverPath -ErrorAction Stop) {\n                  Remove-Item -LiteralPath $LeftoverPath -Recurse -Force -ErrorAction Stop\n              }\n          }\n      } finally {\n          if ($OneDriveFolderExists) {\n              # Restore access even when uninstall or leftover cleanup fails.\n              Set-Acl -LiteralPath $OneDrivePath -AclObject $OneDriveAcl -ErrorAction Stop\n          }\n      }\n\n      if ($OneDriveFolderExists -and -not (Get-ChildItem -LiteralPath $OneDrivePath -Force -ErrorAction Stop)) {\n          # Refuse to delete if files appeared after the emptiness check.\n          [System.IO.Directory]::Delete($OneDrivePath, $false)\n          [Environment]::SetEnvironmentVariable(\u0027OneDrive\u0027, $null, \u0027User\u0027)\n      }\n\n      # OneSyncSvc is a per-user template; Get-Service only exposes user instances.\n      # Skip the operation if this Windows installation has no template.\n      if (Test-Path -LiteralPath \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Services\\OneSyncSvc\u0027) {\n          Set-Service -Name OneSyncSvc -StartupType Disabled\n      }\n      "],"UndoScript":["\n      Write-Host \"Installing OneDrive\"\n      winget install Microsoft.Onedrive --source winget\n\n      # Enable OneSyncSvc when the per-user service template exists\n      if (Test-Path -LiteralPath \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Services\\OneSyncSvc\u0027) {\n          Set-Service -Name OneSyncSvc -StartupType Automatic\n      }\n      "]},"WPFTweaksRemoveHomeAndGallery":{"Content":"Explorer: Ocultar In\u00edcio e Galeria","Description":"Remove as abas In\u00edcio e Galeria do Explorador de Arquivos e define \"Este Computador\" como tela padr\u00e3o.","category":"Avancados","panel":"1","registry":[{"Path":"HKCU:\\Software\\Classes\\CLSID\\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}","Name":"System.IsPinnedToNameSpaceTree","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Classes\\CLSID\\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}","Name":"System.IsPinnedToNameSpaceTree","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"LaunchTo","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksDisplay":{"Content":"Efeitos Visuais - Desempenho M\u00e1ximo","Description":"Ajusta os efeitos visuais do Windows (anima\u00e7\u00f5es/sombras) para priorizar m\u00e1xima velocidade de resposta.","category":"Avancados","panel":"1","registry":[{"Path":"HKCU:\\Control Panel\\Desktop","Name":"DragFullWindows","Value":"0","Type":"String","OriginalValue":"1"},{"Path":"HKCU:\\Control Panel\\Desktop","Name":"MenuShowDelay","Value":"200","Type":"String","OriginalValue":"400"},{"Path":"HKCU:\\Control Panel\\Desktop\\WindowMetrics","Name":"MinAnimate","Value":"0","Type":"String","OriginalValue":"1"},{"Path":"HKCU:\\Control Panel\\Keyboard","Name":"KeyboardDelay","Value":"0","Type":"String","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ListviewAlphaSelect","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ListviewShadow","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarAnimations","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects","Name":"VisualFXSetting","Value":"3","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\DWM","Name":"EnableAeroPeek","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarMn","Value":"0","Type":"DWord","OriginalValue":"1"}],"InvokeScript":["Set-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))"],"UndoScript":["Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\""]},"WPFTweaksReservedStorage":{"Content":"Armazenamento Reservado (7-10 GB) - Desativar","Description":"Libera o espa\u00e7o reservado para atualiza\u00e7\u00f5es futuras. Recomendado apenas em SSDs pequenos; reative antes de grandes updates.","category":"Avancados","panel":"1","InvokeScript":["DISM /Online /Set-ReservedStorageState /State:Disabled"],"UndoScript":["DISM /Online /Set-ReservedStorageState /State:Enabled"]},"WPFTweaksRestorePoint":{"Content":"Ponto de Restaura\u00e7\u00e3o - Criar Agora","Description":"Cria um Ponto de Restaura\u00e7\u00e3o do Sistema antes de aplicar otimiza\u00e7\u00f5es, permitindo reverter facilmente pelo Windows.","category":"Essenciais","panel":"1","Checked":"False","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore","Name":"SystemRestorePointCreationFrequency","Value":"0","Type":"DWord","OriginalValue":"1440"}],"InvokeScript":["\n      if (-not (Get-ComputerRestorePoint)) {\n          Enable-ComputerRestore -Drive $Env:SystemDrive\n      }\n\n      Checkpoint-Computer -Description \"System Restore Point created by Alt Tweaks\" -RestorePointType MODIFY_SETTINGS\n      Write-Host \"System Restore Point Created Successfully\" -ForegroundColor Green\n      "]},"WPFTweaksEndTaskOnTaskbar":{"Content":"Finalizar Tarefa no Bot\u00e3o Direito","Description":"Ativa a op\u00e7\u00e3o r\u00e1pida \"Finalizar Tarefa\" ao clicar com o bot\u00e3o direito em qualquer app na Barra de Tarefas (Win 11).","category":"Essenciais","panel":"1","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings","Name":"TaskbarEndTask","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksStorage":{"Content":"Sensor de Armazenamento - Desativar","Description":"Desativa a exclus\u00e3o autom\u00e1tica de arquivos tempor\u00e1rios e da lixeira gerenciada pelo Sensor de Armazenamento.","category":"Avancados","panel":"1","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy","Name":"01","Value":"0","Type":"DWord","OriginalValue":"1"}]},"WPFTweaksWindowsAI":{"Content":"IA do Windows (Copilot \u0026 Recall) - Remover","Description":"Remove pacotes Copilot/AI e desativa o recurso Recall para m\u00e1xima privacidade e menor consumo de recursos.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer","Name":"SettingsPageVisibility","Value":"hide:aicomponents","Type":"String","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKLM:\\SOFTWARE\\Policies\\WindowsNotepad","Name":"DisableAIFeatures","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}],"InvokeScript":["\n      $Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName\n      $Sid = (Get-LocalUser $Env:UserName).Sid.Value\n\n      New-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Appx\\AppxAllUserStore\\EndOfLife\\$Sid\\$Appx\" -Force\n\n      Get-AppxPackage -AllUsers \"*Copilot*\" | Remove-AppxPackage -AllUsers\n      winget uninstall -e --name \"Copilot\" --silent --force --accept-source-agreements 2\u003e$null\n      Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers\n\n      if ($Appx) {\n          Remove-AppxPackage $Appx\n      }\n\n      # WSAIFabricSvc only exists on some Windows 11 builds; without the guard a\n      # missing service aborts the rest of this script block and Recall stays enabled\n      if (Get-Service -Name WSAIFabricSvc -ErrorAction SilentlyContinue) {\n          Set-Service -Name WSAIFabricSvc -StartupType Disabled\n      }\n      # Store/MSIX PowerShell 7 can hang or fail COM activation in DISM.\n      $RecallCommand = {\n          Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction Stop | Out-Null\n      }\n      $RecallOutput = powershell.exe -NoProfile -NonInteractive -Command $RecallCommand 2\u003e\u00261\n      if ($LASTEXITCODE -ne 0) {\n          throw \"Failed to disable Recall (exit code $LASTEXITCODE): $(($RecallOutput | Out-String).Trim())\"\n      }\n      $RecallOutput | ForEach-Object { Write-Host $_ }\n\n      Write-Host \"Windows AI Disabled\"\n      "]},"WPFTweaksWPBT":{"Content":"WPBT (Execut\u00e1veis da BIOS) - Bloquear","Description":"Bloqueia o recurso WPBT que permite a fabricantes injetarem programas e bloatwares direto do firmware durante o boot.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager","Name":"DisableWpbtExecution","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksPreventDeviceMetadataFromNetwork":{"Content":"Bloqueio de Apps Autom\u00e1ticos de Dispositivos","Description":"Impede o Windows de baixar softwares promocionais de fabricantes ao conectar perif\u00e9ricos ou monitores.","category":"Essenciais","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Device Metadata","Name":"PreventDeviceMetadataFromNetwork","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFTweaksRazerBlock":{"Content":"Auto-Instala\u00e7\u00e3o Razer Synapse - Bloquear","Description":"Bloqueia a instala\u00e7\u00e3o for\u00e7ada do software Razer via Windows Update ao plugar mouses ou teclados.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching","Name":"SearchOrderConfig","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Device Installer","Name":"DisableCoInstallers","Value":"1","Type":"DWord","OriginalValue":"0"}],"InvokeScript":["\n      $RazerPath = \"$Env:SystemRoot\\Installer\\Razer\"\n\n      if (Test-Path $RazerPath) {\n        Remove-Item $RazerPath\\* -Recurse -Force\n      } else {\n        New-Item -Path $RazerPath -ItemType Directory\n      }\n\n      icacls $RazerPath /deny \"*S-1-1-0:(W)\"\n      "],"UndoScript":["\n      icacls \"$Env:SystemRoot\\Installer\\Razer\" /remove:d *S-1-1-0\n      "]},"WPFTweaksLogiBlock":{"Content":"Auto-Instala\u00e7\u00e3o Logitech Assistant - Bloquear","Description":"Bloqueia a reinstala\u00e7\u00e3o autom\u00e1tica do Logitech Download Assistant via drivers do Windows.","category":"Avancados","panel":"1","InvokeScript":["\n      Stop-Process -Name \"logi_download_assistant\" -Force -ErrorAction SilentlyContinue\n\n      $ProgramFiles64 = if ($Env:ProgramW6432) { $Env:ProgramW6432 } else { $Env:ProgramFiles }\n      $LogiPath = \"$ProgramFiles64\\LogiDownloadAssistant\"\n\n      if (Test-Path $LogiPath) {\n        Remove-Item $LogiPath\\* -Recurse -Force\n      } else {\n        New-Item -Path $LogiPath -ItemType Directory\n      }\n\n      icacls $LogiPath /deny \"*S-1-1-0:(W)\"\n      if ($LASTEXITCODE -ne 0) { throw \"icacls failed to deny write access on $LogiPath (exit code $LASTEXITCODE)\" }\n      "],"UndoScript":["\n      $ProgramFiles64 = if ($Env:ProgramW6432) { $Env:ProgramW6432 } else { $Env:ProgramFiles }\n      $LogiPath = \"$ProgramFiles64\\LogiDownloadAssistant\"\n\n      if (Test-Path $LogiPath) {\n        icacls $LogiPath /remove:d \"*S-1-1-0\"\n        if ($LASTEXITCODE -ne 0) { throw \"icacls failed to remove the write-deny rule on $LogiPath (exit code $LASTEXITCODE)\" }\n      }\n      "]},"WPFTweaksDisableNotifications":{"Content":"Central de Notifica\u00e7\u00f5es \u0026 Calend\u00e1rio - Desativar","Description":"Desativa popups de notifica\u00e7\u00f5es da bandeja e a barra de notifica\u00e7\u00f5es do sistema (Aten\u00e7\u00e3o: oculta alertas).","category":"Avancados","panel":"1","registry":[{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer","Name":"DisableNotificationCenter","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications","Name":"ToastEnabled","Value":"0","Type":"DWord","OriginalValue":"1"}]},"WPFTweaksBlockAdobeNet":{"Content":"Lista de Bloqueio Telemetria Adobe (Hosts)","Description":"Adiciona regras no arquivo hosts para bloquear servidores de telemetria e verifica\u00e7\u00e3o em segundo plano da Adobe.","category":"Avancados","panel":"1","InvokeScript":["\n      $hostsUrl = Invoke-RestMethod -Uri https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts\n      Add-Content -Path \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\" -Value $hostsUrl\n\n      ipconfig /flushdns\n      Write-Host \u0027Added Adobe url block list from host file\u0027\n      "],"UndoScript":["\n      Set-Content \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\" (\n          (Get-Content \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\") -join \"`n\" -replace \u0027(?s)#New Ver.*\u0027, \u0027\u0027\n      )\n\n      ipconfig /flushdns\n      Write-Host \u0027Removed Adobe url block list from host file\u0027\n      "]},"WPFTweaksRightClickMenu":{"Content":"Menu de Contexto Cl\u00e1ssico (Bot\u00e3o Direito)","Description":"Restaura o menu completo cl\u00e1ssico ao clicar com o bot\u00e3o direito no Windows 11, sem precisar clicar em \"Mostrar mais op\u00e7\u00f5es\".","category":"Avancados","panel":"1","InvokeScript":["Set-ClassicContextMenu"],"UndoScript":["Set-ClassicContextMenu -Undo"]},"WPFTweaksDiskCleanup":{"Content":"Limpeza de Disco do Windows - Executar","Description":"Executa a Limpeza de Disco (cleanmgr) removendo caches antigos de atualiza\u00e7\u00f5es e arquivos de sistema.","category":"Essenciais","panel":"1","InvokeScript":["\n      cleanmgr.exe /d C: /VERYLOWDISK\n      Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase\n      "]},"WPFTweaksDeleteTempFiles":{"Content":"Limpar Arquivos Tempor\u00e1rios \u0026 Prefetch","Description":"Apaga pastas TEMP do usu\u00e1rio e do sistema para recuperar espa\u00e7o e remover lixo acumulado.","category":"Essenciais","panel":"1","InvokeScript":["\n      # A temp folder always holds files something has open, including this run\u0027s own, and\n      # the job layer counts a logged error as a failed step\n      Remove-Item -Path \"$Env:Temp\\*\" -Recurse -Force -ErrorAction SilentlyContinue\n      Remove-Item -Path \"$Env:SystemRoot\\Temp\\*\" -Recurse -Force -ErrorAction SilentlyContinue\n      "]},"WPFTweaksIPv46":{"Content":"Priorizar IPv4 sobre IPv6","Description":"Configura o sistema para preferir conex\u00f5es IPv4 em redes onde o IPv6 local \u00e9 inst\u00e1vel ou mal configurado.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"32","Type":"DWord","OriginalValue":"0"}]},"WPFTweaksTeredo":{"Content":"Tunelamento Teredo - Desativar","Description":"Desativa o t\u00fanel Teredo (IPv6). Pode melhorar lat\u00eancia, por\u00e9m alguns jogos Xbox/Microsoft dependem do Teredo para Multiplayer.","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"1","Type":"DWord","OriginalValue":"0"}],"InvokeScript":["netsh interface teredo set state disabled"],"UndoScript":["netsh interface teredo set state default"]},"WPFTweaksDisableSearchIndexing":{"Content":"Indexa\u00e7\u00e3o de Pesquisa (WSearch) - Desativar","Description":"Desativa o servi\u00e7o de indexa\u00e7\u00e3o em disco (ideal para HDs mec\u00e2nicos antigos; a busca de arquivos pode ficar mais lenta).","category":"Avancados","panel":"1","service":[{"Name":"WSearch","StartupType":"Disabled","OriginalType":"Automatic"}],"InvokeScript":["$search = Get-Service -Name WSearch -ErrorAction SilentlyContinue\n      if ($search -and $search.StartType -eq \u0027Disabled\u0027 -and $search.Status -ne \u0027Stopped\u0027) {\n        Stop-Service -Name WSearch -Force -ErrorAction Stop\n      }"],"UndoScript":["$search = Get-Service -Name WSearch -ErrorAction SilentlyContinue\n      if ($search -and $search.StartType -eq \u0027Automatic\u0027 -and $search.Status -ne \u0027Running\u0027) {\n        Start-Service -Name WSearch -ErrorAction Stop\n      }"]},"WPFTweaksDisableIPv6":{"Content":"Protocolo IPv6 - Desativar","Description":"Desativa o protocolo IPv6 em todas as placas de rede (use com cautela caso seu provedor utilize IPv6 nativo).","category":"Avancados","panel":"1","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"255","Type":"DWord","OriginalValue":"0"}],"InvokeScript":["Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"],"UndoScript":["Enable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"]},"WPFTweaksDisableBGapps":{"Content":"Apps da Store em Segundo Plano - Desativar","Description":"Impede que aplicativos universais (UWP/Store) continuem rodando e consumindo RAM quando fechados.","category":"Avancados","panel":"1","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications","Name":"GlobalUserDisabled","Value":"1","Type":"DWord","OriginalValue":"0"}]},"WPFTweaksDisableExplorerAutoDiscovery":{"Content":"Auto-Descoberta de Pastas do Explorer - Desativar","Description":"Impede o Explorer de reanalisar milhares de arquivos para adivinhar o tipo da pasta, deixando a navega\u00e7\u00e3o muito mais r\u00e1pida.","category":"Essenciais","panel":"1","InvokeScript":["\n      # Previously detected folders\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\n\n      # Folder types lookup table\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\n\n      # Flush Explorer view database. Explorer creates these keys only after a folder\n      # view has been saved, so skip them when missing or already removed\n      if (Test-Path $bags) {\n        Remove-Item -Path $bags -Recurse -Force\n        Write-Host \"Removed $bags\"\n      }\n\n      if (Test-Path $bagMRU) {\n        Remove-Item -Path $bagMRU -Recurse -Force\n        Write-Host \"Removed $bagMRU\"\n      }\n\n      # Every folder\n      $allFolders = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\\AllFolders\\Shell\"\n\n      if (!(Test-Path $allFolders)) {\n        New-Item -Path $allFolders -Force\n        Write-Host \"Created $allFolders\"\n      }\n\n      # Generic view\n      New-ItemProperty -Path $allFolders -Name \"FolderType\" -Value \"NotSpecified\" -PropertyType String -Force\n      Write-Host \"Set FolderType to NotSpecified\"\n\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\n      "],"UndoScript":["\n      # Previously detected folders\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\n\n      # Folder types lookup table\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\n\n      # Flush Explorer view database. Explorer creates these keys only after a folder\n      # view has been saved, so skip them when missing or already removed\n      if (Test-Path $bags) {\n        Remove-Item -Path $bags -Recurse -Force\n        Write-Host \"Removed $bags\"\n      }\n\n      if (Test-Path $bagMRU) {\n        Remove-Item -Path $bagMRU -Recurse -Force\n        Write-Host \"Removed $bagMRU\"\n      }\n\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\n      "]},"WPFToggleDetailedBSoD":{"Content":"Tela Azul (BSoD) em Modo Detalhado","Description":"Exibe c\u00f3digos t\u00e9cnicos completos e par\u00e2metros de falha caso ocorra uma tela azul.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl","Name":"DisplayParameters","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"},{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl","Name":"DisableEmoticon","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleBatteryPercentage":{"Content":"Porcentagem de Bateria na Bandeja","Description":"Exibe o percentual num\u00e9rico exato da bateria ao lado do \u00edcone do sistema.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"IsBatteryPercentageEnabled","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e","DefaultState":"false"}]},"WPFToggleDarkMode":{"Content":"Tema Escuro Global do Windows","Description":"Alterna instantaneamente o modo escuro para aplicativos e interface do Windows.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize","Name":"AppsUseLightTheme","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"},{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize","Name":"SystemUsesLightTheme","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}],"InvokeScript":["Invoke-ExplorerRefresh\nif ($WinRepairSync -and $WinRepairSync.ThemeMode -eq \u0027Auto\u0027) { Invoke-ThemeRefresh -Theme \u0027Auto\u0027 }"],"UndoScript":["Invoke-ExplorerRefresh\nif ($WinRepairSync -and $WinRepairSync.ThemeMode -eq \u0027Auto\u0027) { Invoke-ThemeRefresh -Theme \u0027Auto\u0027 }"]},"WPFToggleShowExt":{"Content":"Mostrar Extens\u00f5es de Arquivos","Description":"Exibe extens\u00f5es como .exe, .dll, .pdf e .zip no Explorador de Arquivos para maior seguran\u00e7a.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"HideFileExt","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}],"InvokeScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "],"UndoScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "]},"WPFToggleHiddenFiles":{"Content":"Mostrar Arquivos e Pastas Ocultas","Description":"Torna vis\u00edveis arquivos e pastas ocultas no Explorador de Arquivos.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"Hidden","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}],"InvokeScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "],"UndoScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "]},"WPFToggleVerboseLogon":{"Content":"Mensagens Detalhadas de Boot/Logon","Description":"Mostra passo a passo qual servi\u00e7o ou etapa est\u00e1 carregando ao ligar e desligar o PC.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System","Name":"VerboseStatus","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleNewOutlook":{"Content":"Usar Novo Microsoft Outlook","Description":"Alterna o uso da nova vers\u00e3o do cliente Outlook integrada ao Windows.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Office\\16.0\\Outlook\\Preferences","Name":"UseNewOutlook","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Software\\Microsoft\\Office\\16.0\\Outlook\\Options\\General","Name":"HideNewOutlookToggle","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Options\\General","Name":"DoNewOutlookAutoMigration","Value":"0","Type":"DWord","OriginalValue":"0","DefaultState":"false"},{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Preferences","Name":"NewOutlookMigrationUserSetting","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e","DefaultState":"true"}]},"WPFToggleScrollbars":{"Content":"Barras de Rolagem Sempre Vis\u00edveis","Description":"Impede o Windows de esconder automaticamente as barras de rolagem quando o mouse sai da janela.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Accessibility","Name":"DynamicScrollbars","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}]},"WPFMultiplaneOverlay":{"Content":"Multiplane Overlay (MPO - GPU)","Description":"Controla a composi\u00e7\u00e3o de camadas de v\u00eddeo (desativar resolve engasgos/flicker em placas NVIDIA e AMD).","category":"Preferencias","panel":"2","Type":"Combobox","ComboItems":"Enabled|Disabled (Compatibility)|Fully Disabled","ComboDescriptions":{"Enabled":"Uses Windows\u0027 default overlay behavior.","Disabled (Compatibility)":"Disables MPO using OverlayTestMode=5, the less aggressive compatibility method.","Fully Disabled":"Disables MPO using OverlayTestMode=5 and DisableOverlays=1, the more aggressive method."},"registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\Dwm","Name":"OverlayTestMode","Type":"DWord","DefaultValue":"0","Values":{"Enabled":"\u003cRemoveEntry\u003e","Disabled (Compatibility)":"5","Fully Disabled":"5"}},{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers","Name":"DisableOverlays","Type":"DWord","DefaultValue":"0","Values":{"Enabled":"\u003cRemoveEntry\u003e","Disabled (Compatibility)":"\u003cRemoveEntry\u003e","Fully Disabled":"1"}}]},"WPFToggleMouseAcceleration":{"Content":"Acelera\u00e7\u00e3o do Mouse (Precis\u00e3o)","Description":"Quando desativado (recomendado em jogos), garante movimento 1:1 fiel ao sensor f\u00edsico do mouse.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseSpeed","Value":"1","Type":"String","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseThreshold1","Value":"6","Type":"String","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseThreshold2","Value":"10","Type":"String","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleNumLock":{"Content":"Num Lock Ligado ao Iniciar","Description":"Mant\u00e9m a tecla Num Lock automaticamente ativada na tela de login ao ligar o PC.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKU:\\.Default\\Control Panel\\Keyboard","Name":"InitialKeyboardIndicators","Value":"2","Type":"String","OriginalValue":"0","DefaultState":"false"},{"Path":"HKCU:\\Control Panel\\Keyboard","Name":"InitialKeyboardIndicators","Value":"2","Type":"String","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleWindowSnapping":{"Content":"Ajuste Magn\u00e9tico de Janelas (Snap)","Description":"Ativa ou desativa o encaixe autom\u00e1tico de janelas ao arrast\u00e1-las para os cantos da tela.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Desktop","Name":"WindowArrangementActive","Value":"1","Type":"String","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleStandbyFix":{"Content":"Rede Ativa em Espera Moderna (S0)","Description":"Controla se o Wi-Fi/rede continua conectado durante o modo de espera de baixo consumo em notebooks.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Policies\\Microsoft\\Power\\PowerSettings\\f15576e8-98b7-4186-b944-eafa664402d9","Name":"ACSettingIndex","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleS3Sleep":{"Content":"Suspens\u00e3o Cl\u00e1ssica S3 (Em vez de Modern Standby)","Description":"Alterna entre espera moderna (S0) e suspens\u00e3o S3 tradicional que corta energia da CPU preservando a RAM.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power","Name":"PlatformAoAcOverride","Value":"0","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e","DefaultState":"false"}]},"WPFToggleHideSettingsHome":{"Content":"P\u00e1gina Inicial das Configura\u00e7\u00f5es","Description":"Oculta ou exibe a tela inicial de recomenda\u00e7\u00f5es e propagandas no app Configura\u00e7\u00f5es.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer","Name":"SettingsPageVisibility","Value":"show:home","Type":"String","OriginalValue":"hide:home","DefaultState":"true"}]},"WPFToggleBingSearch":{"Content":"Pesquisa Web (Bing) no Menu Iniciar","Description":"Remove ou ativa resultados da internet (Bing) ao digitar no Menu Iniciar.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search","Name":"BingSearchEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleLoginBlur":{"Content":"Desfoque Acr\u00edlico na Tela de Login","Description":"Ativa ou desativa o efeito de desfoque (blur) no papel de parede da tela de senha.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"DisableAcrylicBackgroundOnLogon","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"}]},"WPFToggleDisableLockscreen":{"Content":"Desativar Tela de Bloqueio","Description":"Pula a cortina de bloqueio e vai direto para a tela de senha ao ligar ou acordar o PC.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Personalization","Name":"NoLockScreen","Value":"1","Type":"DWord","OriginalValue":"\u003cRemoveEntry\u003e"}]},"WPFToggleStartMenuRecommendations":{"Content":"Recomenda\u00e7\u00f5es no Menu Iniciar","Description":"Controla a se\u00e7\u00e3o de arquivos/apps recomendados no Menu Iniciar do Windows 11.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Start","Name":"HideRecommendedSection","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Education","Name":"IsEducationEnvironment","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer","Name":"HideRecommendedSection","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"}],"InvokeScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "],"UndoScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "]},"WPFToggleStickyKeys":{"Content":"Teclas de Ader\u00eancia (Sticky Keys)","Description":"Desativa o popup irritante das Teclas de Ader\u00eancia ao pressionar Shift 5 vezes.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Accessibility\\StickyKeys","Name":"Flags","Value":"506","Type":"DWord","OriginalValue":"58","DefaultState":"true"}]},"WPFToggleTaskbarAlignment":{"Content":"\u00cdcones Centralizados na Barra de Tarefas","Description":"Alinha os \u00edcones da Barra de Tarefas do Windows 11 no Centro (ligado) ou \u00e0 Esquerda (desligado).","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarAl","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}],"InvokeScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "],"UndoScript":["\n      Invoke-ExplorerRefresh -action \"restart\"\n      "]},"WPFToggleTaskbarSearch":{"Content":"\u00cdcone de Pesquisa na Barra de Tarefas","Description":"Mostra ou oculta a lupa/caixa de pesquisa na barra de tarefas.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search","Name":"SearchboxTaskbarMode","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleTaskView":{"Content":"Bot\u00e3o Vis\u00e3o de Tarefas na Barra","Description":"Mostra ou oculta o bot\u00e3o de m\u00faltiplas \u00e1reas de trabalho (Task View) na barra de tarefas.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ShowTaskViewButton","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleGameMode":{"Content":"Modo de Jogo do Windows (Game Mode)","Description":"Prioriza recursos de CPU/GPU e reduz processos em segundo plano enquanto voc\u00ea joga.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\GameBar","Name":"AllowAutoGameMode","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Software\\Microsoft\\GameBar","Name":"AutoGameModeEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleLongPaths":{"Content":"Habilitar Caminhos Longos (\u003e260 chars)","Description":"Permite que o Windows e softwares manipulem pastas e arquivos com caminhos maiores que 260 caracteres.","category":"Preferencias","panel":"2","Type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem","Name":"LongPathsEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFOOSUbutton":{"Content":"O\u0026O ShutUp10++ - Run","Description":"Baixa O\u0026O ShutUp10++ (~82 MB) em %LocalAppData%\\Alts e executa diretamente.","category":"Avancados","panel":"1","Type":"Button"},"WPFchangedns":{"Content":"DNS - Set to:","category":"Avancados","panel":"1","Type":"Combobox","ComboItems":"Default DHCP Fastest Google Cloudflare Cloudflare_Malware Cloudflare_Malware_Adult Open_DNS Quad9 AdGuard_Ads_Trackers AdGuard_Ads_Trackers_Malware_Adult"},"WPFAddUltPerf":{"Content":"Ultimate Performance Profile - Enable","category":"Energia","panel":"2","Type":"Button","ButtonWidth":"300"},"WPFRemoveUltPerf":{"Content":"Ultimate Performance Profile - Disable","category":"Energia","panel":"2","Type":"Button","ButtonWidth":"300"},"TweaksGameDvr":{"Content":"GameDVR \u0026 Grava\u00e7\u00e3o em Fundo - Desativar","Description":"Desativa captura oculta do GameDVR para reduzir input lag e quedas de FPS em jogos.","category":"Essenciais","Type":"CheckBox","InvokeScript":["Disable-GameDvrAndBackgroundRecording"],"UndoScript":["Set-RegistryEntry -Path \u0027HKCU:\\System\\GameConfigStore\u0027 -Name \u0027GameDVR_Enabled\u0027 -Type DWord -Value 1\nSet-RegistryEntry -Path \u0027HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR\u0027 -Name \u0027AllowGameDVR\u0027 -Type DWord -Value 1"]},"TweaksSsdTrim":{"Content":"Otimizar Unidades SSD (Executar TRIM)","Description":"Executa comando ReTrim nos SSDs para manter velocidade m\u00e1xima de escrita e sa\u00fade dos blocos.","category":"Essenciais","Type":"CheckBox","InvokeScript":["Optimize-SsdTrim"],"UndoScript":["Write-ToolLog \u0027TRIM e uma otimizacao pontual e nao requer reversao.\u0027 \u0027INFO\u0027"]},"TweaksFastMenus":{"Content":"Acelerar Menus \u0026 Prioridade de CPU","Description":"Reduz MenuShowDelay para 10ms e ajusta Win32PrioritySeparation=38 para interface instant\u00e2nea.","category":"Essenciais","Type":"CheckBox","InvokeScript":["Optimize-SystemResponsivenessAndVisuals"],"UndoScript":["Set-RegistryEntry -Path \u0027HKCU:\\Control Panel\\Desktop\u0027 -Name \u0027MenuShowDelay\u0027 -Type String -Value \u0027400\u0027\nSet-RegistryEntry -Path \u0027HKLM:\\SYSTEM\\CurrentControlSet\\Control\\PriorityControl\u0027 -Name \u0027Win32PrioritySeparation\u0027 -Type DWord -Value 2"]},"TweaksTakeOwnership":{"Content":"Adicionar \"Obter Acesso Total\" no Bot\u00e3o Direito","Description":"Adiciona atalho Take Ownership no menu de contexto para assumir posse de pastas e arquivos protegidos.","category":"Avancados","Type":"CheckBox","InvokeScript":["Add-TakeOwnershipContextMenu"],"UndoScript":["Remove-Item -Path \u0027HKCR:\\*\\shell\\runas\u0027 -Recurse -Force -ErrorAction SilentlyContinue\nRemove-Item -Path \u0027HKCR:\\Directory\\shell\\runas\u0027 -Recurse -Force -ErrorAction SilentlyContinue"]},"TweaksTcpGaming":{"Content":"Otimizar Lat\u00eancia TCP/IP (AutoTune, RSS, ECN)","Description":"Ajusta par\u00e2metros TCP, RSS, ECN e NetworkThrottlingIndex para menor ping e m\u00e1xima taxa de transfer\u00eancia.","category":"Essenciais","Type":"CheckBox","InvokeScript":["Optimize-TcpLatencyAndThroughput"],"UndoScript":["Set-RegistryEntry -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\u0027 -Name \u0027NetworkThrottlingIndex\u0027 -Type DWord -Value 10\nSet-RegistryEntry -Path \u0027HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\u0027 -Name \u0027SystemResponsiveness\u0027 -Type DWord -Value 20"]},"TweaksFlushDns":{"Content":"Limpar Cache DNS Local","Description":"Limpa o cache do resolvedor DNS do Windows para corrigir rotas e sites desatualizados.","category":"Essenciais","Type":"CheckBox","InvokeScript":["Invoke-FlushDns"],"UndoScript":["Write-ToolLog \u0027Limpeza de cache DNS nao requer reversao.\u0027 \u0027INFO\u0027"]},"TweaksRenewDhcp":{"Content":"Renovar Concess\u00e3o de IP / DHCP","Description":"Libera o IP local atual e solicita um novo endere\u00e7o IP ao roteador/servidor DHCP.","category":"Avancados","Type":"CheckBox","InvokeScript":["Invoke-RenewDhcp"],"UndoScript":["Write-ToolLog \u0027Renovacao DHCP nao requer reversao.\u0027 \u0027INFO\u0027"]},"TweaksResetNetStack":{"Content":"Redefinir Pilha de Rede Completa","Description":"Executa reset de Winsock, TCP/IP, IPv4/IPv6, Proxy WinHTTP, cache ARP e regras padr\u00e3o de Firewall.","category":"Avancados","Type":"CheckBox","InvokeScript":["Invoke-ResetNetworkStack"],"UndoScript":["Write-ToolLog \u0027Reset de pilha de rede nao possui reversao automatica.\u0027 \u0027WARN\u0027"]}}
'@ | ConvertFrom-Json
}

$embeddedUnattendXml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <!--https://schneegans.de/windows/unattend-generator/?LanguageMode=Interactive&ProcessorArchitecture=amd64&BypassRequirementsCheck=true&ComputerNameMode=Random&CompactOsMode=Default&TimeZoneMode=Implicit&PartitionMode=Interactive&DiskAssertionMode=Skip&WindowsEditionMode=Interactive&InstallFromMode=Automatic&PEMode=Default&UserAccountMode=InteractiveLocal&PasswordExpirationMode=Unlimited&LockoutMode=Default&HideFiles=Hidden&ClassicContextMenu=true&LaunchToThisPC=true&ShowEndTask=true&TaskbarSearch=Hide&TaskbarIconsMode=Empty&DisableWidgets=true&LeftTaskbar=true&HideTaskViewButton=true&StartTilesMode=Default&StartPinsMode=Empty&EnableLongPaths=true&HideEdgeFre=true&DisableEdgeStartupBoost=true&DeleteWindowsOld=true&EffectsMode=Default&DeleteEdgeDesktopIcon=true&DesktopIconsMode=Default&StartFoldersMode=Default&WifiMode=Skip&ExpressSettings=DisableAll&LockKeysMode=Configure&CapsLockInitial=Off&CapsLockBehavior=Toggle&NumLockInitial=On&NumLockBehavior=Toggle&ScrollLockInitial=Off&ScrollLockBehavior=Toggle&StickyKeysMode=Disabled&ColorMode=Custom&SystemColorTheme=Dark&AppsColorTheme=Dark&AccentColor=%230078d4&WallpaperMode=Default&LockScreenMode=Default&WdacMode=Skip&AppLockerMode=Skip-->
    <settings pass="offlineServicing"></settings>
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <UserData>
                <AcceptEula>true</AcceptEula>
            </UserData>
            <UseConfigurationSet>false</UseConfigurationSet>
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>4</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>5</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="generalize"></settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>powershell.exe -WindowStyle "Normal" -NoProfile -Command "$xml = [xml]::new(); $xml.Load('C:\Windows\Panther\unattend.xml'); $sb = [scriptblock]::Create( $xml.unattend.Extensions.ExtractScript ); Invoke-Command -ScriptBlock $sb -ArgumentList $xml;"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>powershell.exe -WindowStyle "Normal" -ExecutionPolicy "Unrestricted" -NoProfile -File "C:\Windows\Setup\Scripts\Specialize.ps1"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg.exe load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>4</Order>
                    <Path>powershell.exe -WindowStyle "Normal" -ExecutionPolicy "Unrestricted" -NoProfile -File "C:\Windows\Setup\Scripts\DefaultUser.ps1"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>5</Order>
                    <Path>reg.exe unload "HKU\DefaultUser"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>6</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>7</Order>
                    <Path>reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\BitLocker" /v PreventDeviceEncryption /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>8</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /v ShippedWithReserves /t REG_DWORD /d 0 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="auditSystem"></settings>
    <settings pass="auditUser"></settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <ProtectYourPC>3</ProtectYourPC>
                <HideEULAPage>true</HideEULAPage>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
            </OOBE>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell.exe -WindowStyle "Normal" -ExecutionPolicy "Unrestricted" -NoProfile -File "C:\Windows\Setup\Scripts\FirstLogon.ps1"</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
    <Extensions xmlns="https://schneegans.de/windows/unattend-generator/">
        <ExtractScript>
param(
    [xml]$Document
);

foreach( $file in $Document.unattend.Extensions.File ) {
    $path = [System.Environment]::ExpandEnvironmentVariables( $file.GetAttribute( 'path' ) );
    mkdir -Path( $path | Split-Path -Parent ) -ErrorAction 'SilentlyContinue';
    $encoding = switch( [System.IO.Path]::GetExtension( $path ) ) {
        { $_ -in '.ps1', '.xml' } { [System.Text.Encoding]::UTF8; }
        { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new( $false, $true ); }
        default { [System.Text.Encoding]::Default; }
    };
    $bytes = $encoding.GetPreamble() + $encoding.GetBytes( $file.InnerText.Trim() );
    [System.IO.File]::WriteAllBytes( $path, $bytes );
}
        </ExtractScript>
        <File path="C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml">
&lt;LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1"&gt;
    &lt;CustomTaskbarLayoutCollection PinListPlacement="Replace"&gt;
        &lt;defaultlayout:TaskbarLayout&gt;
            &lt;taskbar:TaskbarPinList&gt;
                &lt;taskbar:DesktopApp DesktopApplicationLinkPath="#leaveempty" /&gt;
            &lt;/taskbar:TaskbarPinList&gt;
        &lt;/defaultlayout:TaskbarLayout&gt;
    &lt;/CustomTaskbarLayoutCollection&gt;
&lt;/LayoutModificationTemplate&gt;
        </File>
        <File path="C:\Windows\Setup\Scripts\UnlockStartLayout.vbs">
HKU = &amp;H80000003
Set reg = GetObject("winmgmts://./root/default:StdRegProv")
Set fso = CreateObject("Scripting.FileSystemObject")

If reg.EnumKey(HKU, "", sids) = 0 Then
    If Not IsNull(sids) Then
        For Each sid In sids
            key = sid + "\Software\Policies\Microsoft\Windows\Explorer"
            name = "LockedStartLayout"
            If reg.GetDWORDValue(HKU, key, name, existing) = 0 Then
                reg.SetDWORDValue HKU, key, name, 0
            End If
        Next
    End If
End If
        </File>
        <File path="C:\Windows\Setup\Scripts\UnlockStartLayout.xml">
&lt;Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"&gt;
    &lt;Triggers&gt;
        &lt;EventTrigger&gt;
            &lt;Enabled&gt;true&lt;/Enabled&gt;
            &lt;Subscription&gt;&amp;lt;QueryList&amp;gt;&amp;lt;Query Id="0" Path="Application"&amp;gt;&amp;lt;Select Path="Application"&amp;gt;*[System[Provider[@Name='UnattendGenerator'] and EventID=1]]&amp;lt;/Select&amp;gt;&amp;lt;/Query&amp;gt;&amp;lt;/QueryList&amp;gt;&lt;/Subscription&gt;
        &lt;/EventTrigger&gt;
    &lt;/Triggers&gt;
    &lt;Principals&gt;
        &lt;Principal id="Author"&gt;
            &lt;UserId&gt;S-1-5-18&lt;/UserId&gt;
            &lt;RunLevel&gt;LeastPrivilege&lt;/RunLevel&gt;
        &lt;/Principal&gt;
    &lt;/Principals&gt;
    &lt;Settings&gt;
        &lt;MultipleInstancesPolicy&gt;IgnoreNew&lt;/MultipleInstancesPolicy&gt;
        &lt;DisallowStartIfOnBatteries&gt;false&lt;/DisallowStartIfOnBatteries&gt;
        &lt;StopIfGoingOnBatteries&gt;false&lt;/StopIfGoingOnBatteries&gt;
        &lt;AllowHardTerminate&gt;true&lt;/AllowHardTerminate&gt;
        &lt;StartWhenAvailable&gt;false&lt;/StartWhenAvailable&gt;
        &lt;RunOnlyIfNetworkAvailable&gt;false&lt;/RunOnlyIfNetworkAvailable&gt;
        &lt;IdleSettings&gt;
            &lt;StopOnIdleEnd&gt;true&lt;/StopOnIdleEnd&gt;
            &lt;RestartOnIdle&gt;false&lt;/RestartOnIdle&gt;
        &lt;/IdleSettings&gt;
        &lt;AllowStartOnDemand&gt;true&lt;/AllowStartOnDemand&gt;
        &lt;Enabled&gt;true&lt;/Enabled&gt;
        &lt;Hidden&gt;false&lt;/Hidden&gt;
        &lt;RunOnlyIfIdle&gt;false&lt;/RunOnlyIfIdle&gt;
        &lt;WakeToRun&gt;false&lt;/WakeToRun&gt;
        &lt;ExecutionTimeLimit&gt;PT72H&lt;/ExecutionTimeLimit&gt;
        &lt;Priority&gt;7&lt;/Priority&gt;
    &lt;/Settings&gt;
    &lt;Actions Context="Author"&gt;
        &lt;Exec&gt;
            &lt;Command&gt;C:\Windows\System32\wscript.exe&lt;/Command&gt;
            &lt;Arguments&gt;C:\Windows\Setup\Scripts\UnlockStartLayout.vbs&lt;/Arguments&gt;
        &lt;/Exec&gt;
    &lt;/Actions&gt;
&lt;/Task&gt;
        </File>
        <File path="C:\Windows\Setup\Scripts\SetStartPins.ps1">
$json = '{"pinnedList":[]}';
if( [System.Environment]::OSVersion.Version.Build -lt 20000 ) {
    return;
}
$key = 'Registry::HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start';
New-Item -Path $key -ItemType 'Directory' -ErrorAction 'SilentlyContinue';
Set-ItemProperty -LiteralPath $key -Name 'ConfigureStartPins' -Value $json -Type 'String';
        </File>
        <File path="C:\Windows\Setup\Scripts\SetColorTheme.ps1">
$lightThemeSystem = 0;
$lightThemeApps = 0;
$accentColorOnStart = 0;
$enableTransparency = 0;
$htmlAccentColor = '#0078D4';
&amp; {
    $params = @{
        LiteralPath = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';
        Force = $true;
        Type = 'DWord';
    };
    Set-ItemProperty @params -Name 'SystemUsesLightTheme' -Value $lightThemeSystem;
    Set-ItemProperty @params -Name 'AppsUseLightTheme' -Value $lightThemeApps;
    Set-ItemProperty @params -Name 'ColorPrevalence' -Value $accentColorOnStart;
    Set-ItemProperty @params -Name 'EnableTransparency' -Value $enableTransparency;
};
&amp; {
    Add-Type -AssemblyName 'System.Drawing';
    $accentColor = [System.Drawing.ColorTranslator]::FromHtml( $htmlAccentColor );

    function ConvertTo-DWord {
        param(
            [System.Drawing.Color]
            $Color
        );

        [byte[]]$bytes = @(
            $Color.R;
            $Color.G;
            $Color.B;
            $Color.A;
        );
        return [System.BitConverter]::ToUInt32( $bytes, 0);
    }

    $startColor = [System.Drawing.Color]::FromArgb( 0xD2, $accentColor );
    Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'StartColorMenu' -Value( ConvertTo-DWord -Color $accentColor ) -Type 'DWord' -Force;
    Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name 'AccentColorMenu' -Value( ConvertTo-DWord -Color $accentColor ) -Type 'DWord' -Force;
    Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\DWM' -Name 'AccentColor' -Value( ConvertTo-DWord -Color $accentColor ) -Type 'DWord' -Force;
    $params = @{
        LiteralPath = 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent';
        Name = 'AccentPalette';
    };
    $palette = Get-ItemPropertyValue @params;
    $index = 20;
    $palette[ $index++ ] = $accentColor.R;
    $palette[ $index++ ] = $accentColor.G;
    $palette[ $index++ ] = $accentColor.B;
    $palette[ $index++ ] = $accentColor.A;
    Set-ItemProperty @params -Value $palette -Type 'Binary' -Force;
};
        </File>
        <File path="C:\Windows\Setup\Scripts\Specialize.ps1">
$scripts = @(
    {
        reg.exe add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f;
    };
    {
        net.exe accounts /maxpwage:UNLIMITED;
    };
    {
        reg.exe add "HKLM\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d 1 /f;
        [System.Diagnostics.EventLog]::CreateEventSource( 'UnattendGenerator', 'Application' );
    };
    {
        Register-ScheduledTask -TaskName 'UnlockStartLayout' -Xml $( Get-Content -LiteralPath 'C:\Windows\Setup\Scripts\UnlockStartLayout.xml' -Raw );
    };
    {
        reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
    };
    {
        Remove-Item -LiteralPath 'C:\Users\Public\Desktop\Microsoft Edge.lnk' -ErrorAction 'SilentlyContinue' -Verbose;
    };
    {
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f;
    };
    {
        reg.exe add "HKLM\Software\Policies\Microsoft\Edge" /v HideFirstRunExperience /t REG_DWORD /d 1 /f;
    };
    {
        reg.exe add "HKLM\Software\Policies\Microsoft\Edge\Recommended" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f;
        reg.exe add "HKLM\Software\Policies\Microsoft\Edge\Recommended" /v StartupBoostEnabled /t REG_DWORD /d 0 /f;
    };
    {
        &amp; 'C:\Windows\Setup\Scripts\SetStartPins.ps1';
    };
    {
        reg.exe add "HKU\.DEFAULT\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 10 /f;
    };
    {
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f;
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /t REG_DWORD /d 1 /f;
    };
);

&amp; {
  [float]$complete = 0;
  [float]$increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Id 0 -Activity 'Running scripts to customize your Windows installation. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 | Out-String -Width 1KB -Stream &gt;&gt; "C:\Windows\Setup\Scripts\Specialize.log";
        </File>
        <File path="C:\Windows\Setup\Scripts\UserOnce.ps1">
$scripts = @(
    {
        [System.Diagnostics.EventLog]::WriteEntry( 'UnattendGenerator', "User '$env:USERNAME' has requested to unlock the Start menu layout.", [System.Diagnostics.EventLogEntryType]::Information, 1 );
    };
    {
        Remove-Item -Path "${env:USERPROFILE}\Desktop\*.lnk" -Force -ErrorAction 'SilentlyContinue';
        Remove-Item -Path "$env:HOMEDRIVE\Users\Default\Desktop\*.lnk" -Force -ErrorAction 'SilentlyContinue';
    };
    {
        $taskbarPath = "$env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar";
        if( Test-Path $taskbarPath ) {
            Get-ChildItem -Path $taskbarPath -File | Remove-Item -Force;
        }
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Name 'FavoritesRemovedChanges' -Force -ErrorAction 'SilentlyContinue';
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Name 'FavoritesChanges' -Force -ErrorAction 'SilentlyContinue';
        Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Name 'Favorites' -Force -ErrorAction 'SilentlyContinue';
    };
    {
        reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /f;
        $createdClassicMenuKey = $null;
        try {
            $classicMenuPath = 'HKCU:\Software\Classes\CLSID\{51668040-5e31-4023-bbe3-149163bd80f1}';
            if (-not (Test-Path -LiteralPath $classicMenuPath -ErrorAction Stop)) {
                $createdClassicMenuKey = New-Item -Path $classicMenuPath -ErrorAction Stop;
                New-ItemProperty -LiteralPath $classicMenuPath -Name 'AltsClassicContextMenu' -Value 1 -PropertyType DWord -ErrorAction Stop | Out-Null;
            };
            $classicMenuKey = Get-Item -LiteralPath $classicMenuPath -ErrorAction Stop;
            $classicMenuMarker = $classicMenuKey.GetValue('AltsClassicContextMenu');
            if ($classicMenuMarker -is [int] -and $classicMenuMarker -eq 1) {
                $classicMenuServer = "$classicMenuPath\InprocServer32";
                if (-not (Test-Path -LiteralPath $classicMenuServer -ErrorAction Stop)) {
                    New-Item -Path $classicMenuServer -Value '' -ErrorAction Stop | Out-Null;
                } else {
                    $classicMenuServerKey = Get-Item -LiteralPath $classicMenuServer -ErrorAction Stop;
                    if ($classicMenuServerKey.ValueCount -eq 0 -and $classicMenuServerKey.SubKeyCount -eq 0) {
                        Set-Item -LiteralPath $classicMenuServer -Value '' -Force -ErrorAction Stop;
                    };
                };
            };
        } catch {
            Write-Warning "Could not apply the newer classic context menu workaround: $($_.Exception.Message)";
            if ($null -ne $createdClassicMenuKey -and $createdClassicMenuKey.ValueCount -eq 0 -and $createdClassicMenuKey.SubKeyCount -eq 0) {
                try {
                    Remove-Item -LiteralPath $classicMenuPath -ErrorAction Stop;
                } catch {
                    Write-Warning "Could not remove the empty classic context menu key: $($_.Exception.Message)";
                };
            };
        };
    };
    {
        Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Type 'DWord' -Value 1;
    };
    {
        Set-ItemProperty -LiteralPath 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Type 'DWord' -Value 0;
    };
    {
        &amp; 'C:\Windows\Setup\Scripts\SetColorTheme.ps1';
    };
    {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" /v Enabled /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupApp" /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupApp" /v Enabled /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop" /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Microsoft.SkyDrive.Desktop" /v Enabled /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.AccountHealth" /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.AccountHealth" /v Enabled /t REG_DWORD /d 0 /f;
    };
    {
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v AllAppsViewMode /t REG_DWORD /d 2 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_AccountNotifications /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v ShowAllPinsList /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v ShowFrequentList /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v ShowRecentList /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_TrackDocs /t REG_DWORD /d 0 /f;
    };
);

&amp; {
  [float]$complete = 0;
  [float]$increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Id 0 -Activity 'Running scripts to configure this user account. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 | Out-String -Width 1KB -Stream &gt;&gt; "$env:TEMP\UserOnce.log";

# RunOnce and FirstLogonCommands can overlap. Publish completion after the log is flushed.
$completionDir = Join-Path $env:LOCALAPPDATA 'Alt Tweaks';
[System.IO.Directory]::CreateDirectory($completionDir) | Out-Null;
[System.IO.File]::WriteAllText((Join-Path $completionDir 'UserOnce.complete'), '');
        </File>
        <File path="C:\Windows\Setup\Scripts\DefaultUser.ps1">
$scripts = @(
    {
        reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v "StartLayoutFile" /t REG_SZ /d "C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml" /f;
        reg.exe add "HKU\DefaultUser\Software\Policies\Microsoft\Windows\Explorer" /v "LockedStartLayout" /t REG_DWORD /d 1 /f;
    };
    {
        reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f;
    };
    {
        reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f;
    };
    {
        foreach( $root in 'Registry::HKU\.DEFAULT', 'Registry::HKU\DefaultUser' ) {
          Set-ItemProperty -LiteralPath "$root\Control Panel\Keyboard" -Name 'InitialKeyboardIndicators' -Type 'String' -Value 2 -Force;
        }
    };
    {
        reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v TaskbarEndTask /t REG_DWORD /d 1 /f;
    };
    {
        reg.exe add "HKU\DefaultUser\Control Panel\Accessibility\StickyKeys" /v Flags /t REG_SZ /d 10 /f;
    };
    {
        reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\DWM" /v ColorPrevalence /t REG_DWORD /d 0 /f;
    };
    {
        reg.exe add "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "UnattendedSetup" /t REG_SZ /d "powershell.exe -WindowStyle \""Normal\"" -ExecutionPolicy \""Unrestricted\"" -NoProfile -File \""C:\Windows\Setup\Scripts\UserOnce.ps1\""" /f;
    };
);

&amp; {
  [float]$complete = 0;
  [float]$increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Id 0 -Activity 'Running scripts to modify the default user&#x2019;&#x2019;s registry hive. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 | Out-String -Width 1KB -Stream &gt;&gt; "C:\Windows\Setup\Scripts\DefaultUser.log";
        </File>
        <File path="C:\Windows\Setup\Scripts\FirstLogon.ps1">
$scripts = @(
    {
        Remove-Item -LiteralPath @(
          'C:\Windows\Panther\unattend.xml';
          'C:\Windows\Panther\unattend-original.xml';
          'C:\Windows\Setup\Scripts\Wifi.xml';
          'C:\Windows.old';
        ) -Recurse -Force -ErrorAction 'SilentlyContinue';
    };
    {
        reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v UseWUServer /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWindowsUpdateAccess /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v WUServer /f;
        reg.exe delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v WUStatusServer /f;
        reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" /v DODownloadMode /f;
        reg.exe add "HKLM\Software\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 0 /f;
        reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f;
        $services = @{ BITS = 'Manual'; wuauserv = 'Manual'; UsoSvc = 'Automatic' };
        foreach ($name in $services.Keys) {
            Set-Service -Name $name -StartupType $services[$name] -ErrorAction Continue;
        }
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc' -Name 'Start' -Value 3 -Type DWord -ErrorAction Continue;
    };
    {
        reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Education" /f;
        reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start" /f;
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /f;
        reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Education" /v IsEducationEnvironment /t REG_DWORD /d 1 /f;
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f;
        reg.exe add "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start" /v HideRecommendedSection /t REG_DWORD /d 1 /f;
    };
    {
        $recallFeature = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' -and $_.FeatureName -like 'Recall' };
        if( $recallFeature ) {
            Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -Remove -NoRestart -ErrorAction SilentlyContinue;
        }
    };
    {
        $viveDir = Join-Path $env:TEMP 'ViVeTool';
        $viveZip = Join-Path $env:TEMP 'ViVeTool.zip';
        Invoke-WebRequest 'https://github.com/thebookisclosed/ViVe/releases/download/v0.3.4/ViVeTool-v0.3.4-IntelAmd.zip' -OutFile $viveZip;
        Expand-Archive -Path $viveZip -DestinationPath $viveDir -Force;
        Remove-Item -Path $viveZip -Force;
        Start-Process -FilePath (Join-Path $viveDir 'ViVeTool.exe') -ArgumentList '/disable /id:47205210' -Wait -NoNewWindow;
        Remove-Item -Path $viveDir -Recurse -Force;
    };
    {
        Start-Process C:\Windows\System32\OneDriveSetup.exe -ArgumentList /uninstall -Wait
    };
    {
        if( (Get-BitLockerVolume -MountPoint $Env:SystemDrive).ProtectionStatus -eq 'On' ) {
            Disable-BitLocker -MountPoint $Env:SystemDrive;
        }
    };
    {
        if( (bcdedit | Select-String 'path').Count -eq 2 ) {
            bcdedit /set `{bootmgr`} timeout 0;
        }
    };
);

&amp; {
  [float]$complete = 0;
  [float]$increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Id 0 -Activity 'Running scripts to finalize your Windows installation. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 | Out-String -Width 1KB -Stream &gt;&gt; "C:\Windows\Setup\Scripts\FirstLogon.log";

# UserOnce may finish first, so keep any completion flag it has already written.
$completionPath = Join-Path $env:LOCALAPPDATA 'Alt Tweaks\UserOnce.complete';
$deadline = (Get-Date).AddMinutes(5);
'Alt Tweaks: Waiting for user configuration to finish before restarting (up to 5 minutes).' | Out-File -LiteralPath 'C:\Windows\Setup\Scripts\FirstLogon.log' -Append -ErrorAction Stop;
while( -not (Test-Path -LiteralPath $completionPath -PathType Leaf) ) {
    if( (Get-Date) -ge $deadline ) {
        $message = 'Alt Tweaks: Timed out waiting for user configuration. Automatic restart skipped. Check %TEMP%\UserOnce.log.';
        $message | Out-File -LiteralPath 'C:\Windows\Setup\Scripts\FirstLogon.log' -Append -ErrorAction Stop;
        return;
    }
    Start-Sleep -Seconds 1;
}

$message = 'Alt Tweaks: First-logon customization complete. Restarting the computer.';
$message | Out-File -LiteralPath 'C:\Windows\Setup\Scripts\FirstLogon.log' -Append -ErrorAction Stop;
Restart-Computer -Force;
        </File>
    </Extensions>
</unattend>

'@

$embeddedXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Alt Tweaks v3.1"
        Height="860" Width="1300"
        MinHeight="700" MinWidth="1080"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource BrushBgApp}"
        Foreground="{DynamicResource BrushTextPrimary}"
        FontFamily="Segoe UI, Segoe UI Emoji"
        FontSize="13"
        ToolTipService.InitialShowDelay="150"
        ToolTipService.BetweenShowDelay="50"
        ToolTipService.ShowDuration="15000">

    <Window.Resources>
        <!-- Paleta Crimson Noir (Din&#xE2;mica) -->
        <SolidColorBrush x:Key="BrushBgApp" Color="#0B0B0D"/>
        <SolidColorBrush x:Key="BrushBgSidebar" Color="#101014"/>
        <SolidColorBrush x:Key="BrushBgSurface" Color="#16161A"/>
        <SolidColorBrush x:Key="BrushBgCard" Color="#1F1F24"/>
        <SolidColorBrush x:Key="BrushBgCardAlt" Color="#28282F"/>
        <SolidColorBrush x:Key="BrushBgCardHover" Color="#322024"/>
        <SolidColorBrush x:Key="BrushBgInput" Color="#121216"/>
        <SolidColorBrush x:Key="BrushBrandStart" Color="#1F1F24"/>
        <SolidColorBrush x:Key="BrushBrandEnd" Color="#C1121F"/>
        <SolidColorBrush x:Key="BrushBorder" Color="#2F2F38"/>
        <SolidColorBrush x:Key="BrushBorderStrong" Color="#C1121F"/>
        <SolidColorBrush x:Key="BrushBorderHover" Color="#FF4D4D"/>
        <SolidColorBrush x:Key="BrushTextPrimary" Color="#F2F2F2"/>
        <SolidColorBrush x:Key="BrushTextSecondary" Color="#FF4D4D"/>
        <SolidColorBrush x:Key="BrushTextMuted" Color="#A3A3AE"/>
        <SolidColorBrush x:Key="BrushAccent" Color="#C1121F"/>
        <SolidColorBrush x:Key="BrushAccentHover" Color="#FF4D4D"/>
        <SolidColorBrush x:Key="BrushAccentDeep" Color="#4A0D13"/>
        <SolidColorBrush x:Key="BrushAccentText" Color="#F2F2F2"/>
        <SolidColorBrush x:Key="BrushSuccess" Color="#4ADE80"/>
        <SolidColorBrush x:Key="BrushWarning" Color="#FBBF24"/>
        <SolidColorBrush x:Key="BrushDanger" Color="#FF4D4D"/>
        <SolidColorBrush x:Key="BrushConsoleBg" Color="#08080A"/>
        <SolidColorBrush x:Key="BrushConsoleFg" Color="#F2F2F2"/>

        <!-- ToolTip Global Estilizado -->
        <Style TargetType="ToolTip">
            <Setter Property="HasDropShadow" Value="True"/>
            <Setter Property="OverridesDefaultStyle" Value="True"/>
            <Setter Property="Placement" Value="Mouse"/>
            <Setter Property="VerticalOffset" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToolTip">
                        <Border Background="{DynamicResource BrushBgSurface}"
                                BorderBrush="{DynamicResource BrushAccent}"
                                BorderThickness="1.5"
                                CornerRadius="8"
                                Padding="12,9"
                                MaxWidth="360">
                            <Border.Effect>
                                <DropShadowEffect Color="#000000" BlurRadius="14" ShadowDepth="4" Opacity="0.55"/>
                            </Border.Effect>
                            <ContentPresenter>
                                <ContentPresenter.Resources>
                                    <Style TargetType="TextBlock">
                                        <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
                                        <Setter Property="FontSize" Value="12"/>
                                        <Setter Property="TextWrapping" Value="Wrap"/>
                                    </Style>
                                </ContentPresenter.Resources>
                            </ContentPresenter>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar Slim Verde &#xC1;gua -->
        <Style TargetType="ScrollBar">
            <Setter Property="Stylus.IsFlicksEnabled" Value="False"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="8"/>
            <Setter Property="MinWidth" Value="8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.Thumb>
                                    <Thumb Margin="1,0">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border x:Name="ThumbBd"
                                                        Background="{DynamicResource BrushBorder}"
                                                        CornerRadius="4"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ThumbBd" Property="Background" Value="{DynamicResource BrushAccent}"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Height" Value="8"/>
                                <Setter Property="MinHeight" Value="8"/>
                                <Setter Property="Width" Value="Auto"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Bot&#xE3;o Padr&#xE3;o -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource BrushBgCardAlt}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.82"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Bot&#xE3;o Prim&#xE1;rio Verde &#xC1;gua -->
        <Style x:Key="PrimaryButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{DynamicResource BrushAccent}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushAccentText}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushTextSecondary}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Bot&#xE3;o Secund&#xE1;rio Destaque Crimson -->
        <Style x:Key="SuccessButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{DynamicResource BrushBgCardAlt}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushAccent}"/>
        </Style>

        <!-- Bot&#xE3;o Perigo -->
        <Style x:Key="DangerButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#3D0C12"/>
            <Setter Property="Foreground" Value="#FF4D4D"/>
            <Setter Property="BorderBrush" Value="#FF4D4D"/>
        </Style>

        <!-- Bot&#xE3;o Card para os 3 Perfis (Desktop / Notebook / All) -->
        <Style x:Key="PresetCardButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="{DynamicResource BrushBgCardAlt}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorderStrong}"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="9"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushTextSecondary}"/>
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.84"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Chip / P&#xED;lula de Filtro -->
        <Style x:Key="PillButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Padding" Value="11,4"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="14"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Navega&#xE7;&#xE3;o Lateral (Sidebar) -->
        <Style x:Key="NavRadioButtonStyle" TargetType="RadioButton">
            <Setter Property="Foreground" Value="{DynamicResource BrushTextMuted}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="11,9"/>
            <Setter Property="Margin" Value="2,2"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                CornerRadius="8"
                                BorderThickness="3,0,0,0"
                                BorderBrush="Transparent"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Stretch"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushBgCard}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushAccentDeep}"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushTextSecondary}"/>
                                <Setter Property="Foreground" Value="{DynamicResource BrushTextSecondary}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Estilizado -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource BrushBgInput}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="9,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="{DynamicResource BrushAccentHover}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushAccent}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- CheckBox Interativo com Linha de Destaque no Hover + Indicador (?) -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="FontSize" Value="12.2"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="RowBd"
                                Background="Transparent"
                                CornerRadius="6"
                                Padding="7,5">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <Border x:Name="Box"
                                        Grid.Column="0"
                                        Width="18" Height="18"
                                        CornerRadius="4"
                                        Background="{DynamicResource BrushBgInput}"
                                        BorderBrush="{DynamicResource BrushBorder}"
                                        BorderThickness="1.5"
                                        Margin="0,0,9,0"
                                        VerticalAlignment="Center">
                                    <Path x:Name="CheckMark"
                                          Data="M 3.5 8.5 L 7 12 L 13.5 4.5"
                                          Stroke="{DynamicResource BrushAccentText}"
                                          StrokeThickness="2.4"
                                          StrokeStartLineCap="Round"
                                          StrokeEndLineCap="Round"
                                          Visibility="Collapsed"/>
                                </Border>
                                <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                                <TextBlock x:Name="HintBadge"
                                           Grid.Column="2"
                                           Text="?"
                                           FontSize="10.5"
                                           FontWeight="Bold"
                                           Foreground="{DynamicResource BrushAccentHover}"
                                           VerticalAlignment="Center"
                                           Margin="8,0,2,0"
                                           Opacity="0"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Box" Property="Background" Value="{DynamicResource BrushAccent}"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="HintBadge" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Toggle Switch Deslizante com Linha de Destaque no Hover -->
        <Style x:Key="ToggleSwitchStyle" TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="RowBd" Background="Transparent" CornerRadius="6" Padding="7,5">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <ContentPresenter Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                <Border x:Name="Track"
                                        Grid.Column="1"
                                        Width="42" Height="22"
                                        CornerRadius="11"
                                        Background="{DynamicResource BrushBgInput}"
                                        BorderBrush="{DynamicResource BrushBorder}"
                                        BorderThickness="1.2"
                                        Padding="2.5">
                                    <Border x:Name="Thumb"
                                            Width="15" Height="15"
                                            CornerRadius="7.5"
                                            Background="{DynamicResource BrushTextMuted}"
                                            HorizontalAlignment="Left"/>
                                </Border>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Track" Property="Background" Value="{DynamicResource BrushAccent}"/>
                                <Setter TargetName="Track" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                                <Setter TargetName="Thumb" Property="Background" Value="{DynamicResource BrushAccentText}"/>
                                <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                                <Setter TargetName="Track" Property="BorderBrush" Value="{DynamicResource BrushAccentHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ComboBox Estilizado -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="{DynamicResource BrushBgCard}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Padding" Value="9,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter Property="Background" Value="{DynamicResource BrushAccent}"/>
                    <Setter Property="Foreground" Value="{DynamicResource BrushAccentText}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{DynamicResource BrushBgInput}"/>
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton"
                                          Focusable="False"
                                          IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="Bd"
                                                Background="{DynamicResource BrushBgInput}"
                                                BorderBrush="{DynamicResource BrushBorder}"
                                                BorderThickness="1"
                                                CornerRadius="7">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="28"/>
                                                </Grid.ColumnDefinitions>
                                                <Path Grid.Column="1" Data="M 0 0 L 4.5 4.5 L 9 0 Z"
                                                      Fill="{DynamicResource BrushAccentHover}"
                                                      HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource BrushAccent}"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite"
                                              IsHitTestVisible="False"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="10,4,30,4"
                                              VerticalAlignment="Center"
                                              HorizontalAlignment="Left"/>
                            <Popup x:Name="Popup"
                                   Placement="Bottom"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide">
                                <Grid x:Name="DropDown"
                                      SnapsToDevicePixels="True"
                                      MinWidth="{TemplateBinding ActualWidth}"
                                      MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder"
                                            Background="{DynamicResource BrushBgCard}"
                                            BorderThickness="1.5"
                                            CornerRadius="7"
                                            BorderBrush="{DynamicResource BrushAccent}">
                                        <ScrollViewer Margin="2" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Expander Limpo Verde &#xC1;gua -->
        <Style TargetType="Expander">
            <Setter Property="Foreground" Value="{DynamicResource BrushTextPrimary}"/>
            <Setter Property="Background" Value="{DynamicResource BrushBgCard}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="IsExpanded" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Expander">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="9">
                            <DockPanel>
                                <ToggleButton x:Name="HeaderToggle"
                                              DockPanel.Dock="Top"
                                              IsChecked="{Binding IsExpanded, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                              Cursor="Hand">
                                    <ToggleButton.Template>
                                        <ControlTemplate TargetType="ToggleButton">
                                            <Border x:Name="HdrBd" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="8,8,0,0" Padding="10,7">
                                                <Grid>
                                                    <Grid.ColumnDefinitions>
                                                        <ColumnDefinition Width="*"/>
                                                        <ColumnDefinition Width="Auto"/>
                                                    </Grid.ColumnDefinitions>
                                                    <ContentPresenter Grid.Column="0"
                                                                      Content="{Binding Header, RelativeSource={RelativeSource AncestorType=Expander}}"
                                                                      VerticalAlignment="Center"/>
                                                    <Path x:Name="Arrow"
                                                          Grid.Column="1"
                                                          Data="M 0 0 L 5 5 L 10 0"
                                                          Stroke="{DynamicResource BrushAccentHover}"
                                                          StrokeThickness="2"
                                                          StrokeStartLineCap="Round"
                                                          StrokeEndLineCap="Round"
                                                          VerticalAlignment="Center"/>
                                                </Grid>
                                            </Border>
                                            <ControlTemplate.Triggers>
                                                <Trigger Property="IsMouseOver" Value="True">
                                                    <Setter TargetName="HdrBd" Property="Background" Value="{DynamicResource BrushBgCardHover}"/>
                                                </Trigger>
                                                <Trigger Property="IsChecked" Value="False">
                                                    <Setter TargetName="HdrBd" Property="CornerRadius" Value="8"/>
                                                </Trigger>
                                            </ControlTemplate.Triggers>
                                        </ControlTemplate>
                                    </ToggleButton.Template>
                                </ToggleButton>
                                <ContentPresenter x:Name="ExpandSite" Visibility="Collapsed"/>
                            </DockPanel>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsExpanded" Value="True">
                                <Setter TargetName="ExpandSite" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Card Base -->
        <Style x:Key="CardBorderStyle" TargetType="Border">
            <Setter Property="Background" Value="{DynamicResource BrushBgCard}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource BrushBorder}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="14"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="244"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- ================================================================ -->
        <!-- SIDEBAR FIXA                                                     -->
        <!-- ================================================================ -->
        <Border Grid.Column="0" Background="{DynamicResource BrushBgSidebar}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="0,0,1,0">
            <Grid Margin="10,12">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Cart&#xE3;o da Marca com Gradiente Crimson Noir -->
                <Border Grid.Row="0" CornerRadius="10" Padding="12,11" Margin="2,0,2,14" BorderBrush="#FF4D4D" BorderThickness="1">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#1F1F24" Offset="0"/>
                            <GradientStop Color="#C1121F" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <StackPanel>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="&#x26A1; Alt Tweaks" FontSize="17" FontWeight="Bold" Foreground="#F2F2F2"/>
                            <Border Grid.Column="1" Background="#0B0B0D" BorderBrush="#FF4D4D" BorderThickness="1" CornerRadius="5" Padding="6,1" VerticalAlignment="Center">
                                <TextBlock Text="v3.1" FontSize="10" FontWeight="Bold" Foreground="#FF4D4D"/>
                            </Border>
                        </Grid>
                        <TextBlock Text="Otimiza&#xE7;&#xE3;o, Rede &amp; Diagn&#xF3;stico" FontSize="11" Foreground="#F2F2F2" Opacity="0.92" Margin="0,3,0,7"/>
                        <Border Background="#0B0B0D" Opacity="0.92" CornerRadius="5" Padding="7,3" HorizontalAlignment="Left">
                            <TextBlock Text="&#x1F6E1; Administrador Ativo" FontSize="10.5" FontWeight="SemiBold" Foreground="#F2F2F2"/>
                        </Border>
                    </StackPanel>
                </Border>

                <!-- Menu de Navega&#xE7;&#xE3;o Agrupado -->
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <TextBlock Text="OTIMIZA&#xC7;&#xC3;O &amp; APPS" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushTextMuted}" Margin="10,2,0,4"/>
                        <RadioButton x:Name="navTweaks" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}" IsChecked="True">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="&#x26A1;  Tweaks &amp; Perfis"/>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" CornerRadius="8" Padding="6,1"><TextBlock Text="73" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                            </Grid>
                        </RadioButton>
                        <RadioButton x:Name="navHardware" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="&#x1F3AE;  Hardware (GPU &amp; CPU)"/>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" CornerRadius="8" Padding="6,1"><TextBlock Text="16" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                            </Grid>
                        </RadioButton>
                        <RadioButton x:Name="navInstall" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="&#x1F4E6;  Softwares"/>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" CornerRadius="8" Padding="6,1"><TextBlock Text="239" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                            </Grid>
                        </RadioButton>
                        <RadioButton x:Name="navAppx" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="&#x1F9F9;  AppX &amp; Bloatware"/>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" CornerRadius="8" Padding="6,1"><TextBlock Text="34" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                            </Grid>
                        </RadioButton>

                        <TextBlock Text="REDE &amp; MANUTEN&#xC7;&#xC3;O" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushTextMuted}" Margin="10,12,0,4"/>
                        <RadioButton x:Name="navNetwork" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <Grid>
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="&#x1F310;  Rede &amp; Diagn&#xF3;stico"/>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" CornerRadius="8" Padding="6,1"><TextBlock Text="14+" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                            </Grid>
                        </RadioButton>
                        <RadioButton x:Name="navConfig" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <TextBlock Text="&#x2699;  Recursos &amp; Reparos"/>
                        </RadioButton>
                        <RadioButton x:Name="navUpdates" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <TextBlock Text="&#x1F504;  Windows Update"/>
                        </RadioButton>

                        <TextBlock Text="IMAGEM DO WINDOWS" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushTextMuted}" Margin="10,12,0,4"/>
                        <RadioButton x:Name="navIso" GroupName="SidebarNav" Style="{StaticResource NavRadioButtonStyle}">
                            <TextBlock Text="&#x1F4BF;  Criador de ISO &amp; USB"/>
                        </RadioButton>
                    </StackPanel>
                </ScrollViewer>

                <!-- Rodap&#xE9; da Sidebar -->
                <StackPanel Grid.Row="2" Margin="2,8,2,0">
                    <Border Background="{DynamicResource BrushBgCard}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="1" CornerRadius="9" Padding="8">
                        <StackPanel>
                            <TextBlock Text="PERFIL &amp; APAR&#xCA;NCIA" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource BrushTextMuted}" Margin="3,0,0,5"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="btnImportConfig" Grid.Column="0" Content="&#x1F4E5; Importar" FontSize="11" Padding="6,5"/>
                                <Button x:Name="btnExportConfig" Grid.Column="1" Content="&#x1F4E4; Exportar" FontSize="11" Padding="6,5"/>
                            </Grid>
                            <Button x:Name="btnEnvReport" Content="&#x1F4CB; Relat&#xF3;rio do Ambiente" FontSize="11" Padding="6,5"/>
                            <Grid Margin="0,2,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="btnToggleTheme" Grid.Column="0" Content="&#x1F317; Alternar Tema" FontSize="11" Padding="6,5"/>
                                <Button x:Name="btnFontDown" Grid.Column="1" Content="A-" FontSize="11" Padding="8,5"/>
                                <Button x:Name="btnFontUp" Grid.Column="2" Content="A+" FontSize="11" Padding="8,5"/>
                            </Grid>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ================================================================ -->
        <!-- &#xC1;REA PRINCIPAL (HEADER + VIEWS + HOVER BAR + SPLITTER + CONSOLE) -->
        <!-- ================================================================ -->
        <Grid Grid.Column="1" Background="{DynamicResource BrushBgApp}">
            <Grid.RowDefinitions>
                <RowDefinition Height="66"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="5"/>
                <RowDefinition x:Name="rowConsole" Height="155" MinHeight="38"/>
            </Grid.RowDefinitions>

            <!-- HEADER TOPBAR -->
            <Border Grid.Row="0" Background="{DynamicResource BrushBgSurface}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="0,0,0,1" Padding="18,10">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="270"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" VerticalAlignment="Center">
                        <TextBlock x:Name="txtSectionTitle" Text="Tweaks &amp; Perfis Recomendados" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                        <TextBlock x:Name="txtSectionSubtitle" Text="Passe o mouse em qualquer op&#xE7;&#xE3;o para ler o que ela faz ou escolha um perfil abaixo" FontSize="11.5" Foreground="{DynamicResource BrushTextMuted}"/>
                    </StackPanel>

                    <!-- Busca Contextual com Placeholder -->
                    <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="1" CornerRadius="7" Margin="10,4" Padding="9,0">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="&#x1F50D;" VerticalAlignment="Center" Margin="0,0,7,0" FontSize="12"/>
                            <TextBlock x:Name="txtSearchPlaceholder" Grid.Column="1" Text="Filtrar op&#xE7;&#xF5;es desta aba..." VerticalAlignment="Center" FontSize="12" Foreground="{DynamicResource BrushTextMuted}" Opacity="0.7" IsHitTestVisible="False"/>
                            <TextBox x:Name="txtGlobalSearch" Grid.Column="1" BorderThickness="0" Background="Transparent" Padding="0,6" VerticalAlignment="Center"/>
                            <Button x:Name="btnClearSearch" Grid.Column="2" Content="&#x2715;" Padding="4,1" Margin="0" FontSize="10" Background="Transparent" BorderThickness="0"/>
                        </Grid>
                    </Border>

                    <!-- Info Hardware -->
                    <Border Grid.Column="2" Background="{DynamicResource BrushBgCard}" CornerRadius="7" Padding="10,5" Margin="6,4" VerticalAlignment="Center" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="1">
                        <TextBlock x:Name="txtSystemInfo" Text="Carregando hardware..." FontSize="11" Foreground="{DynamicResource BrushTextMuted}"/>
                    </Border>

                    <!-- P&#xED;lula de Status -->
                    <Border x:Name="borderStatusPill" Grid.Column="3" Background="{DynamicResource BrushBgCard}" CornerRadius="7" Padding="10,5" Margin="4,4,0,4" VerticalAlignment="Center" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1">
                        <TextBlock x:Name="txtTaskStatus" Text="&#x25CF; Pronto" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource BrushSuccess}"/>
                    </Border>
                </Grid>
            </Border>

            <!-- CONTAINER DE P&#xC1;GINAS -->
            <Grid Grid.Row="1" Margin="16,12,16,4">

                <!-- ==================================================== -->
                <!-- VIEW 1: SOFTWARES (WINGET / CHOCO - 239 APPS)         -->
                <!-- ==================================================== -->
                <Grid x:Name="viewInstall" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Style="{StaticResource CardBorderStyle}" Padding="10,8">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,12,0">
                                <TextBlock Text="Gerenciador:" VerticalAlignment="Center" FontWeight="SemiBold" Margin="0,0,8,0" Foreground="{DynamicResource BrushTextMuted}"/>
                                <RadioButton x:Name="rbManagerWinget" GroupName="PkgMgr" Content="WinGet" IsChecked="True" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextPrimary}" Margin="0,0,10,0"/>
                                <RadioButton x:Name="rbManagerChoco" GroupName="PkgMgr" Content="Chocolatey" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextPrimary}"/>
                            </StackPanel>

                            <WrapPanel Grid.Column="1" VerticalAlignment="Center">
                                <Button x:Name="btnInstallApps" Style="{StaticResource PrimaryButtonStyle}" Content="&#x2B07; Instalar / Atualizar Selecionados"/>
                                <Button x:Name="btnUninstallApps" Style="{StaticResource DangerButtonStyle}" Content="&#x1F5D1; Desinstalar Selecionados"/>
                                <Button x:Name="btnUpgradeAllApps" Style="{StaticResource SuccessButtonStyle}" Content="&#x1F504; Atualizar Todos"/>
                                <Button x:Name="btnDetectInstalledApps" Content="&#x1F50D; Mostrar Instalados"/>
                                <Button x:Name="btnClearApps" Content="&#x2715; Limpar Sele&#xE7;&#xE3;o"/>
                                <Button x:Name="btnExpandAllApps" Content="Expandir Tudo"/>
                                <Button x:Name="btnCollapseAllApps" Content="Recolher Tudo"/>
                            </WrapPanel>

                            <Border Grid.Column="2" Background="{DynamicResource BrushBgInput}" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1" CornerRadius="7" Padding="10,5" VerticalAlignment="Center">
                                <TextBlock x:Name="txtAppsSelectedCount" Text="Selecionados: 0" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}" FontSize="12"/>
                            </Border>
                        </Grid>
                    </Border>

                    <WrapPanel x:Name="panelAppCategoryChips" Grid.Row="1" Margin="0,0,0,8"/>

                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel x:Name="panelAppsCol0" Grid.Column="0"/>
                            <StackPanel x:Name="panelAppsCol1" Grid.Column="2"/>
                            <StackPanel x:Name="panelAppsCol2" Grid.Column="4"/>
                        </Grid>
                    </ScrollViewer>
                </Grid>

                <!-- ==================================================== -->
                <!-- VIEW 2: TWEAKS & PERFIS (SOMENTE SELE&#xC7;&#xC3;O + RESUMO)    -->
                <!-- ==================================================== -->
                <Grid x:Name="viewTweaks" Visibility="Visible">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Card de Perfis Cards-Bot&#xE3;o (Desktop, Notebook, All) -->
                    <Border Grid.Row="0" Style="{StaticResource CardBorderStyle}" Padding="12,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,14,0">
                                <TextBlock Text="Perfis Recomendados" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                <TextBlock Text="Clique para pr&#xE9;-selecionar e revisar" FontSize="11" Foreground="{DynamicResource BrushTextMuted}"/>
                            </StackPanel>
                            <WrapPanel Grid.Column="1" VerticalAlignment="Center">
                                <Button x:Name="btnPresetDesktop" Style="{StaticResource PresetCardButtonStyle}">
                                    <StackPanel>
                                        <TextBlock Text="&#x1F5A5;  Desktop" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                        <TextBlock Text="PC de Mesa &#x2022; Sem hiberna&#xE7;&#xE3;o" FontSize="10.5" Foreground="{DynamicResource BrushTextMuted}"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="btnPresetNotebook" Style="{StaticResource PresetCardButtonStyle}">
                                    <StackPanel>
                                        <TextBlock Text="&#x1F4BB;  Notebook" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}"/>
                                        <TextBlock Text="Bateria segura &#x2022; Equilibrado" FontSize="10.5" Foreground="{DynamicResource BrushTextMuted}"/>
                                    </StackPanel>
                                </Button>
                                <Button x:Name="btnPresetAll" Style="{StaticResource PresetCardButtonStyle}">
                                    <StackPanel>
                                        <TextBlock Text="&#x1F31F;  All (Marcar Tudo)" FontSize="13" FontWeight="Bold" Foreground="{DynamicResource BrushWarning}"/>
                                        <TextBlock Text="Seleciona todas as 48 op&#xE7;&#xF5;es" FontSize="10.5" Foreground="{DynamicResource BrushTextMuted}"/>
                                    </StackPanel>
                                </Button>
                            </WrapPanel>
                            <Button x:Name="btnCreateRestorePoint" Grid.Column="2" Style="{StaticResource SuccessButtonStyle}" Content="&#x1F6E1; Criar Ponto de Restaura&#xE7;&#xE3;o" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <!-- Painel de Resumo e Confirma&#xE7;&#xE3;o antes de Executar -->
                    <Border x:Name="borderSelectionPreview" Grid.Row="1" Style="{StaticResource CardBorderStyle}" Background="{DynamicResource BrushBgSurface}" BorderBrush="{DynamicResource BrushBorderStrong}" Padding="12,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                    <Border Background="{DynamicResource BrushAccentDeep}" BorderBrush="{DynamicResource BrushAccent}" BorderThickness="1" CornerRadius="6" Padding="9,3" Margin="0,0,10,0">
                                        <TextBlock x:Name="txtActivePresetBadge" Text="Perfil: Nenhum" FontSize="11.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                    </Border>
                                    <TextBlock x:Name="txtTweaksSelectedCount" Text="0 op&#xE7;&#xF5;es selecionadas" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource BrushTextPrimary}" VerticalAlignment="Center"/>
                                </StackPanel>
                                <WrapPanel Grid.Column="2" VerticalAlignment="Center">
                                    <Button x:Name="btnApplyTweaks" Style="{StaticResource PrimaryButtonStyle}" Content="&#x1F680; Aplicar Tweaks Selecionados" Padding="15,7"/>
                                    <Button x:Name="btnUndoTweaks" Content="&#x21A9; Desfazer Selecionados" Padding="12,7"/>
                                    <Button x:Name="btnClearTweaks" Content="&#x2715; Limpar" Padding="10,7"/>
                                </WrapPanel>
                            </Grid>
                            <WrapPanel Grid.Row="1" Margin="0,6,0,0" VerticalAlignment="Center">
                                <Button x:Name="btnPreviewTweaks" Content="&#x1F441; Pr&#xE9;-visualizar Altera&#xE7;&#xF5;es" Padding="10,5"/>
                                <CheckBox x:Name="chkAutoRestorePoint" Content="Criar Ponto de Restaura&#xE7;&#xE3;o autom&#xE1;tico" IsChecked="True" Margin="8,0,6,0" VerticalAlignment="Center"/>
                                <CheckBox x:Name="chkDryRunTweaks" Content="Modo Simula&#xE7;&#xE3;o (Dry-Run)" IsChecked="False" Margin="4,0,0,0" VerticalAlignment="Center"/>
                            </WrapPanel>
                            <ScrollViewer Grid.Row="2" MaxHeight="74" VerticalScrollBarVisibility="Auto" Margin="0,8,0,0">
                                <WrapPanel x:Name="panelSelectedTweaksChips"/>
                            </ScrollViewer>
                        </Grid>
                    </Border>

                    <!-- Grade de 3 Colunas -->
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Coluna 1: Essenciais -->
                            <Border Grid.Column="0" Style="{StaticResource CardBorderStyle}">
                                <StackPanel>
                                    <Grid Margin="0,0,0,8">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Tweaks Essenciais" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                        <Border Grid.Column="1" Background="{DynamicResource BrushAccentDeep}" CornerRadius="5" Padding="6,2"><TextBlock Text="Seguro" FontSize="10" Foreground="{DynamicResource BrushSuccess}"/></Border>
                                    </Grid>
                                    <StackPanel x:Name="panelTweaksEssential"/>
                                </StackPanel>
                            </Border>

                            <!-- Coluna 2: Avan&#xE7;ados -->
                            <Border Grid.Column="2" Style="{StaticResource CardBorderStyle}">
                                <StackPanel>
                                    <Grid Margin="0,0,0,8">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Tweaks Avan&#xE7;ados" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushWarning}"/>
                                        <Border Grid.Column="1" Background="#3B2F1A" CornerRadius="5" Padding="6,2"><TextBlock Text="Cuidado" FontSize="10" Foreground="{DynamicResource BrushWarning}"/></Border>
                                    </Grid>
                                    <StackPanel x:Name="panelTweaksAdvanced"/>
                                    <Border Background="{DynamicResource BrushBgSurface}" CornerRadius="8" Padding="10" Margin="0,10,0,0" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1">
                                        <StackPanel>
                                            <TextBlock Text="Energia &amp; Privacidade Extra" FontSize="12" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,6"/>
                                            <Button x:Name="btnEnableUltPerf" Style="{StaticResource SuccessButtonStyle}" Content="&#x26A1; Ativar Plano Desempenho M&#xE1;ximo"/>
                                            <Button x:Name="btnDisableUltPerf" Content="&#x21A9; Restaurar Planos de Energia Padr&#xE3;o"/>
                                            <Button x:Name="btnRunOOSU" Content="&#x1F6E1; Executar O&amp;O ShutUp10++"/>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </Border>

                            <!-- Coluna 3: Prefer&#xEA;ncias Instant&#xE2;neas -->
                            <Border Grid.Column="4" Style="{StaticResource CardBorderStyle}">
                                <StackPanel>
                                    <Grid Margin="0,0,0,8">
                                        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="Prefer&#xEA;ncias R&#xE1;pidas" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushSuccess}"/>
                                        <Border Grid.Column="1" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="5" Padding="6,2"><TextBlock Text="Instant&#xE2;neo" FontSize="10" Foreground="{DynamicResource BrushAccentHover}"/></Border>
                                    </Grid>
                                    <StackPanel x:Name="panelTweaksPrefs"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                    </ScrollViewer>
                </Grid>

                <!-- ==================================================== -->
                <!-- VIEW 3: APPX & BLOATWARE (34 PACOTES)                 -->
                <!-- ==================================================== -->
                <Grid x:Name="viewAppx" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Style="{StaticResource CardBorderStyle}" Padding="10,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <WrapPanel Grid.Column="0" VerticalAlignment="Center">
                                    <Button x:Name="btnAppxDefault" Style="{StaticResource SuccessButtonStyle}" Content="&#x2B50; Marcar Bloatwares Padr&#xE3;o (18)"/>
                                    <Button x:Name="btnAppxSelectAll" Content="&#x2611; Marcar Todos"/>
                                    <Button x:Name="btnAppxClear" Content="&#x2715; Limpar"/>
                                    <Button x:Name="btnAppxDetectInstalled" Content="&#x1F50D; Destacar Instalados"/>
                                    <Button x:Name="btnAppxRemove" Style="{StaticResource DangerButtonStyle}" Content="&#x1F5D1; Remover Selecionados"/>
                                    <Button x:Name="btnAppxInstall" Style="{StaticResource PrimaryButtonStyle}" Content="&#x1F4E5; Reinstalar Selecionados (Store)"/>
                                </WrapPanel>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1" CornerRadius="7" Padding="10,5" VerticalAlignment="Center">
                                    <TextBlock x:Name="txtAppxSelectedCount" Text="Selecionados: 0" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}" FontSize="12"/>
                                </Border>
                            </Grid>
                            <WrapPanel Grid.Row="1" Margin="0,6,0,0" VerticalAlignment="Center">
                                <Button x:Name="btnAppxPreview" Content="&#x1F441; Pr&#xE9;-visualizar Sele&#xE7;&#xE3;o" Padding="10,5"/>
                                <CheckBox x:Name="chkAppxAutoRestorePoint" Content="Criar Ponto de Restaura&#xE7;&#xE3;o autom&#xE1;tico" IsChecked="True" Margin="8,0,6,0" VerticalAlignment="Center"/>
                                <CheckBox x:Name="chkDryRunAppx" Content="Modo Simula&#xE7;&#xE3;o (Dry-Run)" IsChecked="False" Margin="4,0,0,0" VerticalAlignment="Center"/>
                            </WrapPanel>
                        </Grid>
                    </Border>

                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel x:Name="panelAppxCol0" Grid.Column="0"/>
                            <StackPanel x:Name="panelAppxCol1" Grid.Column="2"/>
                            <StackPanel x:Name="panelAppxCol2" Grid.Column="4"/>
                        </Grid>
                    </ScrollViewer>
                </Grid>

                <!-- ==================================================== -->
                <!-- VIEW 4: REDE, DIAGN&#xD3;STICO COMPLETO & DNS              -->
                <!-- ==================================================== -->
                <ScrollViewer x:Name="viewNetwork" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <Border Style="{StaticResource CardBorderStyle}">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="105"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="85"/>
                                    <ColumnDefinition Width="95"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Host / IP Alvo:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}" FontWeight="SemiBold"/>
                                <TextBox x:Name="txtNetTarget" Grid.Column="1" Margin="0,0,12,0" Text="8.8.8.8"/>
                                <TextBlock Grid.Column="2" Text="Porta TCP:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}" HorizontalAlignment="Right" Margin="0,0,8,0" FontWeight="SemiBold"/>
                                <TextBox x:Name="txtNetPort" Grid.Column="3" Text="443"/>
                            </Grid>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Diagn&#xF3;stico &amp; Testes de Conectividade (Op&#xE7;&#xF5;es 1 a 8)" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <Button x:Name="btnNetQuickDiag" Style="{StaticResource PrimaryButtonStyle}" Content="[1] Diagn&#xF3;stico R&#xE1;pido Integrado" Width="230"/>
                                    <Button x:Name="btnNetDetailed" Content="[2] Teste Detalhado (Ping + HTTPS + DNS)" Width="260"/>
                                    <Button x:Name="btnNetSpeedtest" Content="[3] Teste Velocidade Download (Mbps)" Width="245"/>
                                    <Button x:Name="btnNetWifi" Content="[4] Diagn&#xF3;stico Wi-Fi (Sinal/Redes)" Width="225"/>
                                    <Button x:Name="btnNetWifiReport" Content="[4b] Gerar Relat&#xF3;rio Wi-Fi (HTML)" Width="225"/>
                                    <Button x:Name="btnNetTestPort" Content="[5] Testar Porta TCP Alvo" Width="185"/>
                                    <Button x:Name="btnNetPathping" Content="[6] Perda de Pacotes (Pathping)" Width="215"/>
                                    <Button x:Name="btnNetTracert" Content="[7] Rastrear Rota (Tracert)" Width="195"/>
                                    <Button x:Name="btnNetPingCont" Content="[8] Ping Cont&#xED;nuo (-t)" Width="175"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Monitoramento, Varredura &amp; Dispositivos Locais (Op&#xE7;&#xF5;es 9 a 11)" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <Button x:Name="btnNetstatEst" Content="[9a] Netstat: Conex&#xF5;es Ativas" Width="210"/>
                                    <Button x:Name="btnNetstatList" Content="[9b] Netstat: Portas Escutando" Width="210"/>
                                    <Button x:Name="btnNetstatAll" Content="[9c] Netstat: Tudo Detalhado" Width="200"/>
                                    <Button x:Name="btnNetSubnetScan" Style="{StaticResource SuccessButtonStyle}" Content="[10] Varredura Rede Local (IPs Livres/Ocupados)" Width="310"/>
                                    <Button x:Name="btnNetIpConfig" Content="[11] Exibir ipconfig /all" Width="170"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Reparo, Reset de Pilha, TCP Gaming &amp; Relat&#xF3;rio Forense (Op&#xE7;&#xF5;es 12 a 14)" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <Button x:Name="btnNetSimpleRepair" Content="[12] Reparar Conex&#xE3;o (DNS/DHCP/NetBIOS)" Width="270"/>
                                    <Button x:Name="btnNetResetDeep" Style="{StaticResource DangerButtonStyle}" Content="[13] Reset Completo Pilha (Winsock/TCP/FW)" Width="280"/>
                                    <Button x:Name="btnNetForensicReport" Style="{StaticResource PrimaryButtonStyle}" Content="[14] Gerar Relat&#xF3;rio Forense Completo (.TXT)" Width="295"/>
                                    <Button x:Name="btnRestartAdapters" Content="Reiniciar Placas de Rede" Width="185"/>
                                    <Button x:Name="btnOptimizeTcpTab" Style="{StaticResource SuccessButtonStyle}" Content="&#x1F680; Otimizar TCP Baixa Lat&#xEA;ncia" Width="220"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Servidores DNS (IPv4 + IPv6 + DoH) &amp; Benchmark de Lat&#xEA;ncia" FontSize="13.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="280"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Provedor DNS:" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <ComboBox x:Name="cmbDnsProvider" Grid.Column="1" Margin="0,0,10,0"/>
                                    <Button x:Name="btnApplyDns" Grid.Column="2" Style="{StaticResource PrimaryButtonStyle}" Content="Aplicar DNS Selecionado"/>
                                    <Button x:Name="btnDnsBenchmark" Grid.Column="3" Style="{StaticResource SuccessButtonStyle}" Content="&#x26A1; Benchmark DNS (Lat&#xEA;ncia)"/>
                                </Grid>
                                <WrapPanel>
                                    <Button x:Name="btnDnsCloudflare" Content="Cloudflare (1.1.1.1)"/>
                                    <Button x:Name="btnDnsGoogle" Content="Google (8.8.8.8)"/>
                                    <Button x:Name="btnDnsQuad9" Content="Quad9 (9.9.9.9)"/>
                                    <Button x:Name="btnDnsAdGuard" Content="AdGuard (Anti-An&#xFA;ncios)"/>
                                    <Button x:Name="btnDnsDhcp" Content="Restaurar Autom&#xE1;tico (DHCP)"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- ==================================================== -->
                <!-- VIEW 5: RECURSOS, CORRE&#xC7;&#xD5;ES & PAIN&#xC9;IS DO SISTEMA      -->
                <!-- ==================================================== -->
                <ScrollViewer x:Name="viewConfig" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="12"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Recursos Opcionais do Windows" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <StackPanel x:Name="panelFeaturesContainer"/>
                                <Button x:Name="btnInstallFeatures" Style="{StaticResource PrimaryButtonStyle}" Content="&#x2699; Instalar / Aplicar Recursos Selecionados" Margin="0,10,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="0" Grid.Column="2" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Corre&#xE7;&#xF5;es &amp; Reparos do Sistema" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <Button x:Name="btnFixFullCorruption" Style="{StaticResource PrimaryButtonStyle}" Content="&#x1F6E0; Verifica&#xE7;&#xE3;o Completa (DISM + SFC)" Width="265"/>
                                    <Button x:Name="btnSfcScan" Content="SFC /scannow" Width="125"/>
                                    <Button x:Name="btnDismRepair" Content="DISM /RestoreHealth" Width="155"/>
                                    <Button x:Name="btnDismCleanup" Content="Limpar WinSxS" Width="130"/>
                                    <Button x:Name="btnFixWuReset" Content="Resetar Windows Update" Width="185"/>
                                    <Button x:Name="btnFixWuResetAggressive" Style="{StaticResource DangerButtonStyle}" Content="Resetar WU (Agressivo)" Width="180"/>
                                    <Button x:Name="btnFixNetwork" Content="Resetar Rede Completa" Width="170"/>
                                    <Button x:Name="btnFixWinget" Content="Reinstalar / Reparar WinGet" Width="205"/>
                                    <Button x:Name="btnFixNtpPool" Content="Sincronizar NTP (pool.ntp.org)" Width="210"/>
                                    <Button x:Name="btnFixAutologon" Content="Executar Autologon (Sysinternals)" Width="225"/>
                                    <Button x:Name="btnRestartSpooler" Content="Destravar Spooler Impress&#xE3;o" Width="200"/>
                                    <Button x:Name="btnScheduleChkdsk" Content="Agendar CHKDSK (Disco C:)" Width="195"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="1" Grid.Column="0" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Pain&#xE9;is Cl&#xE1;ssicos do Windows (14)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <WrapPanel x:Name="panelLegacyPanelsContainer"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="1" Grid.Column="2" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="Acesso Remoto &amp; Perfil PowerShell 7+" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <TextBlock Text="Habilite o servidor SSH nativo no Windows (porta 22) ou instale o perfil aprimorado para PowerShell 7 com hist&#xF3;rico preditivo." TextWrapping="Wrap" FontSize="11.5" Foreground="{DynamicResource BrushTextMuted}" Margin="0,0,0,10"/>
                                <WrapPanel>
                                    <Button x:Name="btnEnableSshServer" Style="{StaticResource SuccessButtonStyle}" Content="&#x1F510; Habilitar Servidor OpenSSH"/>
                                    <Button x:Name="btnInstallPsProfile" Content="&#x1F4BB; Instalar Perfil PowerShell 7"/>
                                    <Button x:Name="btnUninstallPsProfile" Content="&#x1F5D1; Remover Perfil PowerShell 7"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>

                <!-- ==================================================== -->
                <!-- VIEW 6: WINDOWS UPDATE                                -->
                <!-- ==================================================== -->
                <ScrollViewer x:Name="viewUpdates" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="12"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="&#x1F504; Padr&#xE3;o Original (Microsoft)" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,6"/>
                                <TextBlock Text="Remove pol&#xED;ticas personalizadas, libera permiss&#xF5;es bloqueadas e restaura as configura&#xE7;&#xF5;es originais de f&#xE1;brica do Windows Update." TextWrapping="Wrap" Foreground="{DynamicResource BrushTextMuted}" Margin="0,0,0,12"/>
                                <Button x:Name="btnWuDefault" Content="Restaurar Configura&#xE7;&#xF5;es Padr&#xE3;o"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="0" Grid.Column="2" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="&#x1F6E1; Modo Recomendado (Seguran&#xE7;a Est&#xE1;vel)" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrushSuccess}" Margin="0,0,0,6"/>
                                <TextBlock Text="Bloqueia atualiza&#xE7;&#xE3;o autom&#xE1;tica de drivers via Update, adia atualiza&#xE7;&#xF5;es de recursos por 365 dias e qualidade por 4 dias." TextWrapping="Wrap" Foreground="{DynamicResource BrushTextMuted}" Margin="0,0,0,12"/>
                                <Button x:Name="btnWuRecommended" Style="{StaticResource SuccessButtonStyle}" Content="Aplicar Modo Recomendado"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="1" Grid.Column="0" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="&#x23F8; Pausar Atualiza&#xE7;&#xF5;es (At&#xE9; 2042)" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrushWarning}" Margin="0,0,0,6"/>
                                <TextBlock Text="Estende a pausa oficial do Windows Update at&#xE9; 2042 sem desativar servi&#xE7;os cr&#xED;ticos do sistema ou da Microsoft Store." TextWrapping="Wrap" Foreground="{DynamicResource BrushTextMuted}" Margin="0,0,0,12"/>
                                <Button x:Name="btnWuPause" Content="Pausar Atualiza&#xE7;&#xF5;es at&#xE9; 2042"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Row="1" Grid.Column="2" Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="&#x26A0; Desativar Todas as Atualiza&#xE7;&#xF5;es (Avan&#xE7;ado)" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource BrushDanger}" Margin="0,0,0,6"/>
                                <TextBlock Text="Para e desabilita BITS, wuauserv, UsoSvc e tarefas agendadas de update. Recomendado apenas para ambientes isolados." TextWrapping="Wrap" Foreground="{DynamicResource BrushTextMuted}" Margin="0,0,0,12"/>
                                <Button x:Name="btnWuDisable" Style="{StaticResource DangerButtonStyle}" Content="Desativar Windows Update"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>

                <!-- ==================================================== -->
                <!-- VIEW 7: CRIADOR DE ISO & PENDRIVE USB BOOT&#xC1;VEL        -->
                <!-- ==================================================== -->
                <ScrollViewer x:Name="viewIso" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="1. Imagem ISO Oficial &amp; Sele&#xE7;&#xE3;o de Edi&#xE7;&#xE3;o" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="135"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Arquivo ISO Origem:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <TextBox x:Name="txtIsoPath" Grid.Column="1" Margin="0,0,8,0"/>
                                    <Button x:Name="btnBrowseIso" Grid.Column="2" Content="Procurar ISO..."/>
                                    <Button x:Name="btnInspectIso" Grid.Column="3" Style="{StaticResource PrimaryButtonStyle}" Content="Analisar Edi&#xE7;&#xF5;es"/>
                                </Grid>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="135"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Edi&#xE7;&#xE3;o Selecionada:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <ComboBox x:Name="cmbIsoEdition" Grid.Column="1"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="2. Destino, Drivers &amp; Customiza&#xE7;&#xF5;es" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="135"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Pasta de Destino:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <TextBox x:Name="txtOutputIsoDir" Grid.Row="0" Grid.Column="1" Margin="0,0,8,6" Text="C:\ISO_Work"/>
                                    <Button x:Name="btnBrowseOutputDir" Grid.Row="0" Grid.Column="2" Content="Selecionar Pasta..." Margin="3,0,3,6"/>

                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Nome do Arquivo:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <TextBox x:Name="txtOutputIsoName" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Text="Windows_Custom_Pro.iso"/>
                                </Grid>

                                <CheckBox x:Name="chkIsoBypassHw" Content="Bypass Requisitos Windows 11 (TPM 2.0, Secure Boot, RAM e CPU)" IsChecked="True"/>
                                <CheckBox x:Name="chkIsoBypassAcc" Content="Bypass Conta Microsoft Obrigat&#xF3;ria (Conta Local Offline - BypassNRO)" IsChecked="True"/>
                                <CheckBox x:Name="chkIsoDisableBitLocker" Content="Desativar Criptografia Autom&#xE1;tica BitLocker no Primeiro Boot" IsChecked="True"/>
                                <CheckBox x:Name="chkIsoDebloat" Content="Remover Bloatwares AppX Provisionados na Raiz da Imagem" IsChecked="True"/>
                                <CheckBox x:Name="chkIsoUnattend" Content="Injetar autounattend.xml Completo (Privacidade + P&#xF3;s-Instala&#xE7;&#xE3;o Autom&#xE1;tica)" IsChecked="True"/>
                                <CheckBox x:Name="chkIsoInjectDrivers" Content="Exportar e Injetar Drivers deste Computador na ISO (install.wim + boot.wim)" IsChecked="False"/>

                                <Button x:Name="btnBuildCustomIso" Style="{StaticResource PrimaryButtonStyle}" Content="&#x1F680; Preparar e Gerar ISO Otimizada" Height="40" FontSize="14" Margin="0,10,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardBorderStyle}">
                            <StackPanel>
                                <TextBlock Text="3. Gravar M&#xED;dia Preparada Diretamente em Pendrive USB (Boot&#xE1;vel FAT32 UEFI)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushWarning}" Margin="0,0,0,8"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="135"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Unidade USB Alvo:" VerticalAlignment="Center" Foreground="{DynamicResource BrushTextMuted}"/>
                                    <ComboBox x:Name="cmbUsbDrive" Grid.Column="1" Margin="0,0,8,0"/>
                                    <Button x:Name="btnRefreshUsb" Grid.Column="2" Content="&#x1F504; Atualizar USBs"/>
                                    <Button x:Name="btnWriteUsb" Grid.Column="3" Style="{StaticResource DangerButtonStyle}" Content="&#x1F4BE; Formatar e Gravar Pendrive"/>
                                </Grid>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <!-- ==================================================== -->
                <!-- VIEW 8: HARDWARE (GPU NVIDIA/AMD & CPU AMD/INTEL)     -->
                <!-- ==================================================== -->
                <Grid x:Name="viewHardware" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Resumo de Hardware Detectado + A&#xE7;&#xF5;es -->
                    <Border Grid.Row="0" Style="{StaticResource CardBorderStyle}" Padding="12,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <Border Grid.Row="0" Background="{DynamicResource BrushBgSurface}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="1" CornerRadius="8" Padding="10,7" Margin="0,0,0,8">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="txtHwDetectedGpu" Grid.Column="0" Text="GPU: Detectando..." FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource BrushTextPrimary}"/>
                                        <TextBlock x:Name="txtHwDetectedCpu" Grid.Column="1" Text="CPU: Detectando..." FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource BrushTextPrimary}"/>
                                    </Grid>
                                    <TextBlock x:Name="txtHwDetectedTips" Text="Analisando hardware instalado..." FontSize="11" Foreground="{DynamicResource BrushTextMuted}" TextWrapping="Wrap" Margin="0,3,0,0"/>
                                </StackPanel>
                            </Border>

                            <Grid Grid.Row="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <WrapPanel Grid.Column="0" VerticalAlignment="Center">
                                    <Button x:Name="btnHwAutoSelect" Style="{StaticResource SuccessButtonStyle}" Content="&#x2728; Auto-Selecionar Recomendados"/>
                                    <Button x:Name="btnHwApply" Style="{StaticResource PrimaryButtonStyle}" Content="&#x1F680; Aplicar Selecionados"/>
                                    <Button x:Name="btnHwUndo" Content="&#x21A9; Desfazer Selecionados"/>
                                    <Button x:Name="btnHwClear" Content="&#x2715; Limpar"/>
                                </WrapPanel>
                                <Border Grid.Column="1" Background="{DynamicResource BrushBgInput}" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1" CornerRadius="7" Padding="10,5" VerticalAlignment="Center">
                                    <TextBlock x:Name="txtHwSelectedCount" Text="Selecionados: 0" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}" FontSize="12"/>
                                </Border>
                            </Grid>

                            <WrapPanel Grid.Row="2" Margin="0,6,0,0" VerticalAlignment="Center">
                                <Button x:Name="btnHwPreview" Content="&#x1F441; Pr&#xE9;-visualizar Altera&#xE7;&#xF5;es" Padding="10,5"/>
                                <CheckBox x:Name="chkHwAutoRestorePoint" Content="Criar Ponto de Restaura&#xE7;&#xE3;o autom&#xE1;tico" IsChecked="True" Margin="8,0,6,0" VerticalAlignment="Center"/>
                                <CheckBox x:Name="chkHwDryRun" Content="Modo Simula&#xE7;&#xE3;o (Dry-Run)" IsChecked="False" Margin="4,0,0,0" VerticalAlignment="Center"/>
                            </WrapPanel>
                        </Grid>
                    </Border>

                    <!-- Grade de GPU e CPU + Ferramentas Externas -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="10"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <!-- Coluna Esquerda: GPU -->
                                <StackPanel Grid.Column="0">
                                    <Border Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="GPU Geral (NVIDIA &amp; AMD)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushAccentDeep}" CornerRadius="5" Padding="6,2"><TextBlock Text="Universal" FontSize="10" Foreground="{DynamicResource BrushSuccess}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwGpuGeneral"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="borderHwNvidia" Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="GPU NVIDIA (GeForce / RTX)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushSuccess}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="5" Padding="6,2"><TextBlock x:Name="txtHwNvidiaBadge" Text="Verificando..." FontSize="10" Foreground="{DynamicResource BrushTextMuted}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwGpuNvidia"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="borderHwAmdGpu" Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="GPU AMD Radeon" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushDanger}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="5" Padding="6,2"><TextBlock x:Name="txtHwAmdGpuBadge" Text="Verificando..." FontSize="10" Foreground="{DynamicResource BrushTextMuted}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwGpuAmd"/>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>

                                <!-- Coluna Direita: CPU -->
                                <StackPanel Grid.Column="2">
                                    <Border Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="CPU Geral (Energia &amp; Throttling)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushAccentDeep}" CornerRadius="5" Padding="6,2"><TextBlock Text="Universal" FontSize="10" Foreground="{DynamicResource BrushSuccess}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwCpuGeneral"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="borderHwAmdCpu" Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="CPU AMD (Ryzen / X3D)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushWarning}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="5" Padding="6,2"><TextBlock x:Name="txtHwAmdCpuBadge" Text="Verificando..." FontSize="10" Foreground="{DynamicResource BrushTextMuted}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwCpuAmd"/>
                                        </StackPanel>
                                    </Border>

                                    <Border x:Name="borderHwIntelCpu" Style="{StaticResource CardBorderStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,8">
                                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="0" Text="CPU Intel (Core / P-Cores + E-Cores)" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}"/>
                                                <Border Grid.Column="1" Background="{DynamicResource BrushBgCardAlt}" CornerRadius="5" Padding="6,2"><TextBlock x:Name="txtHwIntelCpuBadge" Text="Verificando..." FontSize="10" Foreground="{DynamicResource BrushTextMuted}"/></Border>
                                            </Grid>
                                            <StackPanel x:Name="panelHwCpuIntel"/>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </Grid>

                            <!-- Ferramentas Externas & Drivers Oficiais -->
                            <Border Style="{StaticResource CardBorderStyle}">
                                <StackPanel>
                                    <TextBlock Text="Ferramentas Externas &amp; Portais Oficiais de Drivers" FontSize="14" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,0,8"/>
                                    <WrapPanel>
                                        <Button x:Name="btnHwToolNvCleanstall" Style="{StaticResource SuccessButtonStyle}" Content="&#x1F4E6; Instalar NVCleanstall"/>
                                        <Button x:Name="btnHwToolDdu" Style="{StaticResource DangerButtonStyle}" Content="&#x1F9F9; Instalar DDU (Display Driver Uninstaller)"/>
                                        <Button x:Name="btnHwToolAfterburner" Content="&#x1F3AE; Instalar MSI Afterburner"/>
                                        <Button x:Name="btnHwToolGpuZ" Content="&#x1F50D; Instalar GPU-Z"/>
                                        <Button x:Name="btnHwToolCpuZ" Content="&#x1F50D; Instalar CPU-Z"/>
                                        <Button x:Name="btnHwToolHwInfo" Content="&#x1F4CA; Instalar HWiNFO"/>
                                        <Button x:Name="btnHwUrlNvidia" Content="&#x1F310; Drivers NVIDIA"/>
                                        <Button x:Name="btnHwUrlAmd" Content="&#x1F310; Drivers AMD"/>
                                        <Button x:Name="btnHwUrlIntel" Content="&#x1F310; Drivers Intel"/>
                                    </WrapPanel>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>

            <!-- BARRA DE INSPE&#xC7;&#xC3;O AO VIVO (HOVER INFO INSTANT&#xC2;NEO) -->
            <Border x:Name="borderHoverInfo" Grid.Row="2" Background="{DynamicResource BrushBgSurface}" BorderBrush="{DynamicResource BrushBorderStrong}" BorderThickness="1" CornerRadius="8" Margin="16,2,16,4">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="4"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Border Grid.Column="0" Background="{DynamicResource BrushAccent}" CornerRadius="6,0,0,6"/>
                    <TextBlock Grid.Column="1" Text="&#x1F4A1;" FontSize="14" VerticalAlignment="Center" Margin="10,0,8,0"/>
                    <Border x:Name="borderHoverBadge" Grid.Column="2" Background="{DynamicResource BrushAccentDeep}" BorderBrush="{DynamicResource BrushAccent}" BorderThickness="1" CornerRadius="6" Padding="8,2" VerticalAlignment="Center" Margin="0,0,10,0">
                        <TextBlock x:Name="txtHoverBadge" Text="Dica" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}"/>
                    </Border>
                    <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,6,12,6">
                        <TextBlock x:Name="txtHoverTitle" Text="Inspe&#xE7;&#xE3;o R&#xE1;pida" FontSize="12.5" FontWeight="Bold" Foreground="{DynamicResource BrushTextSecondary}" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="txtHoverDesc" Text="Passe o mouse sobre qualquer op&#xE7;&#xE3;o ou bot&#xE3;o para ver o que ele faz antes de clicar." FontSize="12" Foreground="{DynamicResource BrushTextPrimary}" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- SPLITTER REDIMENSION&#xC1;VEL DO CONSOLE -->
            <GridSplitter Grid.Row="3" Height="5" HorizontalAlignment="Stretch" Background="{DynamicResource BrushBorder}" Cursor="SizeNS"/>

            <!-- CONSOLE DRAWER INFERIOR -->
            <Border Grid.Row="4" Background="{DynamicResource BrushConsoleBg}" BorderBrush="{DynamicResource BrushBorder}" BorderThickness="0,1,0,0" Padding="14,6">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,4">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="&#x1F4DC; Console de Execu&#xE7;&#xE3;o &amp; Logs" FontSize="11.5" FontWeight="Bold" Foreground="{DynamicResource BrushAccentHover}" VerticalAlignment="Center" Margin="0,0,14,0"/>
                        <ProgressBar x:Name="pbTaskProgress" Grid.Column="1" Height="6" IsIndeterminate="True" Visibility="Collapsed" VerticalAlignment="Center" Foreground="{DynamicResource BrushAccent}" Background="{DynamicResource BrushBgCard}"/>
                        <StackPanel Grid.Column="3" Orientation="Horizontal">
                            <Button x:Name="btnToggleConsole" Content="&#x25BC; Minimizar" Padding="8,3" FontSize="11"/>
                            <Button x:Name="btnCopyLogs" Content="&#x1F4CB; Copiar" Padding="8,3" FontSize="11"/>
                            <Button x:Name="btnSaveLogs" Content="&#x1F4BE; Salvar" Padding="8,3" FontSize="11"/>
                            <Button x:Name="btnClearLogs" Content="&#x1F9F9; Limpar" Padding="8,3" FontSize="11"/>
                        </StackPanel>
                    </Grid>

                    <TextBox x:Name="txtLog" Grid.Row="1"
                             Background="{DynamicResource BrushConsoleBg}"
                             Foreground="{DynamicResource BrushConsoleFg}"
                             FontFamily="Consolas"
                             FontSize="12"
                             IsReadOnly="True"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             TextWrapping="Wrap"
                             BorderThickness="0"
                             Padding="4"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>

'@

# 3. Iniciar Interface Gráfica (HUD v3.0)
Start-WinRepairUI -XamlText $embeddedXaml -Configs $embeddedConfigs -AutoUnattendXml $embeddedUnattendXml
