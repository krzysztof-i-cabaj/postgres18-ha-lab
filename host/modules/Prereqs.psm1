# ==============================================================================
# Tytul:        Prereqs.psm1
# Opis:         Weryfikacja wymagan hosta przed buildem labu: VirtualBox 7.0+,
#               wolny RAM/dysk, dostepnosc internetu, port 8000, klucz SSH,
#               idempotentny blok w ~/.ssh/config dla MobaXterm/PowerShell.
# Description [EN]: Verify host requirements before lab build: VirtualBox 7.0+,
#               free RAM/disk, internet reachability, port 8000, SSH key,
#               idempotent block in ~/.ssh/config for MobaXterm/PowerShell.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - PowerShell 5.1+, OpenSSH client (ssh-keygen)
# Requirements [EN]: - PowerShell 5.1+, OpenSSH client (ssh-keygen)
#
# Uzycie [PL]:       Import-Module .\host\modules\Prereqs.psm1
#                    Test-Prereqs
# Usage [EN]:        Import-Module .\host\modules\Prereqs.psm1
#                    Test-Prereqs
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force -DisableNameChecking

# ------------------------------------------------------------------------------
# Individual checks -- each returns @{ Ok = $bool; Message = '...' }
# ------------------------------------------------------------------------------

function Test-VBox {
    [CmdletBinding()]
    param()
    $vbox = Get-VBoxManagePath
    if (-not $vbox) {
        return @{ Ok = $false; Message = 'VBoxManage.exe not found in Program Files. Install VirtualBox 7.0+.' }
    }
    $verRaw = & $vbox --version 2>&1
    $verNum = [version]([regex]::Match($verRaw, '^(\d+\.\d+\.\d+)').Value)
    if ($verNum.Major -lt 7) {
        return @{ Ok = $false; Message = "VirtualBox $verRaw is too old. Need 7.0+." }
    }
    return @{ Ok = $true; Message = "VirtualBox $verRaw at $vbox" }
}

function Test-Ram {
    [CmdletBinding()]
    param([int]$MinFreeGb = 20)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    if ($freeGb -lt $MinFreeGb) {
        return @{ Ok = $false; Message = "Free RAM ${freeGb} GB < required ${MinFreeGb} GB. Close some apps." }
    }
    return @{ Ok = $true; Message = "Free RAM ${freeGb} GB (>= ${MinFreeGb} GB)" }
}

function Test-Disk {
    [CmdletBinding()]
    param(
        [int]$MinFreeGb = 60,
        [string]$Drive = 'C:'
    )
    $vol = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Drive'"
    if (-not $vol) {
        return @{ Ok = $false; Message = "Drive $Drive not found." }
    }
    $freeGb = [math]::Round($vol.FreeSpace / 1GB, 1)
    if ($freeGb -lt $MinFreeGb) {
        return @{ Ok = $false; Message = "Free disk on $Drive : ${freeGb} GB < required ${MinFreeGb} GB." }
    }
    return @{ Ok = $true; Message = "Free disk on $Drive : ${freeGb} GB (>= ${MinFreeGb} GB)" }
}

