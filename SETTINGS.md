# ⚙️ SETTINGS — postgres18-ha-lab

[![Scope](https://img.shields.io/badge/Scope-Project_only-blue)]()
[![Conventions](https://img.shields.io/badge/Conventions-bilingual_PL%2FEN-orange)]()
[![Domain](https://img.shields.io/badge/Domain-lab.test-success)]()

> 🎯 Project-specific configuration only — the values and conventions that matter for *this*
> repository (the `<repo>` placeholder, lab domain, VM map, secrets layout, SSH access).
> Polish counterpart: [SETTINGS_PL.md](SETTINGS_PL.md).

---

## 🧩 `<repo>` definition

`<repo>` is a **placeholder** for wherever this repository lives on your machine.
Throughout the codebase (script headers, docs, command examples), references to
`<repo>` mean "the absolute path of the repository root on your local disk".

Common layouts:

| Setup | `<repo>` resolves to |
|---|---|
| Typical Windows clone | `C:\dev\postgres18-ha-lab` or `C:\src\postgres18-ha-lab` |
| WSL / git-bash clone | `~/dev/postgres18-ha-lab` |
| Other drive | `E:\projects\postgres18-ha-lab` |

Pick whatever you cloned to. **Do not commit** machine-specific paths back into
script headers or docs — keep them as the literal `<repo>` placeholder so the
project stays portable.

---

## 🌐 Lab domain

- **TLD**: `lab.test` (RFC 6761, deliberately not `.local` to avoid mDNS interference)
- **Authoritative resolver**: Unbound on `infra.lab.test` (`192.168.56.10`)
- **Stable client endpoint**: `db.lab.test:5000` (CNAME → `lb.lab.test`)
- **Reverse zone**: `56.168.192.in-addr.arpa.`

---

## 🔌 Host network

- VirtualBox host-only network: `vboxnet0`
- Subnet: `192.168.56.0/24`, DHCP **off**
- Host IP on this network: `192.168.56.1` (used by KS HTTP server during install)

---

## 🖥️ VM map (default topology)

| Hostname        | IP            | RAM | vCPU | Role                                    |
|-----------------|---------------|-----|------|-----------------------------------------|
| infra.lab.test  | 192.168.56.10 | 1G  | 1    | Unbound (DNS) + chronyd (NTP server)    |
| pg1.lab.test    | 192.168.56.11 | 4G  | 2    | PG18 + Patroni + etcd                   |
| pg2.lab.test    | 192.168.56.12 | 4G  | 2    | PG18 + Patroni + etcd                   |
| pg3.lab.test    | 192.168.56.13 | 4G  | 2    | PG18 + Patroni + etcd                   |
| lb.lab.test     | 192.168.56.20 | 2G  | 2    | HAProxy + PgBouncer                     |
| cli.lab.test    | 192.168.56.30 | 2G  | 2    | Orchestrator + test client + bastion    |

Total: ~17 GB RAM, 10 vCPU. Authoritative source: `lab.config.example.psd1`.

---

## 🔐 Secrets layout

- **Source of truth**: `lab.config.psd1` (gitignored). Copy from
  `lab.config.example.psd1` and fill in real passwords on first run.
- **Sample**: `lab.config.example.psd1` (committed; placeholder passwords only).
- **Transferred to `cli` VM** as `/usr/local/lib/postgres18-ha-lab/lab.config.json`,
  `chmod 600`, owned by `root:root`. Orchestrator reads it from there.
- **Built-in fallback**: kickstart sets `root` password to `labroot` and creates
  user `lab` with password `lab`. SSH keys are the primary auth path; passwords are
  fallback only. Document this in `docs/TROUBLESHOOTING.md`.

---

## 🔑 Host SSH keys (zero-password access from Windows)

- Key path: `%USERPROFILE%\.ssh\id_ed25519` (generated automatically by
  `host/modules/Prereqs.psm1` if missing).
- Public key is rendered into every `*.ks` via `{{SSH_PUBKEY}}` and installed by
  kickstart `%post` into both `/root/.ssh/authorized_keys` and
  `/home/lab/.ssh/authorized_keys`.
- `Prereqs.psm1` also writes (idempotently, between markers) an OpenSSH config
  block to `%USERPROFILE%\.ssh\config`:
  ```
  # >>> postgres18-ha-lab >>>
  Host infra pg1 pg2 pg3 lb cli
      HostName %h.lab.test
      User root
      IdentityFile ~/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
      UserKnownHostsFile ~/.ssh/known_hosts.lab
  # <<< postgres18-ha-lab <<<
  ```
- Net effect: `ssh pg1` from PowerShell or MobaXterm logs in passwordlessly
  (MobaXterm: Settings → SSH → "Use OpenSSH config" — reads the same file).

---

## 📤 SCP examples for this project

```powershell
# upload lab.config.json to cli (orchestrator config)
scp .\lab.config.json root@cli.lab.test:/usr/local/lib/postgres18-ha-lab/lab.config.json

# pull HAProxy stats config back for inspection
scp root@lb.lab.test:/etc/haproxy/haproxy.cfg .\out\haproxy.cfg

# fetch a scenario log from cli after a run
scp root@cli.lab.test:/var/log/postgres18-ha-lab/scenarios/02-*.log .\logs\
```

Without NRPT installed (`lab.ps1 dns install` skipped), substitute the IP for the
hostname (e.g. `root@192.168.56.30` instead of `root@cli.lab.test`).

---

## 📚 Project file map

| File / dir                                              | Role                                                  |
|---------------------------------------------------------|-------------------------------------------------------|
| [README.md](README.md) / [README_PL.md](README_PL.md)   | Top-level intro, quickstart, scenario index           |
| [LICENSE](LICENSE)                                      | MIT licence                                           |
| `lab.ps1`                                               | Windows entrypoint, verb dispatcher                   |
| `lab.config.example.psd1`                               | Configuration template (committed)                    |
| `lab.config.psd1`                                       | Real configuration (gitignored)                       |
| `host/PgHaLab.psm1`                                     | Umbrella PowerShell module imported by `lab.ps1`      |
| `host/modules/*.psm1`                                   | Individual functional modules                         |
| `host/tests/Scancode.Tests.ps1`                         | Pester tests (gating component)                       |
| `kickstart/base.ks.tmpl`                                | Master kickstart template                             |
| `kickstart/post/role-bootstrap.sh`                      | First-boot role installer (downloaded by `%post`)     |
| `guest/orchestrate.sh`                                  | Cluster orchestrator (runs on `cli` VM)               |
| `guest/roles/*.sh`                                      | Idempotent install scripts per role                   |
| `guest/templates/*.tmpl`                                | Config templates rendered with `@@PLACEHOLDER@@`      |
| `client-app/`                                           | Python writer/reader/monitor package                  |
| `scenarios/`                                            | 13 failure-mode scripts + assertions                  |
| `report/`                                               | Run-report generator (logs + metrics -> MD + HTML)    |
| `docs/*.md` + `docs/*_PL.md`                            | Documentation pairs EN/PL (README, ARCHITECTURE, SETUP, SCENARIOS, TROUBLESHOOTING) |
| `docs/diagrams/*.svg`                                   | Architecture and flow diagrams                        |
| `docs/architecture.html`                                | Standalone HTML wrapper around the architecture/flow SVGs |
| `monitoring/`                                           | Optional Prometheus/Grafana extras                    |

---

## 🔗 Conventions

This project follows a small set of repo-wide conventions:

- **Script headers** — every script (`.sh`, `.ps1`, `.psm1`, `.py`, `.sql`) carries a
  bilingual PL/EN header block (title, description, author, date, version, usage).
- **`<repo>` placeholder** — paths in docs and script headers use the literal `<repo>` token
  instead of a machine-specific absolute path (see the table above).
- **Encoding** — UTF-8 **without BOM**; LF line endings for shell/Python/Markdown, CRLF for
  PowerShell (`.ps1`/`.psm1`/`.psd1`). Enforced by `.github/workflows/lint.yml` (`encoding-audit`).
- **Bilingual docs** — every `*.md` has a `*_PL.md` Polish counterpart.
