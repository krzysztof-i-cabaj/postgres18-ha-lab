# 🧪 Scenarios

[![Count](https://img.shields.io/badge/Scenarios-12-darkgreen)]()
[![Runner](https://img.shields.io/badge/Runner-bash-orange)]()

> Twelve failure-mode scripts that exercise the lab. Run from the `cli` VM via
> `lab.ps1 scenario <NN | all>`. Polish counterpart: [README_PL.md](README_PL.md).

| #  | Script | What it does |
|----|--------|---|
| 01 | `01-baseline.sh` | Sanity: leader exists, etcd quorum, read+write through HAProxy |
| 02 | `02-kill-primary-hard.sh` | `pkill -9 postgres` on primary, expect failover |
| 03 | `03-poweroff-primary-vm.sh` | Host powers off primary VM; cluster heals |
| 04 | `04-graceful-switchover.sh` | `patronictl switchover`, planned leadership change |
| 05 | `05-network-partition.sh` | `iptables DROP` on primary, leader moves |
| 06 | `06-etcd-single-loss.sh` | Stop etcd on one node, cluster keeps running |
| 07 | `07-etcd-quorum-loss.sh` | Stop etcd on 2 nodes, cluster -> read-only failsafe |
| 08 | `08-replica-restart.sh` | `systemctl restart patroni` on a replica |
| 09 | `09-pg-rewind-old-primary.sh` | Old primary rejoins via `pg_rewind` |
| 10 | `10-sync-vs-async.sh` | Toggle `synchronous_mode`, observe behaviour |
| 11 | `11-multi-host-libpq.sh` | Direct multi-host string, no HAProxy |
| 12 | `12-cascading-failure.sh` | Kill primary, kill new primary, stabilise |

## Running

```bash
# From host:
.\lab.ps1 scenario 02
.\lab.ps1 scenario all

# From cli VM directly:
ssh root@cli.lab.test
/usr/local/lib/postgres18-ha-lab/scenarios/01-baseline.sh
/usr/local/lib/postgres18-ha-lab/scenarios/run-all.sh
```

Logs land in `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log`.
