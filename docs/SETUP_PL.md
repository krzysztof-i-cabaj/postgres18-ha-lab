# 🚀 Walkthrough setup — Windows 11

[![Host](https://img.shields.io/badge/Host-Windows_11-0078D6)]()
[![Hypervisor](https://img.shields.io/badge/Hypervisor-VirtualBox_7.x-183A61)]()

> 🎯 Krok po kroku setup labu z czystego hosta Windows 11.
> Wersja angielska: [SETUP.md](SETUP.md).

## 0. Twarde wymagania

- Windows 11 Pro x64
- VirtualBox 7.0+ zainstalowany (dostarcza `VBoxManage.exe`)
- Wbudowane narzędzia: PowerShell 5.1+, klient OpenSSH, `curl.exe`
- **Python 3.8+** na hoście (uruchamia serwer HTTP kickstart `host/ks_server.py`)
- ≥ 20 GB wolnego RAM, ≥ 60 GB wolnego dysku
- Internet (do ISO + repozytorium PGDG)

**Niedozwolone na hoście**: Ansible, WSL, Make, Chocolatey, Scoop. (Python jest wymagany — patrz wyżej.)

## 1. Klonowanie i konfiguracja

`<repo>` to lokalizacja gdzie sklonowałeś repozytorium — może być
`D:\projects\postgres18-ha-lab`, `C:\src\postgres18-ha-lab`, `~\dev\...`,
gdziekolwiek. Wybierz własną ścieżkę. (Zobacz `SETTINGS.md` w korzeniu repo
dla wartości specyficznej dla danego setupu.)

```powershell
cd <repo>          # np. cd C:\dev\postgres18-ha-lab

# Stworz prawdziwy config z szablonu, wpisz hasla:
Copy-Item lab.config.example.psd1 lab.config.psd1
notepad lab.config.psd1
```

Zamień każdy `@@REPLACE@@` na prawdziwe hasło. Orkiestrator **odmawia**
provisionowania klastra z hasłami-placeholderami.

## 2. Włącz wykonywanie skryptów PowerShell

Raz na maszynie:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Weryfikacja wymagań hosta

```powershell
.\lab.ps1 prereqs
```

Generuje `~/.ssh/id_ed25519` (jeśli brak) i dopisuje zarządzany blok do
`~/.ssh/config`, dzięki czemu `ssh pg1` działa bez hasła z PowerShella **i**
MobaXterm (Settings -> SSH -> "Use OpenSSH config").

## 4. Build

### Jednorazowa reguła zapory (admin)

`lab.ps1 build` uruchamia mały serwer HTTP w **Pythonie** (`host/ks_server.py`,
serwuje tylko `kickstart/` + `guest/`) na `http://192.168.56.1:8000/`; VM-ki pobierają
z niego kickstart. Windows Firewall (i każda zapora zewnętrzna) domyślnie blokuje
ruch przychodzący na `:8000` z sieci host-only, więc instalacja zapętla się na
`failed to fetch kickstart`. Otwórz to **raz** z **podniesionego** PowerShell,
zawężając do podsieci labu:

```powershell
# Kliknij prawym na PowerShell > Uruchom jako administrator
netsh advfirewall firewall add rule name="pgha-lab-ks-8000" dir=in action=allow protocol=TCP localport=8000 remoteip=192.168.56.0/24
```

Jeśli masz zaporę zewnętrzną (np. **Bitdefender Total Security**), nadpisuje ona
regułę Windows — ogarnij to też tam. Oznaczenie karty *VirtualBox Host-Only* jako
**Dom/Biuro (zaufana)** jest konieczne, ale **może nie wystarczyć** — upewnij się też,
że dla serwera kickstart (`python.exe`) **dozwolony jest kierunek przychodzący
/ „odbieranie" (inbound)**. Objaw przy pominięciu: VM-ki pętlą `failed to fetch
kickstart`, choć serwer odpowiada z hosta. **Nie** używaj „wstrzymaj na 1h" — wygasa
i blokada wraca.

Cofnięcie reguły:

```powershell
netsh advfirewall firewall delete rule name="pgha-lab-ks-8000"
```

> Serwer używa surowego socketu Pythona (nie .NET `HttpListener`/`http.sys`), więc
> **rezerwacja URL ACL nie jest potrzebna**. Jeśli dodałeś ją wcześniej, możesz
> usunąć: `netsh http delete urlacl url=http://192.168.56.1:8000/`. Whitelista w
> `ks_server.py` gwarantuje, że serwowane są tylko `kickstart/` i `guest/` — nigdy
> `lab.config.psd1`.

### Build labu

```powershell
.\lab.ps1 build
```

Domyślna topologia: 6 VMek (infra + pg1/2/3 + lb + cli). Łącznie ~17 GB RAM,
~30 minut na Ryzen 9 + NVMe. Użyj `-Topology extended` dla 10 VMek (oddzielne
węzły etcd, ~20 GB RAM).

## 5. Integracja DNS na Windows (NRPT)

Rozwiązanie `pg1.lab.test` z hosta wymaga skierowania `*.lab.test` do infry.
Natywne rozwiązanie Windows to **Name Resolution Policy Table (NRPT)**.

### Jednorazowa instalacja (admin)

```powershell
# Kliknij prawym na PowerShell -> Uruchom jako administrator
.\lab.ps1 dns install
```

Dodaje regułę NRPT: `.lab.test -> 192.168.56.10`. Weryfikacja:

```powershell
Resolve-DnsName pg2.lab.test
# Powinno zwrocic 192.168.56.12
```

### Dlaczego NRPT zamiast `hosts`

- NRPT jest per-namespace (inne domeny zachowują normalny DNS)
- Przeżywa renew DHCP
- Współistnieje z korporacyjnymi VPN
- Nie wymaga edycji plików systemowych

### Fallback (bez admina)

Jeśli nie możesz uzyskać elevacji, dopisz do `C:\Windows\System32\drivers\etc\hosts`:

```
192.168.56.10 infra.lab.test
192.168.56.11 pg1.lab.test
192.168.56.12 pg2.lab.test
192.168.56.13 pg3.lab.test
192.168.56.20 lb.lab.test  db.lab.test
192.168.56.30 cli.lab.test
```

(Edycja `hosts` wymaga admina raz; potem nie potrzebujesz uprawnień NRPT.)

## 6. Weryfikacja

```powershell
.\lab.ps1 status            # Klaster Patroni + URL HAProxy stats
ssh pg1 'patronictl -c /etc/patroni/patroni.yml list'
psql 'host=db.lab.test port=5000 dbname=labdb user=lab password=lab' -c 'select 1'
```

Otwórz `http://lb.lab.test:7000/` (lub `http://192.168.56.20:7000/`) — HAProxy stats.

## 7. Uruchomienie scenariuszy

```powershell
.\lab.ps1 scenario 01
.\lab.ps1 scenario all
```

Logi lądują w `/var/log/postgres18-ha-lab/scenarios/` na VMce cli.

## 8. Zwijanie

```powershell
.\lab.ps1 destroy           # poweroff + unregister wszystkich VMek
.\lab.ps1 clean             # destroy + usuniecie cache ISO
.\lab.ps1 dns uninstall     # admin; usun regule NRPT
# opcjonalnie, admin; usun regule zapory serwera kickstart:
netsh advfirewall firewall delete rule name="pgha-lab-ks-8000"
```
