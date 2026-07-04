# Windows Server 2025 Active Directory Home Lab

An end-to-end Windows infrastructure lab built from scratch in VMware Workstation Pro:
a **Windows Server 2025** domain controller running **Active Directory, DNS, and DHCP**,
with a **file server** whose permissions are tied to security groups, and **PowerShell
automation** that provisions the entire user base from a CSV.

The goal is to practise and document the core skills of a managed-services / systems-support
technician: standing up and configuring Windows Server, building identity and network
services, modelling permissions, automating repetitive work, and writing documentation
another technician could follow.

---

## Skills Demonstrated

| Area | What this lab shows |
|------|---------------------|
| **Windows Server 2025** | Clean install (Desktop Experience), post-install configuration, roles & features |
| **Active Directory (AD DS)** | New forest, domain controller promotion, OUs, security groups, 15 users |
| **DNS** | AD-integrated DNS, forwarders for external resolution, record verification |
| **DHCP** | Authorized scope with options (DNS, gateway, lease) and a client reservation |
| **File Services** | SMB shares with share-level **and** NTFS permissions, least-privilege, group-based access |
| **PowerShell automation** | Idempotent, CSV-driven bulk provisioning of OUs, groups, and users; inventory reporting |
| **IP networking** | Static addressing, subnets, gateway, DNS client config, connectivity troubleshooting |
| **Virtualization** | VM provisioning in VMware Workstation Pro, snapshots, virtual networking |
| **Documentation** | This repository and a reproducible build run-book |

---

## Lab Architecture

```
                 +-----------------------------------+
                 |   Host: Windows 11 Pro            |
                 |   Intel i7-1185G7 / 16 GB RAM     |
                 |   VMware Workstation Pro           |
                 +-----------------+-----------------+
                                   |
                        NAT network (192.168.8.0/24)
                                   |
                       +-----------+-----------+
                       |  DC01                 |
                       |  Windows Server 2025  |
                       |  192.168.8.10 (static)|
                       |                       |
                       |  Roles:               |
                       |   - AD DS             |
                       |   - DNS               |
                       |   - DHCP              |
                       |   - File Server       |
                       +-----------------------+

   Domain: emeka.lab.local     Forest functional level: Windows Server 2025
```

| Setting | Value |
|---------|-------|
| Domain | `emeka.lab.local` |
| NetBIOS | `EMEKA` |
| DC hostname | `DC01` |
| DC static IP | `192.168.8.10` |
| DNS forwarder / gateway | `192.168.8.2` |
| DHCP scope | `192.168.8.50 – 192.168.8.99` |

---

## Environment

- **Hypervisor:** VMware Workstation Pro (free for personal use)
- **Domain controller VM:** 2 vCPU, 4 GB RAM, 60 GB disk, Windows Server 2025 Standard (Desktop Experience)

---

## 1. Active Directory, DNS & the Domain Controller

The server was given a static IP, then promoted to the first domain controller in a new
forest. DNS installs automatically with AD DS; forwarders were added so the DC can also
resolve external names.

```powershell
# Static IP, DNS pointing at itself
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.8.10 -PrefixLength 24 -DefaultGateway 192.168.8.2
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 192.168.8.10

# Promote to a new forest (DNS installs automatically)
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "emeka.lab.local" -DomainNetbiosName "EMEKA" -InstallDns -Force

# External name resolution
Add-DnsServerForwarder -IPAddress 192.168.8.2
Add-DnsServerForwarder -IPAddress 8.8.8.8
```

Health verified with `Get-ADDomain` and by confirming the `NTDS`, `ADWS`, `DNS`, and
`Netlogon` services are all running.

📸 `screenshots/ad-domain-healthy.png`

---

## 2. PowerShell Automation — Bulk User Provisioning

Rather than creating users by hand, a CSV of 15 users drives a single idempotent script
(`scripts/New-BulkADUsers.ps1`) that builds the full structure: a parent `Company` OU, a
sub-OU per department, a security group per department, and each user placed in the right
OU and added to the right group. Re-running the script safely skips anything that already
exists.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd C:\ad-lab\scripts
.\New-BulkADUsers.ps1
```

Result: **6 department OUs, 6 security groups, 15 users** created in one run.
A companion read-only script (`scripts/Get-ADInventoryReport.ps1`) lists OUs, group
membership counts, and all users, then exports a CSV report — useful for auditing.

📸 `screenshots/bulk-users-output.png`
📸 `screenshots/ad-inventory-report.png`
📸 `screenshots/aduc-company-ou.png`

---

## 3. DHCP

The DHCP role was installed, authorized in Active Directory, and configured with a scope,
options, and a reservation. The scope range sits below VMware's NAT pool to avoid overlap.

```powershell
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName "DC01.emeka.lab.local" -IPAddress 192.168.8.10

