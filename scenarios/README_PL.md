# 🧪 Scenariusze

[![Count](https://img.shields.io/badge/Scenariuszy-12-darkgreen)]()
[![Runner](https://img.shields.io/badge/Runner-bash-orange)]()

> Dwanaście skryptów scenariuszy awarii dla labu. Uruchamiane z VMki `cli`
> przez `lab.ps1 scenario <NN | all>`. Wersja angielska: [README.md](README.md).

| #  | Skrypt | Co robi |
|----|--------|---|
| 01 | `01-baseline.sh` | Sanity: leader istnieje, kworum etcd, read+write przez HAProxy |
| 02 | `02-kill-primary-hard.sh` | `pkill -9 postgres` na primary, oczekiwany failover |
| 03 | `03-poweroff-primary-vm.sh` | Host wyłącza VMkę primary; klaster się leczy |
| 04 | `04-graceful-switchover.sh` | `patronictl switchover`, planowana zmiana lidera |
| 05 | `05-network-partition.sh` | `iptables DROP` na primary, lider się przesuwa |
| 06 | `06-etcd-single-loss.sh` | Stop etcd na jednym węźle, klaster działa |
| 07 | `07-etcd-quorum-loss.sh` | Stop etcd na 2 węzłach, klaster -> read-only failsafe |
| 08 | `08-replica-restart.sh` | `systemctl restart patroni` na replice |
| 09 | `09-pg-rewind-old-primary.sh` | Stary primary wraca przez `pg_rewind` |
| 10 | `10-sync-vs-async.sh` | Toggle `synchronous_mode`, obserwacja zachowania |
| 11 | `11-multi-host-libpq.sh` | Bezpośredni multi-host connection string, bez HAProxy |
| 12 | `12-cascading-failure.sh` | Zabij primary, zabij nowy primary, stabilizacja |

## Uruchamianie

```bash
# Z hosta:
.\lab.ps1 scenario 02
.\lab.ps1 scenario all

# Z VMki cli bezpośrednio:
ssh root@cli.lab.test
/usr/local/lib/postgres18-ha-lab/scenarios/01-baseline.sh
/usr/local/lib/postgres18-ha-lab/scenarios/run-all.sh
```

Logi lądują w `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log`.
