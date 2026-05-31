# 🔧 Instrukcja ręcznej instalacji i konfiguracji

[![Guide](https://img.shields.io/badge/Typ-Manual_krok_po_kroku-blue)]()
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791)]()
[![Stack](https://img.shields.io/badge/Patroni%2Betcd%2BHAProxy%2BPgBouncer-darkgreen)]()
[![Guest](https://img.shields.io/badge/Guest_OS-Rocky_Linux_9.8-10B981)]()
[![Host](https://img.shields.io/badge/Host-Windows_11_%2B_VirtualBox-0078D6)]()
[![Bez automatu](https://img.shields.io/badge/lab.ps1-nieu%C5%BCywane-lightgrey)]()

> 🎯 Zbuduj **lab PostgreSQL 18 HA ręcznie**, węzeł po węźle, bez `lab.ps1`. Każda komenda, plik
> konfiguracyjny i kolejność, którą wykonuje automat, jest tu rozpisana — możesz zrobić to z ręki
> i zrozumieć każdą warstwę. Wersja angielska: [MANUAL_INSTALL.md](MANUAL_INSTALL.md).
>
> To dokładny odpowiednik tego, co robią skrypty ról `guest/roles/*.sh` i szablony
> `guest/templates/*.tmpl` — ręczny ekwiwalent `.\lab.ps1 build`.

---

## 🧩 Topologia

| Host  | IP            | Rola                                    | NIC-i |
|-------|---------------|-----------------------------------------|------|
| infra | 192.168.56.10 | DNS (Unbound) + NTP (serwer chrony)     | host-only + NAT |
| pg1   | 192.168.56.11 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| pg2   | 192.168.56.12 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| pg3   | 192.168.56.13 | etcd + PostgreSQL 18 + Patroni          | host-only + NAT |
| lb    | 192.168.56.20 | HAProxy + PgBouncer (`db` = CNAME → lb) | host-only + NAT |
| cli   | 192.168.56.30 | klient + (host orkiestratora)           | host-only + NAT |

- Domena: `lab.test`. Sieć host-only: `192.168.56.0/24`, host = `192.168.56.1`.
- Wersje: PostgreSQL **18**, Patroni **4.1+**, etcd **3.5.21** (binarka GitHub — brak w repo EL9), HAProxy (AppStream EL9), PgBouncer (PGDG).
- Demo baza `labdb`, użytkownik `lab` / hasło `lab`.
- **Kolejność budowy:** infra → (pg1,pg2,pg3: etcd → PostgreSQL → Patroni) → lb (HAProxy + PgBouncer) → cli → demo DB.

> ⚠️ Każdy NIC ma osobne zadanie: **NAT (`enp0s8`)** = internet (dnf/pip) i **brama domyślna**;
> **host-only (`enp0s3`)** = wyłącznie ruch wewnątrz labu i **NIE może mieć bramy domyślnej**.
> To pułapka #1 przy ręcznej instalacji — patrz [Pułapka sieciowa](#-pu%C5%82apka-sieciowa-przeczytaj-najpierw).

---

## 🔗 Mapowanie: sekcja ↔ skrypt automatu

Każda sekcja poniżej to **ręczny odpowiednik jednego skryptu roli**. W trybie automatycznym
`.\lab.ps1 build` wgrywa `guest/` na `cli`, a `guest/orchestrate.sh` wywołuje te role po SSH
w kolejności zależności (i przekazuje hasła przez env `PATRONI_*`, `APP_PWD`):

| Sekcja | Skrypt automatu | Szablony (`guest/templates/`) |
|---|---|---|
| 5. infra (DNS+NTP) | `guest/roles/05-infra.sh` | `unbound-lab.conf.tmpl`, `chrony-server.conf.tmpl` |
| 6. wspólne (DNS/hosts/chrony/softdog) | `guest/roles/00-common.sh` | `chrony-client.conf.tmpl` |
| 6. SSH cli→węzły | `host/PgHaLab.psm1` → `Invoke-Provision` | — |
| 7. etcd | `guest/roles/10-etcd.sh` | `etcd.conf.tmpl` |
| 8. PostgreSQL 18 | `guest/roles/20-postgresql.sh` | — |
| 9. Patroni | `guest/roles/30-patroni.sh` | `patroni.yml.tmpl` |
| 10. HAProxy | `guest/roles/40-haproxy.sh` | `haproxy.cfg.tmpl` |
| 11. PgBouncer | `guest/roles/50-pgbouncer.sh` | `pgbouncer.ini.tmpl`, `userlist.txt.tmpl` |
| 12. demo DB | `guest/orchestrate.sh` (faza 6) | — |
| 13. klient | `guest/roles/60-client.sh` | — |

Konfiguracje w sekcjach 5–13 są **dosłownym** rozpisaniem tych szablonów (z podstawionymi
wartościami labu), więc ręczna instalacja daje identyczny stack co automat.

---

## 🚧 Pułapka sieciowa (przeczytaj najpierw)

Jeśli interfejs host-only dostanie bramę domyślną (`192.168.56.1`, host Windows — który **nie routuje**
do internetu), wygra ona z trasą NAT i **wszystkie `dnf`/`pip` padną z "Could not resolve host"**. Zawsze:

- host-only `enp0s3`: statyczne IP, **bez bramy**, `ipv4.never-default yes`.
- NAT `enp0s8`: DHCP (jedyna brama domyślna + internet).
- DNS: na czas bootstrapu używaj publicznego resolvera (`1.1.1.1`); gdy Unbound na infra wstanie,
  klienci przełączają resolver na infra (`192.168.56.10`), a infra na siebie (`127.0.0.1`).

---

## 0. 🖥️ Wymagania hosta (Windows)

- VirtualBox 7.x (`VBoxManage.exe` w `C:\Program Files\Oracle\VirtualBox\`).
- Pobrany ISO Rocky Linux **9.8 minimal** (np. `D:\ISOs\Rocky-9.8-x86_64-minimal.iso`).
- ≥ 20 GB wolnego RAM, ≥ 60 GB wolnego dysku.

Alias dla wygody (PowerShell):
```powershell
Set-Alias vbm 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
```

---

## 1. 🌐 Sieć host-only

VirtualBox zwykle tworzy `VirtualBox Host-Only Ethernet Adapter` na `192.168.56.1/24`. Sprawdź:
```powershell
vbm list hostonlyifs
```
Jeśli brak, utwórz i ustaw IP hosta:
```powershell
vbm hostonlyif create
vbm hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
```
Wbudowany DHCP zostaw **wyłączony** (lab używa statycznych IP).

---

## 2. 🧱 Utwórz VM-ki

Raz na host (`infra`, `pg1`, `pg2`, `pg3`, `lb`, `cli`). Przykład dla `infra` (1024 MB / 1 vCPU);
użyj **4096 MB / 2 vCPU** dla pg1/pg2/pg3 i **2048 MB / 2 vCPU** dla lb/cli.

```powershell
$NAME='infra'; $RAM=1024; $CPU=1
vbm createvm --name $NAME --ostype RedHat_64 --register
vbm modifyvm $NAME --memory $RAM --cpus $CPU `
    --nic1 hostonly --hostonlyadapter1 "VirtualBox Host-Only Ethernet Adapter" `
    --nic2 nat `
    --boot1 disk --boot2 dvd --boot3 none --boot4 none `
    --ioapic on --rtcuseutc on --graphicscontroller vmsvga --vram 16 --audio-driver none

# Dysk 20 GB + kontroler SATA + podpięcie dysku i ISO Rocky
$vmdir = (Split-Path (vbm showvminfo $NAME --machinereadable | Select-String '^CfgFile=' ).ToString().Split('"')[1])
vbm createmedium disk --filename "$vmdir\$NAME.vdi" --size 20480 --format VDI
vbm storagectl $NAME --name SATA --add sata --controller IntelAhci --portcount 2
vbm storageattach $NAME --storagectl SATA --port 0 --type hdd --medium "$vmdir\$NAME.vdi"
vbm storageattach $NAME --storagectl SATA --port 1 --type dvddrive --medium "D:\ISOs\Rocky-9.8-x86_64-minimal.iso"
```

> 🔑 **Kolejność bootowania = `disk` przed `dvd`.** Przy pierwszym boocie pusty dysk „przepada" do DVD
> (rusza instalator); po instalacji dysk jest bootowalny, więc reboot bootuje system — bez pętli
> re-instalacji. **Nie** licz na samo-wysunięcie ISO.

---

## 3. 💿 Zainstaluj Rocky Linux 9.8 (każda VM)

Uruchom VM w trybie GUI i przejdź interaktywny instalator (albo użyj kickstartu — patrz `kickstart/`):
```powershell
vbm startvm infra --type gui
```

W instalatorze Anaconda ustaw:
- **Software:** Minimal Install.
- **Hasło root** + użytkownik `lab` (grupa wheel) — dowolnie.
- **Dysk:** partycjonowanie automatyczne (LVM), bez swap jest OK.
- **Sieć i nazwa hosta:** ustaw nazwę (np. `infra.lab.test`) i skonfiguruj oba NIC-i:
  - `enp0s3` (host-only) → **Ręcznie** IPv4: adres `192.168.56.10/24`, **BEZ bramy**, DNS `1.1.1.1` na teraz.
  - `enp0s8` (NAT) → **Automatycznie (DHCP)**.
  - Włącz **Łącz automatycznie** na obu.
- **Rozpocznij instalację**, potem reboot.

Po reboocie **odepnij ISO**, żeby nigdy więcej nie bootowało instalatora:
```powershell
vbm storageattach infra --storagectl SATA --port 1 --type dvddrive --medium none
```

Powtórz dla `pg1`(.11), `pg2`(.12), `pg3`(.13), `lb`(.20), `cli`(.30) — te same kroki, inna
nazwa/IP/RAM/CPU.

> 💡 Po instalacji zaloguj się (konsola lub `ssh root@<ip>` po dodaniu klucza) i sprawdź sieć:
> `ip route` musi pokazać `default via <brama NAT> dev enp0s8` — **nie** przez `192.168.56.1`. Jeśli źle:
> `nmcli connection modify "enp0s3" ipv4.gateway "" ipv4.never-default yes && nmcli connection up enp0s3`

---

## 4. 🏷️ Pliki metadanych labu (każda VM)

Skrypty ról je czytają. Utwórz na każdej VM (wartości per węzeł). Przykład dla `pg1`:
```bash
mkdir -p /etc/postgres18-ha-lab
echo 'pg-node'        > /etc/postgres18-ha-lab/role      # infra | pg-node | lb | cli
echo 'pg1.lab.test'   > /etc/postgres18-ha-lab/hostname
echo '192.168.56.11'  > /etc/postgres18-ha-lab/ip
echo '192.168.56.10'  > /etc/postgres18-ha-lab/infra_ip
echo 'lab.test'       > /etc/postgres18-ha-lab/domain
```
Wartości `role`: `infra` (infra), `pg-node` (pg1/2/3), `lb` (lb), `cli` (cli).

Możesz też wgrać drzewo `guest/` z repo na każdą VM (lub kopiować potrzebne pliki na bieżąco). Kroki
poniżej odtwarzają szablony „w linii", więc kopiowanie jest opcjonalne.

---

## 5. 🛰️ infra — Unbound (DNS) + chrony (serwer NTP)

> 💡 **Automat:** `guest/roles/05-infra.sh` (szablony `unbound-lab.conf.tmpl`, `chrony-server.conf.tmpl`).

Na **infra** jako root.

```bash
dnf install -y unbound chrony bind-utils
```

Zapisz strefę labu Unbound do **`/etc/unbound/conf.d/lab.conf`** (EL9 dołącza `conf.d/`, **nie**
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

chrony jako **serwer** NTP dla labu:
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

Firewall + start + wskazanie infra na własny resolver:
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

Weryfikacja:
```bash
dig @127.0.0.1 pg1.lab.test +short        # -> 192.168.56.11
dig @127.0.0.1 -x 192.168.56.12 +short    # -> pg2.lab.test.
dig @127.0.0.1 db.lab.test  +short        # -> lb.lab.test. -> 192.168.56.20
chronyc tracking | grep Stratum
ss -lntu | grep -E ':53|:123'
```

---

## 6. 🧩 Wspólna konfiguracja na pg1/pg2/pg3/lb/cli

> 💡 **Automat:** `guest/roles/00-common.sh` (szablon `chrony-client.conf.tmpl`); SSH cli→węzły sieje `Invoke-Provision` w `host/PgHaLab.psm1`.

Na **każdej VM poza infra** jako root. (infra ma już własny DNS/NTP.)

```bash
dnf install -y bind-utils jq curl

# Klient DNS -> infra
conn=$(nmcli -g NAME,DEVICE c show --active | grep ':enp0s3' | head -1 | cut -d: -f1)
nmcli connection modify "$conn" ipv4.dns "192.168.56.10" ipv4.ignore-auto-dns yes ipv4.dns-search "lab.test"
nmcli connection up "$conn"

# Fallback /etc/hosts
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

# chrony jako klient infra
cat > /etc/chrony.conf <<'EOF'
server 192.168.56.10 iburst prefer
makestep 1.0 3
rtcsync
driftfile /var/lib/chrony/drift
logdir /var/log/chrony
EOF
systemctl enable --now chronyd ; systemctl restart chronyd
```

**Tylko na pg1/pg2/pg3** załaduj soft watchdog (fencing Patroni):
```bash
echo softdog > /etc/modules-load.d/softdog.conf
modprobe softdog
ls -l /dev/watchdog          # ma istnieć; jeśli nie — użyj WATCHDOG_MODE=off później
```

Sprawdź DNS przez infra:
```bash
dig pg1.lab.test +short      # -> 192.168.56.11 (rozwiązane przez infra)
```

### 🔑 SSH bez hasła do węzłów (do weryfikacji i scenariuszy)

Komendy weryfikacyjne (`ssh root@pg1 'patronictl ...'`) i scenariusze awarii łączą się
po SSH jako **root** z hosta Windows **oraz** z `cli`. W Rocky 9 `sshd` ma domyślnie
`PermitRootLogin prohibit-password` — root loguje się **tylko kluczem**, hasło jest
odrzucane (`Permission denied (publickey)`). Trzeba więc wgrać klucz **publiczny** do
`/root/.ssh/authorized_keys` na każdym węźle.

**Host Windows → każdy węzeł** (raz; klucz masz z `ssh-keygen`/`prereqs`). Z konsoli
węzła jako root wklej swój klucz publiczny z hosta (`%USERPROFILE%\.ssh\id_ed25519.pub`):
```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA...   # <- wklej zawartosc id_ed25519.pub z hosta Windows
EOF
chmod 600 /root/.ssh/authorized_keys
```
(W trybie automatycznym `lab.ps1` robi to przez kickstart; przy instalacji ręcznej — sam.)

**`cli` → pg1/pg2/pg3/lb** (orkiestrator i scenariusze startują z `cli`, więc `cli`
potrzebuje **własnego** klucza uznanego na węzłach). Na **cli** jako root:
```bash
test -f /root/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519
cat /root/.ssh/id_ed25519.pub        # skopiuj te jedna linie
```
Dopisz tę linię do `/root/.ssh/authorized_keys` na pg1, pg2, pg3 i lb (z konsoli węzła
albo przez `ssh root@<wezel>` z hosta, który już ma dostęp).

> 💡 Szybki wariant z hasłem (wzorzec `ssh_setup.sh` z projektu Oracle): tymczasowo ustaw
> `PermitRootLogin yes` + `PasswordAuthentication yes` w `/etc/ssh/sshd_config`,
> `systemctl restart sshd`, użyj `ssh-copy-id root@<wezel>` (hasło roota = `labroot`
> z kickstartu), a po skończeniu **przywróć** `prohibit-password`. Wygodne w izolowanym
> host-only LAB-ie, ale pamiętaj o cofnięciu zmiany.

---

## 7. 🗳️ Klaster etcd (pg1, pg2, pg3)

> 💡 **Automat:** `guest/roles/10-etcd.sh` (szablon `etcd.conf.tmpl`).

Na **każdym** z pg1/pg2/pg3 jako root. Dostosuj `NAME`/`IP` per węzeł.

```bash
# etcd NIE jest w repozytoriach Rocky/RHEL 9 (usuniety z EL8+, brak tez w EPEL) —
# instalujemy oficjalna binarke z GitHub releases:
ETCD_VER=3.5.21
command -v tar >/dev/null || dnf install -y tar gzip   # Rocky 9 minimal nie ma tar/gzip
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
# Binarka z GitHub nie dostarcza unitu systemd (inaczej niz RPM) — tworzymy wlasny:
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

Wystartuj etcd na wszystkich trzech (klaster formuje się po osiągnięciu kworum peerów). Weryfikacja z
dowolnego węzła:
```bash
etcdctl --endpoints="http://192.168.56.11:2379" endpoint health
etcdctl --endpoints="http://192.168.56.11:2379,http://192.168.56.12:2379,http://192.168.56.13:2379" member list
```

---

## 8. 🐘 Binaria PostgreSQL 18 (pg1, pg2, pg3)

> 💡 **Automat:** `guest/roles/20-postgresql.sh`.

Na **każdym** z pg1/pg2/pg3 jako root. **Nie** uruchamiaj `initdb` — klaster bootstrapuje Patroni.

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

## 9. 🧠 Patroni (pg1, potem pg2, potem pg3 — sekwencyjnie)

> 💡 **Automat:** `guest/roles/30-patroni.sh` (szablon `patroni.yml.tmpl`; hasła z env `PATRONI_*` przekazuje orkiestrator).

Na **każdym** z pg1/pg2/pg3 jako root. Najpierw pg1, poczekaj aż zostanie liderem, potem pg2, pg3.

Wybierz hasła raz (te same na wszystkich trzech węzłach):
```bash
export REPL_PWD='LabRepl2026' SUPER_PWD='LabSuper2026' REWIND_PWD='LabRewind2026' APP_PWD='lab'
export WATCHDOG_MODE='automatic'     # użyj 'off' jeśli /dev/watchdog niedostępny
```

Instalacja Patroni (pip) + sterownik:
```bash
# Bez postgresql18-devel: psycopg2-binary to gotowy wheel (nie wymaga pg headers),
# a devel ciagnie perl-IPC-Run, ktorego nie ma w repo EL9 (jest w EPEL).
dnf install -y python3-pip python3-devel gcc
pip3 install --upgrade 'patroni[etcd3]>=4.1' 'psycopg2-binary>=2.9' 'python-etcd>=0.4'
```

Zapisz `/etc/patroni/patroni.yml` (dostosuj `name`/`connect_address` per węzeł — pokazano pg1/.11):
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

Unit systemd:
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
curl -fsS http://${IP}:8008/health        # czekaj aż odpowie
```

> ⚠️ Wystartuj **pg1 jako pierwszy** i poczekaj aż `patronictl ... list` pokaże go jako `Leader`
> (running), dopiero wtedy startuj Patroni na pg2 i pg3 — sklonują się z lidera i dołączą jako repliki.

Stan klastra (z dowolnego węzła pg):
```bash
patronictl -c /etc/patroni/patroni.yml list
```

---

## 10. ⚖️ HAProxy (lb)

> 💡 **Automat:** `guest/roles/40-haproxy.sh` (szablon `haproxy.cfg.tmpl`).

Na **lb** jako root.
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
HAProxy odpytuje REST Patroni (`:8008`): tylko lider odpowiada `GET /primary` kodem 200 (port 5000),
repliki odpowiadają `GET /replica` (port 5001). Stats UI: `http://lb.lab.test:7000/`.

---

## 11. 🔌 PgBouncer (lb)

> 💡 **Automat:** `guest/roles/50-pgbouncer.sh` (szablony `pgbouncer.ini.tmpl`, `userlist.txt.tmpl`).

Na **lb** jako root. Pooler połączeń przed listenerem primary HAProxy.
```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf install -y pgbouncer

export APP_USER=lab APP_DB=labdb APP_PWD='lab' SUPER_PWD='LabSuper2026'
# Format md5 PostgreSQL: 'md5' + md5(haslo + uzytkownik)
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

## 12. 🗄️ Utwórz demo bazę + użytkownika aplikacji

> 💡 **Automat:** `guest/orchestrate.sh` (faza 6 — te same `CREATE DATABASE`/`CREATE ROLE`/`GRANT`).

Uruchom **raz**, z dowolnego węzła pg (lub skąd `psql` dosięgnie bieżącego primary). Połącz się
bezpośrednio do primary jako `postgres`:
```bash
export SUPER_PWD='LabSuper2026' APP_PWD='lab'
# CREATE DATABASE NIE moze byc w bloku DO (PostgreSQL: "cannot be executed from a
# function") — wykonaj bezposrednio; "already exists" jest nieszkodliwe.
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c 'CREATE DATABASE labdb' 2>&1 | grep -v 'already exists' || true
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c \
  "DO \$\$BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='lab') THEN CREATE ROLE lab LOGIN PASSWORD '${APP_PWD}'; END IF; END\$\$"
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -c "GRANT ALL ON DATABASE labdb TO lab"

# Tabela demo pgha_writer_log -- wymagana przez scenariusze testowe i klienta
# (client-app/writer.py). Tworzymy w bazie labdb na liderze (zreplikuje sie na standby),
# wlasciciel = lab (ma wtedy INSERT/SELECT + sekwencje).
PGPASSWORD="$SUPER_PWD" psql -h 127.0.0.1 -U postgres -d labdb -c \
  "CREATE TABLE IF NOT EXISTS pgha_writer_log (id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT now(), payload TEXT NOT NULL, host TEXT NOT NULL DEFAULT inet_server_addr()::text); ALTER TABLE pgha_writer_log OWNER TO lab;"
```

---

## 13. 🐍 Klient (cli)

> 💡 **Automat:** `guest/roles/60-client.sh`.

Na **cli** jako root.
```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql || true
# pgha-client wymaga Pythona >=3.11; domyślny python3 w Rocky 9.8 to 3.9 (pip odrzuca
# editable install na 3.9). Instalujemy python3.11 jawnie.
dnf install -y python3.11 python3.11-pip postgresql18

# Dołączony klient testowy (writer/reader/monitor) — używany przez scenariusz 13.
# Instalacja do 3.11; skrypt konsolowy `pgha-client` ląduje w /usr/local/bin (na PATH).
python3.11 -m pip install --upgrade -e /usr/local/lib/postgres18-ha-lab/client-app
python3.11 -c 'import pgha_client' && command -v pgha-client   # weryfikacja
/usr/pgsql-18/bin/psql --version
```

---

## ✅ Weryfikacja

Z `cli` (lub skądkolwiek w sieci host-only z `psql`):
```bash
# Członkowie klastra + role
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'

# Zapis przez primary HAProxy (5000) + PgBouncer (6432)
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select 1'
psql 'host=db.lab.test port=6432 dbname=labdb user=lab password=lab' -c 'select 1'

# Read-only przez listener replik
psql 'host=db.lab.test port=5001 dbname=labdb user=lab password=lab' -c 'select pg_is_in_recovery()'
```
Stats HAProxy: otwórz `http://lb.lab.test:7000/` (lub `http://192.168.56.20:7000/`).

---

## 🧪 Szybki test failover

```bash
# 1. Kto jest liderem?
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'

# 2. Zapisz wiersz-sentinel
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' \
  -c 'create table if not exists t(id serial primary key, ts timestamptz default now()); insert into t default values returning id;'

# 3. Zabij twardo PostgreSQL na primary (na bieżącym węźle-liderze)
ssh root@<lider> 'pkill -9 postgres'

# 4. Poczekaj ~30s, potwierdź nowego lidera i że wiersz przetrwał (zero utraty danych)
ssh root@pg1 'patronictl -c /etc/patroni/patroni.yml list'
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select count(*) from t'
```
Pełen zestaw skryptowych scenariuszy jest w `scenarios/` (patrz [SCENARIOS_PL.md](SCENARIOS_PL.md)).

---

## 🚧 Rozwiązywanie problemów (pułapki ręcznej instalacji)

| Objaw | Przyczyna / naprawa |
|---|---|
| `dnf` / `pip` → "Could not resolve host" | Host-only `enp0s3` ma bramę domyślną. Usuń: `nmcli c modify enp0s3 ipv4.gateway "" ipv4.never-default yes; nmcli c up enp0s3`. Brama domyślna ma iść przez NAT (`enp0s8`). |
| `dig pg1.lab.test` → NXDOMAIN; unbound tylko na 127.0.0.1 | Config Unbound w złym katalogu. Na EL9 musi być `/etc/unbound/conf.d/lab.conf` (nie `unbound.conf.d/`). Sprawdź: `grep include /etc/unbound/unbound.conf`. |
| VM ciągle uruchamia instalator po instalacji | Kolejność bootowania DVD-first lub ISO nieodpięte. Ustaw `--boot1 disk --boot2 dvd` i odepnij ISO. |
| Patroni nie startuje / brak lidera | Brak kworum etcd (potrzeba ≥2/3), złe hasła w `patroni.yml`, albo brak `/dev/watchdog` przy `mode: automatic` → ustaw `WATCHDOG_MODE=off`. |
| HAProxy oznacza wszystkie backendy jako down | REST Patroni `:8008` nieosiągalny (firewall) lub PostgreSQL nie działa. |
| `psql` przez `db.lab.test` nie działa z hosta Windows | Dodaj regułę NRPT / wpis hosts, żeby `*.lab.test` rozwiązywało się na Windows (patrz [SETUP_PL.md](SETUP_PL.md)). |
| `ssh root@pgN` → `Permission denied (publickey)` | Klucz publiczny nie jest w `/root/.ssh/authorized_keys` na węźle; EL9 zezwala rootowi **tylko na klucz** (`prohibit-password`), hasło jest odrzucane. Wgraj klucz (sekcja 6, „SSH bez hasła"). Z `cli` potrzebny **osobny** klucz cli posiany na węzły — automat robi to w `Invoke-Provision`. |
| `dnf install etcd` → `No match for argument: etcd` | etcd **nie jest** w repozytoriach Rocky/RHEL 9 (ani w EPEL). Instaluj binarkę z GitHub releases + własny unit systemd (patrz sekcja 7). |
| `nothing provides perl(IPC::Run)` przy `postgresql18-devel` | Nie instaluj `postgresql18-devel` — jest zbędny (`psycopg2-binary` to gotowy wheel). `perl-IPC-Run` jest tylko w EPEL. Patrz sekcja 9. |
| `rsync: command not found` (orkiestrator) | Rocky 9 **minimal** nie ma rsync. Automat używa `scp -rp`; ręcznie albo `dnf install -y rsync`, albo kopiuj przez `scp -rp`. |

---

## 🔗 Referencje

- [SETUP_PL.md](SETUP_PL.md) — ścieżka automatyczna (`lab.ps1`) i DNS Windows (NRPT).
- [ARCHITECTURE_PL.md](ARCHITECTURE_PL.md) — komponenty, sekwencja failover, projekt DNS/NTP.
- [SCENARIOS_PL.md](SCENARIOS_PL.md) — 12 skryptowych scenariuszy awarii.
- `guest/roles/*.sh` + `guest/templates/*.tmpl` — źródło, które ta instrukcja odwzorowuje.
