<#
.SYNOPSIS
    Deploys Azure Arc agent to Windows devices through Intune.
.DESCRIPTION
    This PowerShell script is designed to be deployed through Microsoft Intune to 
    onboard Windows devices to Azure Arc. It handles downloading the agent, 
    installation, and registration with Azure Arc.
.NOTES
    File Name      : Deploy-AzureArcAgent.ps1
    Author         : Ian Relecker
    Prerequisite   : PowerShell 5.1 or later
    Version        : 1.0
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Parameters for Azure Arc onboarding
param (
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = "",  # Will use device login if not provided
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "",   # Will use default Arc resource group if not provided
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",  # Default location
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId = "",        # Will be detected if not provided
    
    [Parameter(Mandatory = $false)]
    [string]$Tags = ""             # Optional tags in format "key1=value1 key2=value2"
)

# Script variables
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Improves download speed
$LogPath = "$env:ProgramData\AzureArcOnboarding"
$LogFile = "$LogPath\ArcOnboarding.log"
$DownloadPath = "$env:TEMP\AzureArcOnboarding"
$AgentInstallerName = "AzureConnectedMachineAgent.msi"
$AgentInstallerPath = "$DownloadPath\$AgentInstallerName"
$AgentDownloadUrl = "https://aka.ms/AzureConnectedMachineAgent"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Create download directory if it doesn't exist
if (-not (Test-Path -Path $DownloadPath)) {
    New-Item -ItemType Directory -Path $DownloadPath -Force | Out-Null
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

# Function to check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check OS version
    $osInfo = Get-WmiObject -Class Win32_OperatingSystem
    $osVersion = [Version]($osInfo.Version)
    
    if ($osVersion -lt [Version]"10.0.17763") {
        Write-Log "Operating system version not supported. Minimum required: Windows Server 2019/Windows 10 (1809)" -Level "Error"
        return $false
    }
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        Write-Log "PowerShell version $psVersion not supported. Minimum required: 5.1" -Level "Error"
        return $false
    }
    
    # Check internet connectivity
    try {
        $testConnection = Test-NetConnection -ComputerName "management.azure.com" -Port 443 -WarningAction SilentlyContinue
        if (-not $testConnection.TcpTestSucceeded) {
            Write-Log "Cannot connect to Azure management endpoints. Please check network connectivity." -Level "Error"
            return $false
        }
    }
    catch {
        Write-Log "Network connectivity test failed: $_" -Level "Error"
        return $false
    }
    
    # Check if already connected to Arc
    if (Get-Service -Name "himds" -ErrorAction SilentlyContinue) {
        Write-Log "Azure Connected Machine Agent (himds service) is already installed. Checking registration status..." -Level "Warning"
        
        # Check if registration exists
        $agentConfig = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show 2>$null
        if ($agentConfig -match "Tenant ID" -and $agentConfig -match "Resource Group") {
            Write-Log "This machine is already registered with Azure Arc." -Level "Warning"
            return $false
        }
        else {
            Write-Log "Azure Connected Machine Agent is installed but not registered. Proceeding with registration." -Level "Info"
            return $true
        }
    }
    
    Write-Log "All prerequisites passed."
    return $true
}

# Function to download Azure Arc agent
function Get-AzureArcAgent {
    Write-Log "Downloading Azure Arc agent..."
    
    try {
        # Download the agent
        Invoke-WebRequest -Uri $AgentDownloadUrl -OutFile $AgentInstallerPath -UseBasicParsing
        
        if (Test-Path -Path $AgentInstallerPath) {
            Write-Log "Azure Arc agent downloaded successfully to: $AgentInstallerPath"
            return $true
        }
        else {
            Write-Log "Failed to download Azure Arc agent. File not found at expected path: $AgentInstallerPath" -Level "Error"
            return $false
        }
    }
    catch {
        Write-Log "Error downloading Azure Arc agent: $_" -Level "Error"
        return $false
    }
}

# Function to install Azure Arc agent
function Install-AzureArcAgent {
    Write-Log "Installing Azure Arc agent..."
    
    try {
        # Install the MSI
        $installArgs = "/i `"$AgentInstallerPath`" /qn /l*v `"$LogPath\ArcAgentInstall.log`""
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Azure Arc agent installed successfully."
            
            # Verify the service is running
            Start-Sleep -Seconds 5  # Give it time to start
            $himdsService = Get-Service -Name "himds" -ErrorAction SilentlyContinue
            
            if ($himdsService -and $himdsService.Status -eq "Running") {
                Write-Log "Azure Connected Machine Agent service (himds) is running."
                return $true
            }
            else {
                Write-Log "Azure Connected Machine Agent service (himds) is not running after installation." -Level "Error"
                return $false
            }
        }
        else {
            Write-Log "Azure Arc agent installation failed with exit code: $($process.ExitCode)" -Level "Error"
            return $false
        }
    }
    catch {
        Write-Log "Error installing Azure Arc agent: $_" -Level "Error"
        return $false
    }
}

