# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

Param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Arm","Classic")] 
    [string] $DeploymentModel,
    [ValidateSet("Windows","Linux")] 
    [string] $OsType,
    [ValidateSet('AzureCloud',
                 'AzureUSGovernment',
                 'AzureChinaCloud',
                 'AzureGermanCloud')]
    [string] $Environment = 'AzureCloud',
	[switch] $ChooseSubscription,
	[switch] $ChooseStorage,
	[switch] $StoragePerLocation,
	[switch] $ChooseVM,
	[switch] $OverrideDiagnostics
)

#######################################

function CreateResultObject {

    $statusProperties = @{
        'RunType' = @{
            'DeploymentModel'= $DeploymentModel;
            'OverrideDiagnostics' = $OverrideDiagnostics;
        }
        'Subscriptions' = @();
    }

    return New-Object –TypeName PSObject –Prop $statusProperties
}

function CreateSubscriptionResultObject {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $SubscriptionName
    )

    $subscriptionProperties = @{
        'SubscriptionName' = $SubscriptionName;
        'StorageAccounts' = @()
        'VirtualMachines' = @()
        'Result' = @{'Status' = $null; 'ReasonOfFailure' = $null};
    }

    return New-Object –TypeName PSObject –Prop $subscriptionProperties
}

function CreateStorageAccountResultObject {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory=$true)]
		[string] $ResourceGroupName,
        [Parameter(Mandatory=$true)]
		[string] $Location,
        [string] $Status
    )

    $storageAccountProperties = @{
        'StorageAccountName' = $StorageAccountName;
        'ResourceGroupName' = $ResourceGroupName;
        'Location' = $Location;
        'Status' = $Status
    }

    return New-Object –TypeName PSObject –Prop $storageAccountProperties
}

function AcquireStorageAccounts() {
    Param (
	    [System.Object[]]$Vms,
        [System.Object]$SubscriptionResult
	)

	Write-Host("Checking storage in each resource group and location")

    $allStorages = LoadStorageAccounts
	$storagesToUse = @{}
    
	$vmGroupedByLocation = $vms | Group-Object -Property Location

	foreach ($vmLocationGroup in $vmGroupedByLocation) {

	    $location =  $vmLocationGroup.Name;
	    $locationStorages = $allStorages[$location]
        $storagesToUse[$location] = @()

	    Write-Host("Checking storage in '$location' location")

        $storageToUse = $null
        if ($StoragePerLocation) {
            $input = Read-Host("Enter name for resource group (press enter to use 'DiagnosticStorageAccounts') for new storage accounts")

            $resourceGroupName = if ($input) {$input} else {"DiagnosticStorageAccounts"}
            EnsureResourceGroupExists -ResourceGroupName $resourceGroupName -Location $location

            $storageToUse = AcquireStorageAccountsInGroup -SubscriptionResult $SubscriptionResult -ResourceGroupName $resourceGroupName -StoragesToLookIn $locationStorages -Location $location -AllStorages $allStorages -StoragesToUse $storagesToUse
        } else {

            $vmGroupedByResourceGroup = $vmLocationGroup.Group | Group-Object -Property ResourceGroupName
	        foreach ($vmResourceGroupGroup in $vmGroupedByResourceGroup)
	        {
                $resourceGroupName = $vmResourceGroupGroup.Name
                $resourceGroupStorages = $LocationStorages | where { $_.ResourceGroupName -eq $resourceGroupName  }
		        $storageToUse = AcquireStorageAccountsInGroup -SubscriptionResult $SubscriptionResult -ResourceGroupName $resourceGroupName -StoragesToLookIn $resourceGroupStorages -Location $location -AllStorages $allStorages -StoragesToUse $storagesToUse
	        }
        }

	}
	return $storagesToUse
}

function AcquireStorageAccountsInGroup() {
    Param (
        [System.Object]$SubscriptionResult,
        [String]$ResourceGroupName,
        [String]$Location,
        [System.Array]$StoragesToLookIn,
        [Hashtable]$AllStorages,
        [Hashtable]$StoragesToUse

	)
	$toCreate = $false
    $storageAccountResult = $null

    $storageToUse = $null
    if ($StoragesToLookIn -ne $null) {
        $storageToUse = SelectStorage $StoragesToLookIn -Location $Location -ResourceGroupName $ResourceGroupName
	} 

	if ($storageToUse -eq $null) {
        $storageToUse = CreateStorage -ResourceGroupName $ResourceGroupName -Location $Location
	    [array]$AllStorages[$location] += $storageToUse

	    $storageName = $storageToUse.StorageAccountName
        $storageAccountResult = CreateStorageAccountResultObject -StorageAccountName $storageName -ResourceGroupName $ResourceGroupName -Location $Location -Status "New"
	    Write-Host("'$storageName' storage account for resource group '$ResourceGroupName' in location '$Location' was created")
	}
	else{
	    $storageName = $storageToUse.StorageAccountName
        $storageAccountResult = CreateStorageAccountResultObject -StorageAccountName $storageName -ResourceGroupName $storageToUse.ResourceGroupName -Location $Location -Status "Existing"

        $message = $null
        $message = if ($StoragePerLocation) {
            "Using '$storageName' storage account in location '$Location'"
        } else {
            "Using '$storageName' storage account for resource group '$ResourceGroupName' in location '$Location'"
        }
	    Write-Host($message)
	}

	[array]$StoragesToUse[$location] += $storageToUse
    $SubscriptionResult.StorageAccounts += $storageAccountResult
}

