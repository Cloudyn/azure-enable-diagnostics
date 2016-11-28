# Azure Enable Diagnostics

azure-enable-diagnostics automates enabling monitoring Diagnostics on Azure VMs.

For details on the context for this utility, see [Enabling Azure Diagnostics](https://www.cloudyn.com/blog/)

For each subscription assigned to the entered Azure login credentials:
   * Register the Resource Provider: "Microsoft.Insights"
   * Create or choose a Standard storage account to use for each resource group location
   * For chosen running VMs, enable Monitoring Diagnostics, set the Storage
     * For Linux, enable: Basic metrics
     * For Windows, enable: Basic metrics, Network metrics, Diagnostics infrastructure logs

The user can control:
* which subscriptions
* which storage
* which VMs: Classic/Arm, Windows/Linux
* whether to override existing diagnostics settings

The outcome of the script is logged to file.


#Prerequisites

##Once off
Start "Windows PowerShell" with "Run as Administrator"
```PowerShell
Install-Module Azure
Install-Module AzureRM -Force
```

##Per session
Type the following to enable running an unsigned script in PowerShell session.
```PowerShell
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
```
Type "Y" to change the execution policy.
When you close session, the policy will return to default.


#Parameters
* **DeploymentModel**
    * "Arm" / "Classic"  (Mandatory)
    * Arm refers to "Azure Resource Manager"
    * Classic refers to "Service Manager"
* **OsType**
    * "Windows" / "Linux"
    * Optional. Default = both
* **ChooseSubscription**
    * Prompt the user to choose which subscriptions assigned to the current user should have their subscriptions enabled.
    * Default = true
* **ChooseStorage**
    * Prompt the user to choose which Storage Accounts should be used per ResourceGroup-Location combination.
    * Default = false
* **ChooseVM**
    * Prompt the user to choose which VMs should have Diagnostics enabled.
    * Default = false
* **OverrideDiagnostics**
    * Whether to override diagnostics of VMs that already have diagnostic settings enabled.
    * Default = false


#Examples
Enable Diagnostics on all ARM specific VMs, within specific subscriptions
Automatically determine storage account to be used
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Arm'
```
Enable Diagnostics on specific ARM VMs, within specific subscriptions
Automatically determine storage account to be used
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Arm' -ChooseSubscription -ChooseVM
```
Enable Diagnostics on specific Classic VMs, within specific subscriptions, choosing storage
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Classic' -ChooseSubscription -ChooseVM -ChooseStorage
```
Enable Diagnostics on specific Classic Linux VMs, within specific subscriptions, overriding existing diagnostic settings
Automatically determine storage account to be used
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Classic' -OsType 'Linux' -OverrideDiagnostics
```
