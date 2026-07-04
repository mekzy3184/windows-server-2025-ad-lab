<#
.SYNOPSIS
    Bulk-creates Active Directory Organizational Units, security groups, and user
    accounts for the emeka.lab.local domain from a CSV file.

.DESCRIPTION
    Reads a CSV of users (FirstName, LastName, SamAccountName, Department, JobTitle)
    and, for each unique Department:
        - creates a department OU under the parent "Company" OU (if missing)
        - creates a department security group (if missing)
    Then creates each user inside their department OU, sets attributes, and adds
    them to the matching department group. The script is idempotent: it skips any
    OU, group, or user that already exists, so it is safe to re-run.

.NOTES
    Author : Emeka (Chukwuemeka) Anolue
    Domain : emeka.lab.local
    Lab     : Windows Server 2025 Active Directory Home Lab
    Run on the domain controller in an elevated PowerShell session.
#>

# --- Configuration -----------------------------------------------------------
$DomainDN       = "DC=emeka,DC=lab,DC=local"
$ParentOUName   = "Company"
$ParentOUPath   = "OU=$ParentOUName,$DomainDN"
$CsvPath        = Join-Path $PSScriptRoot "..\data\new-users.csv"
$UpnSuffix      = "emeka.lab.local"
$DefaultPassword = ConvertTo-SecureString "P@ssw0rd2026!" -AsPlainText -Force

# --- Pre-flight checks -------------------------------------------------------
Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $CsvPath)) {
    Write-Host "ERROR: CSV file not found at $CsvPath" -ForegroundColor Red
    exit 1
}

$Users = Import-Csv $CsvPath
Write-Host "Loaded $($Users.Count) users from CSV." -ForegroundColor Cyan

# --- Ensure the parent "Company" OU exists -----------------------------------
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ParentOUName'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $ParentOUName -Path $DomainDN -ProtectedFromAccidentalDeletion $false
    Write-Host "Created parent OU: $ParentOUName" -ForegroundColor Green
} else {
    Write-Host "Parent OU already exists: $ParentOUName" -ForegroundColor DarkGray
}

# --- Create department OUs and groups ----------------------------------------
$Departments = $Users | Select-Object -ExpandProperty Department -Unique

foreach ($dept in $Departments) {
    $deptOUPath = "OU=$dept,$ParentOUPath"

    # Department OU
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $ParentOUPath -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $dept -Path $ParentOUPath -ProtectedFromAccidentalDeletion $false
        Write-Host "  Created OU: $dept" -ForegroundColor Green
    } else {
        Write-Host "  OU already exists: $dept" -ForegroundColor DarkGray
    }

    # Department security group
    $groupName = "$dept-Team"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $deptOUPath
        Write-Host "  Created group: $groupName" -ForegroundColor Green
    } else {
        Write-Host "  Group already exists: $groupName" -ForegroundColor DarkGray
    }
}

# --- Create users ------------------------------------------------------------
$created = 0
$skipped = 0

foreach ($u in $Users) {
    $deptOUPath = "OU=$($u.Department),$ParentOUPath"
    $displayName = "$($u.FirstName) $($u.LastName)"
    $upn = "$($u.SamAccountName)@$UpnSuffix"

    if (Get-ADUser -Filter "SamAccountName -eq '$($u.SamAccountName)'" -ErrorAction SilentlyContinue) {
        Write-Host "  User already exists, skipping: $($u.SamAccountName)" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    New-ADUser `
        -Name $displayName `
        -GivenName $u.FirstName `
        -Surname $u.LastName `
        -SamAccountName $u.SamAccountName `
        -UserPrincipalName $upn `
        -DisplayName $displayName `
        -Title $u.JobTitle `
        -Department $u.Department `
        -Path $deptOUPath `
        -AccountPassword $DefaultPassword `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    # Add to the department group
    Add-ADGroupMember -Identity "$($u.Department)-Team" -Members $u.SamAccountName

    Write-Host "  Created user: $displayName  ($($u.SamAccountName))  ->  $($u.Department)-Team" -ForegroundColor Green
    $created++
}

# --- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Bulk provisioning complete." -ForegroundColor Cyan
Write-Host "   Users created : $created" -ForegroundColor Green
Write-Host "   Users skipped : $skipped" -ForegroundColor DarkGray
Write-Host "   Departments   : $($Departments.Count)" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
