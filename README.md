# Handy PowerShell Scripts

A collection of useful PowerShell scripts for Windows device management, Azure, and Intune administration.

## Scripts

### Autopilot-enroll.ps1
Enrolls Windows devices in Autopilot and imports them to Intune:
- Uses modern OAuth authentication with 2FA support
- Automatically extracts device hardware hash
- Supports both interactive and headless authentication

### Deploy-AzureArcAgent.ps1
Onboards Windows devices to Azure Arc:
- Downloads and installs the Azure Arc agent
- Registers devices with Azure Arc
- Provides comprehensive error handling and logging

### Prepare-IntuneArcPackage.ps1
Creates an Intune Win32 app package for Azure Arc deployment:
- Generates supporting detection and installation scripts
- Packages files into .intunewin format
- Provides deployment instructions

### 90dayauditandsigninlogretention.ps1
Configures Azure AD sign-in and audit log retention:
- Sets retention period to 90 days
- Automates Azure AD log management
- Ensures security and compliance requirements

### Compliance-EDR-Intune-Enabled
Checks and enforces EDR (Endpoint Detection and Response) settings:
- Verifies EDR configurations on Intune-managed devices
- Reports compliance status
- Includes configuration rules in JSON format

## Requirements

- Windows 10/11 or Windows Server 2019/2022
- PowerShell 5.1 or later
- Internet connectivity
- Appropriate Azure/Microsoft 365 permissions

## Usage

Most scripts include detailed help information accessible via:
```powershell
Get-Help .\ScriptName.ps1 -Full
```

## Authentication

Scripts use modern authentication methods:
- OAuth-based interactive browser authentication
- Support for Multi-Factor Authentication (MFA/2FA)
- Device code flow for headless scenarios

## Logging

Scripts include logging capabilities for troubleshooting:
- Detailed progress information
- Error handling with meaningful messages
- Troubleshooting guidance for common issues

## Additional Resources

- [Azure Arc documentation](https://docs.microsoft.com/azure/azure-arc/)
- [Windows Autopilot documentation](https://docs.microsoft.com/autopilot/)
- [Intune documentation](https://docs.microsoft.com/mem/intune/)
