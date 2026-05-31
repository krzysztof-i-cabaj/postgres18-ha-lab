# ==============================================================================
# Tytul:        Iso.psm1
# Opis:         Pobieranie ISO Rocky Linux z weryfikacja SHA256, cache w
#               %LOCALAPPDATA%, pomijane jesli juz pobrane i poprawne.
# Description [EN]: Rocky Linux ISO download with SHA256 verification, cache in
#               %LOCALAPPDATA%, skipped when already present and valid.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - PowerShell 5.1+ (Invoke-WebRequest, Get-FileHash)
# Requirements [EN]: - PowerShell 5.1+ (Invoke-WebRequest, Get-FileHash)
#
# Uzycie [PL]:       Get-RockyIso -Url ... -Sha256 ... -CachePath ...
# Usage [EN]:        Get-RockyIso -Url ... -Sha256 ... -CachePath ...
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force -DisableNameChecking

function Test-Sha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Expected
    )
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
    return ($actual -eq $Expected.ToLower())
}

function Get-RockyIso {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Sha256,
        [Parameter(Mandatory)][string]$CachePath
    )

    Write-Step "ISO: ensure $CachePath"

    $cacheDir = Split-Path -Parent $CachePath
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }

    if (Test-Path $CachePath) {
        Write-Log -Level Info -Message 'ISO present, verifying SHA256...'
        if (Test-Sha256 -Path $CachePath -Expected $Sha256) {
            Write-Ok 'Cached ISO matches expected SHA256, skipping download.'
            return $CachePath
        } else {
            Write-Log -Level Warn -Message 'Cached ISO SHA256 mismatch, redownloading.'
            Remove-Item -Path $CachePath -Force
        }
    }

    Write-Log -Level Info -Message "Downloading $Url"
    Write-Log -Level Info -Message '(this is ~2 GB; expect 5-30 minutes depending on link)'

    # BITS is faster + resumable; fall back to Invoke-WebRequest if BITS missing
    try {
        $bits = Get-Command 'Start-BitsTransfer' -ErrorAction SilentlyContinue
        if ($bits) {
            Start-BitsTransfer -Source $Url -Destination $CachePath -Description 'Rocky 9.8 ISO'
        } else {
            $progressPreference = 'Continue'
            Invoke-WebRequest -Uri $Url -OutFile $CachePath -UseBasicParsing
        }
    } catch {
        if (Test-Path $CachePath) { Remove-Item $CachePath -Force -ErrorAction SilentlyContinue }
        throw "ISO download failed: $($_.Exception.Message)"
    }

    Write-Log -Level Info -Message 'Verifying SHA256...'
    if (-not (Test-Sha256 -Path $CachePath -Expected $Sha256)) {
        Remove-Item $CachePath -Force
        throw "Downloaded ISO SHA256 mismatch -- corrupt download. Try again."
    }
    Write-Ok 'ISO verified.'
    return $CachePath
}

Export-ModuleMember -Function 'Test-Sha256', 'Get-RockyIso'
