<#
.SYNOPSIS
    Prepares the Azure Arc onboarding script for Intune deployment.
.DESCRIPTION
    This script creates a Win32 application package for deploying the Azure Arc
    agent through Microsoft Intune. It includes the main deployment script and
    supporting files needed for successful deployment and detection.
.NOTES
    File Name      : Prepare-IntuneArcPackage.ps1
    Author         : Ian Relecker
    Prerequisite   : PowerShell 5.1 or later, IntuneWinAppUtil.exe
    Version        : 1.0
.EXAMPLE
    .\Prepare-IntuneArcPackage.ps1
#>

# Script variables
$PackagePath = "$PSScriptRoot\IntunePackage"
$SourcePath = "$PackagePath\Source"
$OutputPath = "$PackagePath\Output"
$IntuneWinAppUtilPath = "$PackagePath\IntuneWinAppUtil.exe"
$IntuneWinAppUtilUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
$DetectionScriptPath = "$SourcePath\Detect-AzureArcAgent.ps1"
$InstallScriptPath = "$SourcePath\Install-AzureArcAgent.ps1"
$UninstallScriptPath = "$SourcePath\Uninstall-AzureArcAgent.ps1"
$MainScriptPath = "$PSScriptRoot\Deploy-AzureArcAgent.ps1"

# Create package directories
function Initialize-Directories {
    Write-Host "Creating package directories..."
    
    if (-not (Test-Path -Path $PackagePath)) {
        New-Item -ItemType Directory -Path $PackagePath -Force | Out-Null
    }
    
    if (-not (Test-Path -Path $SourcePath)) {
        New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
    }
    
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
}

# Download IntuneWinAppUtil if not already present
function Get-IntuneWinAppUtil {
    Write-Host "Checking for IntuneWinAppUtil.exe..."
    
    if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
        Write-Host "Downloading IntuneWinAppUtil.exe..."
        try {
            Invoke-WebRequest -Uri $IntuneWinAppUtilUrl -OutFile $IntuneWinAppUtilPath -UseBasicParsing
            if (Test-Path -Path $IntuneWinAppUtilPath) {
                Write-Host "Downloaded IntuneWinAppUtil.exe successfully."
            }
            else {
                Write-Host "Failed to download IntuneWinAppUtil.exe." -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "Error downloading IntuneWinAppUtil.exe: $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "IntuneWinAppUtil.exe already exists."
    }
    
    return $true
}

# Create detection script
function New-DetectionScript {
    Write-Host "Creating detection script..."
    
    $detectionScriptContent = @'
<#
.SYNOPSIS
    Detects if Azure Arc agent is installed and connected.
.DESCRIPTION
    This script checks if Azure Arc agent is installed and registered
    with Azure. Used as a detection method for Intune Win32 app deployment.
.NOTES
    File Name      : Detect-AzureArcAgent.ps1
    Author         : Ian Relecker
    Version        : 1.0
#>

try {
    # Check if the Azure Connected Machine Agent service exists
    $himdsService = Get-Service -Name "himds" -ErrorAction SilentlyContinue
    
    if (-not $himdsService) {
        # Service not found, agent not installed
        Write-Host "Azure Connected Machine Agent not installed."
        exit 1
    }
    
    # Check if the agent is registered with Azure Arc
    $agentExePath = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
    
    if (-not (Test-Path -Path $agentExePath)) {
        Write-Host "Azure Connected Machine Agent installed but executable not found."
        exit 1
    }
    
    # Check registration status
    $agentConfig = & "$agentExePath" show 2>$null
    
    if (-not ($agentConfig -match "Tenant ID" -and $agentConfig -match "Resource Group")) {
        Write-Host "Azure Connected Machine Agent installed but not registered."
        exit 1
    }
    
    # Everything is good - agent is installed and registered
    Write-Host "Azure Connected Machine Agent is installed and registered with Azure Arc."
    exit 0
}
catch {
    Write-Host "Error in detection script: $_"
    exit 1
}
'@
    
    Set-Content -Path $DetectionScriptPath -Value $detectionScriptContent
    
    if (Test-Path -Path $DetectionScriptPath) {
        Write-Host "Detection script created successfully."
        return $true
    }
    else {
        Write-Host "Failed to create detection script." -ForegroundColor Red
        return $false
    }
}

# Create installation wrapper script
function New-InstallScript {
    Write-Host "Creating installation wrapper script..."
    
    $installScriptContent = @'
<#
.SYNOPSIS
    Installs and configures Azure Arc agent.
.DESCRIPTION
    This script serves as a wrapper for the main Azure Arc deployment script.
    It sets up any necessary environment and executes the main script.
.NOTES
    File Name      : Install-AzureArcAgent.ps1
    Author         : Ian Relecker
    Version        : 1.0
#>

# Set execution policy for current process only
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
}
catch {
    # Continue even if this fails
}

# Get script directory
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainScript = Join-Path -Path $ScriptPath -ChildPath "Deploy-AzureArcAgent.ps1"

# Check if main script exists
if (-not (Test-Path -Path $MainScript)) {
    Write-Host "Main deployment script not found at: $MainScript" -ForegroundColor Red
    exit 1
}

# Execute the main script with parameters
# Add any required parameters here:
& "$MainScript" `
    -SubscriptionId "" `
    -ResourceGroup "" `
    -Location "eastus" `
    -Tags ""

# Return the exit code from the main script
exit $LASTEXITCODE
'@
    
    Set-Content -Path $InstallScriptPath -Value $installScriptContent
    
    if (Test-Path -Path $InstallScriptPath) {
        Write-Host "Installation wrapper script created successfully."
        return $true
    }
    else {
        Write-Host "Failed to create installation wrapper script." -ForegroundColor Red
        return $false
    }
}

