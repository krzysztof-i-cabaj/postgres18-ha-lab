# 🔧 Manual Installation & Configuration Guide

[![Guide](https://img.shields.io/badge/Type-Manual_walkthrough-blue)]()
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791)]()
[![Stack](https://img.shields.io/badge/Patroni%2Betcd%2BHAProxy%2BPgBouncer-darkgreen)]()
[![Guest](https://img.shields.io/badge/Guest_OS-Rocky_Linux_9.8-10B981)]()
[![Host](https://img.shields.io/badge/Host-Windows_11_%2B_VirtualBox-0078D6)]()
[![No automation](https://img.shields.io/badge/lab.ps1-not_used-lightgrey)]()

> 🎯 Build the **PostgreSQL 18 HA lab by hand**, node by node, without `lab.ps1`. Every command,
> config file and ordering decision the automation makes is written out here so you can do it
> manually and understand each layer. Polish version: [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md).
>
> This mirrors exactly what the role scripts in `guest/roles/*.sh` and templates in
> `guest/templates/*.tmpl` do — it is the manual equivalent of `.\lab.ps1 build`.

---

## 🧩 Topology

| Host  | IP            | Role                                    | NICs |
|-------|---------------|-----------------------------------------|------|
| infra | 192.168.56.10 | DNS (Unbound) + NTP (chrony server)     | host-only + NAT |
| pg1   | 192.168.56.11 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| pg2   | 192.168.56.12 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| pg3   | 192.168.56.13 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| lb    | 192.168.56.20 | HAProxy + PgBouncer (`db` = CNAME → lb) | host-only + NAT |
| cli   | 192.168.56.30 | client + (orchestrator host)            | host-only + NAT |

- Domain: `lab.test`. Host-only network: `192.168.56.0/24`, host = `192.168.56.1`.
- Component versions: PostgreSQL **18**, Patroni **4.1+**, etcd **3.5.21** (GitHub binary — not in EL9 repos), HAProxy (EL9 AppStream), PgBouncer (PGDG).
- Demo database `labdb`, app user `lab` / password `lab`.
- **Build order:** infra → (pg1,pg2,pg3: etcd → PostgreSQL → Patroni) → lb (HAProxy + PgBouncer) → cli → demo DB.

> ⚠️ Each NIC has a distinct job: **NAT (`enp0s8`)** = internet (dnf/pip) and the **default route**;
> **host-only (`enp0s3`)** = lab-internal traffic only and **must NOT have a default gateway**.
> This is the #1 manual-install pitfall — see [Networking gotcha](#-networking-gotcha-read-first).

---

## 🔗 Mapping: section ↔ automation script

Each section below is the **manual equivalent of one role script**. In automatic mode
`.\lab.ps1 build` ships `guest/` to `cli`, and `guest/orchestrate.sh` invokes these roles over
SSH in dependency order (passing passwords via env `PATRONI_*`, `APP_PWD`):

| Section | Automation script | Templates (`guest/templates/`) |
|---|---|---|
| 5. infra (DNS+NTP) | `guest/roles/05-infra.sh` | `unbound-lab.conf.tmpl`, `chrony-server.conf.tmpl` |
| 6. common (DNS/hosts/chrony/softdog) | `guest/roles/00-common.sh` | `chrony-client.conf.tmpl` |
| 6. SSH cli→nodes | `host/PgHaLab.psm1` → `Invoke-Provision` | — |
| 7. etcd | `guest/roles/10-etcd.sh` | `etcd.conf.tmpl` |
| 8. PostgreSQL 18 | `guest/roles/20-postgresql.sh` | — |
| 9. Patroni | `guest/roles/30-patroni.sh` | `patroni.yml.tmpl` |
| 10. HAProxy | `guest/roles/40-haproxy.sh` | `haproxy.cfg.tmpl` |
| 11. PgBouncer | `guest/roles/50-pgbouncer.sh` | `pgbouncer.ini.tmpl`, `userlist.txt.tmpl` |
| 12. demo DB | `guest/orchestrate.sh` (phase 6) | — |
| 13. client | `guest/roles/60-client.sh` | — |

The configs in sections 5–13 are the **literal** expansion of those templates (with lab values
substituted), so a manual install yields a stack identical to the automation.

---

## 🚧 Networking gotcha (read first)

If the host-only interface gets a default gateway (`192.168.56.1`, the Windows host — which does **not**
route to the internet), it wins over the NAT route and **all `dnf`/`pip` fail with "Could not resolve
host"**. Always:

- host-only `enp0s3`: static IP, **no gateway**, `ipv4.never-default yes`.
- NAT `enp0s8`: DHCP (provides the only default route + internet).
- For DNS: during bootstrap use a public resolver (`1.1.1.1`); after infra's Unbound is up, the clients
  switch their resolver to infra (`192.168.56.10`), and infra switches to itself (`127.0.0.1`).

---

## 0. 🖥️ Host prerequisites (Windows)

- VirtualBox 7.x (`VBoxManage.exe` in `C:\Program Files\Oracle\VirtualBox\`).
- Rocky Linux **9.8 minimal** ISO downloaded (e.g. `D:\ISOs\Rocky-9.8-x86_64-minimal.iso`).
- ≥ 20 GB free RAM, ≥ 60 GB free disk.

Set a shell alias for convenience (PowerShell):
```powershell
Set-Alias vbm 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
```

---

## 1. 🌐 Host-only network

VirtualBox usually creates `VirtualBox Host-Only Ethernet Adapter` at `192.168.56.1/24`. Verify:
```powershell
vbm list hostonlyifs
```
If absent, create it and set the host IP:
```powershell
vbm hostonlyif create
vbm hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```
Leave its built-in DHCP **disabled** (the lab uses static IPs).

---

## 2. 🧱 Create the VMs

Do this once per host (`infra`, `pg1`, `pg2`, `pg3`, `lb`, `cli`). Example shown for `infra`
(1024 MB / 1 vCPU); use **4096 MB / 2 vCPU** for pg1/pg2/pg3 and **2048 MB / 2 vCPU** for lb/cli.

```powershell
$NAME='infra'; $RAM=1024; $CPU=1
vbm createvm --name $NAME --ostype RedHat_64 --register
vbm modifyvm $NAME --memory $RAM --cpus $CPU `
    --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter" `
    --nic2 nat `
    --boot1 disk --boot2 dvd --boot3 none --boot4 none `
    --ioapic on --rtcuseutc on --graphicscontroller vmsvga --vram 16 --audio-driver none

# 20 GB disk + SATA controller + attach disk and the Rocky ISO
$vmdir = (Split-Path (vbm showvminfo $NAME --machinereadable | Select-String '^CfgFile=' ).ToString().Split('"')[1])
vbm createmedium disk --filename "$vmdir\$NAME.vdi" --size 20480 --format VDI
vbm storagectl $NAME --name SATA --add sata --controller IntelAhci --portcount 2
vbm storageattach $NAME --storagectl SATA --port 0 --type hdd --medium "$vmdir\$NAME.vdi"
vbm storageattach $NAME --storagectl SATA --port 1 --type dvddrive --medium "D:\ISOs\Rocky-9.8-x86_64-minimal.iso"
```

> 🔑 **Boot order = `disk` before `dvd`.** On first boot the empty disk falls through to the DVD
> (installer runs); after install the disk is bootable, so reboots boot the OS — no re-install loop.
> Do **not** rely on the ISO ejecting itself.

---

## 3. 💿 Install Rocky Linux 9.8 (each VM)

Start the VM in GUI mode and run the interactive installer (or use a kickstart — see `kickstart/`):
```powershell
vbm startvm infra --type gui
```

In the Anaconda installer set:
- **Software:** Minimal Install.
- **Root password** + a `lab` user (wheel group) — your choice.
- **Disk:** automatic partitioning (LVM), no swap is fine.
- **Network & Hostname:** set the hostname (e.g. `infra.lab.test`) and configure both NICs:
  - `enp0s3` (host-only) → **Manual** IPv4: address `192.168.56.10/24`, **NO gateway**, DNS `1.1.1.1` for now.
  - `enp0s8` (NAT) → **Automatic (DHCP)**.
  - Toggle both to **Connect automatically**.
- **Begin Installation**, then reboot.

After reboot, **detach the ISO** so it never boots the installer again:
```powershell
vbm storageattach infra --storagectl SATA --port 1 --type dvddrive --medium none
```

Repeat for `pg1`(.11), `pg2`(.12), `pg3`(.13), `lb`(.20), `cli`(.30) — same steps, different
hostname/IP/RAM/CPU.

> 💡 After install, log in (console or `ssh root@<ip>` once you add your key) and verify networking:
> `ip route` must show `default via <NAT gw> dev enp0s8` — **not** via `192.168.56.1`. If it does, run:
> `nmcli connection modify "enp0s3" ipv4.gateway "" ipv4.never-default yes && nmcli connection up enp0s3`

---

## 4. 🏷️ Lab metadata files (every VM)

The role scripts read these. Create them on each VM (values per node). Example for `pg1`:
```bash
mkdir -p /etc/postgres18-ha-lab
echo 'pg-node'        > /etc/postgres18-ha-lab/role      # infra | pg-node | lb | cli
echo 'pg1.lab.test'   > /etc/postgres18-ha-lab/hostname
echo '192.168.56.11'  > /etc/postgres18-ha-lab/ip
echo '192.168.56.10'  > /etc/postgres18-ha-lab/infra_ip
echo 'lab.test'       > /etc/postgres18-ha-lab/domain
```
`role` values: `infra` (infra), `pg-node` (pg1/2/3), `lb` (lb), `cli` (cli).

Also place the repo's `guest/` tree on each VM (or just copy the files you need as you go). The manual
steps below reproduce the templates inline, so copying is optional.

---

## 5. 🛰️ infra — Unbound (DNS) + chrony (NTP server)

> 💡 **Automation:** `guest/roles/05-infra.sh` (templates `unbound-lab.conf.tmpl`, `chrony-server.conf.tmpl`).

Run on **infra** as root.

```bash
dnf install -y unbound chrony bind-utils
```

Write the Unbound lab zone to **`/etc/unbound/conf.d/lab.conf`** (EL9 includes `conf.d/`, **not**
`unbound.conf.d/`):
```bash
install -d -m 0755 /etc/unbound/conf.d
cat > /etc/unbound/conf.d/lab.conf <<'EOF'
server:
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-ip6: no
    access-control: 192.168.56.0/24 allow
    access-control: 127.0.0.0/8 allow
    verbosity: 1
    log-queries: no
    log-replies: no

    local-zone: "lab.test." static
    local-data: "infra.lab.test. IN A 192.168.56.10"
    local-data: "pg1.lab.test.   IN A 192.168.56.11"
    local-data: "pg2.lab.test.   IN A 192.168.56.12"
    local-data: "pg3.lab.test.   IN A 192.168.56.13"
    local-data: "lb.lab.test.    IN A 192.168.56.20"
    local-data: "cli.lab.test.   IN A 192.168.56.30"

    local-zone: "56.168.192.in-addr.arpa." static
    local-data-ptr: "192.168.56.10 infra.lab.test."
    local-data-ptr: "192.168.56.11 pg1.lab.test."
    local-data-ptr: "192.168.56.12 pg2.lab.test."
    local-data-ptr: "192.168.56.13 pg3.lab.test."
    local-data-ptr: "192.168.56.20 lb.lab.test."
    local-data-ptr: "192.168.56.30 cli.lab.test."

    local-data: "db.lab.test. IN CNAME lb.lab.test."

forward-zone:
    name: "."
    forward-addr: 1.1.1.1
    forward-addr: 9.9.9.9
    forward-addr: 8.8.8.8
EOF
```

chrony as an NTP **server** for the lab:
```bash
cat > /etc/chrony.conf <<'EOF'
pool pool.ntp.org iburst maxsources 4
pool 0.rocky.pool.ntp.org iburst
allow 192.168.56.0/24
local stratum 10
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
```

Firewall + start + point infra at its own resolver:
```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=53/udp --add-port=53/tcp --add-port=123/udp
firewall-cmd --reload
unbound-checkconf
systemctl enable --now unbound
systemctl restart chronyd
chattr -i /etc/resolv.conf 2>/dev/null || true
printf 'search lab.test\nnameserver 127.0.0.1\n' > /etc/resolv.conf
```

Verify:
```bash
dig @127.0.0.1 pg1.lab.test +short        # -> 192.168.56.11
dig @127.0.0.1 -x 192.168.56.12 +short    # -> pg2.lab.test.
dig @127.0.0.1 db.lab.test  +short        # -> lb.lab.test. -> 192.168.56.20
chronyc tracking | grep Stratum
ss -lntu | grep -E ':53|:123'
```

---

## 6. 🧩 Common setup on pg1/pg2/pg3/lb/cli

> 💡 **Automation:** `guest/roles/00-common.sh` (template `chrony-client.conf.tmpl`); the cli→nodes SSH key is seeded by `Invoke-Provision` in `host/PgHaLab.psm1`.

Run on **every non-infra VM** as root. (infra already has its own DNS/NTP.)

```bash
dnf install -y bind-utils jq curl

# DNS client -> infra
conn=$(nmcli -g NAME,DEVICE c show --active | grep ':enp0s3' | head -1 | cut -d: -f1)
nmcli connection modify "$conn" ipv4.dns "192.168.56.10" ipv4.ignore-auto-dns yes ipv4.dns-search "lab.test"
nmcli connection up "$conn"

# /etc/hosts fallback
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
192.168.56.10 infra.lab.test infra
192.168.56.11 pg1.lab.test pg1
192.168.56.12 pg2.lab.test pg2
192.168.56.13 pg3.lab.test pg3
192.168.56.20 lb.lab.test lb db.lab.test db
192.168.56.30 cli.lab.test cli
EOF

# chrony client of infra
cat > /etc/chrony.conf <<'EOF'
server 192.168.56.10 iburst prefer
makestep 1.0 3
rtcsync
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
EOF
systemctl enable --now chronyd ; systemctl restart chronyd
```

**Only on pg1/pg2/pg3** load the soft watchdog (Patroni fencing):
```bash
echo softdog > /etc/modules-load.d/softdog.conf
modprobe softdog
ls -l /dev/watchdog          # should exist; if not, use WATCHDOG_MODE=off later
```

Verify DNS through infra:
```bash
dig pg1.lab.test +short      # -> 192.168.56.11 (resolved via infra)
```

### 🔑 Passwordless SSH to the nodes (for verification & scenarios)

The verification commands (`ssh root@pg1 'patronictl ...'`) and the failure scenarios
connect over SSH as **root** from the Windows host **and** from `cli`. On Rocky 9 `sshd`
defaults to `PermitRootLogin prohibit-password` — root logs in **by key only**, passwords
are rejected (`Permission denied (publickey)`). So you must place the **public** key into
`/root/.ssh/authorized_keys` on every node.

**Windows host → every node** (once; you have the key from `ssh-keygen`/`prereqs`). From
the node console as root, paste your host public key (`%USERPROFILE%\.ssh\id_ed25519.pub`):
```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA...   # <- paste the contents of id_ed25519.pub from the Windows host
EOF
chmod 600 /root/.ssh/authorized_keys
```
(In automatic mode `lab.ps1` does this via kickstart; for a manual install you do it yourself.)

**`cli` → pg1/pg2/pg3/lb** (the orchestrator and scenarios run from `cli`, so `cli` needs
its **own** key trusted on the nodes). On **cli** as root:
```bash
test -f /root/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519
cat /root/.ssh/id_ed25519.pub        # copy this single line
```
Append that line to `/root/.ssh/authorized_keys` on pg1, pg2, pg3 and lb (from the node
console, or via `ssh root@<node>` from the host that already has access).

> 💡 Quick password-based variant (the `ssh_setup.sh` pattern from the Oracle project):
> temporarily set `PermitRootLogin yes` + `PasswordAuthentication yes` in
> `/etc/ssh/sshd_config`, `systemctl restart sshd`, use `ssh-copy-id root@<node>` (root
> password = `labroot` from kickstart), then **restore** `prohibit-password` afterwards.
> Convenient on an isolated host-only LAB, but remember to revert the change.

---

## 7. 🗳️ etcd cluster (pg1, pg2, pg3)

> 💡 **Automation:** `guest/roles/10-etcd.sh` (template `etcd.conf.tmpl`).

Run on **each** of pg1/pg2/pg3 as root. Adjust `NAME`/`IP` per node.

```bash
# etcd is NOT in Rocky/RHEL 9 repos (dropped in EL8+, not in EPEL either) —
# install the official GitHub-release binary:
ETCD_VER=3.5.21
command -v tar >/dev/null || dnf install -y tar gzip   # Rocky 9 minimal ships no tar/gzip
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VER}/etcd-v${ETCD_VER}-linux-amd64.tar.gz" -o /tmp/etcd.tar.gz
tar -xzf /tmp/etcd.tar.gz -C /tmp
install -m 0755 /tmp/etcd-v${ETCD_VER}-linux-amd64/etcd    /usr/local/bin/etcd
install -m 0755 /tmp/etcd-v${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/etcdctl
id etcd &>/dev/null || useradd --system --home-dir /var/lib/etcd --shell /sbin/nologin etcd

NAME=pg1 ; IP=192.168.56.11        # pg2 -> 192.168.56.12 ; pg3 -> 192.168.56.13
install -d -m 0755 /etc/etcd
cat > /etc/etcd/etcd.conf.yml <<EOF
name: '${NAME}'
data-dir: '/var/lib/etcd/default.etcd'
listen-peer-urls: 'http://${IP}:2380'
listen-client-urls: 'http://${IP}:2379,http://127.0.0.1:2379'
initial-advertise-peer-urls: 'http://${IP}:2380'
advertise-client-urls: 'http://${IP}:2379'
initial-cluster: 'pg1=http://192.168.56.11:2380,pg2=http://192.168.56.12:2380,pg3=http://192.168.56.13:2380'
initial-cluster-state: 'new'
initial-cluster-token: 'etcd-cluster-pg-ha-lab'
auto-compaction-mode: 'periodic'
auto-compaction-retention: '1h'
quota-backend-bytes: 2147483648
EOF

install -d -m 0700 -o etcd -g etcd /var/lib/etcd
# The GitHub binary ships no systemd unit (unlike the RPM) — create our own:
cat > /etc/systemd/system/etcd.service <<'EOF'
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
User=etcd
ExecStart=/usr/local/bin/etcd --config-file=/etc/etcd/etcd.conf.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

firewall-cmd --permanent --add-port=2379/tcp --add-port=2380/tcp ; firewall-cmd --reload
systemctl enable --now etcd
```

Start etcd on all three nodes (the cluster forms once a quorum of peers is up). Verify from any node:
```bash
etcdctl --endpoints="http://192.168.56.11:2379" endpoint health
etcdctl --endpoints="http://192.168.56.11:2379,http://192.168.56.12:2379,http://192.168.56.13:2379" member list
```

---

## 8. 🐘 PostgreSQL 18 binaries (pg1, pg2, pg3)

> 💡 **Automation:** `guest/roles/20-postgresql.sh`.

Run on **each** of pg1/pg2/pg3 as root. **Do not** run `initdb` — Patroni bootstraps the cluster.

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql || true
dnf install -y postgresql18-server postgresql18-contrib

install -d -m 0700 -o postgres -g postgres /var/lib/pgsql/18/data
systemctl disable --now postgresql-18 2>/dev/null || true
/usr/pgsql-18/bin/postgres --version    # PostgreSQL 18.x

firewall-cmd --permanent --add-port=5432/tcp --add-port=8008/tcp ; firewall-cmd --reload
```

---

## 9. 🧠 Patroni (pg1, then pg2, then pg3 — sequentially)

> 💡 **Automation:** `guest/roles/30-patroni.sh` (template `patroni.yml.tmpl`; passwords passed via env `PATRONI_*` by the orchestrator).

Run on **each** of pg1/pg2/pg3 as root. Do pg1 first, wait for it to become leader, then pg2, pg3.

Pick passwords once (reuse the same on all three nodes):
```bash
export REPL_PWD='LabRepl2026' SUPER_PWD='LabSuper2026' REWIND_PWD='LabRewind2026' APP_PWD='lab'
export WATCHDOG_MODE='automatic'     # use 'off' if /dev/watchdog is unavailable
```

Install Patroni (pip) + driver:
```bash
# No postgresql18-devel: psycopg2-binary is a prebuilt wheel (no pg headers needed),
# and devel pulls perl-IPC-Run, which is absent from EL9 repos (it's in EPEL).
dnf install -y python3-pip python3-devel gcc
pip3 install --upgrade 'patroni[etcd3]>=4.1' 'psycopg2-binary>=2.9' 'python-etcd>=0.4'
```

Write `/etc/patroni/patroni.yml` (adjust `name`/`connect_address` per node — pg1/.11 shown):
```bash
install -d -m 0755 /etc/patroni
NAME=pg1 ; IP=192.168.56.11
cat > /etc/patroni/patroni.yml <<EOF
scope: pg-ha-lab
namespace: /service/
name: ${NAME}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${IP}:8008

etcd3:
  hosts:
    - 192.168.56.11:2379
    - 192.168.56.12:2379
    - 192.168.56.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 1024MB
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
        archive_mode: "on"
        archive_command: "/bin/true"
        listen_addresses: "*"
        max_connections: 200
        shared_buffers: 1GB
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host  replication  replicator  192.168.56.0/24  md5
    - host  all          all         192.168.56.0/24  md5
    - local all          all                          peer
  users:
    lab:
      password: "${APP_PWD}"
      options:
        - LOGIN

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${IP}:5432
  data_dir: /var/lib/pgsql/18/data
  bin_dir: /usr/pgsql-18/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: "${REPL_PWD}"
    superuser:
      username: postgres
      password: "${SUPER_PWD}"
    rewind:
      username: rewind_user
      password: "${REWIND_PWD}"

watchdog:
  mode: ${WATCHDOG_MODE}
  device: /dev/watchdog
  safety_margin: 5

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
chown -R postgres:postgres /etc/patroni
chmod 600 /etc/patroni/patroni.yml
```

systemd unit:
```bash
cat > /etc/systemd/system/patroni.service <<'EOF'
[Unit]
Description=Patroni — PostgreSQL HA
After=network-online.target etcd.service
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
KillMode=process
KillSignal=SIGINT
Restart=on-failure
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now patroni
curl -fsS http://${IP}:8008/health        # wait until it answers
```

> ⚠️ Start **pg1 first** and wait until `patronictl ... list` shows it as `Leader` (running), then start
> Patroni on pg2 and pg3 — they will clone from the leader and join as replicas.

Cluster check (from any pg node):
```bash
patronictl -c /etc/patroni/patroni.yml list
```

---

## 10. ⚖️ HAProxy (lb)

> 💡 **Automation:** `guest/roles/40-haproxy.sh` (template `haproxy.cfg.tmpl`).

Run on **lb** as root.
```bash
dnf install -y haproxy
setsebool -P haproxy_connect_any 1 2>/dev/null || true

cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    maxconn 1000
    log /dev/log local0
    daemon

defaults
    log     global
    mode    tcp
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
    stats refresh 10s
    stats show-legends

listen postgres_primary
    bind *:5000
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 5s fall 2 rise 1 on-marked-down shutdown-sessions
    server pg1 192.168.56.11:5432 check port 8008
    server pg2 192.168.56.12:5432 check port 8008
    server pg3 192.168.56.13:5432 check port 8008

listen postgres_replicas
    bind *:5001
    option httpchk GET /replica
    http-check expect status 200
    balance roundrobin
    default-server inter 5s fall 2 rise 1 on-marked-down shutdown-sessions
    server pg1 192.168.56.11:5432 check port 8008
    server pg2 192.168.56.12:5432 check port 8008
    server pg3 192.168.56.13:5432 check port 8008
EOF

firewall-cmd --permanent --add-port=5000/tcp --add-port=5001/tcp --add-port=7000/tcp --add-port=6432/tcp
firewall-cmd --reload
systemctl enable --now haproxy
ss -lnt | grep -E ':5000|:5001|:7000'
```
HAProxy probes Patroni's REST (`:8008`): only the leader answers `GET /primary` with 200 (port 5000),
replicas answer `GET /replica` (port 5001). Stats UI: `http://lb.lab.test:7000/`.

---

## 11. 🔌 PgBouncer (lb)

> 💡 **Automation:** `guest/roles/50-pgbouncer.sh` (templates `pgbouncer.ini.tmpl`, `userlist.txt.tmpl`).

Run on **lb** as root. Connection pooler in front of HAProxy's primary listener.
```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf install -y pgbouncer

export APP_USER=lab APP_DB=labdb APP_PWD='lab' SUPER_PWD='LabSuper2026'
# PostgreSQL md5 format: 'md5' + md5(password + username)
app_md5="md5$(printf '%s%s' "$APP_PWD"  "$APP_USER" | md5sum | cut -d' ' -f1)"
super_md5="md5$(printf '%s%s' "$SUPER_PWD" postgres   | md5sum | cut -d' ' -f1)"

install -d -m 0750 -o pgbouncer -g pgbouncer /etc/pgbouncer
cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
${APP_DB} = host=127.0.0.1 port=5000 dbname=${APP_DB}

[pgbouncer]
listen_addr = *
listen_port = 6432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
ignore_startup_parameters = extra_float_digits
admin_users = postgres
stats_users = postgres
log_connections = 1
log_disconnections = 1
EOF

cat > /etc/pgbouncer/userlist.txt <<EOF
"${APP_USER}" "${app_md5}"
"postgres" "${super_md5}"
EOF
chmod 0600 /etc/pgbouncer/userlist.txt
chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt /etc/pgbouncer/pgbouncer.ini

systemctl enable --now pgbouncer
ss -lnt | grep :6432
```

---

## 12. 🗄️ Create the demo database + app user

> 💡 **Automation:** `guest/orchestrate.sh` (phase 6 — the same `CREATE DATABASE`/`CREATE ROLE`/`GRANT`).

Run **once**, from any pg node (or wherever `psql` can reach the current primary). Connect directly to
the primary as `postgres`:
```bash
export SUPER_PWD='LabSuper2026' APP_PWD='lab'
# CREATE DATABASE can't run inside a DO block (PostgreSQL: "cannot be executed from
# a function") — run it directly; "already exists" is harmless.
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c 'CREATE DATABASE labdb' 2>&1 | grep -v 'already exists' || true
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c \
  "DO \$\$BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='lab') THEN CREATE ROLE lab LOGIN PASSWORD '${APP_PWD}'; END IF; END\$\$"
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c "GRANT ALL ON DATABASE labdb TO lab"

# Demo table pgha_writer_log -- required by the test scenarios and the client
# (client-app/writer.py). Created in labdb on the leader (replicates to standbys),
# owned by lab (so it has INSERT/SELECT + the sequence).
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -d labdb -c \
  "CREATE TABLE IF NOT EXISTS pgha_writer_log (id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT now(), payload TEXT NOT NULL, host TEXT NOT NULL DEFAULT inet_server_addr()::text); ALTER TABLE pgha_writer_log OWNER TO lab;"
```

---

## 13. 🐍 Client (cli)

> 💡 **Automation:** `guest/roles/60-client.sh`.

Run on **cli** as root.
```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql || true
# pgha-client needs Python >=3.11; Rocky 9.8 default python3 is 3.9 (pip rejects the
# editable install on 3.9). Install python3.11 explicitly.
dnf install -y python3.11 python3.11-pip postgresql18

# The bundled test client (writer/reader/monitor) — used by scenario 13.
# Install into 3.11; the console script `pgha-client` lands in /usr/local/bin (on PATH).
python3.11 -m pip install --upgrade -e /usr/local/lib/postgres18-ha-lab/client-app
python3.11 -c 'import pgha_client' && command -v pgha-client   # verify
/usr/pgsql-18/bin/psql --version
```

---

## ✅ Verification

From `cli` (or anywhere on the host-only net with `psql`):
```bash
# Cluster members + roles
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'

# Write through HAProxy primary (5000) + PgBouncer (6432)
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select 1'
psql 'host=db.lab.test port=6432 dbname=labdb user=lab password=lab' -c 'select 1'

# Read-only via replicas listener
psql 'host=db.lab.test port=5001 dbname=labdb user=lab password=lab' -c 'select pg_is_in_recovery()'
```
HAProxy stats: open `http://lb.lab.test:7000/` (or `http://192.168.56.20:7000/`).

---

## 🧪 Quick failover test

```bash
# 1. Who is leader?
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'

# 2. Write a sentinel row
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' \
  -c 'create table if not exists t(id serial primary key, ts timestamptz default now()); insert into t default values returning id;'

# 3. Kill the primary's PostgreSQL hard (run on the current leader node)
ssh root@<leader> 'pkill -9 postgres'

# 4. Wait ~30s, confirm a new leader and that the row survived (zero data loss)
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select count(*) from t'
```
The full scripted suite lives in `scenarios/` (see [SCENARIOS.md](SCENARIOS.md)).

---

## 🚧 Troubleshooting (manual-install pitfalls)

| Symptom | Cause / fix |
|---|---|
| `dnf` / `pip` → "Could not resolve host" | Host-only `enp0s3` has a default gateway. Remove it: `nmcli c modify enp0s3 ipv4.gateway "" ipv4.never-default yes; nmcli c up enp0s3`. Default route must be via NAT (`enp0s8`). |
| `dig pg1.lab.test` → NXDOMAIN; unbound only on 127.0.0.1 | Unbound config in the wrong dir. It must be `/etc/unbound/conf.d/lab.conf` on EL9 (not `unbound.conf.d/`). `grep include /etc/unbound/unbound.conf` to confirm. |
| VM keeps re-running the installer after install | Boot order is DVD-first, or ISO not detached. Set `--boot1 disk --boot2 dvd` and detach the ISO. |
| Patroni won't start / no leader | etcd quorum down (need ≥2/3), or wrong passwords in `patroni.yml`, or `/dev/watchdog` missing with `mode: automatic` → set `WATCHDOG_MODE=off`. |
| HAProxy marks all backends down | Patroni REST `:8008` not reachable (firewall) or PostgreSQL not running. |
| `psql` via `db.lab.test` fails from Windows host | Add the NRPT rule / hosts entry so `*.lab.test` resolves on Windows (see [SETUP.md](SETUP.md)). |
| `ssh root@pgN` → `Permission denied (publickey)` | The public key isn't in `/root/.ssh/authorized_keys` on the node; EL9 allows root **by key only** (`prohibit-password`), passwords are rejected. Add the key (section 6, "Passwordless SSH"). From `cli` a **separate** cli key must be seeded onto the nodes — the automation does this in `Invoke-Provision`. |
| `dnf install etcd` → `No match for argument: etcd` | etcd is **not** in Rocky/RHEL 9 repos (nor EPEL). Install the GitHub-release binary + your own systemd unit (see section 7). |
| `nothing provides perl(IPC::Run)` on `postgresql18-devel` | Don't install `postgresql18-devel` — it's unnecessary (`psycopg2-binary` is a prebuilt wheel). `perl-IPC-Run` lives only in EPEL. See section 9. |
| `rsync: command not found` (orchestrator) | Rocky 9 **minimal** has no rsync. The automation uses `scp -rp`; manually either `dnf install -y rsync` or copy via `scp -rp`. |

---

## 🔗 References

- [SETUP.md](SETUP.md) — automated path (`lab.ps1`) and Windows DNS (NRPT).
- [ARCHITECTURE.md](ARCHITECTURE.md) — components, failover sequence, DNS/NTP design.
- [SCENARIOS.md](SCENARIOS.md) — 13 scripted failure scenarios.
- `guest/roles/*.sh` + `guest/templates/*.tmpl` — the source this guide mirrors.
