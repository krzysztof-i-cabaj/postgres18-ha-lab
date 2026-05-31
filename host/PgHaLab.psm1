# ==============================================================================
# Tytul:        PgHaLab.psm1
# Opis:         Modul parasolowy importujacy wszystkie host/modules/*.psm1
#               i implementujacy verby Build/Provision/Status/Destroy/Clean/Ssh/Console
#               wywolywane przez lab.ps1.
# Description [EN]: Umbrella module importing every host/modules/*.psm1 and
#               implementing the Build/Provision/Status/Destroy/Clean/Ssh/Console
#               verbs invoked by lab.ps1.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - PowerShell 5.1+, VirtualBox 7.0+, OpenSSH client
# Requirements [EN]: - PowerShell 5.1+, VirtualBox 7.0+, OpenSSH client
#
# Uzycie [PL]:       Import-Module .\host\PgHaLab.psm1
# Usage [EN]:        Import-Module .\host\PgHaLab.psm1
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$modulesDir = Join-Path $here 'modules'

# Order matters -- Common first (everyone depends on it)
$loadOrder = @(
    'Common.psm1',
    'Prereqs.psm1',
    'Iso.psm1',
    'Network.psm1',
    'KsServer.psm1',
    'Scancode.psm1',
    'VmBuilder.psm1',
    'BootKickstart.psm1',
    'HostDns.psm1'
)

# Import bez -Global: funkcje submodulow trafiaja do session state TEGO modulu,
# dzieki czemu funkcje PgHaLab (Invoke-Build itd.) widza Get-LabConfig, Get-RockyIso,
# New-LabVm, Wait-Ssh, ... Verby z submodulow (Invoke-Prereqs, Invoke-Dns) sa
# re-eksportowane nizej, by widzial je dispatcher w lab.ps1.
# Import without -Global: submodule functions land in THIS module's session state so
# PgHaLab functions can resolve them. Submodule verbs are re-exported below.
foreach ($m in $loadOrder) {
    $p = Join-Path $modulesDir $m
    if (Test-Path $p) {
        Import-Module $p -Force -DisableNameChecking
    }
}

# ------------------------------------------------------------------------------
# Kickstart rendering
# ------------------------------------------------------------------------------
function Invoke-RenderKickstarts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $repoRoot = Get-RepoRoot
    $tmpl = Join-Path $repoRoot 'kickstart\base.ks.tmpl'
    if (-not (Test-Path $tmpl)) { throw "Template not found: $tmpl" }

    $tmplContent = Read-Utf8NoBom -Path $tmpl
    $sshPub = Get-HostSshPublicKey -KeyPath $Config.Ssh.KeyPath

    Write-Step "Rendering kickstart files for $($Config.Vms.Count) VMs"
    foreach ($vm in $Config.Vms) {
        $rendered = $tmplContent
        $rendered = $rendered.Replace('{{IP}}',         $vm.Ip)
        $rendered = $rendered.Replace('{{HOSTNAME}}',   $vm.Hostname)
        $rendered = $rendered.Replace('{{ROLE}}',       $vm.Role)
        $rendered = $rendered.Replace('{{SSH_PUBKEY}}', $sshPub)
        $rendered = $rendered.Replace('{{HOST_IP}}',    $Config.Network.HostIp)
        $rendered = $rendered.Replace('{{KS_PORT}}',    $Config.KsServer.Port)
        $rendered = $rendered.Replace('{{INFRA_IP}}',   ($Config.Vms | Where-Object Role -eq 'infra' | Select-Object -First 1).Ip)
        $rendered = $rendered.Replace('{{DOMAIN}}',     $Config.Domain)

        $out = Join-Path $repoRoot ("kickstart\{0}.ks" -f $vm.Name)
        # Force LF for kickstart files
        $renderedLf = $rendered -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($out, $renderedLf, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "Rendered $out"
    }
}

