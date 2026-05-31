# 🚧 Troubleshooting

[![Scope](https://img.shields.io/badge/Scope-Diagnostic-yellow)]()

> 🎯 Common problems and how to fix them.
> Polish: [TROUBLESHOOTING_PL.md](TROUBLESHOOTING_PL.md).

## Scancode injection / boot menu

### Problem: VM boots Rocky installer interactively (no kickstart)

The `Tab` keystroke didn't reach ISOLINUX in time, or the boot params didn't
register. Symptoms: VM is at the install splash with no progress.

**Mitigations**:

- Increase the wait before `Tab`: edit `BootMenuWaitSec` in `BootKickstart.psm1`
- Take a console screenshot to confirm what state the VM was in:
  ```powershell
  .\lab.ps1 console pg1
  ```
- As a last resort, switch to one of the alternative methods (intentionally not
  used, but documented for reference):

### Alternative 1: VBoxManage unattended

VBox 7.0+ has `VBoxManage unattended install` which handles RHEL/Rocky kickstart
natively. We don't use it because:

- Hides the boot params injection (less educational)
- Less control over the boot menu (we want to demonstrate the Tab + boot line approach)

If you want to try it: `VBoxManage unattended install <vm> --iso=... --user=lab --password=lab`.

### Alternative 2: OEMDRV ISO trick

Anaconda auto-discovers `ks.cfg` from any block device labeled `OEMDRV`.
PowerShell can craft a 1 MB ISO via the `IMAPI2FS` COM object, attach as a
second DVD, no scancode needed. Same reason for not using: educational value.

## NRPT

### Resolve-DnsName works but psql doesn't

`nslookup` does **not** use NRPT — it always uses the primary adapter DNS.
Use `Resolve-DnsName` for verification.

### Resolve-DnsName fails with "no DNS server"

Check the rule:

```powershell
Get-DnsClientNrptRule | Where-Object Namespace -eq '.lab.test'
Test-NetConnection 192.168.56.10 -Port 53
```

If port 53 is unreachable, infra DNS isn't running. SSH in:
`ssh root@192.168.56.10 'systemctl status unbound'`.

### Corporate VPN ate my NRPT rules

Most VPN clients install their own NRPT rules. Ours coexists fine because it's
per-namespace (`.lab.test`), but verify:

```powershell
Get-DnsClientNrptRule | Sort-Object Namespace | Format-Table Namespace, NameServers
```

If a VPN-installed rule covers all namespaces (`.`), our specific rule wins
because longest-match wins in NRPT.

## Watchdog

### Patroni won't start: "could not open watchdog"

`softdog` kernel module isn't loaded. On the affected node:

```bash
ssh root@pg1 'lsmod | grep softdog'
ssh root@pg1 'modprobe softdog && lsmod | grep softdog'
```

If `modprobe` fails (kernel module missing), set `WATCHDOG_MODE=off` in
`lab.config.psd1` and re-run `.\lab.ps1 provision`. Note: this disables an
important safety net — only do it for the lab.

## Encoding (Windows-side files served to Linux)

Bash on Rocky chokes on UTF-16 LE BOM or CRLF in shell scripts. The host code
uses `[System.IO.File]::WriteAllText($p, $t, [System.Text.UTF8Encoding]::new($false))`
and explicit LF for `*.sh`, `*.ks`, `*.tmpl`. Audit:

Run from `<repo>` (the repo root):

```bash
cd <repo>          # e.g. cd /c/dev/postgres18-ha-lab
/c/Program\ Files/Python312/python -c "
from pathlib import Path
for p in Path('.').rglob('*'):
    if p.is_file() and p.suffix.lower() in {'.sh', '.ks', '.tmpl', '.yml', '.cfg'}:
        b = p.read_bytes()
        if b.startswith(b'\xef\xbb\xbf'): print(f'BOM:  {p}')
        if b'\r\n' in b: print(f'CRLF: {p}')
"
```

Expect zero output. If a file has CRLF, fix it manually:

```python
p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n'))
```
