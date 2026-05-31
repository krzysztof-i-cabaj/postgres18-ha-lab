# 🧪 Failure scenarios — manual step-by-step reproduction

[![Count](https://img.shields.io/badge/Scenarios-13-darkgreen)]()
[![Mode](https://img.shields.io/badge/Mode-manual_no_lab.ps1-blue)]()
[![Stack](https://img.shields.io/badge/Patroni%2Betcd%2BHAProxy-darkgreen)]()
[![Warning](https://img.shields.io/badge/Some-DESTRUCTIVE-red)]()

> 🎯 How to **manually** reproduce what the `scenarios/NN-*.sh` scripts do — command by command,
> without `lab.ps1 scenario`. Each scenario: goal, steps, expected result, cleanup.
> Polish version: [MANUAL_SCENARIOS_PL.md](MANUAL_SCENARIOS_PL.md). Automation description + expected
> output: [SCENARIOS.md](SCENARIOS.md). Building the lab by hand: [MANUAL_INSTALL.md](MANUAL_INSTALL.md).

---

## 🧩 Before you start

- **Where to run:** all commands from the **`cli`** VM (as root), unless a step says "host" — then
  from the Windows host (PowerShell + `VBoxManage`). `cli` has passwordless SSH to `pg1/pg2/pg3/lb`.
- **Requirements:** a running cluster (`patronictl list` → 1 Leader + 2 replicas, etcd 3/3) and the
  demo table `pgha_writer_log` in database `labdb` (created by `build`/`orchestrate.sh` phase 6;
  manually — section 12 of [MANUAL_INSTALL.md](MANUAL_INSTALL.md)).
- **DNS:** we use names `pg1.lab.test`, `lb.lab.test`, etc. (resolved by infra's Unbound).
- **⚠️ DESTRUCTIVE** scenarios (02, 03, 05, 09, 12, 13) deliberately kill processes/VMs or cut the
  network — the cluster self-heals, but run them knowingly. Each has a cleanup step.
- Scenario **13** additionally needs the **`pgha-client`** test client on `cli` (installed into
  **Python 3.11** — Rocky 9.8's default 3.9 is too old; see [MANUAL_INSTALL.md](MANUAL_INSTALL.md) §13).

### 🧰 Helper commands (toolbox)

```bash
# Cluster state (who is leader, roles, lag):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# Just the leader's name (handy for scripting):
curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[] | select(.role=="leader") | .name'

# Write via HAProxy primary (:5000) — reaches the leader only:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At \
  -c "INSERT INTO pgha_writer_log (payload) VALUES ('test-'||clock_timestamp()) RETURNING id"

# Read (row count):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# etcd health (on a given node):
ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
```

> 💡 In the scripts the `leader` is the short name (`pg1`), while SSH targets the FQDN
> (`pg1.lab.test`). Below we store it in a variable `L` so the steps stay copy-pasteable.

---

## 🔗 Mapping: scenario ↔ script

| # | Scenario | Script | Type |
|---|---|---|---|
| 01 | baseline (sanity) | `scenarios/01-baseline.sh` | safe |
| 02 | kill-primary-hard | `scenarios/02-kill-primary-hard.sh` | ⚠️ destructive |
| 03 | poweroff-primary-vm | `scenarios/03-poweroff-primary-vm.sh` | ⚠️ host action |
| 04 | graceful-switchover | `scenarios/04-graceful-switchover.sh` | safe |
| 05 | network-partition | `scenarios/05-network-partition.sh` | ⚠️ destructive |
| 06 | etcd-single-loss | `scenarios/06-etcd-single-loss.sh` | safe |
| 07 | etcd-quorum-loss | `scenarios/07-etcd-quorum-loss.sh` | safe |
| 08 | replica-restart | `scenarios/08-replica-restart.sh` | safe |
| 09 | pg-rewind-old-primary | `scenarios/09-pg-rewind-old-primary.sh` | ⚠️ destructive |
| 10 | sync-vs-async | `scenarios/10-sync-vs-async.sh` | changes DCS |
| 11 | multi-host-libpq | `scenarios/11-multi-host-libpq.sh` | safe |
| 12 | cascading-failure | `scenarios/12-cascading-failure.sh` | ⚠️ destructive |
| 13 | app-failover-continuous | `scenarios/13-app-failover-continuous.sh` | ⚠️ destructive |

---

## 01 — baseline (sanity)

**Goal:** confirm the cluster is healthy before running failure tests.

```bash
# 1. A leader exists, etcd has quorum (>=2/3), 3 members are visible:
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
ssh root@pg2 "etcdctl --endpoints=http://localhost:2379 endpoint health"
ssh root@pg3 "etcdctl --endpoints=http://localhost:2379 endpoint health"

# 2. Write and read via HAProxy:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('baseline') RETURNING id"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"
```

**Expected:** 1 `Leader` + 2 replicas (`streaming`, lag 0), 3× `is healthy`, the write returns an `id`, the read returns a row count.

---

## 02 — kill-primary-hard ⚠️

**Goal:** hard failover (`pkill -9 postgres` on the leader) + proof of **zero data loss** (sentinel committed under `synchronous_mode`).

```bash
# 1. Remember the leader and commit a sentinel row BEFORE the failure:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
SID=$(PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('sentinel') RETURNING id")
echo "leader=$L sentinel_id=$SID"

# 2. Kill PostgreSQL on the leader:
ssh root@${L}.lab.test "pkill -9 postgres" || true

# 3. Wait (<=60s) and confirm the NEW leader:
sleep 30; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# 4. Read/write works again (HAProxy re-routed to the new leader):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# 5. ZERO-DATA-LOSS proof — the sentinel survived:
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT 1 FROM pgha_writer_log WHERE id = $SID"
```

**Expected:** the leader changed (`$L` → another node) within ~30s, step 5 returns `1` (sentinel survived → zero data loss). Patroni brings the killed node back as a replica.

**Cleanup:** none — Patroni restarts PostgreSQL on the old leader automatically (rejoins as a replica; see scenario 09 for `pg_rewind`).

---

## 03 — poweroff-primary-vm ⚠️ (host action)

**Goal:** hard loss of the leader VM (not just the process). `cli` cannot power off a VM — the **host** does.

```bash
# 1. On cli — who is the leader:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
echo "leader=$L"
```
```powershell
# 2. On the HOST (PowerShell) — power off the leader VM (substitute the name, e.g. pg1):
VBoxManage controlvm pg1 poweroff
```
```bash
# 3. On cli — wait (<=90s) for failover:
sleep 40; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```
```powershell
# 4. On the HOST — start the powered-off VM back up:
VBoxManage startvm pg1 --type headless
```

**Expected:** after the VM is powered off, the leader changes within <=90s; after `startvm` the node rejoins as a replica.

**Cleanup:** step 4 (start the VM) — otherwise the cluster stays at 2 nodes.

---

## 04 — graceful-switchover

**Goal:** a planned, controlled leadership change (`patronictl switchover`) — no data loss, no client errors.

```bash
# 1. Leader + candidate (first replica):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
C=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role!="leader").name' | head -1)
echo "switchover $L -> $C"

# 2. Perform the switchover (from the leader node):
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml switchover --master $L --candidate $C --force"

# 3. Confirm the new leader + writes work:
sleep 10; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('after-switchover') RETURNING id"
```

**Expected:** `$C` becomes leader, the old leader rejoins as a replica, writes keep working.

---

## 05 — network-partition ⚠️

**Goal:** cut the leader off the lab network (`iptables DROP`); watchdog + etcd lease expiry force failover.

```bash
# 1. Leader:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')

# 2. Partition — drop traffic to/from the lab subnet on the leader:
ssh root@${L}.lab.test "iptables -I INPUT -s 192.168.56.0/24 -j DROP; iptables -I OUTPUT -d 192.168.56.0/24 -j DROP"

# 3. Wait (<=60s) for failover (query a node other than $L):
sleep 40; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"

# 4. CLEANUP — heal the partition (flush iptables on the cut-off node):
ssh root@${L}.lab.test "iptables -F INPUT; iptables -F OUTPUT"
```

**Expected:** the leader changes within <=60s; after the flush the old leader rejoins and catches up.

**Cleanup:** step 4 is **mandatory** — without it the node stays isolated.

---

## 06 — etcd-single-loss

**Goal:** lose etcd on one node; quorum (2/3) holds → the cluster keeps working normally.

```bash
# 1. Stop etcd on pg3:
ssh root@pg3.lab.test "systemctl stop etcd"
sleep 5

# 2. Leader still present, writes work (2/3 quorum is enough):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('etcd-1-loss') RETURNING id"

# 3. CLEANUP — restore etcd:
ssh root@pg3.lab.test "systemctl start etcd"
```

**Expected:** no leader change, the write succeeds. After `start` etcd returns to 3/3.

---

## 07 — etcd-quorum-loss

**Goal:** lose etcd quorum (stop on 2 nodes) → Patroni enters DCS failsafe (reads work, writes may stall).

```bash
# 1. Stop etcd on pg2 and pg3 (leaves 1/3 = no quorum):
ssh root@pg2.lab.test "systemctl stop etcd"
ssh root@pg3.lab.test "systemctl stop etcd"
sleep 10

# 2. Reads still work (writes may stall — depends on failsafe):
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT count(*) FROM pgha_writer_log"

# 3. CLEANUP — restore quorum:
ssh root@pg2.lab.test "systemctl start etcd"
ssh root@pg3.lab.test "systemctl start etcd"
sleep 10; ssh root@pg1 "etcdctl --endpoints=http://localhost:2379 endpoint health"
```

**Expected:** the read succeeds, the cluster does not fall apart; after `start` quorum (>=2/3) returns.

**Cleanup:** step 3 mandatory — without quorum the cluster stays in failsafe.

---

## 08 — replica-restart

**Goal:** restart Patroni on a replica; leader unchanged (a change is acceptable), the replica rejoins → 3 members again.

```bash
# 1. Pick a replica (first non-leader):
R=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role!="leader").name' | head -1)
echo "restarting replica: $R"

# 2. Restart Patroni on the replica:
ssh root@${R}.lab.test "systemctl restart patroni"

# 3. Wait (~30s) and confirm 3 members:
sleep 15; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```

**Expected:** the replica rejoins in ~10–15s, the cluster returns to 3 members, the leader usually unchanged.

---

## 09 — pg-rewind-old-primary ⚠️

**Goal:** after failover, bring back the **old** primary; Patroni runs `pg_rewind` to reconcile the diverged timeline and the node rejoins as a replica.

```bash
# 1. Leader, then kill PostgreSQL on it (forces failover):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "pkill -9 postgres" || true
sleep 30   # wait for the new leader

# 2. Bring back the old primary — Patroni runs pg_rewind and rejoins it as a replica:
ssh root@${L}.lab.test "systemctl restart patroni"
sleep 30

# 3. Check the old primary's role (should be replica / sync_standby):
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
curl -s http://pg1.lab.test:8008/cluster | jq -r ".members[]|select(.name==\"$L\")|.role"

# (optional) pg_rewind proof in the Patroni log:
ssh root@${L}.lab.test "journalctl -u patroni --no-pager | grep -i rewind | tail -5"
```

**Expected:** `$L` rejoins as `replica`/`sync_standby` (not a separate leader — `pg_rewind` succeeded).

---

## 10 — sync-vs-async

**Goal:** show the durability ↔ write-availability trade-off by toggling `synchronous_mode`.

```bash
# 1. Leader + current mode:
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml show-config | grep -E 'synchronous_mode'"

# 2. Switch to async, check the write, switch back to sync:
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml edit-config --apply '{\"synchronous_mode\": false}' --force"
sleep 3
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "INSERT INTO pgha_writer_log (payload) VALUES ('async-mode') RETURNING id"
ssh root@${L}.lab.test "patronictl -c /etc/patroni/patroni.yml edit-config --apply '{\"synchronous_mode\": true}' --force"
```

**Expected:** in async mode writes never block (but may lose data on crash); in sync mode writes wait for the sync standby (durability). We **return to `true`** at the end — the lab's default, safe mode.

**Cleanup:** restoring `synchronous_mode: true` (the script does this last).

---

## 11 — multi-host-libpq

**Goal:** connect **bypassing HAProxy** — libpq itself, with `target_session_attrs=read-write`, finds the writeable node (fallback when `lb` is down).

```bash
PGPASSWORD=lab psql \
  "host=pg1.lab.test,pg2.lab.test,pg3.lab.test port=5432 dbname=labdb user=lab password=lab target_session_attrs=read-write" \
  -At -c "SELECT inet_server_addr()"
```

**Expected:** returns the **current leader's** IP (libpq skips replicas and lands on the read-write node), no `FATAL`.

---

## 12 — cascading-failure ⚠️

**Goal:** two failures in a row — kill the leader, then immediately the new leader; the cluster elects a third and does not get stuck.

```bash
# 1. First leader — kill it:
P1=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${P1}.lab.test "pkill -9 postgres" || true
sleep 30

# 2. Second leader — kill it:
P2=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
echo "second leader=$P2 (after the first failover)"
ssh root@${P2}.lab.test "pkill -9 postgres" || true
sleep 30

# 3. The third node should be leader; bring back the two killed ones:
ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
ssh root@${P1}.lab.test "systemctl restart patroni" || true
ssh root@${P2}.lab.test "systemctl restart patroni" || true
sleep 30; ssh root@pg1 "patronictl -c /etc/patroni/patroni.yml list"
```

**Expected:** after two failovers the surviving third node is leader; after restart the cluster returns to 3 members.

**Cleanup:** step 3 (restart Patroni on both killed nodes) — restores the full set.

---

## 13 — app-failover-continuous ⚠️

**Goal:** failover **from the application's point of view** — `pgha-client` drives continuous load
while the leader is killed; the run JSON captures the availability gap (downtime, reconnects).

> ℹ️ Requires `pgha-client` on `cli` (Python 3.11 — see [MANUAL_INSTALL.md](MANUAL_INSTALL.md) §13).
> Reference run (2026-05-31): writer 580 inserts, 1 outage, **downtime ~2 s**, leader `pg3→pg1`,
> reader `max_id 894→1488`. The automated equivalent is `scenarios/13-app-failover-continuous.sh`.

```bash
# 0. Baseline id (to scope the multi-host check to this run):
BASE=$(PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At -c "SELECT COALESCE(MAX(id),0) FROM pgha_writer_log")
mkdir -p /tmp/app
pgha-client monitor --snapshot > /tmp/app/cluster-before.json

# 1. Start continuous load in the background (60s), recording HA metrics to JSON:
export PGPASSWORD=lab
pgha-client writer --rate 10 --target haproxy --duration 60 --report /tmp/app/writer.json &
pgha-client reader --rate 10 --target direct  --duration 60 --report /tmp/app/reader.json &
sleep 8

# 2. Kill the leader mid-run (pkill alone won't fail over — stop Patroni to release the lease):
L=$(curl -s http://pg1.lab.test:8008/cluster | jq -r '.members[]|select(.role=="leader").name')
ssh root@${L}.lab.test "pkill -9 postgres; systemctl stop patroni" || true

# 3. Wait for the load to finish, then inspect the metrics:
wait
pgha-client monitor --snapshot > /tmp/app/cluster-after.json
jq '{inserts,outages,reconnects,downtime_max_sec}' /tmp/app/writer.json
jq '{selects,max_id_start,max_id_end}'             /tmp/app/reader.json
PGPASSWORD=lab psql -h lb.lab.test -p 5000 -U lab -d labdb -At \
  -c "SELECT count(DISTINCT host) FROM pgha_writer_log WHERE id > $BASE"

# 4. Bring the old leader back (pg_rewind rejoin):
ssh root@${L}.lab.test "systemctl start patroni" || true
```

**Expected:** writer `outages >= 1` yet keeps inserting; `downtime_max_sec` within budget (≤ 45s);
reader `max_id_end > max_id_start`; distinct hosts since `$BASE` is ≥ 2 (HAProxy moved the primary).

**Cleanup:** step 4 (restart Patroni on the old leader) — rejoins as a replica.

---

## 🔁 Suite (all at once)

Automation: `lab.ps1 scenario all` → `scenarios/run-all.sh` (on cli) runs `01`→`13` and prints a
`PASSED/FAILED` summary. The manual equivalent:
```bash
for s in /usr/local/lib/postgres18-ha-lab/scenarios/[0-9][0-9]-*.sh; do echo "== $s =="; bash "$s"; echo; done
```
Per-run logs: `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log` on `cli`.

> ⚠️ The suite also runs the destructive scenarios (02/05/09/12) — run it on a fresh, healthy
> cluster and check `patronictl list` afterwards.

---

## 🔗 Related

- [SCENARIOS.md](SCENARIOS.md) — per-scenario description + expected automation output
- [MANUAL_INSTALL.md](MANUAL_INSTALL.md) — manual lab build (incl. the demo table, section 12)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — gotchas (watchdog, NRPT, scancode)
- `scenarios/` — script source + `lib/assertions.sh`