# ------------------------------------------------------------------------------
# BUILD -- full lab from scratch
# ------------------------------------------------------------------------------
function Invoke-Build {
    [CmdletBinding()]
    param([string[]]$Args)

    $cfg = Get-LabConfig

    # Topology override from -Topology argument (simplified: accept positional 'extended')
    if ($Args -and ($Args -contains '-Topology')) {
        $idx = [Array]::IndexOf($Args, '-Topology')
        if ($idx -ge 0 -and $idx + 1 -lt $Args.Count) {
            $cfg.Topology = $Args[$idx + 1]
        }
    }

    Write-Step "BUILD postgres18-ha-lab (topology=$($cfg.Topology), domain=$($cfg.Domain))"

    # 1. Prereqs
    if (-not (Test-Prereqs -Config $cfg)) {
        throw 'Prereqs failed. Resolve the issues above and re-run.'
    }

    # 2. ISO
    Get-RockyIso -Url $cfg.Iso.Url -Sha256 $cfg.Iso.Sha256 -CachePath $cfg.Iso.CachePath | Out-Null

    # 3. Network
    $hostonlyName = Initialize-LabNetwork -HostIp $cfg.Network.HostIp -Netmask $cfg.Network.Netmask

    # 4. Render kickstarts
    Invoke-RenderKickstarts -Config $cfg

    # 5. Start KS server
    Start-KsServer -RepoRoot (Get-RepoRoot) -BindIp $cfg.KsServer.BindIp -Port $cfg.KsServer.Port | Out-Null

    try {
        # 6. Create + boot infra alone, wait for SSH, then DNS
        $infra = $cfg.Vms | Where-Object Role -eq 'infra' | Select-Object -First 1
        if (-not $infra) { throw 'No VM with role=infra in lab.config' }
        New-LabVm -Name $infra.Name -Ram $infra.Ram -Cpu $infra.Cpu -HostonlyAdapter $hostonlyName -IsoPath $cfg.Iso.CachePath
        $ksUrl = "http://$($cfg.KsServer.BindIp):$($cfg.KsServer.Port)/kickstart/$($infra.Name).ks"
        Start-VmWithKickstart -VmName $infra.Name -KsUrl $ksUrl -VmIp $infra.Ip -VmHostname $infra.Hostname -Gateway $cfg.Network.HostIp -Netmask $cfg.Network.Netmask
        Wait-Ssh -IpAddress $infra.Ip -TimeoutMinutes 30
        Detach-LabVmIso -Name $infra.Name
        Write-Log -Level Info -Message 'Waiting for infra DNS to come online (firstboot-role.service running 05-infra)...'
        # 20 min: firstboot infra robi dnf install unbound/chrony/bind-utils ze swiezego
        # mirrora (zimne metadane + pakiety) -- 10 min bywa za malo. / cold dnf can exceed 10m.
        Wait-Dns -DnsServer $infra.Ip -Hostname $infra.Hostname -TimeoutMinutes 20

        # 7. Build remaining VMs
        $rest = $cfg.Vms | Where-Object Role -ne 'infra'
        foreach ($vm in $rest) {
            New-LabVm -Name $vm.Name -Ram $vm.Ram -Cpu $vm.Cpu -HostonlyAdapter $hostonlyName -IsoPath $cfg.Iso.CachePath
            $ksUrl = "http://$($cfg.KsServer.BindIp):$($cfg.KsServer.Port)/kickstart/$($vm.Name).ks"
            Start-VmWithKickstart -VmName $vm.Name -KsUrl $ksUrl -VmIp $vm.Ip -VmHostname $vm.Hostname -Gateway $cfg.Network.HostIp -Netmask $cfg.Network.Netmask
        }
        foreach ($vm in $rest) {
            Wait-Ssh -IpAddress $vm.Ip -TimeoutMinutes 30
            Detach-LabVmIso -Name $vm.Name
        }

        # 8. Distribute orchestration to cli + run orchestrate.sh
        Invoke-Provision -Args @()

    } finally {
        Stop-KsServer
    }

    Write-Step 'BUILD COMPLETE'
    Write-Host '  Use:' -ForegroundColor Cyan
    Write-Host '    .\lab.ps1 status            # show cluster state'
    Write-Host '    .\lab.ps1 ssh pg1           # bastion to leader candidate'
    Write-Host '    .\lab.ps1 dns install       # one-time, NRPT for *.lab.test (admin)'
    Write-Host '    .\lab.ps1 scenario all      # run all 13 failure scenarios'
    Write-Host '    .\lab.ps1 report            # build docs/run-report.html from the run'
}

