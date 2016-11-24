New-Module -name CommonModule -ScriptBlock {

    function LoadSubscriptions() {

        $default = Login-AzureRmAccount
        
        return Get-AzureRmSubscription | Where {$_.State -eq "Enabled"}
    }

    function SelectSubscription() {
        Param (
            [Parameter(Mandatory=$true)]
            [string]$subscriptionId
        )

        Select-AzureSubscription -SubscriptionId $subscriptionId
	    Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Insights
    }

    function LoadStorageAccounts {
        $allStorages = @{}

	    Write-Host("Getting existing storage accounts")
        $arr = @()

	    $storageAccounts = Get-AzureStorageAccount | Where {$_.AccountType.StartsWith("Standard")}
        foreach($storageAccount in $storageAccounts) {
            $arr = $arr + (WrapClassicResource $storageAccount $storageAccount.StorageAccountName "StorageAccountName" "Microsoft.ClassicStorage/storageAccounts" $storageAccount.Location)
        }

        $arr | Group-Object -Property Location | foreach { $allStorages.Add($_.Name, $_.Group) }

        return $allStorages
    }

    function WrapClassicResource() {
        Param (
            [Parameter(Mandatory=$true)]
            [System.Object]$ClassicReource,
            [Parameter(Mandatory=$true)]
            [string]$ResourceName,
            [Parameter(Mandatory=$true)]
            [string]$ResourcePropertyName,
            [Parameter(Mandatory=$true)]
            [string]$ResourceType,
            [string]$Location
        )

        $resource = Find-AzureRmResource -Name $ResourceName -ResourceType $ResourceType -WarningAction Ignore
        $props = @{ClassicResource = $ClassicReource; Resource = $resource; ResourceGroupName = $resource.ResourceGroupName; Location = $Location; $ResourcePropertyName = $ResourceName; ResourceId = $resource.ResourceId}
        return New-Object PSObject –Property $props
    }

    function CreateStorageAccount {
    Param (
    		[Parameter(Mandatory=$true)]
    		[string] $ResourceGroupName,
    		[Parameter(Mandatory=$true)]
    		[string] $StorageName,
            [Parameter(Mandatory=$true)]
    		[string] $Location
    )
        New-AzureStorageAccount -StorageAccountName $StorageName -Location $Location -Type "Standard_LRS"
        $storageAccount = Get-AzureStorageAccount -StorageAccountName $StorageName
        
        Start-Sleep 5
        $storageAccount.Context

        $storageResource = WrapClassicResource $storageAccount.Context $storageAccount.StorageAccountName "StorageAccountName" "Microsoft.ClassicStorage/storageAccounts" $storageAccount.Location

        Move-AzureRmResource -DestinationResourceGroupName $ResourceGroupName -ResourceId $storageResource.ResourceId -Force
        $storageResource.ResourceGroupName = $ResourceGroupName

        return $storageResource
    }

    function LoadVirtualMachines() {
        $vms = $null

        if ($OsType){
            $vms = Get-AzureVM | where {$_.VM.OSVirtualHardDisk.OS -eq $OsType}
        } else {
            $vms = Get-AzureVM
        }
        
        return $vms | foreach{ WrapClassicResource $_ $_.Name "Name" "Microsoft.ClassicCompute/virtualMachines" (Get-AzureService -ServiceName $_.ServiceName).Location }
    }

    function ReloadVm() {
        Param (
            [Parameter(Mandatory=$true)]
            [System.Object] $Vm
        )

        $reloadedVm = Get-AzureVm -ServiceName $Vm.ClassicResource.ServiceName -Name $Vm.Name
        $Vm.ClassicResource = $reloadedVm
        return $Vm
    }

    function CreateVirtualMachineResultObject {
        Param (
            [Parameter(Mandatory=$true)]
		    [System.Object] $Vm
        )
    
        $virtualMachineProperties = @{
            'OsType' = $Vm.ClassicResource.VM.OSVirtualHardDisk.OS.ToString();
            'VmName' = $Vm.Name
            'ResourceGroupName' = $Vm.ResourceGroupName;
            'StorageAccountName' = "";
            'Result' = @{'Status' = $null; 'ReasonOfFailure' = $null};
            'IsOverriden' = $false
        }
    
        return New-Object –TypeName PSObject –Prop $virtualMachineProperties
    }

    function IsRunning() {
        Param (
    		[Parameter(Mandatory=$true)]
    		[System.Object] $Vm
    	)

        return $vm.ClassicResource.PowerState -eq "Started"

    }

    function IsDiagnosticsEnabled() {
       	Param (
    		[Parameter(Mandatory=$true)]
    		[System.Object] $Vm
    	)

        $diag = $null
        $ResourceGroupName = $vm.ResourceGroupName

        switch -regex ($Vm.ClassicResource.VM.OSVirtualHardDisk.OS) {
            "[Ww]indows" {$diag = Get-AzureVMDiagnosticsExtension -VM $Vm.ClassicResource.VM}
            "[Ll]inux" {$diag = Get-AzureVMExtension -VM $Vm.ClassicResource.VM | where {$_.ExtensionName -eq "LinuxDiagnostic"}}
            default {throw [System.InvalidOperationException] "$OsType is not supported. Allowed values are 'Windows' or 'Linux' "}
        }
        

        if ($diag -eq $null) {
		    return $false
	    }

	    $cfg = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((ConvertFrom-Json -InputObject $diag.PublicConfiguration).xmlCfg))
	    if (([xml]$cfg).WadCfg.DiagnosticMonitorConfiguration.Metrics -eq $null) {
		    return $false
	    }

		return $true
    }

    function SetVmDiagnostic() {
        Param (
            [Parameter(Mandatory=$true)]
		    [System.Object] $Vm,
            [Parameter(Mandatory=$true)]
            [System.Object] $Storage,
            [Parameter(Mandatory=$true)]
            [string] $CfgPath
        )

        $vmName = $Vm.Name
        $ResourceGroupName = $Vm.ResourceGroupName
        $VmLocation =  $Vm.Location

	    Write-Host("Enabling Classic diagnostics for '$vmName' virtual machine")
	    Write-Host("Enabling diagnostics")

        $classicVm = $Vm.ClassicResource
        switch -regex ($classicVm.VM.OSVirtualHardDisk.OS) {
            "[Ww]indows" {
                $vmUpdate = Set-AzureVMDiagnosticsExtension -DiagnosticsConfigurationPath $CfgPath -VM $classicVm -StorageContext $Storage.ClassicResource.Context
                Update-AzureVM -ServiceName $Vm.ClassicResource.ServiceName -Name $Vm.Name -VM $vmUpdate.VM
            }
            "[Ll]inux" {     
                $content = Get-Content($CfgPath)
                $xmlCfg = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

                $storageName = $Storage.StorageAccountName
                $storageKey = (Get-AzureStorageKey -StorageAccountName $storageName).Primary

                $privateSetting = ConvertTo-Json (@{storageAccountName = $storageName; storageAccountKey = $storageKey})
                $publicSetting = ConvertTo-Json (@{StorageAccount = $storageName; xmlCfg = $xmlCfg})

                Set-AzureVMExtension -ExtensionName "LinuxDiagnostic" -VM $classicVm -Publisher "Microsoft.OSTCExtensions" -PublicConfiguration $publicSetting -PrivateConfiguration $privateSetting -Version 2.3 | Update-AzureVm -ServiceName $vm.ClassicResource.ServiceName -Name $vm.Name -WarningAction Ignore
            }
        }   


		Write-Host("Diagnostics enabled")
    }

    Export-ModuleMember -Function LoadSubscriptions
    Export-ModuleMember -Function SelectSubscription
    Export-ModuleMember -Function LoadStorageAccounts 
    Export-ModuleMember -Function LoadVirtualMachines
    Export-ModuleMember -Function CreateVirtualMachineResultObject
    Export-ModuleMember -Function ReloadVm
    Export-ModuleMember -Function CreateStorageAccount
    Export-ModuleMember -Function IsRunning
    Export-ModuleMember -Function IsDiagnosticsEnabled
    Export-ModuleMember -Function SetVmDiagnostic

} | Import-Module
