# 🐘 PostgreSQL 18 HA Lab

[![License](https://img.shields.io/badge/License-MIT-blue)]()
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18.3-336791)]()
[![Patroni](https://img.shields.io/badge/Patroni-4.1+-darkgreen)]()
[![Host](https://img.shields.io/badge/Host-Windows_11-0078D6)]()
[![Hypervisor](https://img.shields.io/badge/Hypervisor-VirtualBox_7.x-183A61)]()
[![Domain](https://img.shields.io/badge/Domain-lab.test-orange)]()
[![OS](https://img.shields.io/badge/Guest_OS-Rocky_Linux_9.8-10B981)]()
[![Status](https://img.shields.io/badge/Status-WIP-yellow)]()

> 🎯 A reproducible PostgreSQL 18 **high-availability** laboratory built with
> **Patroni + etcd + HAProxy + PgBouncer** on **Rocky Linux 9.8** guests,
> driven entirely from a **Windows 11** host with **only VirtualBox** installed.
> Polish counterpart: [README_PL.md](README_PL.md).

🌐 **Prefer a visual tour?** Open the interactive landing page (GitHub Pages) — visual
overview, architecture diagrams and run results:
**[🇬🇧 English version](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/index.html)** ·
**[🇵🇱 wersja polska](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/index_PL.html)**.

---

## 🎯 What is this?

This repository builds a **real PostgreSQL cluster on your own Windows 11 machine** — six
small virtual machines that together behave like a production database that *keeps working
when things break*. One PowerShell command builds the whole thing; another tears it down.
No cloud account, no Ansible, no WSL — **just VirtualBox**.

Once it is running you can deliberately **break it** — kill the database leader, power off a
VM, cut the network, knock out the consensus store — and watch the cluster heal itself, with
**13 ready-made test scenarios** that check the outcome automatically (PASS/FAIL).

**New to PostgreSQL or high availability?** Read the next two sections first — they explain
the idea in plain language — then jump to the [Quickstart](#-quickstart).

---

## 🛡️ What is "high availability" (HA)?

A single database server is a **single point of failure**: if it crashes, reboots, or loses
its disk, your application stops. **High availability** removes that single point by running
several copies of the database and adding automation that, when the active copy fails,
**promotes another copy and redirects traffic to it — automatically, in seconds, without a
human**.

A few terms used throughout this lab, in plain words:

- **Leader / primary** — the one node that currently accepts writes (`INSERT`/`UPDATE`).
- **Replica / standby** — a node that continuously copies the leader's data and can take
  over. Replicas can also serve read-only queries.
- **Failover** — the automatic switch: a replica becomes the new leader after the old one dies.
- **Synchronous replication** — the leader waits for a replica to confirm each commit, so a
  committed row is guaranteed to survive a failover (**zero data loss**).
- **Quorum** — a majority vote (here 2 of 3) that decides who the leader is, preventing two
  nodes from both believing they are in charge ("split-brain").

---

## 🧠 How HA works in this lab (the concept)

![Cluster architecture](docs/diagrams/architecture.svg)

The lab runs **three PostgreSQL nodes** (one leader, two replicas) plus the supporting cast
that makes failover automatic:

1. **Patroni** runs next to PostgreSQL on each node and continuously renews a "I am the
   leader" lease.
2. **etcd** stores that lease — it is the cluster's shared source of truth about *who is the
   leader right now*.
3. If the leader dies, its lease expires (~30 s). The remaining nodes hold a vote through
   etcd; the winner is **promoted** to leader by Patroni.
4. **HAProxy** constantly asks Patroni "who is the leader?" and **reroutes client writes** to
   whoever it is — so applications keep using one stable address (`db.lab.test:5000`).
5. Because replication is **synchronous**, the row your app committed a moment before the
   crash is still there on the new leader.

The old leader, once restarted, rejoins as a replica (using `pg_rewind` if its history
diverged). Full walkthrough with diagrams: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**
· standalone diagram page: **[architecture.html](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/architecture.html)**.

---

## 🧩 The building blocks (in plain words)

| Component | What job it does | Runs on |
|---|---|---|
| 🐘 **PostgreSQL 18** | The database itself; three-node streaming-replication cluster holding `labdb`. | pg1 · pg2 · pg3 |
| 🧭 **Patroni 4.1** | The HA supervisor — elects a leader, promotes a replica on failure, rejoins old leaders. | pg1 · pg2 · pg3 |
| 🗳️ **etcd 3.5** | Distributed "brain" — stores the leader lease and cluster state; 2-of-3 quorum. | pg1 · pg2 · pg3 |
| 🔀 **HAProxy 2.8** | Routes writes (`:5000`) to the leader and reads (`:5001`) to replicas; reroutes on failover. | lb |
| 🪣 **PgBouncer 1.23** | Connection pooler in front of HAProxy — keeps overhead low under load. | lb |
| 🌐 **Unbound DNS** | Resolves the lab's `lab.test` names, including the stable `db.lab.test` endpoint. | infra |
| ⏱️ **chronyd NTP** | Keeps every node's clock in sync — important for reliable consensus. | infra |
| 🐕 **softdog watchdog** | Kernel safety net: reboots a hung leader so it can't hold the lease forever. | pg1 · pg2 · pg3 |
| 🐍 **pgha-client** | Python test client (writer/reader/monitor) that measures real app downtime during a failover. | cli |

---

## 🖥️ What you get

- **6 VMs** on a private host-only network `192.168.56.0/24` (no internet exposure):
  - `infra` — recursive DNS (Unbound) + NTP (chronyd)
  - `pg1`, `pg2`, `pg3` — the 3-node Patroni/etcd/PostgreSQL cluster (synchronous + watchdog)
  - `lb` — HAProxy + PgBouncer (stable client endpoint `db.lab.test`)
  - `cli` — orchestrator + Python test client
- **13 scripted failure scenarios** with automatic PASS/FAIL assertions
- **A static GitHub Pages site** (`docs/`) with diagrams and interactive run reports

---

## 🚀 Quickstart

```powershell
# from a regular (non-elevated) PowerShell window
.\lab.ps1 prereqs        # verify host requirements + generate SSH key if missing
.\lab.ps1 build          # build the entire lab (~30 min on Ryzen 9 + NVMe)
.\lab.ps1 status         # show cluster state and open HAProxy stats in the browser

# one-time, requires elevated PowerShell:
.\lab.ps1 dns install    # add NRPT rule so *.lab.test resolves on Windows
```

After `lab.ps1 dns install`:

```powershell
ssh root@pg1.lab.test 'patronictl -c /etc/patroni/patroni.yml list'
psql "host=db.lab.test port=5000 dbname=labdb user=lab password=lab"
```

Command-by-command runbook with pitfalls: **[docs/QUICKSTART.md](docs/QUICKSTART.md)** ·
full Windows 11 walkthrough: **[docs/SETUP.md](docs/SETUP.md)**.

---

## 📋 Host requirements

- **Windows 11 Pro** x64 with **VirtualBox 7.0+** (provides `VBoxManage.exe`)
- Built-in tooling: PowerShell 5.1+, OpenSSH client, `curl.exe`
- **Python 3.8+** on the host (runs the tiny kickstart HTTP server `host/ks_server.py`)
- **Not used on the host**: Ansible, WSL, Make, Chocolatey, Scoop
- ≥ 20 GB free RAM, ≥ 60 GB free disk

All cluster tooling lives **inside the VMs**. The host runs only VirtualBox + a small Python
kickstart server.

---

## 🧪 Test scenarios

Thirteen scripted failure modes, runnable individually (`lab.ps1 scenario NN`) or as a suite:

| #  | Scenario                  | What it proves                                              |
|----|---------------------------|------------------------------------------------------------|
| 01 | `baseline`                | Cluster sanity — `patronictl list`, etcd health            |
| 02 | `kill-primary-hard`       | `pkill -9 postgres` on the leader, verify zero data loss   |
| 03 | `poweroff-primary-vm`     | `VBoxManage controlvm <pri> poweroff` → failover → restart |
| 04 | `graceful-switchover`     | Planned `patronictl switchover`, no data loss              |
| 05 | `network-partition`       | `iptables DROP` isolates the leader → failover, self-heal  |
| 06 | `etcd-single-loss`        | Stop etcd on one node — quorum 2/3 holds                   |
| 07 | `etcd-quorum-loss`        | Stop etcd on two nodes — observe failsafe, then recover    |
| 08 | `replica-restart`         | `systemctl restart patroni` on a replica — leader unchanged|
| 09 | `pg-rewind-old-primary`   | Old primary rejoins via `pg_rewind` after a diverged timeline |
| 10 | `sync-vs-async`           | Toggle `synchronous_mode`, demonstrate durability tradeoff |
| 11 | `multi-host-libpq`        | Driverless failover via libpq `target_session_attrs`       |
| 12 | `cascading-failure`       | Kill the leader, then the new leader — a third is elected  |
| 13 | `app-failover-continuous` | `pgha-client` load through a leader kill — measures app-side downtime |

```powershell
.\lab.ps1 scenario 02
.\lab.ps1 scenario all
.\lab.ps1 report          # build docs/run-report.html from the run logs + metrics
```

Scenario details and expected output: **[docs/SCENARIOS.md](docs/SCENARIOS.md)**.

---

## 📚 Key documents & pages

- 🏠 **Project landing page (GitHub Pages):** [index.html](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/index.html) (EN) ·
  [index_PL.html](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/index_PL.html) (PL) — visual overview, architecture, results.
- 🏛️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, failover sequence, DNS/NTP infrastructure
- 🚀 [docs/QUICKSTART.md](docs/QUICKSTART.md) — assemble & start the lab (command-by-command + pitfalls)
- ⚙️ [docs/SETUP.md](docs/SETUP.md) — full Windows 11 walkthrough incl. NRPT DNS
- 🧪 [docs/SCENARIOS.md](docs/SCENARIOS.md) — the 13 scenarios with expected output
- 🛠️ [docs/MANUAL_INSTALL.md](docs/MANUAL_INSTALL.md) — build the lab by hand, node by node (no `lab.ps1`)
- 🚧 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — VBox/scancode, NRPT fallback, watchdog
- 📊 **Run reports (GitHub Pages):** [agentic-run-all.html](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/agentic-run-all.html) (full-suite 13/13)
  · [run-report.html](https://krzysztof-i-cabaj.github.io/postgres18-ha-lab/run-report.html) (latest run) — Polish: `*_PL.html`
- 📃 [docs/AGENTIC_RUN_ALL.md](docs/AGENTIC_RUN_ALL.md) / [docs/RUN_REPORT.md](docs/RUN_REPORT.md) — the same reports as Markdown
- 📘 [docs/README.md](docs/README.md) — full documentation index (all EN/PL pairs)
- 🔧 [report/README.md](report/README.md) — run-report generator (`lab.ps1 report`)
- ⚙️ [SETTINGS.md](SETTINGS.md) — project-specific values (`<repo>` path, VM map, secrets, SSH)

---

## 📄 License

[MIT](LICENSE) © 2026 KCB Kris