function Get-LabSshOpts {
    # Wspolne opcje SSH/SCP dla labowych VM. VM sa efemeryczne — ich klucze hosta
    # zmieniaja sie przy KAZDYM rebuildzie, wiec NIE walidujemy ani nie zapisujemy
    # known_hosts; inaczej po przebudowie ten sam IP ma nowy klucz i ssh odrzuca
    # polaczenie ("Host key verification failed", bo accept-new akceptuje tylko
    # NOWE hosty, nie ZMIANE klucza). Lab jest izolowany w sieci host-only, wiec
    # to bezpieczne — odpowiednik /dev/null po stronie orchestrate.sh.
    # Common SSH/SCP options for lab VMs. VMs are ephemeral — their host keys
    # change on EVERY rebuild, so we neither validate nor record known_hosts;
    # otherwise a rebuilt IP presents a new key and ssh refuses ("Host key
    # verification failed", since accept-new only accepts NEW hosts, not a CHANGED
    # key). The lab is isolated on a host-only network, so this is safe — the
    # host-side equivalent of orchestrate.sh's /dev/null.
    param([Parameter(Mandatory)][string]$KeyPath)
    $nul = if ($env:OS -eq 'Windows_NT') { 'NUL' } else { '/dev/null' }
    return @('-o', 'StrictHostKeyChecking=no', '-o', "UserKnownHostsFile=$nul", '-i', $KeyPath)
}

