# 🧪 Scenariusze awarii — ręczne odtworzenie krok po kroku

[![Count](https://img.shields.io/badge/Scenariusze-13-darkgreen)]()
[![Tryb](https://img.shields.io/badge/Tryb-r%C4%99czny_bez_lab.ps1-blue)]()
[![Stack](https://img.shields.io/badge/Patroni%2Betcd%2BHAProxy-darkgreen)]()
[![Uwaga](https://img.shields.io/badge/Cz%C4%99%C5%9B%C4%87-DESTRUKCYJNE-red)]()

> 🎯 Jak **ręcznie** odtworzyć to, co robią skrypty `scenarios/NN-*.sh` — polecenie po poleceniu,
> bez `lab.ps1 scenario`. Każdy scenariusz: cel, kroki, oczekiwany wynik, sprzątanie.
> Wersja angielska: [MANUAL_SCENARIOS.md](MANUAL_SCENARIOS.md). Opis + oczekiwany output automatu:
> [SCENARIOS_PL.md](SCENARIOS_PL.md). Budowa labu z ręki: [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md).

---

## 🧩 Zanim zaczniesz

- **Gdzie uruchamiać:** wszystkie polecenia z VM **`cli`** (jako root), chyba że krok mówi „host" —
  wtedy z hosta Windows (PowerShell + `VBoxManage`). `cli` ma SSH bez hasła do `pg1/pg2/pg3/lb`.
- **Wymagania:** działający klaster (`patronictl list` → 1 Leader + 2 repliki, etcd 3/3), tabela demo
  `pgha_writer_log` w bazie `labdb` (tworzy ją `build`/`orchestrate.sh` faza 6; ręcznie — sekcja 12
  [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md)).
- **DNS:** używamy nazw `pg1.lab.test`, `lb.lab.test` itd. (rozwiązuje infra Unbound).
- **⚠️ DESTRUKCYJNE** scenariusze (02, 03, 05, 09, 12, 13) celowo zabijają procesy/VM lub tną sieć —
  klaster sam się odbudowuje, ale uruchamiaj je świadomie. Każdy ma krok sprzątania.
- Scenariusz **13** dodatkowo wymaga klienta testowego **`pgha-client`** na `cli` (zainstalowanego do
  **Pythona 3.11** — domyślny 3.9 w Rocky 9.8 jest za stary; patrz [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md) §13).

### 🧰 Polecenia pomocnicze (toolbox)

```bash
# Stan klastra (kto jest liderem, role, lag):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# Sama nazwa lidera (przydatne do skryptowania):
curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[] | select(.role=="leader") | .name'

# Zapis przez HAProxy primary (:5000) — trafia tylko do lidera:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At \
  -c "INSERT INTO pgha_writer_log (payload) VALUES ('test-'||clock_timestamp()) RETURNING id"

# Odczyt (liczba wierszy):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# Zdrowie etcd (na danym węźle):
ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
```

> 💡 W skryptach `lider` to nazwa krótka (`pg1`), a SSH idzie do FQDN (`pg1.lab.test`). Poniżej
> zapisujemy ją do zmiennej `L`, żeby kroki były kopiowalne.

---

## 🔗 Mapowanie: scenariusz ↔ skrypt

| # | Scenariusz | Skrypt | Typ |
|---|---|---|---|
| 01 | baseline (sanity) | `scenarios/01-baseline.sh` | bezpieczny |
| 02 | kill-primary-hard | `scenarios/02-kill-primary-hard.sh` | ⚠️ destrukcyjny |
| 03 | poweroff-primary-vm | `scenarios/03-poweroff-primary-vm.sh` | ⚠️ akcja hosta |
| 04 | graceful-switchover | `scenarios/04-graceful-switchover.sh` | bezpieczny |
| 05 | network-partition | `scenarios/05-network-partition.sh` | ⚠️ destrukcyjny |
| 06 | etcd-single-loss | `scenarios/06-etcd-single-loss.sh` | bezpieczny |
| 07 | etcd-quorum-loss | `scenarios/07-etcd-quorum-loss.sh` | bezpieczny |
| 08 | replica-restart | `scenarios/08-replica-restart.sh` | bezpieczny |
| 09 | pg-rewind-old-primary | `scenarios/09-pg-rewind-old-primary.sh` | ⚠️ destrukcyjny |
| 10 | sync-vs-async | `scenarios/10-sync-vs-async.sh` | zmienia DCS |
| 11 | multi-host-libpq | `scenarios/11-multi-host-libpq.sh` | bezpieczny |
| 12 | cascading-failure | `scenarios/12-cascading-failure.sh` | ⚠️ destrukcyjny |
| 13 | app-failover-continuous | `scenarios/13-app-failover-continuous.sh` | ⚠️ destrukcyjny |

---

## 01 — baseline (sanity)

**Cel:** potwierdzić, że klaster jest zdrowy, zanim zaczniesz testy awarii.

```bash
# 1. Jest lider, etcd ma kworum (≥2/3), widać 3 członków:
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
ssh root@pg2 "etcdctl --endpoints=http://localhost:2379 endpoint health"
ssh root@pg3 "etcdctl --endpoints=http://localhost:2379 endpoint health"

# 2. Zapis i odczyt przez HAProxy:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('baseline') RETURNING id"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"
```

**Oczekiwane:** 1 `Leader` + 2 repliki (`streaming`, lag 0), 3× `is healthy`, zapis zwraca `id`, odczyt zwraca liczbę wierszy.

---

## 02 — kill-primary-hard ⚠️

**Cel:** twardy failover (`pkill -9 postgres` na liderze) + dowód **braku utraty danych** (sentinel commitowany przez `synchronous_mode`).

```bash
# 1. Zapamiętaj lidera i commituj wiersz-sentinel PRZED awarią:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
SID=$(PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('sentinel') RETURNING id")
echo "lider=$L sentinel_id=$SID"

# 2. Zabij PostgreSQL na liderze:
ssh root@${L}.lab.test "pkill -9 postgres" || true

# 3. Poczekaj (≤60s) i potwierdź NOWEGO lidera:
sleep 30; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# 4. Read/write znów działa (HAProxy przekierował na nowego lidera):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# 5. DOWÓD braku utraty danych — sentinel przetrwał:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT 1 FROM pgha_writer_log WHERE id = $SID"
```

**Oczekiwane:** lider zmienił się (`$L` → inny węzeł) w ~30s, krok 5 zwraca `1` (sentinel ocalał → zero data loss). Zabity węzeł Patroni sam podniesie jako replikę.

**Cleanup:** żaden — Patroni restartuje PostgreSQL na starym liderze automatycznie (dołączy jako replika, p. scenariusz 09 dla `pg_rewind`).

---

## 03 — poweroff-primary-vm ⚠️ (akcja hosta)

**Cel:** twarda utrata VM lidera (nie tylko procesu). `cli` nie wyłączy VM — robi to **host**.

```bash
# 1. Na cli — kto jest liderem:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
echo "lider=$L"
```
```powershell
# 2. Na HOŚCIE (PowerShell) — wyłącz VM lidera (podstaw nazwę, np. pg1):
VBoxManage controlvm pg1 poweroff
```
```bash
# 3. Na cli — poczekaj (≤90s) na failover:
sleep 40; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```
```powershell
# 4. Na HOŚCIE — podnieś z powrotem wyłączoną VM:
VBoxManage startvm pg1 --type headless
```

**Oczekiwane:** po wyłączeniu VM lider zmienia się w ≤90s; po `startvm` węzeł wraca jako replika.

**Cleanup:** krok 4 (podnieś VM) — inaczej klaster zostanie z 2 węzłami.

---

## 04 — graceful-switchover

**Cel:** planowa, kontrolowana zmiana lidera (`patronictl switchover`) — bez utraty danych, bez błędów klienta.

```bash
# 1. Lider + kandydat (pierwsza replika):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
C=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role!="leader").name' | head -1)
echo "switchover $L -> $C"

# 2. Wykonaj switchover (z węzła lidera):
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml switchover --master $L --candidate $C --force"

# 3. Potwierdź nowego lidera + zapis działa:
sleep 10; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('after-switchover') RETURNING id"
```

**Oczekiwane:** liderem zostaje `$C`, stary lider dołącza jako replika, zapis dalej działa.

---

## 05 — network-partition ⚠️

**Cel:** odciąć lidera od sieci labu (`iptables DROP`); watchdog + wygaśnięcie leasu etcd wymuszają failover.

```bash
# 1. Lider:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')

# 2. Partycja — odetnij ruch z/do podsieci labu na liderze:
ssh root@${L}.lab.test "iptables -I INPUT -s 192.168.56.0/24 -j DROP; iptables -I OUTPUT -d 192.168.56.0/24 -j DROP"

# 3. Poczekaj (≤60s) na failover (odpytuj z innego węzła niż $L):
sleep 40; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# 4. CLEANUP — zagój partycję (flush iptables na odciętym węźle):
ssh root@${L}.lab.test "iptables -F INPUT; iptables -F OUTPUT"
```

**Oczekiwane:** lider zmienia się w ≤60s; po flush stary lider wraca i dogania klaster.

**Cleanup:** krok 4 jest **obowiązkowy** — bez niego węzeł zostaje odcięty.

---

## 06 — etcd-single-loss

**Cel:** utrata etcd na jednym węźle; kworum (2/3) trzyma → klaster działa normalnie.

```bash
# 1. Zatrzymaj etcd na pg3:
ssh root@pg3.lab.test "systemctl stop etcd"
sleep 5

# 2. Lider nadal jest, zapis działa (kworum 2/3 wystarcza):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('etcd-1-loss') RETURNING id"

# 3. CLEANUP — przywróć etcd:
ssh root@pg3.lab.test "systemctl start etcd"
```

**Oczekiwane:** brak zmiany lidera, zapis przechodzi. Po `start` etcd wraca do 3/3.

---

## 07 — etcd-quorum-loss

**Cel:** utrata kworum etcd (stop na 2 węzłach) → Patroni wchodzi w DCS-failsafe (odczyty działają, zapisy mogą się zatrzymać).

```bash
# 1. Zatrzymaj etcd na pg2 i pg3 (zostaje 1/3 = brak kworum):
ssh root@pg2.lab.test "systemctl stop etcd"
ssh root@pg3.lab.test "systemctl stop etcd"
sleep 10

# 2. Odczyt nadal działa (zapis może stać — zależnie od failsafe):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# 3. CLEANUP — przywróć kworum:
ssh root@pg2.lab.test "systemctl start etcd"
ssh root@pg3.lab.test "systemctl start etcd"
sleep 10; ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
```

**Oczekiwane:** odczyt przechodzi, klaster nie rozpada się; po `start` kworum (≥2/3) wraca.

**Cleanup:** krok 3 obowiązkowy — bez kworum klaster zostanie w trybie failsafe.

---

## 08 — replica-restart

**Cel:** restart Patroni na replice; lider bez zmiany (zmiana dopuszczalna), replika wraca → znów 3 członków.

```bash
# 1. Wybierz replikę (pierwszą nie-lidera):
R=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role!="leader").name' | head -1)
echo "restart repliki: $R"

# 2. Restart Patroni na replice:
ssh root@${R}.lab.test "systemctl restart patroni"

# 3. Poczekaj (~30s) i potwierdź 3 członków:
sleep 15; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```

**Oczekiwane:** replika dołącza w ~10–15s, klaster wraca do 3 członków, lider zwykle bez zmiany.

---

## 09 — pg-rewind-old-primary ⚠️

**Cel:** po failoverze przywrócić **stary** primary; Patroni uruchamia `pg_rewind`, by uzgodnić rozbieżną oś czasu, i węzeł dołącza jako replika.

```bash
# 1. Lider, potem zabij na nim PostgreSQL (wymusza failover):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "pkill -9 postgres" || true
sleep 30   # czekaj na nowego lidera

# 2. Przywróć starego primary — Patroni zrobi pg_rewind i dołączy go jako replikę:
ssh root@${L}.lab.test "systemctl restart patroni"
sleep 30

# 3. Sprawdź rolę starego primary (powinna być replica / sync_standby):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
curl -s http://pg1.lab.test:8008/cluster | jq -r ".members[]|select(.name==\"$L\")|.role"

# (opcjonalnie) dowód pg_rewind w logu Patroni:
ssh root@${L}.lab.test "journalctl -u patroni --no-pager | grep -i rewind | tail -5"
```

**Oczekiwane:** `$L` wraca jako `replica`/`sync_standby` (a nie osobny lider — `pg_rewind` się powiódł).

---

## 10 — sync-vs-async

**Cel:** pokazać trade-off trwałość ↔ dostępność zapisu przez przełączenie `synchronous_mode`.

```bash
# 1. Lider + bieżący tryb:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml show-config | grep -E 'synchronous_mode'"

# 2. Przełącz na async, sprawdź zapis, wróć na sync:
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml edit-config --apply '{\"synchronous_mode\": false}' --force"
sleep 3
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('async-mode') RETURNING id"
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml edit-config --apply '{\"synchronous_mode\": true}' --force"
```

**Oczekiwane:** w trybie async zapis nigdy nie blokuje (ale może gubić dane przy crashu); w sync zapis czeka na sync standby (trwałość). Na koniec **wracamy do `true`** — to domyślny, bezpieczny tryb labu.

**Cleanup:** krok przywrócenia `synchronous_mode: true` (w skrypcie jest na końcu).

---

## 11 — multi-host-libpq

**Cel:** połączenie **z pominięciem HAProxy** — sam libpq z `target_session_attrs=read-write` znajduje zapisywalny węzeł (fallback gdy `lb` padnie).

```bash
PGPASSWORD=lab psql \
  "host=pg1.lab.test,pg2.lab.test,pg3.lab.test port=5432 dbname=labdb user=lab password=lab target_session_attrs=read-write" \
  -At -c "SELECT inet_server_addr()"
```

**Oczekiwane:** zwraca IP **aktualnego lidera** (libpq pomija repliki i trafia do węzła read-write), bez `FATAL`.

---

## 12 — cascading-failure ⚠️

**Cel:** dwie awarie pod rząd — zabij lidera, potem od razu nowego lidera; klaster wybiera trzeciego i nie zacina się.

```bash
# 1. Pierwszy lider — zabij:
P1=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${P1}.lab.test "pkill -9 postgres" || true
sleep 30

# 2. Drugi lider — zabij:
P2=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
echo "drugi lider=$P2 (po pierwszym failoverze)"
ssh root@${P2}.lab.test "pkill -9 postgres" || true
sleep 30

# 3. Trzeci węzeł powinien być liderem; przywróć dwa zabite:
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
ssh root@${P1}.lab.test "systemctl restart patroni" || true
ssh root@${P2}.lab.test "systemctl restart patroni" || true
sleep 30; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```

**Oczekiwane:** po dwóch failoverach liderem jest trzeci, ocalały węzeł; po restarcie klaster wraca do 3 członków.

**Cleanup:** krok 3 (restart Patroni na obu zabitych) — przywraca pełny skład.

---

## 13 — app-failover-continuous ⚠️

**Cel:** failover **z perspektywy aplikacji** — `pgha-client` generuje ciągły ruch w czasie
zabicia lidera; JSON przebiegu rejestruje okno niedostępności (downtime, reconnecty).

> ℹ️ Wymaga `pgha-client` na `cli` (Python 3.11 — patrz [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md) §13).
> Przebieg referencyjny (2026-05-31): writer 580 inserts, 1 outage, **downtime ~2 s**, lider `pg3→pg1`,
> reader `max_id 894→1488`. Automatyczny odpowiednik to `scenarios/13-app-failover-continuous.sh`.

```bash
# 0. Bazowe id (by ograniczyć test multi-host do bieżącego przebiegu):
BASE=$(PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT COALESCE(MAX(id),0) FROM pgha_writer_log")
mkdir -p /tmp/app
pgha-client monitor --snapshot > /tmp/app/cluster-before.json

# 1. Start ciągłego obciążenia w tle (60s), z zapisem metryk HA do JSON:
export PGPASSWORD=lab
pgha-client writer --rate 10 --target haproxy --duration 60 --report /tmp/app/writer.json &
pgha-client reader --rate 10 --target direct  --duration 60 --report /tmp/app/reader.json &
sleep 8

# 2. Zabij lidera w trakcie (samo pkill nie wywoła failoveru — stop Patroni zwalnia lease):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "pkill -9 postgres; systemctl stop patroni" || true

# 3. Poczekaj aż obciążenie się skończy, potem obejrzyj metryki:
wait
pgha-client monitor --snapshot > /tmp/app/cluster-after.json
jq '{inserts,outages,reconnects,downtime_max_sec}' /tmp/app/writer.json
jq '{selects,max_id_start,max_id_end}'             /tmp/app/reader.json
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At \
  -c "SELECT count(DISTINCT host) FROM pgha_writer_log WHERE id > $BASE"

# 4. Przywróć starego lidera (rejoin przez pg_rewind):
ssh root@${L}.lab.test "systemctl start patroni" || true
```

**Oczekiwane:** writer `outages >= 1`, a mimo to dalej wstawia; `downtime_max_sec` w budżecie (≤ 45s);
reader `max_id_end > max_id_start`; liczba różnych hostów od `$BASE` ≥ 2 (HAProxy przełączył primary).

**Cleanup:** krok 4 (restart Patroni na starym liderze) — dołącza jako replika.

---

## 🔁 Suita (wszystkie naraz)

Automat: `lab.ps1 scenario all` → `scenarios/run-all.sh` (na cli) uruchamia `01`→`13` i podsumowuje
`PASSED/FAILED`. Ręcznie odpowiednik:
```bash
for s in /usr/local/lib/postgres18-ha-lab/scenarios/[0-9][0-9]-*.sh; do echo "== $s =="; bash "$s"; echo; done
```
Logi pojedynczych przebiegów: `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log` na `cli`.

> ⚠️ Suita wykonuje też scenariusze destrukcyjne (02/05/09/12) — uruchamiaj na świeżym, zdrowym
> klastrze i sprawdź `patronictl list` po zakończeniu.

---

## 🔗 Powiązane

- [SCENARIOS_PL.md](SCENARIOS_PL.md) — opis każdego scenariusza + oczekiwany output automatu
- [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md) — ręczna budowa labu (w tym tabela demo, sekcja 12)
- [TROUBLESHOOTING_PL.md](TROUBLESHOOTING_PL.md) — pułapki (watchdog, NRPT, scancode)
- `scenarios/` — kod źródłowy skryptów + `lib/assertions.sh`