# Function to connect machine to Azure Arc
function Connect-AzureArc {
    Write-Log "Connecting to Azure Arc..."
    
    # Construct the azcmagent connect command
    $connectArgs = "connect"
    
    # Add optional parameters if provided
    if ($SubscriptionId) {
        $connectArgs += " --subscription-id `"$SubscriptionId`""
    }
    
    if ($ResourceGroup) {
        $connectArgs += " --resource-group `"$ResourceGroup`""
    }
    
    if ($Location) {
        $connectArgs += " --location `"$Location`""
    }
    
    if ($TenantId) {
        $connectArgs += " --tenant-id `"$TenantId`""
    }
    
    # Add tags if provided
    if ($Tags) {
        $connectArgs += " --tags `"$Tags`""
    }
    
    # Add device code authentication for non-interactive environments like Intune
    $connectArgs += " --device"
    
    try {
        # Execute the command
        Write-Log "Executing: azcmagent $connectArgs"
        $connectOutput = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" $connectArgs.Split(" ") 2>&1
        
        # Check for device code login instructions
        $deviceCodeMessage = $connectOutput | Where-Object { $_ -match "To sign in, use a web browser to open the page" }
        if ($deviceCodeMessage) {
            $deviceCode = ($deviceCodeMessage -split "code ")[1] -split " to" | Select-Object -First 1
            Write-Log "Device authentication required. Please authenticate with code: $deviceCode" -Level "Warning"
            
            # In Intune context, we might need to save this information for manual intervention
            $deviceAuthInstructions = $deviceCodeMessage -join "`n"
            Add-Content -Path "$LogPath\DeviceAuth.txt" -Value $deviceAuthInstructions
            
            # Wait for authentication to complete
            for ($i = 0; $i -lt 300; $i++) {  # Wait up to 5 minutes
                Start-Sleep -Seconds 1
                
                # Check if connection process completed
                $status = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show 2>$null
                if ($status -match "Tenant ID" -and $status -match "Resource Group") {
                    Write-Log "Azure Arc connection completed successfully."
                    return $true
                }
            }
            
            Write-Log "Timed out waiting for device authentication to complete." -Level "Error"
            return $false
        }
        
        # Check if connection was successful
        $status = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show 2>$null
        if ($status -match "Tenant ID" -and $status -match "Resource Group") {
            Write-Log "Azure Arc connection completed successfully."
            
            # Output detailed connection information
            $statusInfo = $status -join "`n"
            Write-Log "Connection details: `n$statusInfo"
            
            return $true
        }
        else {
            Write-Log "Azure Arc connection failed. No valid connection information found." -Level "Error"
            Write-Log "Output: `n$($connectOutput -join "`n")" -Level "Error"
            return $false
        }
    }
    catch {
        Write-Log "Error connecting to Azure Arc: $_" -Level "Error"
        return $false
    }
}

# Main execution
try {
    Write-Log "===== Azure Arc onboarding script started ====="
    Write-Log "Computer Name: $env:COMPUTERNAME"
    Write-Log "Current User: $env:USERNAME"
    
    # Check if prerequisites are met
    if (-not (Test-Prerequisites)) {
        Write-Log "Prerequisites check failed. Exiting script." -Level "Error"
        exit 1
    }
    
    # Download Azure Arc agent
    if (-not (Get-AzureArcAgent)) {
        Write-Log "Failed to download Azure Arc agent. Exiting script." -Level "Error"
        exit 1
    }
    
    # Install Azure Arc agent
    if (-not (Install-AzureArcAgent)) {
        Write-Log "Failed to install Azure Arc agent. Exiting script." -Level "Error"
        exit 1
    }
    
    # Connect to Azure Arc
    if (-not (Connect-AzureArc)) {
        Write-Log "Failed to connect to Azure Arc. Exiting script." -Level "Error"
        exit 1
    }
    
    # Cleanup download files
    if (Test-Path -Path $DownloadPath) {
        Remove-Item -Path $DownloadPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary files."
    }
    
    Write-Log "===== Azure Arc onboarding completed successfully ====="
    exit 0
}
catch {
    Write-Log "Unhandled exception: $_" -Level "Error"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "Error"
    exit 1
}