# Create uninstall script
function New-UninstallScript {
    Write-Host "Creating uninstall script..."
    
    $uninstallScriptContent = @'
<#
.SYNOPSIS
    Uninstalls Azure Arc agent.
.DESCRIPTION
    This script uninstalls and unregisters the Azure Arc agent from the machine.
.NOTES
    File Name      : Uninstall-AzureArcAgent.ps1
    Author         : Ian Relecker
    Version        : 1.0
#>

# Log file path
$LogPath = "$env:ProgramData\AzureArcOnboarding"
$LogFile = "$LogPath\ArcUninstall.log"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Function for logging
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogEntry
    
    # Output to console based on level
    switch ($Level) {
        "Info" { Write-Host $LogEntry }
        "Warning" { Write-Host $LogEntry -ForegroundColor Yellow }
        "Error" { Write-Host $LogEntry -ForegroundColor Red }
    }
}

# Main uninstall process
try {
    Write-Log "===== Azure Arc uninstallation started ====="
    
    # Check if the agent is installed
    $agentExePath = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
    
    if (-not (Test-Path -Path $agentExePath)) {
        Write-Log "Azure Connected Machine Agent not found. Nothing to uninstall." -Level "Warning"
        exit 0
    }
    
    # Check if the agent is registered
    $agentConfig = & "$agentExePath" show 2>$null
    if ($agentConfig -match "Tenant ID" -and $agentConfig -match "Resource Group") {
        Write-Log "Azure Connected Machine Agent is registered. Attempting to disconnect..."
        
        # Disconnect the agent
        try {
            & "$agentExePath" disconnect --force
            Write-Log "Azure Arc agent disconnected successfully."
        }
        catch {
            Write-Log "Error disconnecting Azure Arc agent: $_" -Level "Error"
            # Continue with uninstall even if disconnect fails
        }
    }
    else {
        Write-Log "Azure Connected Machine Agent is not registered with Azure Arc."
    }
    
    # Uninstall the agent
    $uninstallProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x {275F2F5B-D459-43A5-8389-3A30B1FA052F} /qn /l*v `"$LogPath\ArcAgentUninstall.log`"" -Wait -PassThru
    
    if ($uninstallProcess.ExitCode -eq 0) {
        Write-Log "Azure Arc agent uninstalled successfully."
    }
    else {
        Write-Log "Azure Arc agent uninstallation failed with exit code: $($uninstallProcess.ExitCode)" -Level "Error"
        exit 1
    }
    
    # Cleanup additional files
    if (Test-Path -Path "$env:ProgramData\AzureConnectedMachineAgent") {
        Remove-Item -Path "$env:ProgramData\AzureConnectedMachineAgent" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed agent data directory."
    }
    
    Write-Log "===== Azure Arc uninstallation completed successfully ====="
    exit 0
}
catch {
    Write-Log "Unhandled exception during uninstall: $_" -Level "Error"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "Error"
    exit 1
}
'@
    
    Set-Content -Path $UninstallScriptPath -Value $uninstallScriptContent
    
    if (Test-Path -Path $UninstallScriptPath) {
        Write-Host "Uninstall script created successfully."
        return $true
    }
    else {
        Write-Host "Failed to create uninstall script." -ForegroundColor Red
        return $false
    }
}

