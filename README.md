# Alt's v3.1

Utilitário gráfico (WPF) em PowerShell para otimização, manutenção, diagnóstico de rede, gerenciamento de aplicativos e criação de mídia bootável do Windows 10 e Windows 11.

## Execução Rápida

Abra o PowerShell como **Administrador** e execute:

```powershell
irm https://raw.githubusercontent.com/joaolsr21/alts/main/dist/alts.ps1 | iex
```

## Funcionalidades

- **Tweaks & Perfis Recomendados**: perfis pré-configurados (`Desktop`, `Notebook` e `All`), ajustes de privacidade/desempenho, preferências instantâneas, plano de energia *Desempenho Máximo* e integração com O&O ShutUp10++.
- **Hardware (GPU & CPU)**: detecção automática de GPU (NVIDIA/AMD) e CPU (AMD Ryzen/X3D e Intel Core/Híbrida) com otimizações reversíveis (HAGS, MMCSS, PCIe ASPM, MSI Mode, ULPS, Telemetria, Core Parking, Power Throttling, Agendamento P-Cores, limpeza de Shader Cache) e atalhos para NVCleanstall, DDU, MSI Afterburner, GPU-Z, CPU-Z, HWiNFO e portais oficiais de drivers.
- **Catálogo de Softwares**: instalação, desinstalação, detecção e atualização em lote via **WinGet** ou **Chocolatey**.
- **Gerenciador de AppX & Bloatware**: listagem, remoção (usuário atual e pacotes provisionados) e reinstalação pela Microsoft Store.
- **Rede, Diagnóstico & DNS**: diagnóstico rápido/detalhado, teste de velocidade, Wi-Fi, `pathping`, `tracert`, `netstat`, varredura de sub-rede local, reset de pilha TCP/IP, otimização TCP e benchmark/aplicação de DNS (IPv4, IPv6 e DoH).
- **Recursos, Reparos & Painéis Clássicos**: habilitação de recursos opcionais do Windows, `DISM` / `SFC`, reset do Windows Update, OpenSSH Server, perfil PowerShell 7 e acesso rápido a painéis clássicos.
- **Políticas do Windows Update**: alternância entre padrão Microsoft, modo recomendado, pausa estendida até 2042 ou desativação.
- **Criador de ISO & Pendrive USB**: inspeção de edições, injeção de `autounattend.xml`/drivers e gravação em pendrive UEFI FAT32.

### Segurança e Controle antes de Executar

- **Ponto de Restauração Automático**: opção habilitada por padrão antes de aplicar/desfazer tweaks ou remover pacotes AppX.
- **Pré-visualização de Alterações**: exibe todas as chaves de registro, serviços, scripts customizados ou pacotes AppX que serão afetados antes da execução.
- **Modo Simulação (`Dry-Run`)**: executa o fluxo registrando exatamente o que seria alterado no console, sem modificar o sistema.

## Requisitos

- Windows 10 ou Windows 11
- Windows PowerShell 5.1 ou PowerShell 7+
- Privilégios de Administrador (o script solicita elevação via UAC automaticamente)

## Desenvolvimento, Compilação e Testes

### Executar localmente a partir do código-fonte

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\main.ps1
```

### Compilar o bundle standalone (`dist/alts.ps1`)

O script [build.ps1](build.ps1) valida os XMLs (`app.xaml` e `autounattend.xml`), protege os blocos *here-string* de configurações JSON/XML, gera o arquivo único em UTF-8 sem BOM e valida a sintaxe PowerShell do bundle resultante:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

### Executar validação local e testes

Validação sem dependências externas (sintaxe, JSONs, integridade referencial de `presets.json`, vínculos `x:Name` no XAML, build em pasta temporária, modo `Dry-Run` e pré-visualização):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-LocalValidation.ps1
```

Com **Pester v5+**:

```powershell
Invoke-Pester -Path .\tests\Alts.Tests.ps1 -CI
```

## Estrutura do Projeto

```text
├── .github/workflows/ci.yml        # Pipeline CI (PSScriptAnalyzer, build e testes)
├── build.ps1                       # Empacotador standalone + validação pós-build
├── dist/alts.ps1                   # Script único compilado para execução via irm | iex
├── PSScriptAnalyzerSettings.psd1   # Regras de lint do PowerShell
├── src/
│   ├── main.ps1                    # Ponto de entrada local
│   ├── config/                     # Configurações declarativas JSON e autounattend.xml
│   ├── core/                       # Elevação UAC e sistema de logs assíncrono
│   ├── modules/                    # Módulos funcionais (tweaks, rede, AppX, ISO, etc.)
│   └── ui/                         # Interface WPF (app.xaml) e controlador (controller.ps1)
└── tests/
    ├── Alts.Tests.ps1              # Suíte de testes Pester v5
    └── Invoke-LocalValidation.ps1  # Validador local compatível com PowerShell 5.1+
```

## Avisos de Segurança

- As ações de tweaks, remoção de pacotes AppX, alterações de políticas do Windows Update e gravação de pendrive modificam configurações do sistema ou unidades de armazenamento.
- Sempre revise a lista selecionada usando **Pré-visualizar Alterações** ou teste primeiro com **Modo Simulação (Dry-Run)**, e mantenha o **Ponto de Restauração automático** ativado antes de aplicar mudanças em máquinas de produção.
