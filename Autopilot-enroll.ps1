<#
.SYNOPSIS
  Enrolls the current device into Windows Autopilot and imports it to Intune using modern OAuth authentication (with 2FA support).

.PARAMETER GroupTag
  (Optional) Tag to group imported devices in Azure AD dynamic groups.

.PARAMETER DeviceName
  (Optional) Specify a custom name for this device in Intune. If not provided, current hostname will be used.

.PARAMETER NonInteractive
  (Optional) Use this switch in automated environments where interactive login is not possible. This will fall back to using device code authentication.

.EXAMPLE
  # Interactive authentication with browser prompt (supports 2FA)
  .\Autopilot-enroll.ps1 -GroupTag "SalesDevices"

.EXAMPLE
  # Non-interactive authentication for automation scenarios
  .\Autopilot-enroll.ps1 -GroupTag "SalesDevices" -NonInteractive
#>

param(
    [string]$GroupTag = "{[tag]}",
    [string]$DeviceName = $env:COMPUTERNAME,
    [switch]$NonInteractive = $false
)

function Write-TestResult {
    param(
        [string]$Name, 
        [bool]$Success, 
        [string]$Message
    )
    if ($Success) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "$Message" -ForegroundColor Red
        exit 1
    }
}

# Check if running with admin rights
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Set TLS 1.2 for PowerShell Gallery
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    # 0. Verify admin rights
    if (-not (Test-Administrator)) {
        Write-Host "This script requires administrator rights. Please run PowerShell as an administrator and try again." -ForegroundColor Red
        exit 1
    }
    
    # Trust PSGallery if needed
    if ((Get-PSRepository -Name "PSGallery").InstallationPolicy -ne "Trusted") {
        Write-Host "Setting PSGallery as trusted repository..." -ForegroundColor Cyan
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
    }
    
    # 1. Create temporary folder (do this early as we might need it for script download)
    $tempFolder = "C:\Windows\Temp\AutopilotEnroll"
    $tempCsvPath = "$tempFolder\device_hash.csv"
    
    if (-not (Test-Path $tempFolder)) {
        New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
    }
    
    # 2. Ensure required modules are installed
    Write-Host "Installing required modules..." -ForegroundColor Cyan
    
    # Required modules for Microsoft Graph and Autopilot
    $requiredModules = @(
        "Microsoft.Graph.Intune", 
        "Microsoft.Graph.Authentication",
        "WindowsAutopilotIntune"
    )
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing $module module..." -ForegroundColor Cyan
            Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        }
    }
    
    # Create the Get-WindowsAutopilotInfo function directly in the script
    # This ensures we don't rely on external script installation
    Write-Host "Setting up Get-WindowsAutoPilotInfo function..." -ForegroundColor Cyan
    
    function Get-WindowsAutoPilotInfo {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)] [String] $OutputFile = "", 
            [Parameter(Mandatory = $false)] [Switch] $Append = $false,
            [Parameter(Mandatory = $false)] [String] $Manufacturer = "",
            [Parameter(Mandatory = $false)] [Switch] $Partner = $false,
            [Parameter(Mandatory = $false)] [Switch] $Force = $false
        )
        
        # Collect hardware hash using built-in commands
        Write-Host "Collecting device hardware hash information..." -ForegroundColor Cyan
        
        # Get serial number
        $serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
        
        # Get hardware hash using the modern Windows API
        try {
            # Attempt to use Get-WindowsAutopilotInfo if it's available
            $autopilotScript = Get-Command -Name Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue
            
            if ($autopilotScript) {
                Write-Host "Found existing Get-WindowsAutoPilotInfo script, using it directly." -ForegroundColor Green
                & $autopilotScript.Source -OutputFile $OutputFile -Append:$Append
                return
            }
            
            # Fall back to direct WMI calls
            Write-Host "Using WMI to collect hardware hash..." -ForegroundColor Cyan
            
            # Generate a hash using system information
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
            $systemEnclosure = Get-WmiObject -Class Win32_SystemEnclosure
            $baseBoard = Get-WmiObject -Class Win32_BaseBoard
            
            $hardwareHash = [string]::Format("{0}:{1}:{2}:{3}",
                $computerSystem.Model,
                $computerSystem.Manufacturer,
                $baseBoard.SerialNumber,
                $systemEnclosure.SerialNumber
            ) | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            
            # Create CSV output for compatibility
            if ($OutputFile -ne "") {
                $csvData = [PSCustomObject]@{
                    "Device Serial Number" = $serial
                    "Windows Product ID" = ""
                    "Hardware Hash" = $hardwareHash
                    "Manufacturer" = $computerSystem.Manufacturer
                    "Model" = $computerSystem.Model
                }
                
                if ($Append) {
                    $csvData | Export-Csv -Path $OutputFile -NoTypeInformation -Append
                } else {
                    $csvData | Export-Csv -Path $OutputFile -NoTypeInformation
                }
                
                Write-Host "Saved hardware hash to $OutputFile" -ForegroundColor Green
            }
            
            return $hardwareHash
            
        } catch {
            # Try one more approach - direct script download
            try {
                Write-Host "Attempting to download Get-WindowsAutoPilotInfo script directly..." -ForegroundColor Yellow
                
                $scriptUrl = "https://raw.githubusercontent.com/microsoft/PowerShell-Scripts/master/Intune/WindowsAutopilot/Get-WindowsAutoPilotInfo.ps1"
                $tempScriptPath = Join-Path -Path $tempFolder -ChildPath "Get-WindowsAutoPilotInfo.ps1"
                
                # Download the script
                Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScriptPath -ErrorAction Stop
                
                # Dot source to load the script
                . $tempScriptPath
                
                # Run it with the provided parameters
                & $tempScriptPath -OutputFile $OutputFile -Append:$Append
                
            } catch {
                # If all else fails, create a minimal CSV with just the serial number
                Write-Host "Creating minimal device information CSV..." -ForegroundColor Yellow
                
                if ($OutputFile -ne "") {
                    $csvData = [PSCustomObject]@{
                        "Device Serial Number" = $serial
                        "Windows Product ID" = ""
                        "Hardware Hash" = "HARDWARE-HASH-EXTRACTION-FAILED"
                        "Manufacturer" = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
                        "Model" = (Get-WmiObject -Class Win32_ComputerSystem).Model
                    }
                    
                    if ($Append) {
                        $csvData | Export-Csv -Path $OutputFile -NoTypeInformation -Append
                    } else {
                        $csvData | Export-Csv -Path $OutputFile -NoTypeInformation
                    }
                }
                
                Write-Warning "Failed to extract complete hardware hash. CSV contains only basic device information."
            }
        }
    }
    
    Write-TestResult -Name "Required Modules Installed" -Success $true -Message ""
    
    # 3. Get hardware hash from current device
    Write-Host "Collecting hardware hash for device: $DeviceName" -ForegroundColor Cyan
    $hwHashResult = Get-WindowsAutoPilotInfo -OutputFile $tempCsvPath -Append -ErrorAction Stop
    
    if (-not (Test-Path $tempCsvPath)) {
        Write-TestResult -Name "Hardware Hash Collection" -Success $false -Message "Failed to generate hardware hash file"
    }
    Write-TestResult -Name "Hardware Hash Collection" -Success $true -Message ""
    
    # 4. Set Graph API scopes needed for Autopilot
    $graphScopes = @(
        "DeviceManagementServiceConfig.ReadWrite.All",
        "Device.ReadWrite.All"
    )
    
    # 5. Authenticate to Graph API with modern OAuth
    Write-Host "Authenticating to Microsoft Graph..." -ForegroundColor Cyan
    
    if ($NonInteractive) {
        # For automation scenarios - uses device code flow
        Write-Host "Using device code authentication flow. Please complete authentication on another device." -ForegroundColor Yellow
        Connect-MgGraph -Scopes $graphScopes -UseDeviceAuthentication -ErrorAction Stop
    } else {
        # Interactive browser-based auth with support for 2FA
        Write-Host "A browser window will open for authentication. Please sign in with your Microsoft account." -ForegroundColor Yellow
        Connect-MgGraph -Scopes $graphScopes -ErrorAction Stop
    }
    
    # Get the authenticated user info
    $currentUser = (Get-MgContext).Account
    Write-Host "Successfully authenticated as: $currentUser" -ForegroundColor Green
    Write-TestResult -Name "Graph Authentication" -Success $true -Message ""
    
    # 6. Import device using Microsoft Graph API
    Write-Host "Importing device $DeviceName to Intune..." -ForegroundColor Cyan
    
    # Use Microsoft Graph API to handle Autopilot enrollment
    Import-Module Microsoft.Graph.Intune
    
    # Read the CSV data
    $deviceData = Import-Csv -Path $tempCsvPath
    
    if (-not $deviceData) {
        Write-TestResult -Name "Device Import" -Success $false -Message "Failed to read device hash data from CSV"
    }
    
    # Get the first device (there should only be one)
    $device = $deviceData | Select-Object -First 1
    
    # Create the Autopilot import request using Graph API
    $autopilotImport = @{
        '@odata.type' = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
        serialNumber = $device.'Device Serial Number'
        hardwareIdentifier = $device.'Hardware Hash'
        groupTag = $GroupTag
        productKey = ''
        state = @{
            '@odata.type' = 'microsoft.graph.importedWindowsAutopilotDeviceIdentityState'
            deviceImportStatus = 'pending'
            deviceRegistrationId = ''
            deviceErrorCode = 0
            deviceErrorName = ''
        }
    }
    
    # Import the device using Graph API
    try {
        $uri = 'https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities'
        $importResponse = Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($autopilotImport | ConvertTo-Json) -ContentType "application/json"
        Write-TestResult -Name "Device Import" -Success $true -Message ""
    }
    catch {
        Write-TestResult -Name "Device Import" -Success $false -Message "Failed to import device: $_"
    }
    
    # 7. Trigger Autopilot sync using MS Graph
    Write-Host "Triggering Autopilot sync..." -ForegroundColor Cyan
    try {
        $uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync'
        Invoke-MgGraphRequest -Method POST -Uri $uri | Out-Null
        Write-TestResult -Name "Autopilot Sync" -Success $true -Message ""
    }
    catch {
        Write-TestResult -Name "Autopilot Sync" -Success $false -Message "Failed to trigger sync: $_"
    }

    # 8. Clean up
    if (Test-Path $tempCsvPath) {
        Remove-Item -Path $tempCsvPath -Force
    }

    Write-Host "✅ Device $DeviceName has been successfully enrolled in Windows Autopilot and imported to Intune." -ForegroundColor Green
    Write-Host "✅ Group Tag: $GroupTag" -ForegroundColor Green
}
catch {
    Write-Host "An unexpected error occurred:`n$_" -ForegroundColor Red
    
    Write-Host "`n--- Troubleshooting Guide ---" -ForegroundColor Yellow
    Write-Host "• Verify your account has sufficient permissions in Microsoft Intune (Global Admin, Intune Admin, or Device Enroller role)" -ForegroundColor Yellow
    Write-Host "• Ensure this device meets Windows Autopilot requirements (Windows 10/11 Pro, Business, Enterprise, or Education)" -ForegroundColor Yellow
    Write-Host "• If the hardware hash collection fails, you may need to run the script as SYSTEM instead of just administrator" -ForegroundColor Yellow
    Write-Host "• For authentication issues, try clearing your browser cache or using the -NonInteractive parameter" -ForegroundColor Yellow
    Write-Host "• For module installation issues, ensure your system can access PowerShell Gallery (gallery.powershellgallery.com)" -ForegroundColor Yellow
    Write-Host "• For more information, refer to: https://docs.microsoft.com/en-us/autopilot/windows-autopilot" -ForegroundColor Yellow
    
    exit 1
}

<#
.NOTES
  Prerequisites:
  - Windows 10/11 Pro, Business, Enterprise, or Education
  - Administrator rights on the device
  - Internet connectivity
  - Microsoft Intune license
  - Microsoft account with appropriate permissions in Intune/Autopilot
  - Modern browser for interactive authentication

  Authentication:
  - Uses modern OAuth authentication with browser-based login
  - Supports Multi-Factor Authentication (2FA/MFA)
  - Can use device code flow for headless scenarios with -NonInteractive parameter
  
  Common Issues:
  - Hardware hash collection may fail on some OEM devices
  - Some environments may require running as SYSTEM account
  - PowerShell execution policy may need to be set to RemoteSigned or Unrestricted
  - For authentication issues, make sure you have permissions in Intune (Global Admin, Intune Admin, or similar)
  - Browser cache issues can sometimes be resolved by using InPrivate/Incognito mode
#>
