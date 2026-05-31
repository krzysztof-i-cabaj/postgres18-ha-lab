# ==============================================================================
# Tytul:        lab.ps1
# Opis:         Entrypoint laboratorium PG18 HA. Dispatcher czasownikow
#               (build, prereqs, status, scenario, dns, ...). Tylko dispatcher --
#               logika zyje w host/modules/*.psm1.
# Description [EN]: Entrypoint for PG18 HA lab. Verb dispatcher
#               (build, prereqs, status, scenario, dns, ...). Dispatcher only --
#               logic lives in host/modules/*.psm1.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Windows 11 Pro
#                    - PowerShell 5.1+ (lub PowerShell 7+)
#                    - VirtualBox 7.0+ (provides VBoxManage.exe)
#                    - Otwarty port 8000/tcp na hoscie
# Requirements [EN]: - Windows 11 Pro
#                    - PowerShell 5.1+ (or PowerShell 7+)
#                    - VirtualBox 7.0+ (provides VBoxManage.exe)
#                    - Free TCP port 8000 on host
#
# Uzycie [PL]:       .\lab.ps1 help
#                    .\lab.ps1 prereqs
#                    .\lab.ps1 build [-Topology default|extended]
# Usage [EN]:        .\lab.ps1 help
#                    .\lab.ps1 prereqs
#                    .\lab.ps1 build [-Topology default|extended]
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Verb = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Repo root + module loading
# ------------------------------------------------------------------------------
$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ModulesDir = Join-Path $script:RepoRoot 'host\modules'

# Umbrella module imports every functional module
$umbrella = Join-Path $script:RepoRoot 'host\PgHaLab.psm1'
if (Test-Path $umbrella) {
    Import-Module $umbrella -Force -DisableNameChecking
}

# ------------------------------------------------------------------------------
# Verb table: name -> @{ Description, Handler }
# ------------------------------------------------------------------------------
$script:Verbs = [ordered]@{
    'help'      = @{ Description = 'Show this help and exit'                                ; Handler = 'Invoke-Help'      }
    'prereqs'   = @{ Description = 'Verify host requirements (VBox, RAM, disk, SSH key)'    ; Handler = 'Invoke-Prereqs'   }
    'build'     = @{ Description = 'Build the entire lab from scratch'                      ; Handler = 'Invoke-Build'     }
    'provision' = @{ Description = 'Re-run guest orchestration only (cluster bring-up)'     ; Handler = 'Invoke-Provision' }
    'status'    = @{ Description = 'Show VM + Patroni cluster state'                        ; Handler = 'Invoke-Status'    }
    'scenario'  = @{ Description = 'Run scenario NN (or "all" for the full suite)'          ; Handler = 'Invoke-Scenario'  }
    'report'    = @{ Description = 'Generate run report (MD + HTML) into docs/ from scenario logs' ; Handler = 'Invoke-Report' }
    'destroy'   = @{ Description = 'Power off and unregister all lab VMs'                   ; Handler = 'Invoke-Destroy'   }
    'clean'     = @{ Description = 'destroy + remove ISO cache + remove lab artefacts'      ; Handler = 'Invoke-Clean'     }
    'ssh'       = @{ Description = 'Interactive SSH to a VM (e.g. lab.ps1 ssh pg1)'         ; Handler = 'Invoke-Ssh'       }
    'console'   = @{ Description = 'Save a screenshot of a VM console to %TEMP%'            ; Handler = 'Invoke-Console'   }
    'dns'       = @{ Description = 'Manage Windows NRPT for *.lab.test (install|uninstall|test|status)' ; Handler = 'Invoke-Dns' }
}

# ------------------------------------------------------------------------------
# Help renderer
# ------------------------------------------------------------------------------
function Invoke-Help {
    param([string[]]$Args)

    $maxLen = ($script:Verbs.Keys | Measure-Object -Property Length -Maximum).Maximum
    Write-Host ''
    Write-Host 'PostgreSQL 18 HA Lab -- Windows 11 entrypoint' -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Usage: .\lab.ps1 <verb> [args]' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Verbs:' -ForegroundColor Yellow
    foreach ($v in $script:Verbs.Keys) {
        $padded = $v.PadRight($maxLen + 2)
        Write-Host ("  {0}{1}" -f $padded, $script:Verbs[$v].Description)
    }
    Write-Host ''
    Write-Host 'Examples:' -ForegroundColor Yellow
    Write-Host '  .\lab.ps1 prereqs'
    Write-Host '  .\lab.ps1 build -Topology default'
    Write-Host '  .\lab.ps1 scenario 02'
    Write-Host '  .\lab.ps1 scenario all'
    Write-Host '  .\lab.ps1 scenario 13         # app-driven failover (pgha-client load + downtime)'
    Write-Host '  .\lab.ps1 report              # build docs/run-report.html from scenario logs'
    Write-Host '  .\lab.ps1 ssh pg1'
    Write-Host '  .\lab.ps1 dns install        # one-time, requires elevated PowerShell'
    Write-Host ''
    Write-Host 'See: SETTINGS.md, README.md (top-level), docs/*.md (full documentation)' -ForegroundColor DarkGray
    Write-Host ''
}

# ------------------------------------------------------------------------------
# Handlery verbów żyją w modułach (importowanych wyżej przez PgHaLab.psm1):
#   Invoke-Prereqs            -> host/modules/Prereqs.psm1
#   Invoke-Dns                -> host/modules/HostDns.psm1
#   Invoke-Build/Provision/Status/Destroy/Clean/Ssh/Console/Scenario -> host/PgHaLab.psm1
# Invoke-Help (powyżej) jest jedynym handlerem definiowanym lokalnie w dispatcherze.
# Handler verbs live in the imported modules; only Invoke-Help is local.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
$VerbLower = $Verb.ToLower()

if (-not $script:Verbs.Contains($VerbLower)) {
    Write-Host ("ERROR: unknown verb '{0}'" -f $Verb) -ForegroundColor Red
    Write-Host ''
    Invoke-Help
    exit 2
}

# Resolve the handler function exported by one of the imported modules.
$HandlerName = $script:Verbs[$VerbLower].Handler
$handlerCmd = Get-Command -Name $HandlerName -CommandType Function -ErrorAction SilentlyContinue

try {
    if ($handlerCmd) {
        & $handlerCmd $Arguments
        exit 0
    } else {
        Write-Host ("ERROR: handler '{0}' not found for verb '{1}'" -f $HandlerName, $VerbLower) -ForegroundColor Red
        exit 3
    }
}
catch {
    Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}
