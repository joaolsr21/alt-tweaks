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
