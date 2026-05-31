# 🚧 Rozwiązywanie problemów

[![Scope](https://img.shields.io/badge/Zakres-Diagnostyka-yellow)]()

> 🎯 Częste problemy i sposoby ich rozwiązania.
> Wersja angielska: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Wstrzyknięcie scancode / menu boot

### Problem: VM bootuje instalator Rocky interaktywnie (bez kickstart)

`Tab` nie dotarł do ISOLINUX na czas, albo boot params się nie zarejestrowały.
Objaw: VM stoi na splashu instalacji bez postępu.

**Mitygacje**:

- Zwiększ czas oczekiwania przed `Tab`: edytuj `BootMenuWaitSec` w `BootKickstart.psm1`
- Zrób screenshot konsoli żeby potwierdzić stan VM:
  ```powershell
  .\lab.ps1 console pg1
  ```
- W ostateczności — alternatywne metody (świadomie nieużywane, ale udokumentowane):

### Alternatywa 1: VBoxManage unattended

VBox 7.0+ ma `VBoxManage unattended install` który natywnie obsługuje
kickstart RHEL/Rocky. Nie używamy bo:

- Ukrywa wstrzyknięcie boot params (mniejsza wartość edukacyjna)
- Mniej kontroli nad menu boot (chcemy pokazać podejście Tab + linia boot)

Jeśli chcesz spróbować: `VBoxManage unattended install <vm> --iso=... --user=lab --password=lab`.

### Alternatywa 2: OEMDRV ISO trick

Anaconda auto-wykrywa `ks.cfg` z każdego urządzenia blokowego z labelem `OEMDRV`.
PowerShell może wygenerować 1 MB ISO przez COM `IMAPI2FS`, podpiąć jako drugi
DVD — bez scancode. Ten sam powód nieużywania: wartość edukacyjna.

## NRPT

### Resolve-DnsName działa ale psql nie

`nslookup` **nie** używa NRPT — zawsze idzie przez DNS adaptera. Do weryfikacji
używaj `Resolve-DnsName`.

### Resolve-DnsName zwraca "no DNS server"

Sprawdź regułę:

```powershell
Get-DnsClientNrptRule | Where-Object Namespace -eq '.lab.test'
Test-NetConnection 192.168.56.10 -Port 53
```

Jeśli port 53 nieosiągalny, DNS infra nie działa. SSH:
`ssh root@192.168.56.10 'systemctl status unbound'`.

### VPN korporacyjny zjadł moje reguły NRPT

Większość klientów VPN instaluje własne reguły NRPT. Nasza współistnieje, bo
jest per-namespace (`.lab.test`), ale zweryfikuj:

```powershell
Get-DnsClientNrptRule | Sort-Object Namespace | Format-Table Namespace, NameServers
```

Jeśli reguła VPN obejmuje wszystkie namespace'y (`.`), nasza wygrywa, bo
longest-match wygrywa w NRPT.

## Watchdog

### Patroni nie startuje: "could not open watchdog"

Moduł kernela `softdog` nie załadowany. Na danym węźle:

```bash
ssh root@pg1 'lsmod | grep softdog'
ssh root@pg1 'modprobe softdog && lsmod | grep softdog'
```

Jeśli `modprobe` zawodzi (brak modułu kernela), ustaw `WATCHDOG_MODE=off`
w `lab.config.psd1` i uruchom `.\lab.ps1 provision`. Uwaga: to wyłącza ważne
zabezpieczenie — rób to tylko w labie.

## Kodowanie (pliki z Windows serwowane do Linux)

Bash na Rocky krztusi się UTF-16 LE BOM-em albo CRLF w skryptach shell.
Kod hosta używa
`[System.IO.File]::WriteAllText($p, $t, [System.Text.UTF8Encoding]::new($false))`
i jawnego LF dla `*.sh`, `*.ks`, `*.tmpl`. Audyt:

Uruchamiaj z `<repo>` (korzeń repozytorium):

```bash
cd <repo>          # np. cd /c/dev/postgres18-ha-lab
/c/Program\ Files/Python312/python -c "
from pathlib import Path
for p in Path('.').rglob('*'):
    if p.is_file() and p.suffix.lower() in {'.sh', '.ks', '.tmpl', '.yml', '.cfg'}:
        b = p.read_bytes()
        if b.startswith(b'\xef\xbb\xbf'): print(f'BOM:  {p}')
        if b'\r\n' in b: print(f'CRLF: {p}')
"
```

Oczekiwany output: zero linii. Jeśli plik ma CRLF, napraw ręcznie:

```python
p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n'))
```
