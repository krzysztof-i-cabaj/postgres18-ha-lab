# ==============================================================================
# Tytul:        HostDns.psm1
# Opis:         Integracja Windows NRPT (Name Resolution Policy Table) -- *.lab.test
#               kierowane do infra DNS (192.168.56.10). Install/Uninstall wymaga
#               admina, Test/Status nie. Ergonomia: Resolve-DnsName pg1.lab.test
#               z hosta po jednorazowym 'lab.ps1 dns install'.
# Description [EN]: Windows NRPT integration -- *.lab.test routed to infra DNS
#               (192.168.56.10). Install/Uninstall require admin, Test/Status
#               do not. Ergonomics: Resolve-DnsName pg1.lab.test from host
#               after one-time 'lab.ps1 dns install'.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - Windows 11 (Add/Get/Remove-DnsClientNrptRule)
#                    - Admin do install/uninstall
# Requirements [EN]: - Windows 11 (Add/Get/Remove-DnsClientNrptRule)
#                    - Admin for install/uninstall
#
# Uzycie [PL]:       Install-LabDns -Namespace .lab.test -DnsServer 192.168.56.10
#                    Test-LabDns
#                    Uninstall-LabDns
# Usage [EN]:        Install-LabDns -Namespace .lab.test -DnsServer 192.168.56.10
#                    Test-LabDns
#                    Uninstall-LabDns
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force -DisableNameChecking

function Install-LabDns {
    [CmdletBinding()]
    param(
        [string]$Namespace = '.lab.test',
        [string]$DnsServer = '192.168.56.10'
    )

    Assert-Elevated

    Write-Step "NRPT: install rule '$Namespace' -> $DnsServer"

    # Idempotency: remove any pre-existing rule for the same namespace
    $existing = Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Namespace -contains $Namespace -or $_.Namespace -eq $Namespace }
    if ($existing) {
        $existing | Remove-DnsClientNrptRule -Force -ErrorAction SilentlyContinue
        Write-Log -Level Info -Message 'Removed previous NRPT rule for the same namespace.'
    }

    Add-DnsClientNrptRule `
        -Namespace $Namespace `
        -NameServers $DnsServer `
        -Comment 'postgres18-ha-lab' | Out-Null

    Clear-DnsClientCache

    Write-Ok "NRPT rule installed: $Namespace -> $DnsServer"
    Write-Log -Level Info -Message 'Verify: Resolve-DnsName pg1.lab.test'
}

function Uninstall-LabDns {
    [CmdletBinding()]
    param([string]$Namespace = '.lab.test')

    Assert-Elevated

    Write-Step "NRPT: uninstall rule '$Namespace'"
    $rules = Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Namespace -contains $Namespace -or $_.Namespace -eq $Namespace }
    if (-not $rules) {
        Write-Log -Level Info -Message 'No matching NRPT rule, nothing to remove.'
        return
    }
    $rules | Remove-DnsClientNrptRule -Force
    Clear-DnsClientCache
    Write-Ok "NRPT rule(s) for $Namespace removed"
}

function Test-LabDns {
    [CmdletBinding()]
    param(
        [string[]]$Names = @('infra.lab.test', 'pg1.lab.test', 'pg2.lab.test', 'pg3.lab.test', 'lb.lab.test', 'cli.lab.test', 'db.lab.test'),
        [string]$DnsServer = '192.168.56.10'
    )

    Write-Step "DNS test against $DnsServer"
    $allOk = $true
    foreach ($n in $Names) {
        try {
            $r = Resolve-DnsName -Name $n -Server $DnsServer -DnsOnly -QuickTimeout -ErrorAction Stop -Type A
            $ip = ($r | Where-Object Type -eq 'A' | Select-Object -First 1).IPAddress
            if ($ip) {
                Write-Host ("  OK   {0,-22} -> {1}" -f $n, $ip) -ForegroundColor Green
            } else {
                Write-Host ("  FAIL {0,-22} -> no A record" -f $n) -ForegroundColor Red
                $allOk = $false
            }
        } catch {
            Write-Host ("  FAIL {0,-22} -> {1}" -f $n, $_.Exception.Message) -ForegroundColor Red
            $allOk = $false
        }
    }
    return $allOk
}

function Get-LabDnsStatus {
    [CmdletBinding()]
    param([string]$Namespace = '.lab.test')

    Write-Step 'NRPT rules (all)'
    Get-DnsClientNrptRule | Format-Table Name, Namespace, NameServers, Comment -AutoSize

    Write-Step "Specific rule for $Namespace"
    $rule = Get-DnsClientNrptRule | Where-Object { $_.Namespace -contains $Namespace -or $_.Namespace -eq $Namespace }
    if ($rule) {
        $rule | Format-List Name, Namespace, NameServers, Comment
    } else {
        Write-Log -Level Warn -Message "No NRPT rule for $Namespace. Run 'lab.ps1 dns install' (elevated)."
    }
}

function Invoke-Dns {
    [CmdletBinding()]
    param([string[]]$Args)

    if (-not $Args -or $Args.Count -lt 1) {
        Write-Host 'Usage: lab.ps1 dns <install|uninstall|test|status>' -ForegroundColor Yellow
        return
    }
    $sub = $Args[0].ToLower()
    switch ($sub) {
        'install'   { Install-LabDns }
        'uninstall' { Uninstall-LabDns }
        'test'      { [void](Test-LabDns) }
        'status'    { Get-LabDnsStatus }
        default     { Write-Host "Unknown dns sub-verb '$sub'. Use: install|uninstall|test|status" -ForegroundColor Red }
    }
}

Export-ModuleMember -Function 'Install-LabDns', 'Uninstall-LabDns', 'Test-LabDns', 'Get-LabDnsStatus', 'Invoke-Dns'
