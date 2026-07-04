# Windows Server 2025 AD Lab — Build Run-Book

A single, ordered checklist to build the entire lab from a blank VM to a fully
configured domain controller with Active Directory, DNS, DHCP, bulk-provisioned
users, and a file server. Every command is meant to run **on the domain controller**
in an **elevated PowerShell** session unless stated otherwise.

**Domain:** `emeka.lab.local`  |  **NetBIOS:** `EMEKA`  |  **DC name:** `DC01`  |  **DC IP:** `192.168.8.10`

> ⚠️ **Golden rules learned the hard way**
> 1. Store all VMs in `C:\Virtual Machines` — **never** in Documents or any Google-Drive-synced folder.
> 2. Confirm Google Drive is **not** syncing `C:\Virtual Machines`.
> 3. Use **VMware Workstation Pro only** — never open Player (causes file-lock errors).
> 4. Take a **snapshot** after each milestone (Pro only).
> 5. Run **one VM at a time** on 16 GB RAM.

---

## Phase 1 — Create the VM (VMware Workstation Pro)

1. **File → New Virtual Machine → Custom (advanced)**
2. Hardware compatibility: **Workstation 25H2 or later** → Next
3. **"I will install the operating system later"** → Next  *(skips Easy Install)*
4. Guest OS: **Microsoft Windows → Windows Server 2025** → Next
5. Name: `DC01` — **Location: `C:\Virtual Machines\DC01`** → Next
6. Processors: **2 cores** (1 processor × 2 cores) → Next
7. Memory: **4096 MB** → Next
8. Network: **NAT** → Next
9. I/O controller: **LSI Logic SAS** → Next
10. Disk type: **NVMe** (default) → Next
11. **Create a new virtual disk**, **60 GB**, **Split into multiple files**, do **not** pre-allocate → Next → Finish
12. **Edit VM settings → CD/DVD → Use ISO image file** → select the Server 2025 ISO → OK
13. **Power on.**

## Phase 2 — Install Windows Server 2025

1. At the edition screen choose **Windows Server 2025 Standard Evaluation (Desktop Experience)** — the GUI version.
2. **Custom install** → select the 60 GB disk → Next.
3. Let it copy files and reboot (~15–20 min).
4. Set a strong **Administrator** password at first login.

## Phase 3 — VMware Tools + baseline snapshot

1. **VM menu → Install VMware Tools** (mounts the disc).
2. In the server: **File Explorer → This PC → DVD Drive → run `setup`** → Typical → Install → reboot.
3. Confirm Tools: mouse moves in/out freely and the desktop auto-resizes.
4. **VM → Snapshot → Take Snapshot** → name `Fresh install - GUI`.

---

## Phase 4 — Server configuration (elevated PowerShell)

### 4.1 Rename the server
```powershell
Rename-Computer -NewName "DC01" -Restart
```

### 4.2 Set a static IP (after reboot)
```powershell
# Check the interface name and current network first
Get-NetIPConfiguration

# If the adapter shows "Disconnected", reconnect it:
#   VM → Settings → Network Adapter → tick "Connected"
#   then: Restart-NetAdapter -Name "Ethernet0"

Set-NetIPInterface -InterfaceAlias "Ethernet0" -Dhcp Disabled
New-NetIPAddress -InterfaceAlias "Ethernet0" -IPAddress 192.168.8.10 -PrefixLength 24 -DefaultGateway 192.168.8.2
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 192.168.8.10
```
> If your NAT gateway is **not** `192.168.8.2`, run `Get-NetIPConfiguration`, read your
> gateway, and substitute the first three octets everywhere in this run-book.

### 4.3 Verify
```powershell
Get-NetIPConfiguration
```
Confirm `IPv4Address : 192.168.8.10`.

---

## Phase 5 — Promote to Domain Controller

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Install-ADDSForest -DomainName "emeka.lab.local" -DomainNetbiosName "EMEKA" -InstallDns -Force
```
- Set a **DSRM password** when prompted (write it down).
- Yellow warnings are normal. The server **reboots automatically**.
- If it errors with *"role change in progress / needs restart"*: run `Restart-Computer`, then re-run the `Install-ADDSForest` line.

After reboot you log in as **`EMEKA\Administrator`**.

### 5.1 Verify the DC is healthy
```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode, DistinguishedName
whoami        # should return: emeka\administrator
dcdiag /q     # no output = all tests passed
```

### 5.2 Add DNS forwarders (internet name resolution)
```powershell
Add-DnsServerForwarder -IPAddress 192.168.8.2
Add-DnsServerForwarder -IPAddress 8.8.8.8
Resolve-DnsName google.com     # should return IP addresses
```

### 5.3 Snapshot
**VM → Snapshot → Take Snapshot** → name `DC healthy - AD DNS`.

---

## Phase 6 — Bulk-provision OUs, groups, and users

1. On the DC, create the folder layout and copy the scripts in:
   ```
   C:\ad-lab\
   ├── scripts\   (New-BulkADUsers.ps1, Get-ADInventoryReport.ps1)
   └── data\      (new-users.csv)
   ```
2. Run:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   cd C:\ad-lab\scripts
   .\New-BulkADUsers.ps1
   ```
   Creates the `Company` OU, 6 department OUs, 6 security groups, and 15 users. **Screenshot the output.**