function EnsureResourceGroupExists {
    Param (
        [Parameter(Mandatory=$true)]
        [String] $ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [String] $Location
    )

    $rg = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Ignore
    if ($rg) {
        return
    }

    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

function SelectStorage() {
    Param (
        [Parameter(Mandatory=$true)]
        [System.Object[]]$existsingStorageAccounts,
        [string]$Location,
        [string]$ResourceGroupName
    )

    if(!$ChooseStorage){
        return $existsingStorageAccounts[0]
    }

    $message = if ($StoragePerLocation) {
        "There are existing storage account/s in location '$location':"
    } else {
        "There are existing storage account/s for resource group '$resourceGroupName' in location '$location':"
    }

	Write-Host($message)
    Write-Host("")

	$storageName = $existsingStorageAccounts | foreach {Write-Host($_.StorageAccountName)}
    Write-Host("")

    $toSkip = ToSkip "Use one of them?" $ChooseStorage
    if ($toSkip) {
        return $null
    }

    $selectedStorage = $null
    $chosen = $false
    while (!$chosen) {
        $choice = Read-Host ("Enter name of storage account you want to use")
        $selectedStorage = $existsingStorageAccounts | where {$_.StorageAccountName -eq $choice}

        $chosen = $selectedStorage -ne $null
    }

    return $selectedStorage
}

function CreateStorage() {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [string]$Location
              
    )

    $storageName = $null
	$storageName = GetStorageName $ResourceGroupName $Location $ChooseStorage
    Write-Host("Creating storage account'$storageName' for resource group '$resourceGroupName' in location '$location'")

	$retries = 0
    $storageCreated = $false

	while (!$storageCreated)
	{
        try {
		    Write-Host("Creating '$storageName' storage account")
            $storageToUse = CreateStorageAccount $resourceGroupName $storageName $location
    
		    $storageCreated = $true
            return $storageToUse
	    }
	    catch {
		    Write-Host("Failed to create storage")
		    $_

		    if  ($retries -ge 3) {
			    Write-Host("Failed to create storage more than 3 times, terminating script")
			    exit
		    }
		    Write-Host("Retry")
		    $retries++;
	    }
	}
}

function ToSetDiagnostics(){
	Param (
        [Parameter(Mandatory=$true)]
		[System.Object] $Vm,
        [Parameter(Mandatory=$true)]
		[System.Object] $virtualMachineResult
	)
    
    $vmName = $Vm.Name
    $isVmRunning = IsRunning $Vm
    if (!$isVmRunning){
        Write-Host("'$vmName' VM is not running")
        $virtualMachineResult.Result.Status = "Skipped"
        $virtualMachineResult.Result.ReasonOfFailure = "Vm is not running"
        return $false
    }

    $isVmAgentReady = IsVmAgentReady $Vm
    if (!$isVmAgentReady){
        Write-Host("VM agent on '$vmName' is not ready")
        $virtualMachineResult.Result.Status = "Skipped"
        $virtualMachineResult.Result.ReasonOfFailure = "Vm agent is not ready"
        return $false
    }

    if (ToSkip "Do you want to enable diagnostic for '$vmName'?" $ChooseVM){
        $virtualMachineResult.Result.Status = "Skipped"
        $virtualMachineResult.Result.ReasonOfFailure = "User choice"
        return $false
	}

    $isEnabled = IsDiagnosticsEnabled $Vm
    if (!$isEnabled){
		return $true
    }

	Write-Host("Diagnostics already enabled for '$vmName'")
	if ($OverrideDiagnostics) {
		Write-Host("Overriding")
        $virtualMachineResult.IsOverriden = $true
		return $true
	}

    $virtualMachineResult.Result.Status = "Skipped"
    $virtualMachineResult.Result.ReasonOfFailure = "Diagnostics already enabled"
    return $false
}

