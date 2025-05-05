<#
.SYNOPSIS
  Intune custom-compliance discovery script to verify Huntress EDR installation.

.DESCRIPTION
  Checks for the "HuntressAgent" Windows service; outputs a single boolean property
  named "HuntressEDR" which Intune will evaluate against the JSON rules.
#>

try {
    # The Huntress Agent Windows service is registered as "HuntressAgent"
    $svc = Get-Service -Name "HuntressAgent" -ErrorAction Stop
    $isInstalled = $true
}
catch {
    $isInstalled = $false
}

$results = @{
    "HuntressEDR" = $isInstalled
}

# Intune requires compressed, single-line JSON
return $results | ConvertTo-Json -Compress