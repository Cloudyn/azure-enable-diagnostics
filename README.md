# Azure Enable Diagnostics

azure-enable-diagnostics automates enabling Monitoring Diagnostics on Azure VMs.

For details on the context for this utility, see [Enabling Azure Diagnostics](https://www.cloudyn.com/blog/)

For each subscription assigned to the entered Azure login credentials:
   * Register the Resource Provider: "Microsoft.Insights"
   * Create or choose a Standard storage account to use for each resource group location
   * For chosen running VMs, enable Monitoring Diagnostics, set the Storage
     * For Linux, enable: Basic metrics
     * For Windows, enable: Basic metrics, Network metrics, Diagnostics infrastructure logs

The user can control:
* which subscriptions
* which storage account
* diagnostics storage account grouping methology:
    * per location, or
    * per resource group per location
* which VMs: Classic/Arm, Windows/Linux
* whether to override existing diagnostics settings

The outcome of the script is logged to file.


#Prerequisites
The following installation tasks are required once-off.
Start "Windows PowerShell" with "Run as Administrator"
```PowerShell
Install-Module Azure
Install-Module AzureRM -Force
```

#Parameters
* **DeploymentModel**
    * "Arm" / "Classic"
    * Mandatory
    * Arm refers to "Azure Resource Manager"
    * Classic refers to "Service Manager"
* **OsType**
    * "Windows" / "Linux"
    * Default = both
* **ChooseSubscription**
    * Prompt the user to choose which subscriptions assigned to the current user should have their subscriptions enabled.
    * Default = true
* **ChooseStorage**
    * Prompt the user to choose/create which Standard Storage Accounts should be used per ResourceGroup-Location combination.
    * Default = false
* **StoragePerLocation**
    * Use a single Diagnostics Storage Account per location
    * Default = Use a Diagnostics Storage Account per ResourceGroup per location
* **ChooseVM**
    * Prompt the user to choose which VMs should have Diagnostics enabled.
    * Default = false
* **OverrideDiagnostics**
    * Whether to override diagnostics of VMs that already have diagnostic settings enabled.
    * Default = false


#Examples
Enable Diagnostics on all ARM specific VMs, within specific subscriptions.
Automatically determine storage account to be used. Use a single storage account per location
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Arm' -StoragePerLocation
```
Enable Diagnostics on all ARM specific VMs, within specific subscriptions.
Automatically determine storage account to be used. Use a single storage account per location
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Arm' -ChooseSubscription -StoragePerLocation 
```
Enable Diagnostics on specific ARM VMs, within specific subscriptions.
Automatically determine storage account to be used. Use storage account per resource group + location
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Arm' -ChooseSubscription -ChooseVM
```
Enable Diagnostics on specific Classic VMs, within specific subscriptions, choosing storage account resource group + location
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Classic' -ChooseSubscription -ChooseVM -ChooseStorage
```
Enable Diagnostics on specific Classic Linux VMs, within specific subscriptions, overriding existing diagnostic settings. Use storage account per location per resource group.
Automatically determine storage account to be used
```PowerShell
.\EnableDiag.ps1 –DeploymentModel 'Classic' -OsType 'Linux' -OverrideDiagnostics
```

#Troubleshooting

## Non digitally signed warning
You may get the following warning when running script:
```
File CommonModules.ps1 cannot be loaded. The file CommonModules.ps1 is not digitally signed.
You cannot run this script on the current system. For more information about running scripts and setting execution
policy, see about_Execution_Policies at http://go.microsoft.com/fwlink/?LinkID=135170.
```
To address this, type the following to enable running an unsigned script in PowerShell session.
```PowerShell
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
```
Type "Y" to change the execution policy.
When you close session, the policy will return to default.


## Non trusted scripts warning
You may get the following warning 3 times when running script:
```
Run only scripts that you trust. While scripts from the internet can be useful, this script can potentially harm your
computer. If you trust this script, use the Unblock-File cmdlet to allow the script to run without this warning
message. Do you want to run EnableDiag.ps1?
[D] Do not run  [R] Run once  [S] Suspend  [?] Help (default is "D"):
```
To address this, either press "R" for each of the 3 files presented, or alternatively type:
```PowerShell
Unblock-File EnableDiag.ps1
Unblock-File ArmModule.ps1
Unblock-File ClassicModule.ps1
Unblock-File CommonModule.ps1
```

## Portal doesn’t support configuring VM diagnostics using JSON
After enabling diagnostics on a Classic VM, you may see the following message in the Portal UI:
"The Azure Portal currently doesn’t support configuring virtual machine diagnostics using JSON. Instead, use PowerShell or CLI to configure diagnostics for this machine".
This message is should automatically disappear when you recheck the VM a bit later.


# Customizing
The configuration can be overridden by custom defined user diagnostics by replacing the *DiagConfig.xml file(s) before running the script.

## Referenced articles
https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-ps-extensions-diagnostics
https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-linux-classic-diagnostic-extension
