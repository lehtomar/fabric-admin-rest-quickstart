<#
.SYNOPSIS
  Lists all workspace admins across the tenant using the Power BI Admin REST
  API (GetGroupsAsAdmin with $expand=users) and writes a Markdown report.

.DESCRIPTION
  Pages through /admin/groups (page size up to 5000), filters each workspace's
  users for groupUserAccessRight = 'Admin', and exports a Markdown file
  grouping admins by workspace plus a reverse index (admin -> workspaces).

  Caller must have the Fabric administrator (or legacy Power BI administrator)
  Entra role. Use -Mode SP for service-principal auth (see Get-PbiAdminToken.ps1).

.EXAMPLE
  az login --tenant <tenant-id>
  .\Export-WorkspaceAdmins.ps1

.EXAMPLE
  .\Export-WorkspaceAdmins.ps1 -OutputPath .\admins.md -IncludeOrphaned
#>
[CmdletBinding()]
param(
    [ValidateSet('User','SP')] [string] $Mode = 'User',
    [string] $TenantId,
    [string] $ClientId,
    [string] $ClientSecret,
    [string] $OutputPath = (Join-Path (Get-Location) "workspace-admins-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"),
    [int]    $PageSize = 1000,
    [switch] $IncludeOrphaned   # also list workspaces that have no Admin users
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Token --------------------------------------------------------------
$tokenArgs = @{ Mode = $Mode }
if ($Mode -eq 'SP') {
    $tokenArgs += @{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret }
}
$token = & "$here\Get-PbiAdminToken.ps1" @tokenArgs

# --- Page through workspaces -------------------------------------------
$workspaces = New-Object System.Collections.Generic.List[object]
$skip = 0
do {
    $path = "/admin/groups?`$top=$PageSize&`$skip=$skip&`$expand=users"
    Write-Host ">>> GET $path" -ForegroundColor DarkGray
    $resp = & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token -Path $path
    $batch = @($resp.value)
    if ($batch.Count -gt 0) { $workspaces.AddRange([object[]]$batch) }
    Write-Host ("    +{0} workspaces (total {1})" -f $batch.Count, $workspaces.Count)
    $skip += $batch.Count
} while ($batch.Count -eq $PageSize)

Write-Host ("Fetched {0} workspaces total." -f $workspaces.Count) -ForegroundColor Green

# --- Build admin index --------------------------------------------------
# Per-workspace admin list
$wsAdmins = foreach ($w in $workspaces) {
    $admins = @($w.users | Where-Object { $_.groupUserAccessRight -eq 'Admin' })
    [pscustomobject]@{
        WorkspaceName = $w.name
        WorkspaceId   = $w.id
        State         = $w.state
        Type          = $w.type
        OnCapacity    = [bool]$w.isOnDedicatedCapacity
        Admins        = $admins
    }
}

# Reverse index: admin identity -> workspaces
$adminMap = @{}
foreach ($w in $wsAdmins) {
    foreach ($a in $w.Admins) {
        $key = if ($a.identifier) { $a.identifier } else { $a.emailAddress }
        if (-not $key) { continue }
        if (-not $adminMap.ContainsKey($key)) {
            $adminMap[$key] = [pscustomobject]@{
                Identifier    = $key
                DisplayName   = $a.displayName
                PrincipalType = $a.principalType
                Workspaces    = New-Object System.Collections.Generic.List[object]
            }
        }
        $adminMap[$key].Workspaces.Add([pscustomobject]@{
            Name = $w.WorkspaceName; Id = $w.WorkspaceId
        }) | Out-Null
    }
}

# --- Write Markdown -----------------------------------------------------
$totalAdminAssignments = ($wsAdmins | ForEach-Object { $_.Admins.Count } | Measure-Object -Sum).Sum
$wsWithNoAdmin         = @($wsAdmins | Where-Object { $_.Admins.Count -eq 0 })
$generated             = (Get-Date).ToString('u')

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Power BI / Fabric Workspace Admins")
[void]$sb.AppendLine()
[void]$sb.AppendLine("_Generated: $generated_")
[void]$sb.AppendLine()
[void]$sb.AppendLine("## Summary")
[void]$sb.AppendLine()
[void]$sb.AppendLine("| Metric | Value |")
[void]$sb.AppendLine("|---|---:|")
[void]$sb.AppendLine("| Workspaces scanned | $($workspaces.Count) |")
[void]$sb.AppendLine("| Total admin assignments | $totalAdminAssignments |")
[void]$sb.AppendLine("| Unique admin principals | $($adminMap.Count) |")
[void]$sb.AppendLine("| Workspaces with no Admin user | $($wsWithNoAdmin.Count) |")
[void]$sb.AppendLine()

# Admins by workspace
[void]$sb.AppendLine("## Admins by workspace")
[void]$sb.AppendLine()
foreach ($w in ($wsAdmins | Sort-Object WorkspaceName)) {
    if ($w.Admins.Count -eq 0 -and -not $IncludeOrphaned) { continue }
    [void]$sb.AppendLine("### $($w.WorkspaceName)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("- Workspace ID: ``$($w.WorkspaceId)``")
    [void]$sb.AppendLine("- State: $($w.State) | Type: $($w.Type) | On capacity: $($w.OnCapacity)")
    [void]$sb.AppendLine()
    if ($w.Admins.Count -eq 0) {
        [void]$sb.AppendLine("> No users with Admin role.")
        [void]$sb.AppendLine()
        continue
    }
    [void]$sb.AppendLine("| Display name | Principal type | Identifier / email |")
    [void]$sb.AppendLine("|---|---|---|")
    foreach ($a in ($w.Admins | Sort-Object displayName)) {
        $id   = if ($a.identifier)   { $a.identifier }   else { $a.emailAddress }
        $name = if ($a.displayName)  { $a.displayName }  else { '_(unknown)_' }
        $pt   = if ($a.principalType){ $a.principalType }else { '' }
        [void]$sb.AppendLine("| $name | $pt | ``$id`` |")
    }
    [void]$sb.AppendLine()
}

# Reverse index
[void]$sb.AppendLine("## Workspaces by admin")
[void]$sb.AppendLine()
[void]$sb.AppendLine("| Admin | Type | # Workspaces | Workspaces |")
[void]$sb.AppendLine("|---|---|---:|---|")
foreach ($a in ($adminMap.Values | Sort-Object DisplayName)) {
    $names = ($a.Workspaces | Sort-Object Name | ForEach-Object { $_.Name }) -join '; '
    $name  = if ($a.DisplayName) { $a.DisplayName } else { $a.Identifier }
    [void]$sb.AppendLine("| $name | $($a.PrincipalType) | $($a.Workspaces.Count) | $names |")
}

$sb.ToString() | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host ""
Write-Host "Wrote report: $OutputPath" -ForegroundColor Green
