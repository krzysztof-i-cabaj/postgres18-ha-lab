# 🚀 Quickstart — assemble & start the LAB (runbook)

[![Time](https://img.shields.io/badge/Build-~30_min-blue)]()
[![Host](https://img.shields.io/badge/Host-Windows_11_%2B_VirtualBox-0078D6)]()
[![Mode](https://img.shields.io/badge/Mode-automated_lab.ps1-darkgreen)]()

> 🎯 The shortest path: from zero to a working HA cluster + scenarios, via the `lab.ps1` automation.
> Includes **real pitfalls from the build** (Bitdefender, "silence ≠ failure"). Full walkthrough with
> explanations: [SETUP.md](SETUP.md). By hand without `lab.ps1`: [MANUAL_INSTALL.md](MANUAL_INSTALL.md).

---

## 0. ✅ Requirements (short)

- **Windows 11** + **VirtualBox 7+** (`VBoxManage`) + **Python 3.8+** (kickstart server).
- Built-in: PowerShell 5.1+, OpenSSH client, `curl.exe`.
- ≥ 20 GB free RAM, ≥ 60 GB disk, internet (ISO + PGDG repo).
- **Not allowed:** Ansible, WSL, Make, Chocolatey, Scoop.

---

## 1. 🔥 Prepare the firewall (once — THE most common pitfall)

`build` starts a kickstart server (`python.exe`) on `192.168.56.1:8000`; the VMs **must** reach it,
otherwise the install loops on `failed to fetch kickstart`.

**Windows Firewall** (elevated PowerShell, once):
```powershell
netsh advfirewall firewall add rule name="pgha-lab-ks-8000" dir=in action=allow protocol=TCP localport=8000 remoteip=192.168.56.0/24
```

**Bitdefender / other 3rd-party firewall** (overrides the Windows rule):
- *VirtualBox Host-Only* adapter → **Home/Office (trusted)** profile,
- **AND enable the INBOUND ("receiving") direction** for `python.exe`.
- ⚠️ This was the cause of a mysterious `failed to fetch kickstart` despite a working server. Do not
  use "pause for 1h" — it expires.

---

## 2. ⚙️ Configuration (once)

```powershell
cd <repo>                                   # the repository directory
Copy-Item lab.config.example.psd1 lab.config.psd1
notepad lab.config.psd1                      # set passwords instead of @@REPLACE@@ (Secrets)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
> The **Rocky 9.8** ISO is downloaded automatically on the first build and cached (SHA256 verified).
> Nothing to fetch manually.

---

## 3. 🏗️ Assembly (command order)

```powershell
.\lab.ps1 prereqs        # verify host + generate ed25519 key (if missing)
.\lab.ps1 build          # ~30 min: 6 VMs from scratch (infra → pg1/2/3 → lb → cli → demo DB)

# one-time, elevated (Administrator) PowerShell:
.\lab.ps1 dns install    # NRPT rule, *.lab.test resolves on Windows

.\lab.ps1 status         # cluster state + HAProxy stats URL
```
> 💡 If orchestration was interrupted midway (e.g. Ctrl+C), **don't rebuild from scratch** —
> `.\lab.ps1 provision` re-runs just the orchestration (idempotent, no VM re-creation).

---

## 4. 🔐 Passwords (your LAB)

| Account | Password | Where |
|---|---|---|
| `postgres` (superuser) | `LabSuper2026` | cluster; PgBouncer admin |
| `replicator` | `LabRepl2026` | replication |
| `rewind_user` | `LabRewind2026` | `pg_rewind` |
| `lab` (app) | `lab` | `labdb` database |
| OS `root` / `lab` | `labroot` / `lab` | every VM (SSH by key only) |

Source of truth: `lab.config.psd1` (cluster) + `kickstart/base.ks.tmpl` (OS). It's a LAB — simple passwords.

---

## 5. 🔎 Verification

```powershell
.\lab.ps1 status
ssh root@pg1.lab.test "patronictl -c /etc/patroni/patroni.yml list"   # 1 Leader + 2 replicas
psql "host=db.lab.test port=5000 dbname=labdb user=lab password=lab" -c "select 1"   # write (primary)
psql "host=db.lab.test port=5001 dbname=labdb user=lab password=lab" -c "select pg_is_in_recovery()"  # read (replicas)
```
HAProxy stats: `http://lb.lab.test:7000/` (or `http://192.168.56.20:7000/`).

---

## 6. 🧪 Failure scenarios

```powershell
.\lab.ps1 scenario 01     # baseline (sanity)
.\lab.ps1 scenario 02     # hard failover + zero-data-loss proof
.\lab.ps1 scenario 13     # app-driven failover (pgha-client load + downtime metrics)
.\lab.ps1 scenario all    # the whole suite 01–13
.\lab.ps1 report          # build docs/run-report.html (interactive) from the run
```
Manual steps: [MANUAL_SCENARIOS.md](MANUAL_SCENARIOS.md). Example report: [agentic-run-all.html](agentic-run-all.html).

---

## 7. ⏸️ Pause — power off / on (state preserved)

> ⚠️ **`destroy` DELETES the VMs (unregister) — do NOT use it to power off temporarily!**
> `lab.ps1` has no `stop`/`start` — use `VBoxManage` or the VirtualBox GUI.

After powering back on **everything starts by itself** (`etcd`/`patroni`/`haproxy`/`pgbouncer`/
`unbound`/`chrony` are `enabled`; etcd returns from its persistent `data-dir`, Patroni rebuilds the
cluster from etcd).

```powershell
$vb = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
# POWER OFF (graceful, ACPI):
'cli','lb','pg3','pg2','pg1','infra' | ForEach-Object { & $vb controlvm $_ acpipowerbutton }
# POWER ON (infra first — DNS/NTP; the rest join):
'infra','pg1','pg2','pg3','lb','cli' | ForEach-Object { & $vb startvm $_ --type headless; Start-Sleep 8 }
```
After ~1–2 min (leader election): `.\lab.ps1 status`. The host NRPT survives (`*.lab.test` keeps working).
VirtualBox GUI: right-click → **Close → ACPI Shutdown**; start = double-click.

> 💡 **Order is not critical** — the cluster runs over IP (not DNS) and assembles itself (etcd quorum +
> Patroni election). You can power all VMs on/off at once. The only start condition: ≥2 of 3 pg nodes
> (etcd quorum). "infra first" and `Start-Sleep` are just cosmetics / host load-spreading.

## 8. 🔁 Operations & teardown

```powershell
.\lab.ps1 provision      # re-run ONLY the cluster orchestration (no VM creation)
.\lab.ps1 ssh pg1        # bastion to a node
.\lab.ps1 destroy        # poweroff + unregister all VMs (PERMANENTLY DELETES — not for pausing!)
.\lab.ps1 clean          # destroy + remove the ISO cache
.\lab.ps1 dns uninstall  # (admin) remove the NRPT rule
```

---

## ⚠️ Pitfalls from practice

| Symptom | What to do |
|---|---|
| `failed to fetch kickstart` (loop) | Firewall — section 1 (Bitdefender **inbound** for python.exe!). |
| Build "hangs" after `OK etcd healthy` | Either a silent phase (dnf) **or** a stall — **don't Ctrl+C**. Check: `ssh root@cli "tail -f /var/log/postgres18-ha-lab/orchestrate.log"`. |
| `ssh root@pgN` → `Permission denied (publickey)` | EL9 = root by key only. A rebuilt VM changes its host key — the automation ignores it; manually drop the stale entry from `~/.ssh/known_hosts`. |
| `*.lab.test` won't resolve on Windows | `.\lab.ps1 dns install` (admin) or a `hosts` entry. |
| Many `orchestrate.sh` processes on cli | Orphaned after Ctrl+C — `ssh root@cli "pkill -9 -f orchestrate.sh"`, then `provision`. |

---

## 🗺️ Documentation map

| File | For |
|---|---|
| **QUICKSTART.md** (this) | cheat sheet: assemble & start |
| [SETUP.md](SETUP.md) | full walkthrough with explanations |
| [MANUAL_INSTALL.md](MANUAL_INSTALL.md) | manual build, node by node (no `lab.ps1`) |
| [MANUAL_SCENARIOS.md](MANUAL_SCENARIOS.md) | manual reproduction of the 13 scenarios |
| [SCENARIOS.md](SCENARIOS.md) | scenario descriptions + expected output |
| [AGENTIC_RUN_ALL.md](AGENTIC_RUN_ALL.md) / [agentic-run-all.html](agentic-run-all.html) | full-suite run report (+ Pages site) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | components, failover, DNS/NTP |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | full troubleshooting |
| [../SETTINGS.md](../SETTINGS.md) | project-specific values |