function Test-Internet {
    [CmdletBinding()]
    param([string]$Url = 'https://download.rockylinux.org/')
    try {
        $req = [System.Net.WebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $resp.Close()
        return @{ Ok = $true; Message = "HTTPS reachable: $Url" }
    } catch {
        return @{ Ok = $false; Message = "Cannot reach $Url : $($_.Exception.Message)" }
    }
}

function Test-PortFree {
    [CmdletBinding()]
    param([int]$Port = 8000)
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return @{ Ok = $true; Message = "Port $Port is free" }
    } catch {
        return @{ Ok = $false; Message = "Port $Port in use: $($_.Exception.Message)" }
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Test-NoForbiddenTooling {
    [CmdletBinding()]
    param()
    # Per brief: Python, WSL, Make, Chocolatey, Scoop should NOT be on host
    # We only warn, not fail -- user may have other reasons to have them.
    $forbidden = @('python', 'python3', 'wsl', 'make', 'choco', 'scoop')
    $found = @()
    foreach ($t in $forbidden) {
        if (Get-Command $t -ErrorAction SilentlyContinue) { $found += $t }
    }
    if ($found.Count -eq 0) {
        return @{ Ok = $true; Message = 'No forbidden host tooling detected' }
    }
    return @{ Ok = $true; Message = "Found (warning, not blocker): $($found -join ', ')" }
}

# ------------------------------------------------------------------------------
# SSH key + ~/.ssh/config block management
# ------------------------------------------------------------------------------

$script:SshConfigBeginMarker = '# >>> postgres18-ha-lab >>>'
$script:SshConfigEndMarker   = '# <<< postgres18-ha-lab <<<'

function Initialize-HostSshKey {
    [CmdletBinding()]
    param(
        [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
    )
    $sshDir = Split-Path -Parent $KeyPath
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }
    if (Test-Path $KeyPath) {
        Write-Ok "SSH key exists: $KeyPath"
        return
    }
    $sshKeygen = Get-Command 'ssh-keygen.exe' -ErrorAction SilentlyContinue
    if (-not $sshKeygen) {
        throw 'ssh-keygen.exe not found. Install OpenSSH Client (Settings > Apps > Optional features).'
    }
    Write-Step "Generating ed25519 SSH key at $KeyPath"
    & $sshKeygen.Source -t ed25519 -f $KeyPath -N '""' -C "postgres18-ha-lab on $env:COMPUTERNAME" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ssh-keygen failed with exit code $LASTEXITCODE"
    }
    Write-Ok "Generated $KeyPath"
}

function Get-HostSshPublicKey {
    [CmdletBinding()]
    param([string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519")
    $pub = "$KeyPath.pub"
    if (-not (Test-Path $pub)) {
        throw "Public key not found: $pub. Run Initialize-HostSshKey first."
    }
    return (Get-Content -Path $pub -Raw).Trim()
}

function Update-SshConfigForLab {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = "$env:USERPROFILE\.ssh\config",
        [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
        [string]$Domain = 'lab.test'
    )

    $configDir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    # Build the lab block (uses ~ syntax which OpenSSH on Win11 understands)
    $keyForwardSlash = $KeyPath -replace '\\', '/'
    $newBlock = @(
        $script:SshConfigBeginMarker
        'Host infra pg1 pg2 pg3 lb cli'
        "    HostName %h.$Domain"
        '    User root'
        "    IdentityFile $keyForwardSlash"
        '    StrictHostKeyChecking accept-new'
        "    UserKnownHostsFile $($configDir -replace '\\','/')/known_hosts.lab"
        $script:SshConfigEndMarker
    ) -join "`n"

    $existing = if (Test-Path $ConfigPath) { Read-Utf8NoBom -Path $ConfigPath } else { '' }

    # Remove any old block between markers (idempotency)
    $pattern = [regex]::Escape($script:SshConfigBeginMarker) + '.*?' + [regex]::Escape($script:SshConfigEndMarker)
    $cleaned = [regex]::Replace($existing, $pattern, '', 'Singleline').TrimEnd("`r", "`n", " ", "`t")

    $final = if ($cleaned) { "$cleaned`n`n$newBlock`n" } else { "$newBlock`n" }

    Write-Utf8NoBom -Path $ConfigPath -Content $final
    Write-Ok "Updated $ConfigPath (idempotent block between markers)"
}

# ------------------------------------------------------------------------------
# Aggregate runner
# ------------------------------------------------------------------------------
function Test-Prereqs {
    [CmdletBinding()]
    param([hashtable]$Config)

    Write-Step 'Host prerequisites check'
    $allOk = $true

    $checks = @(
        @{ Name = 'VirtualBox 7.0+'    ; Action = { Test-VBox } }
        @{ Name = 'Free RAM >= 20 GB'  ; Action = { Test-Ram -MinFreeGb 20 } }
        @{ Name = 'Free disk >= 60 GB' ; Action = { Test-Disk -MinFreeGb 60 } }
        @{ Name = 'Internet reachable' ; Action = { Test-Internet } }
        @{ Name = 'Port 8000 free'     ; Action = { Test-PortFree -Port 8000 } }
        @{ Name = 'No forbidden tooling on host (warn only)' ; Action = { Test-NoForbiddenTooling } }
    )

    foreach ($c in $checks) {
        $r = & $c.Action
        if ($r.Ok) { Write-Ok ("{0}: {1}" -f $c.Name, $r.Message) }
        else       { Write-Fail ("{0}: {1}" -f $c.Name, $r.Message); $allOk = $false }
    }

    Write-Step 'SSH key + config'
    $keyPath = if ($Config -and $Config.Ssh) { $Config.Ssh.KeyPath } else { "$env:USERPROFILE\.ssh\id_ed25519" }
    $cfgPath = if ($Config -and $Config.Ssh) { $Config.Ssh.SshConfigPath } else { "$env:USERPROFILE\.ssh\config" }
    $domain  = if ($Config -and $Config.Domain) { $Config.Domain } else { 'lab.test' }
    Initialize-HostSshKey -KeyPath $keyPath
    Update-SshConfigForLab -ConfigPath $cfgPath -KeyPath $keyPath -Domain $domain

    if (-not $allOk) {
        Write-Fail 'One or more host prerequisites failed.'
        return $false
    }
    Write-Ok 'All host prerequisites satisfied.'
    return $true
}

function Invoke-Prereqs {
    [CmdletBinding()]
    param([string[]]$Args)
    $cfg = Get-LabConfig
    [void](Test-Prereqs -Config $cfg)
}

Export-ModuleMember -Function `
    'Test-VBox', 'Test-Ram', 'Test-Disk', 'Test-Internet', 'Test-PortFree', 'Test-NoForbiddenTooling', `
    'Initialize-HostSshKey', 'Get-HostSshPublicKey', 'Update-SshConfigForLab', `
    'Test-Prereqs', 'Invoke-Prereqs'
