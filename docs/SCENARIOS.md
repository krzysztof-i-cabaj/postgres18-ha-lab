# 🧪 Scenarios — expected output

[![Count](https://img.shields.io/badge/Scenarios-13-darkgreen)]()

> 🎯 What each scenario does and what passing output looks like.
> Polish: [SCENARIOS_PL.md](SCENARIOS_PL.md). See also [/scenarios](../scenarios/) for the actual scripts.

## Conventions

Each scenario is a bash script in `scenarios/NN-name.sh`. They use
`scenarios/lib/assertions.sh` for shared `assert_*` functions. Run individually
or as a suite:

```bash
.\lab.ps1 scenario 02
.\lab.ps1 scenario all      # invokes scenarios/run-all.sh on cli
```

Logs: `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log` on the cli VM.

## 01 — baseline

Sanity. After build, expect (`id`/`rows` values grow on every run —
`pgha_writer_log` accumulates rows):

```
PASS leader is pg1
PASS etcd quorum healthy (3/3 nodes)
PASS 3 members visible
PASS write through HAProxy ok (id=<N>)
PASS read through HAProxy ok (rows=<N>)
SCENARIO PASSED: 01-baseline
```

## 02 — kill-primary-hard

`pkill -9 postgres` on the leader. The scenario commits a sentinel row **before**
the kill, so `synchronous_mode` must preserve it. Patroni acquires the etcd leader
lock from a replica within ~30s. HAProxy notices at next health check.

Expected: `leader changed: pg1 -> pg2` (or another node), write+read pass, and
`committed row N survived failover (no data loss)` — proof of zero data loss.

## 03 — poweroff-primary-vm

Host-side action: `VBoxManage controlvm <pri> poweroff`. The cli scenario
detects the leader change after the host kills the VM. To complete the loop,
the host should bring the VM back: `VBoxManage startvm <pri> --type headless`.

## 04 — graceful-switchover

`patronictl switchover --master pg1 --candidate pg2 --force`. Planned, no data
loss, no client errors with `target_session_attrs=read-write`.

## 05 — network-partition

`iptables -I INPUT/OUTPUT -j DROP` for `192.168.56.0/24` on the leader. Watchdog
+ etcd lease expiry trigger failover. Cleanup: scenario flushes iptables on
the partitioned node when done.

## 06 — etcd-single-loss

Stop etcd on one node. Quorum (2/3) still holds; cluster keeps working.
Restart etcd at end.

## 07 — etcd-quorum-loss

Stop etcd on two nodes. Patroni enters DCS-failsafe; reads continue, writes
may pause until quorum returns. Scenario restarts etcd to restore quorum.

## 08 — replica-restart

`systemctl restart patroni` on a replica. Leader unchanged; replica rejoins
within ~10 seconds.

## 09 — pg-rewind-old-primary

After a primary kill, restart the old primary. Patroni runs `pg_rewind` to
reconcile divergent timeline and rejoins as replica.

## 10 — sync-vs-async

Toggle `synchronous_mode` via `patronictl edit-config`. Demonstrates
durability tradeoff: sync mode blocks writes if no sync standby; async never
blocks but can lose data on crash.

## 11 — multi-host-libpq

Bypass HAProxy. libpq with
`host=pg1.lab.test,pg2.lab.test,pg3.lab.test target_session_attrs=read-write`
finds the writeable node itself. Useful as fallback if `lb` is down.

## 12 — cascading-failure

Kill primary, then immediately kill the new primary. Cluster should still
elect a third leader. Demonstrates that Patroni doesn't get stuck.

## 13 — app-failover-continuous

App-perspective failover. `pgha-client` runs a **continuous** writer (via HAProxy)
and reader (via multi-host libpq) for `--duration 60s`; mid-run the leader is killed
(`pkill -9 postgres` + `systemctl stop patroni`, the technique from 02). Both clients
reconnect and the run JSON (`--report`) captures the **availability gap**.

Expected: `leader changed`, then from the writer/reader JSON metrics —
`app kept writing across failover (inserts=<N>, outages>=1)`,
`max downtime <S>s within budget (<= 45s)`, `reads progressed (max_id A -> B)`, and
`writes served by >=2 distinct hosts` (proof HAProxy moved the primary). Metrics land
in `/var/log/postgres18-ha-lab/scenarios/app/{writer,reader}.json` and feed
`lab.ps1 report` → `docs/run-report.html`.
