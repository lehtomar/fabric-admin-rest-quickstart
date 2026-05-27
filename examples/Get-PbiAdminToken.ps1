<#
.SYNOPSIS
  Get an access token for the Power BI / Fabric Admin REST API.

.DESCRIPTION
  Two modes:
    - User  (default): reuses your existing 'az login' session via Azure CLI.
                       The signed-in user needs the 'Fabric administrator'
                       (or legacy 'Power BI administrator') Entra role to call
                       /admin endpoints.
    - SP            :  client-credentials flow with a service principal.
                       Requires the tenant settings + security group setup.

.EXAMPLE
  # User auth (delegated, via az login):
  $token = .\Get-PbiAdminToken.ps1

.EXAMPLE
  # Service principal auth:
  $token = .\Get-PbiAdminToken.ps1 -Mode SP `
             -TenantId     $env:PBI_TENANT_ID `
             -ClientId     $env:PBI_CLIENT_ID `
             -ClientSecret $env:PBI_CLIENT_SECRET
#>
[CmdletBinding()]
param(
    [ValidateSet('User','SP')] [string] $Mode = 'User',
    [string] $TenantId,
    [string] $ClientId,
    [string] $ClientSecret
)

$resource = 'https://analysis.windows.net/powerbi/api'

if ($Mode -eq 'User') {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI (az) not found. Install it or use -Mode SP."
    }
    # Use existing az login. --resource form returns a token for any audience
    # without needing the audience to be pre-registered as an az CLI scope.
    $json = az account get-access-token --resource $resource --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        throw "az account get-access-token failed. Run 'az login' first (and 'az login --tenant <id>' if you have multiple tenants)."
    }
    return ($json | ConvertFrom-Json).accessToken
}

# --- SP mode ---
foreach ($p in 'TenantId','ClientId','ClientSecret') {
    if (-not $PSBoundParameters[$p]) { throw "-$p is required when -Mode SP." }
}

$body = @{
    grant_type    = 'client_credentials'
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "$resource/.default"
}

$resp = Invoke-RestMethod `
    -Method Post `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body $body

return $resp.access_token
