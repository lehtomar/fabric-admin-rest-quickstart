<#
.SYNOPSIS
  Diagnoses Power BI Admin REST API access for either a signed-in user
  (delegated, via 'az login') or a service principal.

.DESCRIPTION
  User mode is the default and the easiest path: signed-in user just needs the
  'Fabric administrator' (or legacy 'Power BI administrator') Entra role.
  No tenant toggles, no security group, no app registration required.

.EXAMPLE
  # As the signed-in user (recommended easiest path):
  az login --tenant <tenant-id>
  .\Test-AdminApiAccess.ps1 -TestWorkspaceId 'xxxxxxxx-...'

.EXAMPLE
  # As a service principal:
  .\Test-AdminApiAccess.ps1 -Mode SP `
      -TenantId $env:PBI_TENANT_ID `
      -ClientId $env:PBI_CLIENT_ID `
      -ClientSecret $env:PBI_CLIENT_SECRET `
      -TestWorkspaceId 'xxxxxxxx-...'
#>
[CmdletBinding()]
param(
    [ValidateSet('User','SP')] [string] $Mode = 'User',
    [string] $TenantId,
    [string] $ClientId,
    [string] $ClientSecret,
    [string] $TestWorkspaceId
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }

# --- Layer 1: token --------------------------------------------------------
Step 1 "Acquiring token  (mode=$Mode, audience=powerbi)"
if ($Mode -eq 'User') {
    $token = & "$here\Get-PbiAdminToken.ps1" -Mode User
} else {
    $token = & "$here\Get-PbiAdminToken.ps1" -Mode SP -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
}
if (-not $token) { throw "Token acquisition failed." }
Write-Host "  OK (len=$($token.Length))" -ForegroundColor Green

# Decode useful claims for diagnostics
$payload = $token.Split('.')[1].Replace('-','+').Replace('_','/')
switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json

if ($Mode -eq 'User') {
    Write-Host "  upn=$($claims.upn)  oid=$($claims.oid)  aud=$($claims.aud)"
    Write-Host "  (User mode: success requires 'Fabric administrator' or 'Power BI administrator' role on this user.)"
} else {
    Write-Host "  appid=$($claims.appid)  oid=$($claims.oid)  aud=$($claims.aud)"
}

# --- Layer 2: basic Power BI API ------------------------------------------
Step 2 "Calling /groups  (any authenticated PBI user/SP should succeed)"
try {
    & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token -Path '/groups?$top=1' | Out-Null
    Write-Host "  OK – basic Power BI API works." -ForegroundColor Green
} catch {
    if ($Mode -eq 'SP') {
        Write-Host "  FAIL – enable tenant setting 'Allow service principals to use Power BI APIs' for the SP's group." -ForegroundColor Red
    } else {
        Write-Host "  FAIL – token is bad or user has no Power BI license/access. Check 'az account show' and re-login." -ForegroundColor Red
    }
    return
}

# --- Layer 3a: read-only admin API ----------------------------------------
Step 3a "Calling /admin/groups  (requires admin rights)"
try {
    & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token -Path '/admin/groups?$top=1' | Out-Null
    Write-Host "  OK – read-only admin API works." -ForegroundColor Green
} catch {
    if ($Mode -eq 'User') {
        Write-Host "  FAIL – signed-in user needs the 'Fabric administrator' (or 'Power BI administrator') Entra role." -ForegroundColor Red
        Write-Host "         Assign in: Entra admin center -> Roles and administrators -> Fabric administrator." -ForegroundColor Yellow
    } else {
        Write-Host "  FAIL – enable 'Service principals can access read-only admin APIs' and add SP's SG." -ForegroundColor Red
    }
    return
}

# --- Layer 3b: update admin API -------------------------------------------
if (-not $TestWorkspaceId) {
    Write-Host "`n[3b] Skipped – pass -TestWorkspaceId to probe write/update access." -ForegroundColor Yellow
    return
}

Step 3b "Calling admin UPDATE endpoint on workspace $TestWorkspaceId"
try {
    & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token `
        -Path "/admin/groups/$TestWorkspaceId/users" | Out-Null
    Write-Host "  Read on admin/groups/{id}/users: OK"
} catch {
    Write-Host "  Read on admin/groups/{id}/users failed – check workspace id." -ForegroundColor Red
    return
}

# Write probe: re-add the caller itself as Admin (idempotent if already there).
if ($Mode -eq 'User') {
    $probeBody = @{
        emailAddress         = $claims.upn
        groupUserAccessRight = 'Admin'
        principalType        = 'User'
    }
} else {
    $probeBody = @{
        identifier           = $claims.oid
        groupUserAccessRight = 'Admin'
        principalType        = 'App'
    }
}

try {
    & "$here\Invoke-PbiAdminApi.ps1" -AccessToken $token `
        -Path "/admin/groups/$TestWorkspaceId/users" -Method POST -Body $probeBody | Out-Null
    Write-Host "  OK – UPDATE admin API works. All layers healthy." -ForegroundColor Green
} catch {
    Write-Host "  FAIL on update probe." -ForegroundColor Red
    if ($Mode -eq 'User') {
        Write-Host "  --> User mode: confirm the 'Fabric administrator' role is actually active (sign out / sign back in," -ForegroundColor Yellow
        Write-Host "      role can take ~15 min to propagate). PIM-eligible roles must be ACTIVATED, not just eligible." -ForegroundColor Yellow
    } else {
        Write-Host "  --> Enable 'Service principals can access admin APIs used for updates' for the SP's SG, wait ~15 min." -ForegroundColor Yellow
    }
}
