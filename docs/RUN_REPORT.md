# 🧪 PostgreSQL 18 HA Lab — Scenario Run Report

[![Result](https://img.shields.io/badge/Scenarios-12%2F12_PASS-success)]()
[![Date](https://img.shields.io/badge/Date-2026--05--31-blue)]()
[![Stack](https://img.shields.io/badge/Stack-Patroni%2Betcd%2BHAProxy-darkgreen)]()
[![Client](https://img.shields.io/badge/Driver-pgha--client-blueviolet)]()
[![Page](https://img.shields.io/badge/Page-run--report.html-orange)]()

> 🎯 Auto-generated report of the HA failure-scenario run: results table, full command/output transcript per scenario, and **app-perspective failover metrics** (downtime, reconnects) captured by `pgha-client`.
> Interactive page (GitHub Pages): [`run-report.html`](run-report.html). Polish: [RUN_REPORT_PL.md](RUN_REPORT_PL.md).

## 📊 Results

| # | Scenario | Result | Key observation |
|---|---|---|---|
| 01 | `baseline` | ✅ PASS | leader is pg2 |
| 02 | `kill-primary-hard` | ✅ PASS | leader changed: pg2 -> pg1 |
| 04 | `graceful-switchover` | ✅ PASS | leader changed: pg3 -> pg2 |
| 05 | `network-partition` | ✅ PASS | leader changed: pg1 -> pg3 |
| 06 | `etcd-single-loss` | ✅ PASS | leader is pg3 |
| 07 | `etcd-quorum-loss` | ✅ PASS | read through HAProxy ok (rows=18) |
| 08 | `replica-restart` | ✅ PASS | leader is pg3 |
| 09 | `pg-rewind-old-primary` | ✅ PASS | old primary pg3 rejoined as replica (pg_rewind likely succeeded) |
| 10 | `sync-vs-async` | ✅ PASS | write through HAProxy ok (id=174) |
| 11 | `multi-host-libpq` | ✅ PASS | multi-host libpq routed to: 192.168.56.13 |
| 12 | `cascading-failure` | ✅ PASS | leader changed: pg2 -> pg1 |
| 13 | `app-failover-continuous` | ✅ PASS | leader changed: pg3 -> pg1 |

## 🐍 App-driven failover (scenario 13)

**Leader:** `pg3` → `pg1`

| Metric | Value |
|---|---|
| writer inserts | 580 |
| outages | 1 |
| reconnects | 1 |
| **max downtime (s)** | **2.06** |
| total downtime (s) | 2.06 |
| writer actual Hz | 9.67 |
| reader selects | 580 |
| reader max_id | 894 → 1488 |

## 📜 Transcripts (command + output)

### ✅ 01 — `baseline`

```text
PASS leader is pg2
PASS etcd quorum healthy (3/3 nodes)
PASS 3 members visible
PASS write through HAProxy ok (id=306)
PASS read through HAProxy ok (rows=26)
```

### ✅ 02 — `kill-primary-hard`

```text
INFO previous leader: pg2, sentinel id=209
INFO waiting up to 60s for new leader
PASS leader changed: pg2 -> pg1
PASS read through HAProxy ok (rows=23)
PASS write through HAProxy ok (id=241)
PASS committed row 209 survived failover (no data loss)
```

### ✅ 04 — `graceful-switchover`

```text
INFO switchover pg3 -> pg2
Current cluster topology
+ Cluster: pg-ha-lab (7645648652996586224) ---------+----+-------------+-----+------------+-----+
| Member | Host          | Role         | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------+---------------+--------------+-----------+----+-------------+-----+------------+-----+
| pg1    | 192.168.56.11 | Replica      | streaming | 14 |   0/A000C60 |   0 |  0/A000C60 |   0 |
| pg2    | 192.168.56.12 | Sync Standby | streaming | 14 |   0/A000C60 |   0 |  0/A000C60 |   0 |
| pg3    | 192.168.56.13 | Leader       | running   | 14 |             |     |            |     |
+--------+---------------+--------------+-----------+----+-------------+-----+------------+-----+
2026-05-30 17:50:22.27049 Successfully switched over to "pg2"
+ Cluster: pg-ha-lab (7645648652996586224) --+----+-------------+-----+------------+-----+
| Member | Host          | Role    | State   | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------+---------------+---------+---------+----+-------------+-----+------------+-----+
| pg1    | 192.168.56.11 | Replica | running | 14 |   0/B0000A0 |   0 |  0/B0000A0 |   0 |
| pg2    | 192.168.56.12 | Leader  | running | 14 |             |     |            |     |
| pg3    | 192.168.56.13 | Replica | stopped |    |     unknown |     |    unknown |     |
+--------+---------------+---------+---------+----+-------------+-----+------------+-----+
PASS leader changed: pg3 -> pg2
PASS write through HAProxy ok (id=208)
```

### ✅ 05 — `network-partition`

```text
INFO partitioning pg1 (self-healing after ~75s)
PASS leader changed: pg1 -> pg3
INFO partition self-heals in ~75s; old leader rejoins as replica
```

### ✅ 06 — `etcd-single-loss`

```text
PASS leader is pg3
PASS write through HAProxy ok (id=173)
```

### ✅ 07 — `etcd-quorum-loss`

```text
PASS read through HAProxy ok (rows=18)
PASS etcd quorum healthy (3/3 nodes)
```

### ✅ 08 — `replica-restart`

```text
PASS leader is pg3
PASS 3 members visible
PASS leader unchanged
```

### ✅ 09 — `pg-rewind-old-primary`

```text
PASS old primary pg3 rejoined as replica (pg_rewind likely succeeded)
```

### ✅ 10 — `sync-vs-async`

```text
INFO current synchronous_mode at pg3:
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
PASS write through HAProxy ok (id=174)
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
PASS multi-host libpq routed to: 192.168.56.13
```

### ✅ 12 — `cascading-failure`

```text
PASS leader changed: pg2 -> pg1
PASS leader changed: pg1 -> pg3
PASS 3 members visible
```

### ✅ 13 — `app-failover-continuous`

```text
INFO previous leader: pg3, base id=893, load 10Hz/60s
INFO writer pid=3256, reader pid=3257 -- rozbieg 8s przed awaria
[11:16:47] reader target=direct rate=10.0 Hz                        reader.py:50
[11:16:47] writer target=haproxy rate=10.0 Hz                       writer.py:55
[11:16:52]   50 selects in 4.9s max_id=942 (0 reconnects, 0.0s      reader.py:71
           downtime)
[11:16:52]   50 inserts in 4.9s (10.2 actual Hz, 0 reconnects, 0.0s writer.py:81
           downtime)
INFO killing leader pg3 (pkill -9 postgres + systemctl stop patroni)
[11:16:55] writer reconnect after error: consuming input failed:    writer.py:94
           server closed the connection unexpectedly
                   This probably means the server terminated
           abnormally
                   before or while processing the request.
[11:16:55] reader reconnect after error: terminating connection due reader.py:84
           to unexpected postmaster exit
INFO waiting up to 60s for new leader
PASS leader changed: pg3 -> pg1
[11:16:59]   100 selects in 11.9s max_id=1007 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:16:59]   100 inserts in 11.9s (8.4 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:04]   150 selects in 16.9s max_id=1057 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:04]   150 inserts in 16.9s (8.9 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
INFO waiting for background load to finish (writer/reader)
[11:17:09]   200 selects in 21.9s max_id=1108 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:09]   200 inserts in 21.9s (9.1 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:14]   250 selects in 26.9s max_id=1158 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:14]   250 inserts in 26.9s (9.3 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:19]   300 selects in 31.9s max_id=1208 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:19]   300 inserts in 31.9s (9.4 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:24]   350 selects in 36.9s max_id=1258 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:24]   350 inserts in 36.9s (9.5 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:29]   400 selects in 41.9s max_id=1308 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:29]   400 inserts in 41.9s (9.5 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:34]   450 selects in 46.9s max_id=1358 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:34]   450 inserts in 46.9s (9.6 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:39]   500 selects in 51.9s max_id=1408 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:39]   500 inserts in 51.9s (9.6 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:44]   550 selects in 56.9s max_id=1458 (1 reconnects, 2.1s   reader.py:71
           downtime)
[11:17:44]   550 inserts in 56.9s (9.7 actual Hz, 1 reconnects,     writer.py:81
           2.1s downtime)
[11:17:47] reader done selects=580 max_id=1488 outages=1           reader.py:101
           reconnects=1 downtime=2.1s
[11:17:47] writer done inserts=580 outages=1 reconnects=1          writer.py:110
           downtime=2.1s
PASS app kept writing across failover (inserts=580, outages=1)
PASS max downtime 2.06s within budget (<= 45s)
PASS reads progressed (max_id 894 -> 1488)
PASS writes served by 2 distinct hosts since id=893 (>= 2, primary moved)
PASS read through HAProxy ok (rows=1162)
PASS write through HAProxy ok (id=1490)
```

---

_Generated: 2026-05-31 11:18:26_
