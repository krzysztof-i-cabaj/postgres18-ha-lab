# ⚙️ SETTINGS — postgres18-ha-lab

[![Zakres](https://img.shields.io/badge/Zakres-Tylko_projekt-blue)]()
[![Konwencje](https://img.shields.io/badge/Konwencje-dwuj%C4%99zyczne_PL%2FEN-orange)]()
[![Domena](https://img.shields.io/badge/Domena-lab.test-success)]()

> 🎯 Wyłącznie konfiguracja i konwencje specyficzne dla *tego* repozytorium
> (placeholder `<repo>`, domena labu, mapa VMek, układ sekretów, dostęp SSH).
> Wersja angielska: [SETTINGS.md](SETTINGS.md).

---

## 🧩 Definicja `<repo>`

`<repo>` to **placeholder** dla lokalizacji tego repozytorium na Twojej maszynie.
W całym projekcie (nagłówki skryptów, dokumentacja, przykłady komend)
odwołania do `<repo>` oznaczają "absolutną ścieżkę korzenia repozytorium
na lokalnym dysku".

Typowe lokalizacje:

| Setup | `<repo>` rozwija się do |
|---|---|
| Typowy klon na Windows | `C:\dev\postgres18-ha-lab` lub `C:\src\postgres18-ha-lab` |
| Klon w WSL / git-bash | `~/dev/postgres18-ha-lab` |
| Inny dysk | `E:\projects\postgres18-ha-lab` |

Wybierz tam gdzie sklonowałeś. **Nie commituj** ścieżek specyficznych dla
maszyny w nagłówkach skryptów ani docs — zostawiaj je jako literalny
placeholder `<repo>`, żeby projekt pozostał przenośny.

---

## 🌐 Domena lab

- **TLD**: `lab.test` (RFC 6761, świadomie nie `.local` żeby uniknąć kolizji z mDNS)
- **Resolver autorytatywny**: Unbound na `infra.lab.test` (`192.168.56.10`)
- **Stabilny endpoint klienta**: `db.lab.test:5000` (CNAME → `lb.lab.test`)
- **Strefa odwrotna**: `56.168.192.in-addr.arpa.`

---

## 🔌 Sieć hosta

- VirtualBox host-only network: `vboxnet0`
- Subnet: `192.168.56.0/24`, DHCP **off**
- IP hosta w tej sieci: `192.168.56.1` (używane przez KS HTTP server podczas instalacji)

---

## 🖥️ Mapa VMek (topologia domyślna)

| Hostname        | IP            | RAM | vCPU | Rola                                       |
|-----------------|---------------|-----|------|--------------------------------------------|
| infra.lab.test  | 192.168.56.10 | 1G  | 1    | Unbound (DNS) + chronyd (serwer NTP)       |
| pg1.lab.test    | 192.168.56.11 | 4G  | 2    | PG18 + Patroni + etcd                      |
| pg2.lab.test    | 192.168.56.12 | 4G  | 2    | PG18 + Patroni + etcd                      |
| pg3.lab.test    | 192.168.56.13 | 4G  | 2    | PG18 + Patroni + etcd                      |
| lb.lab.test     | 192.168.56.20 | 2G  | 2    | HAProxy + PgBouncer                        |
| cli.lab.test    | 192.168.56.30 | 2G  | 2    | Orchestrator + klient testowy + bastion    |

Razem: ~17 GB RAM, 10 vCPU. Źródło autorytatywne: `lab.config.example.psd1`.

---

## 🔐 Układ sekretów

- **Źródło prawdy**: `lab.config.psd1` (gitignored). Skopiuj z
  `lab.config.example.psd1` i wpisz prawdziwe hasła przy pierwszym uruchomieniu.
- **Wzorzec**: `lab.config.example.psd1` (komitowany; tylko hasła-placeholdery).
- **Transfer do VM `cli`** jako `/usr/local/lib/postgres18-ha-lab/lab.config.json`,
  `chmod 600`, właściciel `root:root`. Orkiestrator czyta go z tej lokalizacji.
- **Wbudowany fallback**: kickstart ustawia hasło `root` na `labroot` i tworzy
  użytkownika `lab` z hasłem `lab`. Klucze SSH to podstawowa metoda uwierzytelniania;
  hasła są tylko fallbackiem. Udokumentowane w `docs/TROUBLESHOOTING.md`.

---

## 🔑 Klucze SSH hosta (logowanie bez hasła z Windows)

- Ścieżka klucza: `%USERPROFILE%\.ssh\id_ed25519` (generowany automatycznie przez
  `host/modules/Prereqs.psm1` jeśli nie istnieje).
- Klucz publiczny jest renderowany do każdego `*.ks` przez `{{SSH_PUBKEY}}`
  i instalowany przez kickstart `%post` zarówno w `/root/.ssh/authorized_keys`
  jak i `/home/lab/.ssh/authorized_keys`.
- `Prereqs.psm1` dopisuje także (idempotentnie, między markerami) blok konfiguracji
  OpenSSH do `%USERPROFILE%\.ssh\config`:
  ```
  # >>> postgres18-ha-lab >>>
  Host infra pg1 pg2 pg3 lb cli
      HostName %h.lab.test
      User root
      IdentityFile ~/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
      UserKnownHostsFile ~/.ssh/known_hosts.lab
  # <<< postgres18-ha-lab <<<
  ```
- Efekt netto: `ssh pg1` z PowerShella albo z MobaXterm loguje się bez hasła
  (MobaXterm: Settings → SSH → "Use OpenSSH config" — czyta ten sam plik).

---

## 📤 Przykłady SCP dla tego projektu

```powershell
# upload lab.config.json do cli (config orkiestratora)
scp .\lab.config.json root@cli.lab.test:/usr/local/lib/postgres18-ha-lab/lab.config.json

# pobierz konfig HAProxy do inspekcji
scp root@lb.lab.test:/etc/haproxy/haproxy.cfg .\out\haproxy.cfg

# pobierz log scenariusza z cli po uruchomieniu
scp root@cli.lab.test:/var/log/postgres18-ha-lab/scenarios/02-*.log .\logs\
```

Bez zainstalowanego NRPT (`lab.ps1 dns install` pominięte) zamień nazwę hosta na IP
(np. `root@192.168.56.30` zamiast `root@cli.lab.test`).

---

## 📚 Mapa plików projektu

| Plik / katalog                                            | Rola                                                       |
|-----------------------------------------------------------|------------------------------------------------------------|
| [README.md](README.md) / [README_PL.md](README_PL.md)     | Główne intro, quickstart, indeks scenariuszy               |
| [LICENSE](LICENSE)                                        | Licencja MIT                                               |
| `lab.ps1`                                                 | Entrypoint dla Windows, dispatcher czasowników             |
| `lab.config.example.psd1`                                 | Szablon konfiguracji (komitowany)                          |
| `lab.config.psd1`                                         | Prawdziwa konfiguracja (gitignored)                        |
| `host/PgHaLab.psm1`                                       | Moduł parasolowy PowerShell importowany przez `lab.ps1`    |
| `host/modules/*.psm1`                                     | Pojedyncze moduły funkcjonalne                             |
| `host/tests/Scancode.Tests.ps1`                           | Testy Pester (komponent gating)                            |
| `kickstart/base.ks.tmpl`                                  | Główny szablon kickstart                                   |
| `kickstart/post/role-bootstrap.sh`                        | Instalator roli przy pierwszym boocie (pobierany przez %post) |
| `guest/orchestrate.sh`                                    | Orkiestrator klastra (działa na VM `cli`)                  |
| `guest/roles/*.sh`                                        | Idempotentne skrypty instalacyjne per rola                 |
| `guest/templates/*.tmpl`                                  | Szablony konfiguracji renderowane przez `@@PLACEHOLDER@@`  |
| `client-app/`                                             | Pakiet Python writer/reader/monitor                        |
| `scenarios/`                                              | 13 skryptów scenariuszy awarii + asercje                   |
| `report/`                                                 | Generator raportu przebiegu (logi + metryki -> MD + HTML)  |
| `docs/*.md` + `docs/*_PL.md`                              | Pary dokumentacji EN/PL (README, ARCHITECTURE, SETUP, SCENARIOS, TROUBLESHOOTING) |
| `docs/diagrams/*.svg`                                     | Diagramy architektury i przepływów                         |
| `docs/architecture.html`                                  | Samodzielny wrapper HTML wokół diagramów SVG (architektura/przepływy) |
| `monitoring/`                                             | Opcjonalne dodatki Prometheus/Grafana                      |

---

## 🔗 Konwencje

Projekt stosuje niewielki zestaw konwencji obowiązujących w całym repo:

- **Nagłówki skryptów** — każdy skrypt (`.sh`, `.ps1`, `.psm1`, `.py`, `.sql`) ma dwujęzyczny
  blok nagłówka PL/EN (tytuł, opis, autor, data, wersja, użycie).
- **Placeholder `<repo>`** — ścieżki w docs i nagłówkach skryptów używają literalnego tokenu
  `<repo>` zamiast ścieżki absolutnej specyficznej dla maszyny (patrz tabela wyżej).
- **Kodowanie** — UTF-8 **bez BOM**; końce linii LF dla shell/Python/Markdown, CRLF dla
  PowerShell (`.ps1`/`.psm1`/`.psd1`). Wymuszane przez `.github/workflows/lint.yml` (`encoding-audit`).
- **Dwujęzyczna dokumentacja** — każdy `*.md` ma polski odpowiednik `*_PL.md`.
