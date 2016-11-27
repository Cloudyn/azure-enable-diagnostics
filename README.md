# Azure Enable Diagnostics

azure-enable-diagnostics automates enabling monitoring Diagnostics on Azure VMs.

For details on the context for this utility, see [Enabling Azure Diagnostics](https://www.cloudyn.com/blog/)

#Algorithm
The script following the following algorithm:
* Prompt for the login credentials of a Azure user
* Loop through each of the assigned subscription
* For each subscription that the user wants to enabled:
   * Register the Resource Provider: "Microsoft.Insights"
   * Loop through each of the resource groups in the chosen deployment model (Arm / Classic)
      * Determine if there exists a Standard storage account for the resource group location
      * If relevant, recommend existing relevant storage account
      * Allow user to override storage account choice for each resource group location
      * Create Standard storage account if necessary
   * Loop through each VM in the subscription
      * If the user wants to enable diagnostics, and the VM is running, then:
      * Enable Monitoring Diagnostics, and set the Storage.
      * For Linux - Enable: Basic metrics
      * For Windows - Enable: Basic metrics, Network metrics, Diagnostics infrastructure logs
  * The entire output is logged to a subdirectory.

#Prerequisites

##Once off
Start "Windows PowerShell" with "Run as Administrator"
```PowerShell
Install-Module Azure
Install-Module AzureRM -Force
```

##Per session
Type the following to enable running an unsigned script in PowerShell session.
When you close session, the policy will return to default.
```PowerShell
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
```

#Parameters
* **DeploymentModel**
    "Arm" / "Classic"  (Mandatory)
    Arm refers to "Azure Resource Manager"
    Classic refers to "Service Manager"
* **OsType**
    "Windows" / "Linux" (Optional. Default = both)
* **ChooseSubscription**
    Default = true
    Prompt the user to choose which subscriptions assigned to the current user should have their subscriptions enabled.
* **ChooseStorage**
    Default = false
    Prompt the user to choose which Storage Accounts should be used per ResourceGroup-Location combination.
* **ChooseVM**
    Default = false
    Prompt the user to choose which VMs should have Diagnostics enabled.
* **OverrideDiagnostics**
    Default = false
    Whether to override diagnostics of VMs that already have diagnostic settings enabled.


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
