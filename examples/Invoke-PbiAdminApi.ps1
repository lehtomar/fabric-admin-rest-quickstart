<#
.SYNOPSIS
  Thin wrapper around Invoke-RestMethod that targets the Power BI REST API
  and surfaces the real error body (PBI often returns 401/404 with a useful
  X-PowerBI-Error-Info header and JSON body that Invoke-RestMethod hides).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AccessToken,
    [Parameter(Mandatory)] [string] $Path,                # e.g. /admin/groups?$top=10
    [ValidateSet('GET','POST','PUT','PATCH','DELETE')]
    [string] $Method = 'GET',
    [object] $Body
)

$uri     = "https://api.powerbi.com/v1.0/myorg$Path"
$headers = @{ Authorization = "Bearer $AccessToken" }

$params = @{
    Method  = $Method
    Uri     = $uri
    Headers = $headers
}
if ($PSBoundParameters.ContainsKey('Body')) {
    $params.ContentType = 'application/json'
    $params.Body        = ($Body | ConvertTo-Json -Depth 10)
}

try {
    Invoke-RestMethod @params
}
catch {
    $status = $null; $errCode = $null; $bodyTxt = $null
    $resp   = $_.Exception.Response

    if ($resp) {
        $status = [int]$resp.StatusCode
        # X-PowerBI-Error-Info header (works in both PS 5.1 WebResponse and PS 7 HttpResponseMessage)
        try {
            if ($resp.Headers -is [System.Collections.Specialized.NameValueCollection]) {
                $errCode = $resp.Headers['X-PowerBI-Error-Info']
            } else {
                $h = $resp.Headers | Where-Object { $_.Key -eq 'X-PowerBI-Error-Info' } | Select-Object -First 1
                if ($h) { $errCode = ($h.Value -join ',') }
            }
        } catch {}
    }

    # PS 7 exposes the body here; PS 5.1 needs the stream
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        $bodyTxt = $_.ErrorDetails.Message
    } elseif ($resp -and $resp.PSObject.Methods.Name -contains 'GetResponseStream') {
        try {
            $reader  = New-Object IO.StreamReader($resp.GetResponseStream())
            $bodyTxt = $reader.ReadToEnd()
        } catch {}
    }

    Write-Host ""
    Write-Host "Power BI API call failed" -ForegroundColor Red
    Write-Host "  HTTP status : $status"
    Write-Host "  Error code  : $errCode"
    Write-Host "  URI         : $uri"
    Write-Host "  Body        : $bodyTxt"
    throw
}
