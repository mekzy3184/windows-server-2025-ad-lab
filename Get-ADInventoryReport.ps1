<#
.SYNOPSIS
    Generates a simple Active Directory inventory report for the emeka.lab.local
    domain: OUs, security groups with member counts, and an enabled-user list.

.DESCRIPTION
    Read-only. Prints a formatted summary to the console and exports a CSV of all
    users to the data folder. Useful for verifying a bulk import and for showing
    AD reporting/auditing skills in a portfolio.

.NOTES
    Author : Emeka (Chukwuemeka) Anolue
    Domain : emeka.lab.local
    Run on the domain controller in an elevated PowerShell session.
#>

Import-Module ActiveDirectory -ErrorAction Stop

$DomainDN  = "DC=emeka,DC=lab,DC=local"
$ExportDir = Join-Path $PSScriptRoot "..\data"
$ExportCsv = Join-Path $ExportDir "ad-user-report.csv"

Write-Host "`n===== ACTIVE DIRECTORY INVENTORY: emeka.lab.local =====`n" -ForegroundColor Cyan

# --- Organizational Units ----------------------------------------------------
Write-Host "ORGANIZATIONAL UNITS" -ForegroundColor Yellow
Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN |
    Select-Object Name, DistinguishedName |
    Sort-Object Name |
    Format-Table -AutoSize

# --- Security groups with member counts --------------------------------------
Write-Host "SECURITY GROUPS (department teams)" -ForegroundColor Yellow
Get-ADGroup -Filter "Name -like '*-Team'" |
    Select-Object Name,
        @{Name="Members"; Expression={ (Get-ADGroupMember $_.Name | Measure-Object).Count }} |
    Sort-Object Name |
    Format-Table -AutoSize

# --- Enabled users -----------------------------------------------------------
Write-Host "ENABLED USER ACCOUNTS" -ForegroundColor Yellow
$report = Get-ADUser -Filter 'Enabled -eq $true' -Properties Department, Title |
    Select-Object Name, SamAccountName, Department, Title |
    Sort-Object Department, Name

$report | Format-Table -AutoSize

# --- Export ------------------------------------------------------------------
$report | Export-Csv -Path $ExportCsv -NoTypeInformation
Write-Host "User report exported to: $ExportCsv" -ForegroundColor Green
Write-Host "Total enabled users: $($report.Count)`n" -ForegroundColor Cyan
