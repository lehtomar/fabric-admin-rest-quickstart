<#
.SYNOPSIS
  Demo: calls a handful of Power BI Admin REST APIs as the signed-in user,
  prints concise output for each, and lists every URL that was called.

.EXAMPLE
  az login --tenant <tenant-id>
  .\Demo-AdminApiCalls.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('User','SP')] [string] $Mode = 'User',
    [string] $TenantId,
    [string] $ClientId,
    [string] $ClientSecret,
    [int]    $Top = 5
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Token --------------------------------------------------------------
$tokenArgs = @{ Mode = $Mode }
if ($Mode -eq 'SP') {
    $tokenArgs += @{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret }
}
$token = & "$here\Get-PbiAdminToken.ps1" @tokenArgs

# --- Helpers ------------------------------------------------------------
$script:CallLog = @()

function Call($label, $path) {
    $url = "https://api.powerbi.com/v1.0/myorg$path"
    Write-Host "`n>>> $label" -ForegroundColor Cyan
    Write-Host "    GET $url" -ForegroundColor DarkGray
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token -Path $path
        $sw.Stop()
        $script:CallLog += [pscustomobject]@{
            Label = $label; Method = 'GET'; Url = $url
            Status = 'OK'; Ms = $sw.ElapsedMilliseconds
        }
        return $resp
    } catch {
        $sw.Stop()
        $script:CallLog += [pscustomobject]@{
            Label = $label; Method = 'GET'; Url = $url
            Status = 'FAIL'; Ms = $sw.ElapsedMilliseconds
        }
        Write-Host "    FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# --- 1. Workspaces (GetGroupsAsAdmin) -----------------------------------
$groups = Call 'Workspaces (top)' "/admin/groups?`$top=$Top&`$expand=users"
if ($groups) {
    $groups.value |
        Select-Object name, id, state, type, isOnDedicatedCapacity |
        Format-Table -AutoSize | Out-String | Write-Host
}

# --- 2. Datasets (GetDatasetsAsAdmin) -----------------------------------
$datasets = Call 'Datasets (top)' "/admin/datasets?`$top=$Top"
if ($datasets) {
    $datasets.value |
        Select-Object name, id, configuredBy, isRefreshable |
        Format-Table -AutoSize | Out-String | Write-Host
}

# --- 3. Reports (GetReportsAsAdmin) -------------------------------------
$reports = Call 'Reports (top)' "/admin/reports?`$top=$Top"
if ($reports) {
    $reports.value |
        Select-Object name, id, reportType, webUrl |
        Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

# --- 4. Capacities (GetCapacitiesAsAdmin) -------------------------------
$caps = Call 'Capacities' '/admin/capacities'
if ($caps) {
    $caps.value |
        Select-Object displayName, id, sku, state, region |
        Format-Table -AutoSize | Out-String | Write-Host
}

# --- 5. Activity events (last 24h) --------------------------------------
$fmt     = 'yyyy-MM-ddTHH\:mm\:ss'
$inv     = [Globalization.CultureInfo]::InvariantCulture
$today   = (Get-Date).ToUniversalTime().Date  # API requires start+end on same UTC day
$startDt = $today.ToString($fmt, $inv)
$endDt   = $today.AddDays(1).AddSeconds(-1).ToString($fmt, $inv)
$activity = Call "Activity events ($($today.ToString('yyyy-MM-dd')) UTC)" `
    "/admin/activityevents?startDateTime='$startDt'&endDateTime='$endDt'"
if ($activity) {
    Write-Host ("    Returned {0} events." -f $activity.activityEventEntities.Count)
    $activity.activityEventEntities |
        Select-Object -First 5 CreationTime, UserId, Activity, WorkspaceName |
        Format-Table -AutoSize | Out-String | Write-Host
}

# --- Summary -----------------------------------------------------------
Write-Host "`n================ API call summary ================" -ForegroundColor Yellow
$script:CallLog | Format-Table Label, Method, Status, Ms, Url -AutoSize -Wrap |
    Out-String | Write-Host

Write-Host "Docs:" -ForegroundColor Yellow
@(
  'GetGroupsAsAdmin    https://learn.microsoft.com/rest/api/power-bi/admin/groups-get-groups-as-admin'
  'GetDatasetsAsAdmin  https://learn.microsoft.com/rest/api/power-bi/admin/datasets-get-datasets-as-admin'
  'GetReportsAsAdmin   https://learn.microsoft.com/rest/api/power-bi/admin/reports-get-reports-as-admin'
  'GetCapacitiesAsAdmin https://learn.microsoft.com/rest/api/power-bi/admin/capacities-get-capacities-as-admin'
  'GetActivityEvents   https://learn.microsoft.com/rest/api/power-bi/admin/get-activity-events'
) | ForEach-Object { Write-Host "  $_" }