function Invoke-Provision {
    [CmdletBinding()]
    param([string[]]$Args)
    $cfg = Get-LabConfig
    $repoRoot = Get-RepoRoot
    $cli = $cfg.Vms | Where-Object Role -eq 'cli' | Select-Object -First 1
    if (-not $cli) { throw 'No VM with role=cli' }

    Write-Step "PROVISION via cli ($($cli.Hostname))"

    # Materialize lab config as JSON for orchestrator (passwords + topology)
    $tmp = Join-Path $env:TEMP 'lab.config.json'
    $payload = @{
        Domain   = $cfg.Domain
        Vms      = $cfg.Vms
        Versions = $cfg.Versions
        Watchdog = $cfg.Watchdog
        Secrets  = $cfg.Secrets
        Cluster  = $cfg.Cluster
    } | ConvertTo-Json -Depth 6
    Write-Utf8NoBom -Path $tmp -Content $payload

    $sshKey = $cfg.Ssh.KeyPath
    $sshOpts = Get-LabSshOpts -KeyPath $sshKey

    & ssh @sshOpts "root@$($cli.Ip)" "mkdir -p /usr/local/lib/postgres18-ha-lab"
    & scp @sshOpts -r (Join-Path $repoRoot 'guest\*') "root@$($cli.Ip):/usr/local/lib/postgres18-ha-lab/"
    & scp @sshOpts $tmp "root@$($cli.Ip):/usr/local/lib/postgres18-ha-lab/lab.config.json"
    & ssh @sshOpts "root@$($cli.Ip)" "chmod 600 /usr/local/lib/postgres18-ha-lab/lab.config.json && chmod +x /usr/local/lib/postgres18-ha-lab/orchestrate.sh /usr/local/lib/postgres18-ha-lab/roles/*.sh /usr/local/lib/postgres18-ha-lab/lib/*.sh"

    # scenarios/ i client-app/ leza w KORZENIU repo (poza guest/), wiec scp guest\*
    # ich nie obejmuje — kopiujemy osobno. client-app/ instaluje 60-client.sh (pip
    # install -e) w fazie 5; scenarios/ uruchamia Invoke-Scenario na cli.
    # scenarios/ and client-app/ live at the repo ROOT (outside guest/), so scp of
    # guest\* misses them — copy separately. client-app/ is installed by 60-client.sh
    # (pip install -e) in phase 5; scenarios/ is run by Invoke-Scenario on cli.
    & scp @sshOpts -r (Join-Path $repoRoot 'scenarios')  "root@$($cli.Ip):/usr/local/lib/postgres18-ha-lab/"
    & scp @sshOpts -r (Join-Path $repoRoot 'client-app') "root@$($cli.Ip):/usr/local/lib/postgres18-ha-lab/"
    & ssh @sshOpts "root@$($cli.Ip)" "chmod +x /usr/local/lib/postgres18-ha-lab/scenarios/*.sh /usr/local/lib/postgres18-ha-lab/scenarios/lib/*.sh 2>/dev/null || true"

    # --- Posiej klucz cli na wszystkie wezly klastra -------------------------
    # Orkiestrator dziala na cli i laczy sie po SSH jako root do kazdego wezla
    # (pg1-3, lb). Kickstart wgral do authorized_keys tylko PUBLICZNY klucz HOSTA,
    # wiec cli nie ma czym sie uwierzytelnic -> "Permission denied (publickey)".
    # Host (ktory MA juz dostep do wszystkich wezlow swoim kluczem) generuje na cli
    # dedykowany klucz ed25519 i rozsiewa jego polowe publiczna do authorized_keys
    # kazdego wezla. Osobisty klucz prywatny hosta NIE opuszcza hosta.
    # --- Seed cli's SSH key onto every cluster node --------------------------
    # The orchestrator runs on cli and SSHes as root to every node (pg1-3, lb).
    # Kickstart only injected the HOST's public key into authorized_keys, so cli
    # cannot authenticate -> "Permission denied (publickey)". The host (which can
    # already reach every node with its own key) generates a dedicated ed25519
    # key on cli and seeds its public half into each node's authorized_keys. The
    # host's personal private key never leaves the host.
    Write-Step 'Seeding cli SSH key to cluster nodes'
    & ssh @sshOpts "root@$($cli.Ip)" "test -f /root/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519 -q"
    $cliPub = (& ssh @sshOpts "root@$($cli.Ip)" "cat /root/.ssh/id_ed25519.pub").Trim()
    if ([string]::IsNullOrWhiteSpace($cliPub)) { throw 'Failed to read cli public key (/root/.ssh/id_ed25519.pub)' }
    foreach ($vm in ($cfg.Vms | Where-Object { $_.Role -ne 'infra' -and $_.Role -ne 'cli' })) {
        & ssh @sshOpts "root@$($vm.Ip)" "install -d -m 700 /root/.ssh; touch /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys; grep -qxF '$cliPub' /root/.ssh/authorized_keys || echo '$cliPub' >> /root/.ssh/authorized_keys"
        if ($LASTEXITCODE -ne 0) { throw "Failed to seed cli key to $($vm.Hostname) (ssh exit $LASTEXITCODE)" }
        Write-Ok "  cli key -> $($vm.Hostname)"
    }

    & ssh @sshOpts "root@$($cli.Ip)" "/usr/local/lib/postgres18-ha-lab/orchestrate.sh"

    if ($LASTEXITCODE -ne 0) {
        throw "Orchestrator failed with exit code $LASTEXITCODE"
    }
    Write-Ok 'Provisioning complete.'
}