Add-DhcpServerv4Scope -Name "LAB-Clients" -StartRange 192.168.8.50 -EndRange 192.168.8.99 -SubnetMask 255.255.255.0 -State Active
Set-DhcpServerv4OptionValue -ScopeId 192.168.8.0 -DnsServer 192.168.8.10 -Force
Set-DhcpServerv4OptionValue -ScopeId 192.168.8.0 -DnsDomain "emeka.lab.local" -Router 192.168.8.2
Add-DhcpServerv4Reservation -ScopeId 192.168.8.0 -IPAddress 192.168.8.55 -ClientId "00-11-22-33-44-55" -Description "Reserved - Reception Printer"
```

Verified scope options include DNS Servers (opt 6), DNS Domain (opt 15), Router (opt 3),
and Lease (opt 51), plus the reservation.

📸 `screenshots/dhcp-verify.png`

---

## 4. File Server — Share & NTFS Permissions

A File Server role hosts two shares. Permissions are applied at **both** layers — share and
NTFS — and access is granted to the department security groups created in step 2, following
least privilege (the broad `BUILTIN\Users` group is removed from the Finance share).

```powershell
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools

New-Item -Path "C:\Shares\Finance" -ItemType Directory -Force
New-Item -Path "C:\Shares\Company" -ItemType Directory -Force

# Share-level permissions
New-SmbShare -Name "Finance" -Path "C:\Shares\Finance" -FullAccess "EMEKA\Domain Admins" -ChangeAccess "EMEKA\Finance-Team"
New-SmbShare -Name "Company" -Path "C:\Shares\Company" -FullAccess "EMEKA\Domain Admins" -ChangeAccess "EMEKA\Domain Users"

# NTFS permissions (least privilege)
icacls "C:\Shares\Finance" /inheritance:d
icacls "C:\Shares\Finance" /remove "BUILTIN\Users"
icacls "C:\Shares\Finance" /grant "EMEKA\Finance-Team:(OI)(CI)M"
icacls "C:\Shares\Finance" /grant "EMEKA\Domain Admins:(OI)(CI)F"
```

The key concept demonstrated: effective access is the **most restrictive** of share and NTFS
permissions, so both layers are configured deliberately rather than left open.

📸 `screenshots/fileserver-permissions.png`

---

## Repository Structure

```
windows-server-2025-ad-lab/
├── README.md
├── BUILD-RUNBOOK.md                 # step-by-step build from a blank VM
├── scripts/
│   ├── New-BulkADUsers.ps1          # CSV-driven bulk provisioning
│   └── Get-ADInventoryReport.ps1    # read-only AD inventory + CSV export
├── data/
│   └── new-users.csv                # sample user source data
└── screenshots/
    ├── ad-domain-healthy.png
    ├── bulk-users-output.png
    ├── ad-inventory-report.png
    ├── aduc-company-ou.png
    ├── dhcp-verify.png
    └── fileserver-permissions.png
```

---

## Notes

- Lab passwords (DSRM, the default user password in the script) are for an isolated lab
  environment only and are not production credentials.
- The lab runs on an isolated NAT network; no lab traffic leaves the host.

---

## Future Enhancements

- Join a Windows 10/11 client to the domain and apply Group Policy end-to-end
- Add a second domain controller and practise FSMO roles / replication
- Deploy software, drive mappings, and a logon banner via Group Policy
- Connect to Microsoft Entra ID for a hybrid-identity scenario
- Schedule AD system-state backups and add `dcdiag`/`repadmin` health reporting

---

## About

Built and documented by **Emeka (Chukwuemeka) Anolue** — Winnipeg, MB.
Part of an ongoing IT portfolio focused on Windows systems administration, networking,
and managed-services support.

🔗 GitHub: [github.com/mekzy3184](https://github.com/mekzy3184)
