<#
.SYNOPSIS
  Idempotently creates the Entra security group used by the Power BI admin
  tenant settings and adds the given service principal to it.

.NOTES
  Requires Microsoft.Graph PowerShell module and Application.ReadWrite.All +
  Group.ReadWrite.All consent.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AppClientId,                 # SP's App (client) ID
    [string] $GroupDisplayName = 'sg-powerbi-admin-api',
    [string] $GroupMailNickname = 'sg-powerbi-admin-api'
)

Import-Module Microsoft.Graph.Groups        -ErrorAction Stop
Import-Module Microsoft.Graph.Applications  -ErrorAction Stop

Connect-MgGraph -Scopes 'Application.ReadWrite.All','Group.ReadWrite.All' | Out-Null

$sp = Get-MgServicePrincipal -Filter "AppId eq '$AppClientId'"
if (-not $sp) { throw "No service principal found for AppId $AppClientId" }

$group = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'" -ConsistencyLevel eventual -CountVariable c
if (-not $group) {
    Write-Host "Creating security group $GroupDisplayName..."
    $group = New-MgGroup `
        -DisplayName     $GroupDisplayName `
        -MailNickname    $GroupMailNickname `
        -SecurityEnabled `
        -MailEnabled:$false
} else {
    Write-Host "Group $GroupDisplayName already exists ($($group.Id))."
}

$existing = Get-MgGroupMember -GroupId $group.Id -All | Where-Object Id -eq $sp.Id
if ($existing) {
    Write-Host "SP $($sp.DisplayName) already a member."
} else {
    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $sp.Id
    Write-Host "Added SP $($sp.DisplayName) to $GroupDisplayName."
}

Write-Host ""
Write-Host "Next step: in Fabric Admin portal -> Tenant settings -> Admin API settings, scope BOTH"
Write-Host "  - 'Service principals can access read-only admin APIs'"
Write-Host "  - 'Service principals can access admin APIs used for updates'"
Write-Host "to group: $GroupDisplayName ($($group.Id))"