# Copy main deployment script to source directory
function Copy-MainScript {
    Write-Host "Copying main deployment script to package source directory..."
    
    if (-not (Test-Path -Path $MainScriptPath)) {
        Write-Host "Main deployment script not found at: $MainScriptPath" -ForegroundColor Red
        return $false
    }
    
    try {
        Copy-Item -Path $MainScriptPath -Destination "$SourcePath\Deploy-AzureArcAgent.ps1" -Force
        
        if (Test-Path -Path "$SourcePath\Deploy-AzureArcAgent.ps1") {
            Write-Host "Main deployment script copied successfully."
            return $true
        }
        else {
            Write-Host "Failed to copy main deployment script." -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error copying main deployment script: $_" -ForegroundColor Red
        return $false
    }
}

# Create the Intune Win32 app package
function New-IntunePackage {
    Write-Host "Creating Intune Win32 app package..."
    
    # Check if IntuneWinAppUtil.exe exists
    if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
        Write-Host "IntuneWinAppUtil.exe not found at: $IntuneWinAppUtilPath" -ForegroundColor Red
        return $false
    }
    
    # Check if the install script exists
    if (-not (Test-Path -Path $InstallScriptPath)) {
        Write-Host "Installation script not found at: $InstallScriptPath" -ForegroundColor Red
        return $false
    }
    
    try {
        # Execute IntuneWinAppUtil to create the package
        $intuneProcess = Start-Process -FilePath $IntuneWinAppUtilPath -ArgumentList "-c `"$SourcePath`" -s `"Install-AzureArcAgent.ps1`" -o `"$OutputPath`" -q" -Wait -PassThru
        
        if ($intuneProcess.ExitCode -eq 0) {
            $packageFile = Get-ChildItem -Path $OutputPath -Filter "*.intunewin" | Select-Object -First 1
            
            if ($packageFile) {
                Write-Host "Intune Win32 app package created successfully: $($packageFile.FullName)"
                return $true
            }
            else {
                Write-Host "Package file not found in output directory." -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Host "Failed to create Intune Win32 app package. Exit code: $($intuneProcess.ExitCode)" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Error creating Intune Win32 app package: $_" -ForegroundColor Red
        return $false
    }
}

# Generate Intune deployment information
function New-DeploymentInstructions {
    Write-Host "Generating deployment instructions..."
    
    $instructionsPath = "$PackagePath\Deployment-Instructions.txt"
    $instructionsContent = @"
# Azure Arc Agent Deployment through Intune

## Package Information

This package contains the necessary scripts to deploy the Azure Arc agent to Windows devices through Microsoft Intune.

## Intune Win32 App Setup

1. In the Microsoft Endpoint Manager admin center, go to Apps > Windows > Add
2. Select "Windows app (Win32)" as the app type
3. Upload the generated .intunewin file from the Output directory

### App Information:
- Name: Azure Arc Agent
- Description: Deploys Azure Arc agent to enable hybrid management of Windows devices
- Publisher: Microsoft
- Category: IT Infrastructure

### Program Settings:
- Install command: powershell.exe -ExecutionPolicy Bypass -File "Install-AzureArcAgent.ps1"
- Uninstall command: powershell.exe -ExecutionPolicy Bypass -File "Uninstall-AzureArcAgent.ps1"
- Install behavior: System
- Device restart behavior: Determine behavior based on return codes

### Requirements:
- Operating system architecture: 64-bit
- Minimum operating system: Windows 10 1809 or later / Windows Server 2019 or later

### Detection Rules:
- Rule type: Use a custom detection script
- Script file: Detect-AzureArcAgent.ps1
- Run script as 32-bit process on 64-bit clients: No
- Enforce script signature check: No
- Run script as administrator: Yes

### Dependencies (Optional):
Add any dependencies your environment requires

### Assignments:
Assign to the appropriate groups based on your organization's requirements

## Notes

- The device may require a restart after installation
- Internet access is required for downloading the Azure Arc agent and registering with Azure
- Users will need to authenticate using device code authentication when the device is registered with Azure Arc
- For automated registration without user interaction, consider modifying the script to use a service principal

## Troubleshooting

- Logs are stored in %ProgramData%\AzureArcOnboarding
- The main log file is ArcOnboarding.log
- Installation logs are in ArcAgentInstall.log
- Uninstallation logs are in ArcAgentUninstall.log
"@
    
    Set-Content -Path $instructionsPath -Value $instructionsContent
    
    if (Test-Path -Path $instructionsPath) {
        Write-Host "Deployment instructions created successfully: $instructionsPath"
        return $true
    }
    else {
        Write-Host "Failed to create deployment instructions." -ForegroundColor Red
        return $false
    }
}

# Main execution
function Start-IntunePackageCreation {
    Write-Host "Starting Intune package creation process..."
    
    # Initialize directories
    if (-not (Initialize-Directories)) {
        Write-Host "Failed to initialize directories." -ForegroundColor Red
        return
    }
    
    # Download IntuneWinAppUtil
    if (-not (Get-IntuneWinAppUtil)) {
        Write-Host "Failed to get IntuneWinAppUtil." -ForegroundColor Red
        return
    }
    
    # Create detection script
    if (-not (New-DetectionScript)) {
        Write-Host "Failed to create detection script." -ForegroundColor Red
        return
    }
    
    # Create install script
    if (-not (New-InstallScript)) {
        Write-Host "Failed to create install script." -ForegroundColor Red
        return
    }
    
    # Create uninstall script
    if (-not (New-UninstallScript)) {
        Write-Host "Failed to create uninstall script." -ForegroundColor Red
        return
    }
    
    # Copy main script
    if (-not (Copy-MainScript)) {
        Write-Host "Failed to copy main script." -ForegroundColor Red
        return
    }
    
    # Attempt to create the package (will be skipped if IntuneWinAppUtil is not available)
    New-IntunePackage
    
    # Generate deployment instructions
    if (-not (New-DeploymentInstructions)) {
        Write-Host "Failed to create deployment instructions." -ForegroundColor Red
        return
    }
    
    Write-Host "Package preparation completed." -ForegroundColor Green
    Write-Host "You can find the package files in: $PackagePath"
    Write-Host "See the Deployment-Instructions.txt file for guidance on deploying through Intune."
}

# Execute the main function
Start-IntunePackageCreation