function Invoke-Status {
    [CmdletBinding()]
    param([string[]]$Args)
    $cfg = Get-LabConfig

    Write-Step 'VM states'
    $names = $cfg.Vms | ForEach-Object Name
    Get-LabVms -Names $names | Format-Table Name, State -AutoSize

    Write-Step 'Patroni cluster (via cli)'
    $cli = $cfg.Vms | Where-Object Role -eq 'cli' | Select-Object -First 1
    if (-not $cli) { return }
    $sshOpts = Get-LabSshOpts -KeyPath $cfg.Ssh.KeyPath
    & ssh @sshOpts "root@$($cli.Ip)" "patronictl -c /etc/patroni/patroni.yml list 2>/dev/null || patronictl -d 'http://localhost:8008' list 2>/dev/null || echo 'patronictl unavailable'"

    Write-Step 'HAProxy stats URL'
    Write-Host "  http://lb.lab.test:7000/  (or http://$(($cfg.Vms | Where-Object Role -eq 'lb' | Select-Object -First 1).Ip):7000/)"
}

function Invoke-Destroy {
    [CmdletBinding()]
    param([string[]]$Args)
    $cfg = Get-LabConfig
    Write-Step 'DESTROY all lab VMs'
    foreach ($vm in $cfg.Vms) {
        Remove-LabVm -Name $vm.Name -Force
    }
    Write-Ok 'All lab VMs removed.'
}

function Invoke-Clean {
    [CmdletBinding()]
    param([string[]]$Args)
    Invoke-Destroy
    $cfg = Get-LabConfig
    if ($cfg.Iso.CachePath -and (Test-Path $cfg.Iso.CachePath)) {
        Remove-Item -Path $cfg.Iso.CachePath -Force
        Write-Ok "Removed ISO cache: $($cfg.Iso.CachePath)"
    }
    Stop-KsServer
    Write-Ok 'Clean complete.'
}

function Invoke-Ssh {
    [CmdletBinding()]
    param([string[]]$Args)
    if (-not $Args -or $Args.Count -lt 1) {
        Write-Host 'Usage: lab.ps1 ssh <vm-name>' -ForegroundColor Yellow
        return
    }
    $name = $Args[0]
    $cfg = Get-LabConfig
    $vm = $cfg.Vms | Where-Object Name -eq $name | Select-Object -First 1
    if (-not $vm) { throw "Unknown VM '$name'" }
    $sshOpts = Get-LabSshOpts -KeyPath $cfg.Ssh.KeyPath
    & ssh @sshOpts "root@$($vm.Hostname)"
}

function Invoke-Console {
    [CmdletBinding()]
    param([string[]]$Args)
    if (-not $Args -or $Args.Count -lt 1) {
        Write-Host 'Usage: lab.ps1 console <vm-name>' -ForegroundColor Yellow
        return
    }
    $name = $Args[0]
    $vbox = Get-VBoxManagePath
    $out = Join-Path $env:TEMP "$name-console-$(Get-Date -Format 'HHmmss').png"
    & $vbox controlvm $name screenshotpng $out | Out-Null
    Write-Ok "Screenshot saved: $out"
}

