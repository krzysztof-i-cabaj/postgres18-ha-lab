# 🚀 Setup walkthrough — Windows 11

[![Host](https://img.shields.io/badge/Host-Windows_11-0078D6)]()
[![Hypervisor](https://img.shields.io/badge/Hypervisor-VirtualBox_7.x-183A61)]()

> 🎯 Step-by-step setup of the lab from a clean Windows 11 host.
> Polish: [SETUP_PL.md](SETUP_PL.md).

## 0. Hard requirements

- Windows 11 Pro x64
- VirtualBox 7.0+ installed (provides `VBoxManage.exe`)
- Built-in tooling: PowerShell 5.1+, OpenSSH client, `curl.exe`
- **Python 3.8+** on host (runs the kickstart HTTP server `host/ks_server.py`)
- ≥ 20 GB free RAM, ≥ 60 GB free disk
- Internet (for ISO + PGDG repo)

**Not on host**: Ansible, WSL, Make, Chocolatey, Scoop. (Python is required — see above.)

## 1. Clone and configure

`<repo>` denotes wherever you cloned this repository — could be
`D:\projects\postgres18-ha-lab`, `C:\src\postgres18-ha-lab`, `~\dev\...`,
anywhere. Pick your own path. (See `SETTINGS.md` at the repo root for the
project-specific value.)

```powershell
cd <repo>          # e.g. cd C:\dev\postgres18-ha-lab

# Make a real config from the template, edit passwords:
Copy-Item lab.config.example.psd1 lab.config.psd1
notepad lab.config.psd1
```

Replace every `@@REPLACE@@` placeholder with a real password. The orchestrator
**refuses** to provision a cluster with placeholder passwords.

## 2. Allow PowerShell execution

Once per machine:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Verify host prereqs

```powershell
.\lab.ps1 prereqs
```

Generates `~/.ssh/id_ed25519` (if missing) and writes a managed
block to `~/.ssh/config` so `ssh pg1` works passwordlessly from PowerShell
**and** MobaXterm (Settings -> SSH -> "Use OpenSSH config").

## 4. Build

### One-time firewall rule (admin)

`lab.ps1 build` starts a small **Python** HTTP server (`host/ks_server.py`,
serving only `kickstart/` + `guest/`) on `http://192.168.56.1:8000/`; the VMs fetch
their kickstart from it. Windows Firewall (and any 3rd-party firewall) blocks
inbound `:8000` from the host-only network by default, so the install loops
`failed to fetch kickstart`. Allow it once from an **elevated** PowerShell, scoped
to the lab subnet:

```powershell
# Right-click PowerShell > Run as administrator
netsh advfirewall firewall add rule name="pgha-lab-ks-8000" dir=in action=allow protocol=TCP localport=8000 remoteip=192.168.56.0/24
```

If you run a 3rd-party firewall (e.g. **Bitdefender Total Security**), it overrides
the Windows rule, so handle it there too. Marking the *VirtualBox Host-Only* adapter
as **Home/Office (trusted)** is necessary but **may not be sufficient** — also ensure
the **inbound / "receiving" direction is allowed** for the kickstart server
(`python.exe`). Symptom if missed: VMs loop `failed to fetch kickstart` even though
the server answers from the host. Do **not** use a temporary "pause for 1h" — it
expires and the block returns.

Remove the rule later with:

```powershell
netsh advfirewall firewall delete rule name="pgha-lab-ks-8000"
```

> The server uses a raw Python socket (not .NET `HttpListener`/`http.sys`), so **no
> URL ACL reservation is needed**. If you added one earlier, you can drop it:
> `netsh http delete urlacl url=http://192.168.56.1:8000/`. The allowlist in
> `ks_server.py` ensures only `kickstart/` and `guest/` are served — never
> `lab.config.psd1`.

### Build the lab

```powershell
.\lab.ps1 build
```

Default topology: 6 VMs (infra + pg1/2/3 + lb + cli). Total ~17 GB RAM,
~30 minutes on Ryzen 9 + NVMe. Use `-Topology extended` for 10 VMs (separate
etcd nodes, ~20 GB RAM).

## 5. DNS integration on Windows (NRPT)

Resolving `pg1.lab.test` from the host requires routing `*.lab.test` to infra.
The Windows-native solution is the **Name Resolution Policy Table (NRPT)**.

### One-time install (admin)

```powershell
# Right-click PowerShell > Run as administrator
.\lab.ps1 dns install
```

This adds an NRPT rule: `.lab.test -> 192.168.56.10`. Verify:

```powershell
Resolve-DnsName pg2.lab.test
# Should return 192.168.56.12
```

### Why NRPT over `hosts`

- NRPT is per-namespace (other domains keep your normal DNS)
- Survives DHCP renewals
- Coexists with corporate VPNs
- Doesn't require editing system files

### Fallback (no admin)

If you cannot elevate, append to `C:\Windows\System32\drivers\etc\hosts`:

```
192.168.56.10 infra.lab.test
192.168.56.11 pg1.lab.test
192.168.56.12 pg2.lab.test
192.168.56.13 pg3.lab.test
192.168.56.20 lb.lab.test  db.lab.test
192.168.56.30 cli.lab.test
```

(Editing `hosts` requires admin once; no NRPT permission needed afterwards.)

## 6. Verify

```powershell
.\lab.ps1 status            # Patroni cluster + HAProxy stats URL
ssh pg1 'patronictl -c /etc/patroni/patroni.yml list'
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select 1'
```

Open `http://lb.lab.test:7000/` (or `http://192.168.56.20:7000/`) for HAProxy stats.

## 7. Run scenarios

```powershell
.\lab.ps1 scenario 01
.\lab.ps1 scenario all
```

Logs land in `/var/log/postgres18-ha-lab/scenarios/` on the cli VM.

## 8. Tear down

```powershell
.\lab.ps1 destroy           # poweroff + unregister all VMs
.\lab.ps1 clean             # destroy + remove ISO cache
.\lab.ps1 dns uninstall     # admin; remove NRPT rule
# optional, admin; remove the kickstart-server firewall rule:
netsh advfirewall firewall delete rule name="pgha-lab-ks-8000"
```
