# ==============================================================================
# Tytul:        lab.config.example.psd1
# Opis:         Szablon konfiguracji laboratorium PG18 HA. Skopiuj jako
#               lab.config.psd1 i wpisz prawdziwe hasla. Lab.config.psd1 jest
#               gitignored, ten plik (example) jest komitowany.
# Description [EN]: Lab configuration template for PG18 HA lab. Copy to
#               lab.config.psd1 and fill in real passwords. lab.config.psd1
#               is gitignored, this template is committed.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - PowerShell 5.1+ (Import-PowerShellDataFile)
#                    - VirtualBox 7.0+ na hoscie
# Requirements [EN]: - PowerShell 5.1+ (Import-PowerShellDataFile)
#                    - VirtualBox 7.0+ on host
#
# Uzycie [PL]:       Copy-Item lab.config.example.psd1 lab.config.psd1
#                    notepad lab.config.psd1   # wpisz hasla
# Usage [EN]:        Copy-Item lab.config.example.psd1 lab.config.psd1
#                    notepad lab.config.psd1   # fill in passwords
# ==============================================================================

@{
    # Lab domain (RFC 6761 -- never .local because of mDNS conflicts)
    Domain = 'lab.test'

    # Host-only network on the host (created by Network.psm1 if absent)
    Network = @{
        Name    = 'vboxnet0'
        Cidr    = '192.168.56.0/24'
        HostIp  = '192.168.56.1'
        Netmask = '255.255.255.0'
    }

    # Topology selector: 'default' (6 VMs, ~17 GB) or 'extended' (10 VMs, ~20 GB)
    Topology = 'default'

    # Default topology VMs (addendum DNS-NTP sec.B.2)
    Vms = @(
        @{ Name='infra'; Hostname='infra.lab.test'; Ip='192.168.56.10'; Ram=1024; Cpu=1; Role='infra'      }
        @{ Name='pg1';   Hostname='pg1.lab.test';   Ip='192.168.56.11'; Ram=4096; Cpu=2; Role='pg-node'    }
        @{ Name='pg2';   Hostname='pg2.lab.test';   Ip='192.168.56.12'; Ram=4096; Cpu=2; Role='pg-node'    }
        @{ Name='pg3';   Hostname='pg3.lab.test';   Ip='192.168.56.13'; Ram=4096; Cpu=2; Role='pg-node'    }
        @{ Name='lb';    Hostname='lb.lab.test';    Ip='192.168.56.20'; Ram=2048; Cpu=2; Role='lb'         }
        @{ Name='cli';   Hostname='cli.lab.test';   Ip='192.168.56.30'; Ram=2048; Cpu=2; Role='cli'        }
    )

    # Rocky Linux 9.8 minimal ISO (9.5 zostalo przeniesione do vault -> 404 na pub)
    Iso = @{
        Url       = 'https://download.rockylinux.org/pub/rocky/9.8/isos/x86_64/Rocky-9.8-x86_64-minimal.iso'
        Sha256    = 'd338032cd1cdd41c67139f2f71b4c832c8e4a21943106519db9c7137df7a63d4'
        CachePath = "$env:LOCALAPPDATA\postgres18-ha-lab\iso\Rocky-9.8-x86_64-minimal.iso"
    }

    # Component versions (pinned for reproducibility)
    Versions = @{
        Postgres  = '18.3'
        Patroni   = '4.1'
        Etcd      = '3.5'
        HAProxy   = '2.8'
        PgBouncer = '1.23'
        RockyOs   = '9.8'
    }

    # Patroni watchdog (softdog kernel module loaded by 00-common)
    # Mode: 'automatic' (production-like, requires /dev/watchdog) | 'off' (fallback)
    Watchdog = @{
        Mode = 'automatic'
    }

    # Cluster secrets -- replace BEFORE running build. The placeholders @@REPLACE@@
    # are NOT valid passwords; orchestrator validates and aborts if unchanged.
    Secrets = @{
        ReplicatorPassword = '@@REPLACE@@'
        SuperuserPassword  = '@@REPLACE@@'
        RewindPassword     = '@@REPLACE@@'
        AppUserPassword    = 'lab'    # demo user 'lab' on labdb (low-risk lab default)
    }

    # Host SSH key paths. If KeyPath does not exist, Prereqs.psm1 generates an ed25519 key.
    Ssh = @{
        KeyPath       = "$env:USERPROFILE\.ssh\id_ed25519"
        SshConfigPath = "$env:USERPROFILE\.ssh\config"
        KnownHosts    = "$env:USERPROFILE\.ssh\known_hosts.lab"
    }

    # PowerShell HttpListener serving kickstart + guest scripts to VMs during install
    KsServer = @{
        Port   = 8000
        BindIp = '192.168.56.1'   # bind to vboxnet0 IP avoids URL ACL admin requirement
    }

    # Cluster identity
    Cluster = @{
        Scope    = 'pg-ha-lab'
        Database = 'labdb'
        AppUser  = 'lab'
    }

    # Logging level for host PowerShell modules: 'Debug' | 'Info' | 'Warn' | 'Error'
    LogLevel = 'Info'
}