function SetDiagnostics {
    	Param (
        [Parameter(Mandatory=$true)]
		[System.Object] $vm,
        [Parameter(Mandatory=$true)]
        [System.Object] $storage
	)

    $cfgPath = $null

    switch -Regex ($DeploymentModel){
        "[Aa]rm" {$cfgPath = GetDiagnosticsConfigPath $path $vm.Id $vm.StorageProfile.OsDisk.OsType }
        "[Cc]lassic" {$cfgPath = GetDiagnosticsConfigPath $path $vm.ResourceId $vm.ClassicResource.VM.OSVirtualHardDisk.OS}
    }
	 
    SetVmDiagnostic $vm $storage $cfgPath
}

#######################################

$path = split-path -parent $MyInvocation.MyCommand.Definition

switch -Regex ($DeploymentModel){
    "[Aa]rm" {&($path + "/ArmModule.ps1")}
    "[Cc]lassic" {&($path + "/ClassicModule.ps1"
    )} 
    default {throw [System.InvalidOperationException] "$DeploymentModel is not supported. Allowed values are 'Arm' or 'Classic' "}
}

&($path + "/CommonModule.ps1")

EnableLogging $path
$ErrorActionPreference = "Stop"

$subscriptions = $null
$subscriptions = LoadSubscriptions -EnvironmentName $Environment

$subscriptionsCount = $subscriptions.Length
Write-Host("Found $subscriptionsCount subscriptions")

$Result = CreateResultObject
foreach ($subscription in $subscriptions){
    $subscriptionId = if ($subscription.SubscriptionId) {
            $subscription.SubscriptionId
        }
        else {
            $subscription.Id
        }
    $subscriptionName = if ($subscription.SubscriptionName)
        {
            $subscription.SubscriptionName
        }
        else {
            $subscription.Name
        }
        
    $subscriptionResult = CreateSubscriptionResultObject -SubscriptionName $subscriptionName
    $Result.Subscriptions += $subscriptionResult

	try {
		if (ToSkip "Do you want to enable diagnostic in '$subscriptionName' subscription?" $ChooseSubscription){
            $subscriptionResult.Result.Status = "Skipped"
            $subscriptionResult.Result.ReasonOfFailure = "User choice"
			continue
		}

		Write-Host("Enabling diagnostics in '$subscriptionName' subscription")
		SelectSubscription $subscriptionId

		$vms = LoadVirtualMachines $OsType
		$vmsCount = $vms.Length
		if ($vms.Length -eq 0) {
			Write-Host ("No vm were found")
            $subscriptionResult.Result.Status = "Skipped"
            $subscriptionResult.Result.ReasonOfFailure = "No vm were found"
			continue
		}

		Write-Host ("Found $vmsCount virtual machines")
		Write-Host("Acquiring storage accounts")
		
        $storages = @{}
		$storages = AcquireStorageAccounts $vms $subscriptionResult
		foreach ($vm in $vms){
			$resourceGroupName = $vm.ResourceGroupName
            $vmName = $vm.Name
            $vmLocation = $vm.Location

            $virtualMachineResult = CreateVirtualMachineResultObject -Vm $vm
            $subscriptionResult.VirtualMachines += $virtualMachineResult

            try {
                $reloadedVm = ReloadVm $vm
			    $toSet = ToSetDiagnostics $reloadedVm $virtualMachineResult

			    if (!$toSet) {
				    continue
			    }
                
                $storageInLocation = ([hashtable]($storages)).Get_Item($vmLocation)
	            $storage = if ($StoragePerLocation) {$storageInLocation} else {$storageInLocation | where {$_.ResourceGroupName -eq $resourceGroupName}}
                $virtualMachineResult.StorageAccountName = $storage.StorageAccountName
    
                SetDiagnostics $reloadedVm $storage
                $virtualMachineResult.Result.Status = "Success"
            }
            catch {
		        Write-Host("Failed to enable diagnostic for '$vmName' VM")
		        $_
                $virtualMachineResult.Result.Status = "Failed"
                $virtualMachineResult.Result.ReasonOfFailure = $_
	        }
		}

        $subscriptionResult.Result.Status = "Succeed"
    }
	catch {
		Write-Host("Failed to enable diagnostic for '$subscriptionName' subscription")
		$_
        $subscriptionResult.Result.Status = "Failed"
        $subscriptionResult.Result.ReasonOfFailure = $_
	}
}
$Result | ConvertTo-Json -Compress -Depth 7 | Out-File ($path + "/logs/" + 
$DeploymentModel.ToLower() + "_" + ((Get-Date).ToUniversalTime()).ToString("yyyyMMddTHHmmssfffffffZ") + ".json")