function Invoke-Scenario {
    [CmdletBinding()]
    param([string[]]$Args)
    if (-not $Args -or $Args.Count -lt 1) {
        Write-Host 'Usage: lab.ps1 scenario <NN|all>' -ForegroundColor Yellow
        return
    }
    $cfg = Get-LabConfig
    $cli = $cfg.Vms | Where-Object Role -eq 'cli' | Select-Object -First 1
    $sshOpts = Get-LabSshOpts -KeyPath $cfg.Ssh.KeyPath
    $repoRoot = Get-RepoRoot

    # Dogrywamy scenarios/ na cli przed uruchomieniem. Lezy w korzeniu repo (nie w
    # guest/), wiec samo `provision` go nie wgrywalo; tu robimy to lazy, dzieki czemu
    # `scenario` dziala bez pelnego re-`provision` i zawsze bierze swieze skrypty.
    # Push scenarios/ to cli before running. It lives at the repo root (not guest/),
    # so provision didn't ship it; do it lazily here so `scenario` works without a
    # full re-`provision` and always uses fresh scripts.
    & ssh @sshOpts "root@$($cli.Ip)" "mkdir -p /usr/local/lib/postgres18-ha-lab"
    & scp @sshOpts -r (Join-Path $repoRoot 'scenarios') "root@$($cli.Ip):/usr/local/lib/postgres18-ha-lab/"
    & ssh @sshOpts "root@$($cli.Ip)" "chmod +x /usr/local/lib/postgres18-ha-lab/scenarios/*.sh /usr/local/lib/postgres18-ha-lab/scenarios/lib/*.sh 2>/dev/null || true"

    $target = $Args[0]
    if ($target -eq 'all') {
        & ssh @sshOpts "root@$($cli.Ip)" "/usr/local/lib/postgres18-ha-lab/scenarios/run-all.sh"
        return
    }
    # Map NN to actual scenario filename via remote glob
    & ssh @sshOpts "root@$($cli.Ip)" "ls /usr/local/lib/postgres18-ha-lab/scenarios/${target}-*.sh | head -1 | xargs -r bash"
}

function Invoke-Report {
    [CmdletBinding()]
    param([string[]]$Args)
    $cfg = Get-LabConfig
    $cli = $cfg.Vms | Where-Object Role -eq 'cli' | Select-Object -First 1
    $sshOpts = Get-LabSshOpts -KeyPath $cfg.Ssh.KeyPath
    $repoRoot = Get-RepoRoot
    $libDir = '/usr/local/lib/postgres18-ha-lab'
    $remoteOut = "$libDir/report/out"

    # 'agentic' -> raport brandowany jako agentowy przebieg pelnej suity (inne nazwy plikow).
    # 'agentic' -> brand the report as an agentic full-suite run (different output names).
    $agentic = ($Args -contains 'agentic')
    if ($agentic) {
        $flag = '--agentic'
        $files = @('AGENTIC_RUN_ALL.md', 'AGENTIC_RUN_ALL_PL.md', 'agentic-run-all.html', 'agentic-run-all_PL.html')
    } else {
        $flag = ''
        $files = @('RUN_REPORT.md', 'RUN_REPORT_PL.md', 'run-report.html', 'run-report_PL.html')
    }

    # Dogrywamy generator na cli (report/ lezy w korzeniu repo, poza guest/ -- jak
    # scenarios/), potem generujemy raport z logow scenariuszy + metryk pgha-client
    # i sciagamy wyniki do docs/ (gotowe pod GitHub Pages). python3.11 jest pewny na cli.
    # Push report/ to cli, generate from scenario logs + pgha-client metrics, pull into docs/.
    & ssh @sshOpts "root@$($cli.Ip)" "mkdir -p $libDir/report"
    & scp @sshOpts -r (Join-Path $repoRoot 'report') "root@$($cli.Ip):$libDir/"
    & ssh @sshOpts "root@$($cli.Ip)" "python3.11 $libDir/report/gen_report.py --log-dir /var/log/postgres18-ha-lab/scenarios --out-dir $remoteOut $flag"

    $docs = Join-Path $repoRoot 'docs'
    foreach ($f in $files) {
        & scp @sshOpts "root@$($cli.Ip):$remoteOut/$f" (Join-Path $docs $f)
    }
    Write-Ok "Report written to docs/ ($($files -join ', '))"
}

Export-ModuleMember -Function `
    'Invoke-Build', 'Invoke-Provision', 'Invoke-Status', `
    'Invoke-Destroy', 'Invoke-Clean', 'Invoke-Ssh', 'Invoke-Console', 'Invoke-Scenario', `
    'Invoke-Report', 'Invoke-RenderKickstarts', `
    'Invoke-Prereqs', 'Invoke-Dns'