3. Audit / verify:
   ```powershell
   .\Get-ADInventoryReport.ps1
   ```
4. GUI view: **Tools → Active Directory Users and Computers → emeka.lab.local → Company**. **Screenshot the tree.**

---

## Phase 7 — DHCP

```powershell
Install-WindowsFeature -Name DHCP -IncludeManagementTools

Add-DhcpServerInDC -DnsName "DC01.emeka.lab.local" -IPAddress 192.168.8.10

# Clear the Server Manager post-install flag
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2
Restart-Service DHCPServer

# Scope (kept below VMware's NAT DHCP pool to avoid overlap)
Add-DhcpServerv4Scope -Name "LAB-Clients" -StartRange 192.168.8.50 -EndRange 192.168.8.99 -SubnetMask 255.255.255.0 -State Active

# Scope options — use -Force on the DNS server so validation doesn't reject the DC
Set-DhcpServerv4OptionValue -ScopeId 192.168.8.0 -DnsServer 192.168.8.10 -Force
Set-DhcpServerv4OptionValue -ScopeId 192.168.8.0 -DnsDomain "emeka.lab.local" -Router 192.168.8.2

# A reservation (fixed IP pinned to a MAC)
Add-DhcpServerv4Reservation -ScopeId 192.168.8.0 -IPAddress 192.168.8.55 -ClientId "00-11-22-33-44-55" -Description "Reserved - Reception Printer"
```

### Verify (screenshot these)
```powershell
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 192.168.8.0    # look for OptionId 6 = DNS Servers
Get-DhcpServerv4Reservation -ScopeId 192.168.8.0
```
GUI view: **Tools → DHCP → server → IPv4 → LAB-Clients**.

---

## Phase 8 — File Server with share + NTFS permissions

```powershell
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools

New-Item -Path "C:\Shares\Finance" -ItemType Directory -Force
New-Item -Path "C:\Shares\Company" -ItemType Directory -Force

# Share-level permissions
New-SmbShare -Name "Finance" -Path "C:\Shares\Finance" -FullAccess "EMEKA\Domain Admins" -ChangeAccess "EMEKA\Finance-Team"
New-SmbShare -Name "Company" -Path "C:\Shares\Company" -FullAccess "EMEKA\Domain Admins" -ChangeAccess "EMEKA\Domain Users"

# NTFS permissions (least privilege: lock Finance to Finance-Team + admins)
icacls "C:\Shares\Finance" /inheritance:d
icacls "C:\Shares\Finance" /remove "BUILTIN\Users"
icacls "C:\Shares\Finance" /grant "EMEKA\Finance-Team:(OI)(CI)M"
icacls "C:\Shares\Finance" /grant "EMEKA\Domain Admins:(OI)(CI)F"
```

### Verify (screenshot these)
```powershell
Get-SmbShare
Get-SmbShareAccess -Name "Finance"
icacls "C:\Shares\Finance"
```
GUI view: right-click `C:\Shares\Finance` → **Properties → Security** (NTFS) and **Sharing → Advanced Sharing → Permissions** (share).

---

## Phase 9 — Wrap up

- Take a final snapshot: `Lab complete - AD DNS DHCP FS`.
- Capture any remaining screenshots into `screenshots/`.
- Commit everything to GitHub:
  ```bash
  git init
  git add .
  git commit -m "Windows Server 2025 AD lab: AD, DNS, DHCP, file server, automation"
  git branch -M main
  git remote add origin https://github.com/mekzy3184/windows-server-2025-ad-lab.git
  git push -u origin main
  ```

---

## Quick reference

| Item | Value |
|------|-------|
| Domain | `emeka.lab.local` |
| NetBIOS | `EMEKA` |
| DC hostname | `DC01` |
| DC static IP | `192.168.8.10` |
| Gateway / forwarder | `192.168.8.2` (VMware NAT) |
| DHCP scope | `192.168.8.50 – 192.168.8.99` |
| DSRM password | *(kept private — not stored in repo)* |
| Default user password | `P@ssw0rd2026!` (lab only; users must change at logon) |

---

*Built and documented by Emeka (Chukwuemeka) Anolue — Winnipeg, MB.*
