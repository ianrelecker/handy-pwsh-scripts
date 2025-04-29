# 1. Sign in to Azure
Connect-AzAccount
#  [oai_citation:3‡Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/az.accounts/connect-azaccount?view=azps-13.3.0&utm_source=chatgpt.com)

# 2. Variables
$rgName                  = "RG-LogAnalytics" 
$location                = "westus3"
$workspaceName           = "LA-LogAnalytics"
$diagnosticSettingName   = "EntraID-Diagnostics"
$apiVersion              = "2017-04-01"  # Tenant-scope API for Entra ID diagSettings
#  [oai_citation:4‡Microsoft Learn](https://learn.microsoft.com/en-us/azure/templates/microsoft.aadiam/2017-04-01/diagnosticsettings?utm_source=chatgpt.com)

# 3. Create Resource Group
New-AzResourceGroup -Name $rgName -Location $location
#  [oai_citation:5‡Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/az.resources/new-azresourcegroup?view=azps-13.3.0&utm_source=chatgpt.com)

# 4. Create Log Analytics workspace with 90-day retention
$workspace = New-AzOperationalInsightsWorkspace `
  -ResourceGroupName $rgName `
  -Name $workspaceName `
  -Location $location `
  -Sku Standard `
  -RetentionInDays 90
#  [oai_citation:6‡Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/az.operationalinsights/new-azoperationalinsightsworkspace?view=azps-13.4.0&utm_source=chatgpt.com)

# 5. Acquire an ARM access token for REST calls
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
#  [oai_citation:7‡Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/az.accounts/get-azaccesstoken?view=azps-13.3.0&utm_source=chatgpt.com)

# 6. Build diagnostic setting request body
$body = @{
  properties = @{
    workspaceId = $workspace.ResourceId
    logs        = @(
      @{ category = "AuditLogs";    enabled = $true; retentionPolicy = @{ days = 0; enabled = $false } },
      @{ category = "SignInLogs";   enabled = $true; retentionPolicy = @{ days = 0; enabled = $false } }
    )
  }
} | ConvertTo-Json -Depth 5
#  [oai_citation:8‡Microsoft Learn](https://learn.microsoft.com/en-us/azure/templates/microsoft.aadiam/2017-04-01/diagnosticsettings?utm_source=chatgpt.com)

# 7. Invoke REST API to create tenant-level diagnostic setting
$uri = "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/$diagnosticSettingName?api-version=$apiVersion"
Invoke-RestMethod -Method Put -Uri $uri -Headers @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
} -Body $body

Write-Output "Diagnostic setting '$diagnosticSettingName' created successfully."
#  [oai_citation:9‡Stack Overflow](https://stackoverflow.com/questions/77758811/create-azure-entra-id-diagnostic-setting-using-powershell)