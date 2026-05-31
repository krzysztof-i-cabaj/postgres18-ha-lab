# 🚀 Quickstart — złóż i wystartuj LAB (runbook)

[![Czas](https://img.shields.io/badge/Build-~30_min-blue)]()
[![Host](https://img.shields.io/badge/Host-Windows_11_%2B_VirtualBox-0078D6)]()
[![Tryb](https://img.shields.io/badge/Tryb-automat_lab.ps1-darkgreen)]()

> 🎯 Najkrótsza ścieżka: od zera do działającego klastra HA + scenariuszy, automatem `lab.ps1`.
> Wpleciono **realne pułapki z budowy** (Bitdefender, „cisza ≠ błąd"). Pełny walkthrough z
> wyjaśnieniami: [SETUP_PL.md](SETUP_PL.md). Ręcznie bez `lab.ps1`: [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md).

---

## 0. ✅ Wymagania (skrót)

- **Windows 11** + **VirtualBox 7+** (`VBoxManage`) + **Python 3.8+** (serwer kickstart).
- Wbudowane: PowerShell 5.1+, klient OpenSSH, `curl.exe`.
- ≥ 20 GB wolnego RAM, ≥ 60 GB dysku, internet (ISO + repo PGDG).
- **Niedozwolone:** Ansible, WSL, Make, Chocolatey, Scoop.

---

## 1. 🔥 Przygotuj zaporę (raz — NAJCZĘSTSZA PUŁAPKA)

`build` uruchamia serwer kickstart (`python.exe`) na `192.168.56.1:8000`; VM-ki **muszą** go
dosięgnąć, inaczej instalacja zapętla się na `failed to fetch kickstart`.

**Windows Firewall** (PowerShell jako **Administrator**, raz):
```powershell
netsh advfirewall firewall add rule name="pgha-lab-ks-8000" dir=in action=allow protocol=TCP localport=8000 remoteip=192.168.56.0/24
```

**Bitdefender / inna zapora 3rd-party** (nadpisuje regułę Windows):
- karta *VirtualBox Host-Only* → profil **Dom/Biuro (zaufana)**,
- **ORAZ włącz kierunek PRZYCHODZĄCY (odbieranie / inbound)** dla `python.exe`.
- ⚠️ To było źródłem zagadkowego `failed to fetch kickstart` mimo działającego serwera. Nie używaj
  „wstrzymaj na 1h" — wygasa.

---

## 2. ⚙️ Konfiguracja (raz)

```powershell
cd <repo>                                   # katalog repozytorium
Copy-Item lab.config.example.psd1 lab.config.psd1
notepad lab.config.psd1                      # wpisz hasła zamiast @@REPLACE@@ (Secrets)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
> ISO **Rocky 9.8** pobierze się automatycznie przy 1. buildzie i zostanie zcache'owane
> (SHA256 weryfikowany). Nie trzeba nic ściągać ręcznie.

---

## 3. 🏗️ Składanie (kolejność komend)

```powershell
.\lab.ps1 prereqs        # weryfikacja hosta + generacja klucza ed25519 (jeśli brak)
.\lab.ps1 build          # ~30 min: 6 VM od zera (infra → pg1/2/3 → lb → cli → demo DB)

# jednorazowo, PowerShell jako ADMINISTRATOR:
.\lab.ps1 dns install    # reguła NRPT, *.lab.test rozwiązuje się na Windows

.\lab.ps1 status         # stan klastra + URL HAProxy stats
```
> 💡 Jeśli orkiestracja przerwała się w połowie (np. Ctrl+C), **nie buduj od zera** —
> `.\lab.ps1 provision` ponawia samą orkiestrację (idempotentnie, bez ponownego tworzenia VM).

---

## 4. 🔐 Hasła (Twój LAB)

| Konto | Hasło | Gdzie |
|---|---|---|
| `postgres` (superuser) | `LabSuper2026` | klaster; admin PgBouncer |
| `replicator` | `LabRepl2026` | replikacja |
| `rewind_user` | `LabRewind2026` | `pg_rewind` |
| `lab` (aplikacja) | `lab` | baza `labdb` |
| OS `root` / `lab` | `labroot` / `lab` | każda VM (SSH tylko kluczem) |

Źródło prawdy: `lab.config.psd1` (klaster) + `kickstart/base.ks.tmpl` (OS). To LAB — hasła proste.

---

## 5. 🔎 Weryfikacja

```powershell
.\lab.ps1 status
ssh root@pg1.lab.test "patronictl -c /etc/patroni/patroni.yml list"   # 1 Leader + 2 repliki
psql "host=db.lab.test port=5000 dbname=labdb user=lab password=lab" -c "select 1"   # zapis (primary)
psql "host=db.lab.test port=5001 dbname=labdb user=lab password=lab" -c "select pg_is_in_recovery()"  # odczyt (repliki)
```
HAProxy stats: `http://lb.lab.test:7000/` (lub `http://192.168.56.20:7000/`).

---

## 6. 🧪 Scenariusze awarii

```powershell
.\lab.ps1 scenario 01     # baseline (sanity)
.\lab.ps1 scenario 02     # twardy failover + dowód zero-data-loss
.\lab.ps1 scenario 13     # failover sterowany aplikacją (pgha-client + metryki downtime)
.\lab.ps1 scenario all    # cała suita 01–13
.\lab.ps1 report          # zbuduj docs/run-report_PL.html (interaktywny) z przebiegu
```
Ręczne kroki: [MANUAL_SCENARIOS_PL.md](MANUAL_SCENARIOS_PL.md). Raport przykładowy: [agentic-run-all_PL.html](agentic-run-all_PL.html).

---

## 7. ⏸️ Pauza — wyłącz / włącz (stan zachowany)

> ⚠️ **`destroy` NISZCZY VM (unregister) — NIE używaj do chwilowego wyłączenia!**
> `lab.ps1` nie ma `stop`/`start` — użyj `VBoxManage` lub GUI VirtualBox.

Po ponownym włączeniu **wszystko startuje samo** (usługi `etcd`/`patroni`/`haproxy`/`pgbouncer`/
`unbound`/`chrony` są `enabled`; etcd wraca z trwałego `data-dir`, Patroni odbudowuje klaster z etcd).

```powershell
$vb = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
# WYŁĄCZ (łagodnie, ACPI):
'cli','lb','pg3','pg2','pg1','infra' | ForEach-Object { & $vb controlvm $_ acpipowerbutton }
# WŁĄCZ (infra pierwsza — DNS/NTP; reszta dołączy):
'infra','pg1','pg2','pg3','lb','cli' | ForEach-Object { & $vb startvm $_ --type headless; Start-Sleep 8 }
```
Po ~1–2 min (elekcja lidera): `.\lab.ps1 status`. NRPT na hoście przeżywa (`*.lab.test` działa dalej).
GUI VirtualBox: prawy klik → **Close → ACPI Shutdown**; start = dwuklik.

> 💡 **Kolejność nie jest krytyczna** — klaster działa po IP (nie po DNS) i sam się składa (etcd kworum
> + elekcja Patroni). Możesz włączyć/wyłączyć wszystkie naraz. Jedyny warunek startu: ≥2 z 3 pg-węzłów
> (kworum etcd). „infra pierwsza" i `Start-Sleep` to tylko kosmetyka / odciążenie hosta.

## 8. 🔁 Operacje i zwijanie

```powershell
.\lab.ps1 provision      # ponów TYLKO orkiestrację klastra (bez tworzenia VM)
.\lab.ps1 ssh pg1        # bastion do węzła
.\lab.ps1 destroy        # poweroff + unregister wszystkich VM (TRWALE USUWA — nie do pauzy!)
.\lab.ps1 clean          # destroy + usunięcie cache ISO
.\lab.ps1 dns uninstall  # (admin) usuń regułę NRPT
```

---

## ⚠️ Pułapki z praktyki

| Objaw | Co zrobić |
|---|---|
| `failed to fetch kickstart` (pętla) | Zapora — sekcja 1 (Bitdefender **inbound** dla python.exe!). |
| Build „wisi" po `OK etcd healthy` | To cicha faza (dnf) **albo** zacięcie — **NIE Ctrl+C**. Sprawdź: `ssh root@cli "tail -f /var/log/postgres18-ha-lab/orchestrate.log"`. |
| `ssh root@pgN` → `Permission denied (publickey)` | EL9 = root tylko kluczem. Po przebudowie VM zmienia klucz hosta — automat to ignoruje, ręcznie usuń stary wpis z `~/.ssh/known_hosts`. |
| `*.lab.test` nie rozwiązuje się na Windows | `.\lab.ps1 dns install` (admin) lub wpis w `hosts`. |
| Wiele procesów `orchestrate.sh` na cli | Osierocone po Ctrl+C — `ssh root@cli "pkill -9 -f orchestrate.sh"`, potem `provision`. |

---

## 🗺️ Mapa dokumentacji

| Plik | Do czego |
|---|---|
| **QUICKSTART_PL.md** (ten) | ściąga: złóż i wystartuj |
| [SETUP_PL.md](SETUP_PL.md) | pełny walkthrough z wyjaśnieniami |
| [MANUAL_INSTALL_PL.md](MANUAL_INSTALL_PL.md) | budowa ręczna, węzeł po węźle (bez `lab.ps1`) |
| [MANUAL_SCENARIOS_PL.md](MANUAL_SCENARIOS_PL.md) | ręczne odtworzenie 13 scenariuszy |
| [SCENARIOS_PL.md](SCENARIOS_PL.md) | opis scenariuszy + oczekiwany output |
| [AGENTIC_RUN_ALL_PL.md](AGENTIC_RUN_ALL_PL.md) / [agentic-run-all_PL.html](agentic-run-all_PL.html) | raport przebiegu pełnej suity (+ strona Pages) |
| [ARCHITECTURE_PL.md](ARCHITECTURE_PL.md) | komponenty, failover, DNS/NTP |
| [TROUBLESHOOTING_PL.md](TROUBLESHOOTING_PL.md) | pełny troubleshooting |
| [../SETTINGS.md](../SETTINGS.md) | wartości specyficzne projektu |
