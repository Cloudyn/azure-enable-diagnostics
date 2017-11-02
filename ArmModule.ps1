# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

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

        Select-AzureRmSubscription -SubscriptionId $subscriptionId
	    Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Insights
    }

    function LoadStorageAccounts {
        
        $allStorages = @{}

	    Write-Host("Getting existing storage accounts")
	    (Get-AzureRmStorageAccount | Where {$_.Sku.Tier -eq "Standard"} | Group-Object -Property Location) | foreach { $allStorages.Add($_.Name, $_.Group) }

        return $allStorages
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

        return New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageName -SkuName "Standard_LRS" -Location $Location
    }

    function LoadVirtualMachines() {
        Param (
            [string]$OsType
        )

        if ($OsType){
            return Get-AzureRmVM | where {$_.StorageProfile.OsDisk.OsType -eq $OsType}
        }
        
        return Get-AzureRmVM
    }

    function ReloadVm() {
        Param (
            [Parameter(Mandatory=$true)]
            [System.Object] $Vm
        )

        return Get-AzureRmVM -VMName $Vm.Name -ResourceGroupName $Vm.ResourceGroupName
    }

    function CreateVirtualMachineResultObject {
        Param (
            [Parameter(Mandatory=$true)]
		    [System.Object] $Vm
        )
    
        $virtualMachineProperties = @{
            'OsType' = $Vm.StorageProfile.OsDisk.OsType.ToString();
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

        $status = Get-AzureRmVM -ResourceGroupName $Vm.ResourceGroupName -Name $Vm.Name -Status
        return [bool] ($status.Statuses | foreach { [bool] ($_.Code -eq "PowerState/running") } | where { $_ } | select -first 1)
    }

    function IsVmAgentReady() {
        Param (
    		[Parameter(Mandatory=$true)]
    		[System.Object] $Vm
    	)

        $status = (Get-AzureRmVM -ResourceGroupName $Vm.ResourceGroupName -Name $Vm.Name -Status).VMAgent
        return [bool] ($status.Statuses | foreach { [bool] ($_.DisplayStatus -eq "Ready") } | where { $_ } | select -first 1)
    }

    function IsDiagnosticsEnabled() {
       	Param (
    		[Parameter(Mandatory=$true)]
    		[System.Object] $Vm
    	)

        $diag = $null
        $ResourceGroupName = $vm.ResourceGroupName

        switch -regex ($Vm.StorageProfile.OsDisk.OsType) {
            "[Ww]indows" {$diag = Get-AzureRmVMDiagnosticsExtension -ResourceGroupName $ResourceGroupName -VMName $Vm.Name}
            "[Ll]inux" {

                $extensionName = $null
                $extension = $Vm.Extensions | Where {$_.VirtualMachineExtensionType -eq "LinuxDiagnostic"}

                if (!$extension) {
		            return $false
                }

                $diag = Get-AzureRmVMExtension -ResourceGroupName $ResourceGroupName -VMName $Vm.Name -Name $extension.Name -ErrorAction Ignore
            } 
            default {throw [System.InvalidOperationException] "$OsType is not supported. Allowed values are 'Windows' or 'Linux' "}
        }

        if ($diag -eq $null) {
		    return $false
	    }

	    $cfg = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((ConvertFrom-Json -InputObject $diag.PublicSettings).xmlCfg))
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

        $ErrorActionPreference = "Stop"

        $vmName = $Vm.Name
        $ResourceGroupName = $Vm.ResourceGroupName
        $VmLocation =  $Vm.Location

        $storageName = $Storage.StorageAccountName
    	$storageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $Storage.ResourceGroupName -Name $storageName)[0].Value
	
	    Write-Host("Enabling ARM diagnostics for '$VmName' virtual machine")
        
        Write-Host("Enabling diagnostics")
        switch -regex ($Vm.StorageProfile.OsDisk.OsType) {
            "[Ww]indows" {
                Set-AzureRmVMDiagnosticsExtension -ResourceGroupName $ResourceGroupName -VMName $vmName -DiagnosticsConfigurationPath $CfgPath -StorageAccountName $storageName -StorageAccountKey $storageKey
            }
            "[Ll]inux" {

                $content = Get-Content($CfgPath)
                $xmlCfg = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

                $publicSetting = @{StorageAccount = $storageName; xmlCfg = $xmlCfg}
                $privateSettings = @{storageAccountName = $storageName; storageAccountKey = $storageKey}

                $extensionName = $null
                $extension = $Vm.Extensions | Where {$_.VirtualMachineExtensionType -eq "LinuxDiagnostic"}

                if ($extension) {
                    $extensionName = if ([string]::IsNullOrWhiteSpace($extension.Name)) {"LinuxDiagnostic"} else {$extension.Name}
                } else {
                    $extensionName = "LinuxDiagnostic"
                }

                Write-Host("Using $extensionName as linux diagnostics extension name")
                Set-AzureRmVMExtension -ResourceGroupName $ResourceGroupName -VMName $vmName -Publisher "Microsoft.OSTCExtensions" -ExtensionType "LinuxDiagnostic" -Name $extensionName -Location $VmLocation -Settings $publicSetting -ProtectedSettings $privateSettings -TypeHandlerVersion "2.3" 
            } 
            default {throw [System.InvalidOperationException] "$OsType is not supported. Allowed values are 'Windows' or 'Linux' "}
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
    Export-ModuleMember -Function IsVmAgentReady
    Export-ModuleMember -Function IsDiagnosticsEnabled
    Export-ModuleMember -Function SetVmDiagnostic

} | Import-Module
