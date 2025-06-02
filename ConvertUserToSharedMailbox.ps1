# Connect to Exchange Online and MSOL Service
$exchangeOnlineCredential = Get-Credential
try {
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -UserPrincipalName $exchangeOnlineCredential.UserName -Password $exchangeOnlineCredential.Password
    Write-Host "Connected to Exchange Online."

    Write-Host "Connecting to MSOL Service..."
    Connect-MsolService -Credential $exchangeOnlineCredential
    Write-Host "Connected to MSOL Service."
} catch {
    Write-Host "Failed to connect to services: $_"
    exit 1
}

# Variables (replace with actual values)
$userToConvert = "user1@domain.com"
$accessGrantedTo = "user2@domain.com"

try {
    # Convert user to shared mailbox and grant access
    Write-Host "Converting $userToConvert to a shared mailbox..."
    Set-Mailbox -Identity $userToConvert -Type Shared
    Write-Host "$userToConvert has been converted to a shared mailbox."

    Write-Host "Granting full access to $accessGrantedTo on $userToConvert's mailbox..."
    Add-MailboxPermission -Identity $userToConvert -User $accessGrantedTo -AccessRights FullAccess
    Write-Host "Full access granted to $accessGrantedTo."

    # Grant OneDrive access
    Write-Host "Granting OneDrive access for $userToConvert to $accessGrantedTo..."
    $oneDriveUrl = "https://domain-my.sharepoint.com/personal/$($userToConvert.Split('@')[0])_onmicrosoft_com"
    Set-SPOSite -Identity $oneDriveUrl -Owner $accessGrantedTo
    Write-Host "OneDrive access granted to $accessGrantedTo."

    # Remove licenses from the user
    Write-Host "Removing licenses for $userToConvert..."
    $licenses = (Get-MsolUser -UserPrincipalName $userToConvert).Licenses
    foreach ($license in $licenses) {
        Set-MsolUserLicense -UserPrincipalName $userToConvert -RemoveLicenses $($license.AccountSkuId)
    }
    Write-Host "All licenses removed for $userToConvert."

    Write-Host "Script completed successfully."
} catch {
    Write-Host "An error occurred: $_"
}

Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MsolService -Confirm:$false