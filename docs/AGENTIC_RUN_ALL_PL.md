# 🤖 PostgreSQL 18 HA Lab — Agentowy przebieg pełnej suity (`scenario all`)

[![Result](https://img.shields.io/badge/Scenarios-13%2F13_PASS-success)]()
[![Date](https://img.shields.io/badge/Date-2026--05--31-blue)]()
[![Run](https://img.shields.io/badge/Run-agentic-blueviolet)]()
[![Stack](https://img.shields.io/badge/Stack-Patroni%2Betcd%2BHAProxy-darkgreen)]()
[![Client](https://img.shields.io/badge/Driver-pgha--client-blueviolet)]()
[![Page](https://img.shields.io/badge/Page-agentic--run--all.html-orange)]()

> 🎯 Automatycznie wygenerowany raport przebiegu scenariuszy awarii HA: tabela wynikow, pelny transcript komend/outputow per scenariusz oraz **metryki failoveru z perspektywy aplikacji** (downtime, reconnecty) zebrane przez `pgha-client`.
> Strona interaktywna (GitHub Pages): [`agentic-run-all_PL.html`](agentic-run-all_PL.html). Wersja EN: [AGENTIC_RUN_ALL.md](AGENTIC_RUN_ALL.md).
> 🤖 **Wykonane agentowo** na żywym klastrze: agent przeprowadził pełną suitę (`scenarios/run-all.sh`, 01–13) przez SSH (klucz) na `cli`, a akcję hosta dla scenariusza 03 (`VBoxManage poweroff`/`startvm`) wykonał z hosta. Klaster **nie był resetowany między scenariuszami** — samodzielnie się odbudowywał.

## 📊 Wyniki

| # | Scenariusz | Wynik | Kluczowa obserwacja |
|---|---|---|---|
| 01 | `baseline` | ✅ PASS | leader is pg3 |
| 02 | `kill-primary-hard` | ✅ PASS | leader changed: pg3 -> pg1 |
| 03 | `poweroff-primary-vm` | ✅ PASS | leader changed: pg1 -> pg2 |
| 04 | `graceful-switchover` | ✅ PASS | leader changed: pg2 -> pg3 |
| 05 | `network-partition` | ✅ PASS | leader changed: pg3 -> pg2 |
| 06 | `etcd-single-loss` | ✅ PASS | leader is pg2 |
| 07 | `etcd-quorum-loss` | ✅ PASS | read through HAProxy ok (rows=1178) |
| 08 | `replica-restart` | ✅ PASS | leader is pg2 |
| 09 | `pg-rewind-old-primary` | ✅ PASS | old primary pg2 rejoined as replica (pg_rewind likely succeeded) |
| 10 | `sync-vs-async` | ✅ PASS | write through HAProxy ok (id=1788) |
| 11 | `multi-host-libpq` | ✅ PASS | multi-host libpq routed to: 192.168.56.12 |
| 12 | `cascading-failure` | ✅ PASS | leader changed: pg3 -> pg1 |
| 13 | `app-failover-continuous` | ✅ PASS | leader changed: pg2 -> pg3 |

## 🐍 Failover sterowany aplikacja (scenariusz 13)

**Leader:** `pg2` → `pg3`

| Metryka | Wartosc |
|---|---|
| writer inserts | 500 |
| outages | 1 |
| reconnects | 3 |
| **max downtime (s)** | **10.08** |
| total downtime (s) | 10.08 |
| writer actual Hz | 8.33 |
| reader selects | 580 |
| reader max_id | 1821 → 2337 |

## 📜 Transcripty (komenda + output)

### ✅ 01 — `baseline`

```text
PASS leader is pg3
PASS etcd quorum healthy (3/3 nodes)
PASS 3 members visible
PASS write through HAProxy ok (id=1656)
PASS read through HAProxy ok (rows=1172)
```

### ✅ 02 — `kill-primary-hard`

```text
INFO previous leader: pg3, sentinel id=1657
INFO waiting up to 60s for new leader
PASS leader changed: pg3 -> pg1
PASS read through HAProxy ok (rows=1174)
PASS write through HAProxy ok (id=1690)
PASS committed row 1657 survived failover (no data loss)
```

### ✅ 03 — `poweroff-primary-vm`

```text
INFO previous leader: pg1 (host should poweroff its VM)
INFO from host: VBoxManage controlvm pg1 poweroff
PASS leader changed: pg1 -> pg2
INFO host should now: VBoxManage startvm pg1 --type headless
```

### ✅ 04 — `graceful-switchover`

```text
INFO switchover pg2 -> pg3
Current cluster topology
+ Cluster: pg-ha-lab (7645648652996586224) ---------+----+-------------+-----+------------+-----+
| Member | Host          | Role         | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------+---------------+--------------+-----------+----+-------------+-----+------------+-----+
| pg1    | 192.168.56.11 | Replica      | stopped   |    |     unknown |     |    unknown |     |
| pg2    | 192.168.56.12 | Leader       | running   | 31 |             |     |            |     |
| pg3    | 192.168.56.13 | Sync Standby | streaming | 31 |   0/D029FD0 |   0 |  0/D029FD0 |   0 |
+--------+---------------+--------------+-----------+----+-------------+-----+------------+-----+
2026-05-31 13:38:08.95125 Successfully switched over to "pg3"
+ Cluster: pg-ha-lab (7645648652996586224) ---+----+-------------+-----+------------+-----+
| Member | Host          | Role    | State    | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------+---------------+---------+----------+----+-------------+-----+------------+-----+
| pg1    | 192.168.56.11 | Replica | starting |    |     unknown |     |    unknown |     |
| pg2    | 192.168.56.12 | Replica | stopped  |    |     unknown |     |    unknown |     |
| pg3    | 192.168.56.13 | Leader  | running  | 31 |             |     |            |     |
+--------+---------------+---------+----------+----+-------------+-----+------------+-----+
PASS leader changed: pg2 -> pg3
PASS write through HAProxy ok (id=1723)
```

### ✅ 05 — `network-partition`

```text
INFO partitioning pg3 (self-healing after ~75s)
PASS leader changed: pg3 -> pg2
INFO partition self-heals in ~75s; old leader rejoins as replica
```

### ✅ 06 — `etcd-single-loss`

```text
PASS leader is pg2
PASS write through HAProxy ok (id=1755)
```

### ✅ 07 — `etcd-quorum-loss`

```text
PASS read through HAProxy ok (rows=1178)
PASS etcd quorum healthy (3/3 nodes)
```

### ✅ 08 — `replica-restart`

```text
PASS leader is pg2
PASS 3 members visible
PASS leader unchanged
```

### ✅ 09 — `pg-rewind-old-primary`

```text
PASS old primary pg2 rejoined as replica (pg_rewind likely succeeded)
```

### ✅ 10 — `sync-vs-async`

```text
INFO current synchronous_mode at pg2:
synchronous_mode: true
synchronous_mode_strict: false
INFO switching to async (synchronous_mode=false), then back
---
+++
@@ -16,7 +16,7 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-synchronous_mode: true
+synchronous_mode: false
 synchronous_mode_strict: false
 synchronous_node_count: 1
 ttl: 30
Configuration changed
PASS write through HAProxy ok (id=1788)
---
+++
@@ -16,7 +16,7 @@
   use_pg_rewind: true
   use_slots: true
 retry_timeout: 10
-synchronous_mode: false
+synchronous_mode: true
 synchronous_mode_strict: false
 synchronous_node_count: 1
 ttl: 30
Configuration changed
```

### ✅ 11 — `multi-host-libpq`

```text
PASS multi-host libpq routed to: 192.168.56.12
```

### ✅ 12 — `cascading-failure`

```text
PASS leader changed: pg3 -> pg1
PASS leader changed: pg1 -> pg2
PASS 3 members visible
```

### ✅ 13 — `app-failover-continuous`

```text
INFO previous leader: pg2, base id=1788, load 10Hz/60s
INFO writer pid=9958, reader pid=9959 -- rozbieg 8s przed awaria
[13:44:51] writer target=haproxy rate=10.0 Hz                       writer.py:55
[13:44:51] reader target=direct rate=10.0 Hz                        reader.py:50
[13:44:56]   50 inserts in 4.9s (10.2 actual Hz, 0 reconnects, 0.0s writer.py:81
           downtime)
[13:44:56]   50 selects in 4.9s max_id=1870 (0 reconnects, 0.0s     reader.py:71
           downtime)
INFO killing leader pg2 (pkill -9 postgres + systemctl stop patroni)
[13:45:00] writer reconnect after error: consuming input failed:    writer.py:94
           server closed the connection unexpectedly
                   This probably means the server terminated
           abnormally
                   before or while processing the request.
[13:45:00] reader reconnect after error: consuming input failed:    reader.py:84
           server closed the connection unexpectedly
                   This probably means the server terminated
           abnormally
                   before or while processing the request.
INFO waiting up to 60s for new leader
PASS leader changed: pg2 -> pg3
[13:45:03]   100 selects in 11.9s max_id=1903 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:04] writer reconnect after error: connection failed:         writer.py:94
           connection to server at "192.168.56.20", port 5000
           failed: server closed the connection unexpectedly
                   This probably means the server terminated
           abnormally
                   before or while processing the request.
[13:45:08] writer reconnect after error: connection failed:         writer.py:94
           connection to server at "192.168.56.20", port 5000
           failed: server closed the connection unexpectedly
                   This probably means the server terminated
           abnormally
                   before or while processing the request.
[13:45:08]   150 selects in 16.9s max_id=1903 (1 reconnects, 2.1s   reader.py:71
           downtime)
INFO waiting for background load to finish (writer/reader)
[13:45:11]   100 inserts in 20.0s (5.0 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:13]   200 selects in 21.9s max_id=1957 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:16]   150 inserts in 25.0s (6.0 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:18]   250 selects in 26.9s max_id=2007 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:21]   200 inserts in 30.0s (6.7 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:23]   300 selects in 31.9s max_id=2057 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:26]   250 inserts in 35.0s (7.2 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:28]   350 selects in 36.9s max_id=2107 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:31]   300 inserts in 40.0s (7.5 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:33]   400 selects in 41.9s max_id=2157 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:36]   350 inserts in 45.0s (7.8 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:38]   450 selects in 46.9s max_id=2207 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:41]   400 inserts in 50.0s (8.0 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:43]   500 selects in 51.9s max_id=2257 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:46]   450 inserts in 55.0s (8.2 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
[13:45:48]   550 selects in 57.0s max_id=2306 (1 reconnects, 2.1s   reader.py:71
           downtime)
[13:45:51]   500 inserts in 60.0s (8.3 actual Hz, 3 reconnects,     writer.py:81
           10.1s downtime)
           writer done inserts=500 outages=1 reconnects=3          writer.py:110
           downtime=10.1s
[13:45:51] reader done selects=580 max_id=2337 outages=1           reader.py:101
           reconnects=1 downtime=2.1s
PASS app kept writing across failover (inserts=500, outages=1)
PASS max downtime 10.08s within budget (<= 45s)
PASS reads progressed (max_id 1821 -> 2337)
PASS writes served by 2 distinct hosts since id=1788 (>= 2, primary moved)
PASS read through HAProxy ok (rows=1680)
PASS write through HAProxy ok (id=2338)
```

---

_Wygenerowano: 2026-05-31 13:50:01_
