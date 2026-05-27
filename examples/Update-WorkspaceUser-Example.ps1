<#
.SYNOPSIS
  End-to-end example of the failing scenario:
  service principal adds a user as Admin to an arbitrary workspace via the
  Power BI Admin REST API.

  Endpoint: POST /v1.0/myorg/admin/groups/{groupId}/users
  Requires tenant setting: "Service principals can access admin APIs used for updates"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $ClientId,
    [Parameter(Mandatory)] [string] $ClientSecret,
    [Parameter(Mandatory)] [string] $WorkspaceId,
    [Parameter(Mandatory)] [string] $UserPrincipalName,
    [ValidateSet('Admin','Member','Contributor','Viewer')]
    [string] $Role = 'Member'
)

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$token = & "$here\Get-PbiAdminToken.ps1" -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

$body = @{
    identifier            = $UserPrincipalName
    groupUserAccessRight  = $Role
    principalType         = 'User'
}

& "$here\Invoke-PbiAdminApi.ps1" `
    -AccessToken $token `
    -Path        "/admin/groups/$WorkspaceId/users" `
    -Method      POST `
    -Body        $body

Write-Host "Added $UserPrincipalName as $Role to workspace $WorkspaceId" -ForegroundColor Green
