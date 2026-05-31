# 🧪 Scenariusze — oczekiwany output

[![Count](https://img.shields.io/badge/Scenariusze-13-darkgreen)]()

> 🎯 Co robi każdy scenariusz i jak wygląda przejście testu.
> Wersja angielska: [SCENARIOS.md](SCENARIOS.md). Zobacz też [/scenarios](../scenarios/) — kod skryptów.

## Konwencje

Każdy scenariusz to skrypt bash w `scenarios/NN-name.sh`. Używają
`scenarios/lib/assertions.sh` dla wspólnych funkcji `assert_*`. Uruchamianie
pojedynczo lub jako suite:

```bash
.\lab.ps1 scenario 02
.\lab.ps1 scenario all      # wywoluje scenarios/run-all.sh na cli
```

Logi: `/var/log/postgres18-ha-lab/scenarios/<NN>-<timestamp>.log` na cli.

## 01 — baseline

Sanity. Po buildzie, oczekiwane (wartości `id`/`rows` rosną z każdym
uruchomieniem — `pgha_writer_log` akumuluje wiersze):

```
PASS leader is pg1
PASS etcd quorum healthy (3/3 nodes)
PASS 3 members visible
PASS write through HAProxy ok (id=<N>)
PASS read through HAProxy ok (rows=<N>)
SCENARIO PASSED: 01-baseline
```

## 02 — kill-primary-hard

`pkill -9 postgres` na liderze. Scenariusz commituje wiersz-sentinel **przed**
zabiciem, więc `synchronous_mode` ma go zachować. Patroni przejmuje leader lock
w etcd z repliki w ~30s. HAProxy zauważa przy następnym health check.

Oczekiwane: `leader changed: pg1 -> pg2` (lub inny węzeł), write+read pass oraz
`committed row N survived failover (no data loss)` — dowód braku utraty danych.

## 03 — poweroff-primary-vm

Akcja po stronie hosta: `VBoxManage controlvm <pri> poweroff`. Scenariusz na cli
wykrywa zmianę lidera po tym jak host wyłączy VM. Żeby domknąć pętlę, host
powinien podnieść VM: `VBoxManage startvm <pri> --type headless`.

## 04 — graceful-switchover

`patronictl switchover --master pg1 --candidate pg2 --force`. Planowane, bez
utraty danych, bez błędów klienta z `target_session_attrs=read-write`.

## 05 — network-partition

`iptables -I INPUT/OUTPUT -j DROP` dla `192.168.56.0/24` na liderze. Watchdog
+ wygaśnięcie leasu etcd uruchamiają failover. Cleanup: scenariusz robi flush
iptables na partycjonowanym węźle na końcu.

## 06 — etcd-single-loss

Stop etcd na jednym węźle. Kworum (2/3) trzyma; klaster działa. Restart etcd
na końcu.

## 07 — etcd-quorum-loss

Stop etcd na dwóch węzłach. Patroni wchodzi w DCS-failsafe; reads idą, writes
mogą się zatrzymać do powrotu kworum. Scenariusz restartuje etcd żeby
przywrócić kworum.

## 08 — replica-restart

`systemctl restart patroni` na replice. Lider bez zmiany; replika dołącza
w ~10 sekund.

## 09 — pg-rewind-old-primary

Po zabiciu primary, restart starego primary. Patroni uruchamia `pg_rewind`
żeby uzgodnić rozbieżną oś czasu i dołącza jako replika.

## 10 — sync-vs-async

Toggle `synchronous_mode` przez `patronictl edit-config`. Demonstruje tradeoff
trwałości: tryb sync blokuje zapisy gdy brak sync standby; async nigdy nie
blokuje ale może gubić dane przy crashu.

## 11 — multi-host-libpq

Pominięcie HAProxy. libpq z
`host=pg1.lab.test,pg2.lab.test,pg3.lab.test target_session_attrs=read-write`
sam znajduje węzeł zapisywalny. Użyteczne jako fallback gdy `lb` padnie.

## 12 — cascading-failure

Zabij primary, potem od razu zabij nowego primary. Klaster powinien wybrać
trzeciego lidera. Demonstruje że Patroni nie zacina się.

## 13 — app-failover-continuous

Failover z perspektywy aplikacji. `pgha-client` uruchamia **ciągły** writer (przez
HAProxy) i reader (przez multi-host libpq) na `--duration 60s`; w trakcie zabijamy
lidera (`pkill -9 postgres` + `systemctl stop patroni`, technika ze scenariusza 02).
Oba klienty reconnectują, a JSON przebiegu (`--report`) rejestruje **okno
niedostępności**.

Oczekiwane: `leader changed`, a z metryk JSON writera/readera —
`app kept writing across failover (inserts=<N>, outages>=1)`,
`max downtime <S>s within budget (<= 45s)`, `reads progressed (max_id A -> B)` oraz
`writes served by >=2 distinct hosts` (dowód, że HAProxy przełączył primary). Metryki
trafiają do `/var/log/postgres18-ha-lab/scenarios/app/{writer,reader}.json` i zasilają
`lab.ps1 report` → `docs/run-report_PL.html`.
