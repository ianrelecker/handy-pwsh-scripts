# Azure Arc Deployment for Intune-Managed Windows Devices

This repository contains PowerShell scripts for onboarding Windows devices to Azure Arc through Microsoft Intune.

## Scripts

### Deploy-AzureArcAgent.ps1

The main script that handles:
- Downloading the Azure Arc agent
- Installing the agent
- Registering the device with Azure Arc
- Error handling and logging

### Prepare-IntuneArcPackage.ps1

Helper script to prepare an Intune Win32 app package, which:
- Creates necessary supporting scripts (detection, installation, uninstallation)
- Downloads the required Microsoft Win32 Content Prep Tool
- Packages everything into an .intunewin file for Intune deployment
- Generates deployment instructions

## Requirements

- Windows 10 version 1809 or later / Windows Server 2019 or later
- PowerShell 5.1 or later
- Internet connectivity for downloading the Azure Arc agent and registration
- Proper Azure permissions

## Getting Started

1. Clone or download this repository
2. Run the preparation script: `.\Prepare-IntuneArcPackage.ps1`
3. This will create an IntunePackage directory with all necessary files
4. Follow the instructions in the generated Deployment-Instructions.txt file

## Deployment Process

Once the package is created, you'll deploy it through Intune as a Win32
application. The deployment involves:

1. Uploading the .intunewin package to Intune
2. Configuring the application properties, including:
   - Installation and uninstallation commands
   - Detection method using the included detection script
   - Requirements and dependencies
3. Assigning the application to your device groups

## Configuration Options

The main deployment script (`Deploy-AzureArcAgent.ps1`) accepts several parameters:

- **SubscriptionId**: Azure subscription to register the machine in
- **ResourceGroup**: Resource group for the Arc-enabled machine
- **Location**: Azure region for the Arc resource
- **TenantId**: Azure AD tenant ID
- **Tags**: Optional tags to assign to the Arc-enabled machine

These parameters can be customized in the `Install-AzureArcAgent.ps1` wrapper script.

## Authentication

By default, the script uses device code authentication, which requires user intervention
to complete the registration process. For fully automated deployments, you can modify
the script to use a service principal by changing the authentication method in the
Connect-AzureArc function.

## Troubleshooting

Logs are stored in the following locations:
- Main logs: `%ProgramData%\AzureArcOnboarding\ArcOnboarding.log`
- Installation logs: `%ProgramData%\AzureArcOnboarding\ArcAgentInstall.log`
- Uninstallation logs: `%ProgramData%\AzureArcOnboarding\ArcAgentUninstall.log`

Common issues:
- Network connectivity problems
- Insufficient permissions
- Device already registered with Azure Arc

## Additional Resources

- [Azure Arc documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)
- [Intune Win32 app management](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
