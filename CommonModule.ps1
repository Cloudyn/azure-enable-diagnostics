# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 

New-Module -name CommonModule -ScriptBlock {
    function EnableLogging() {
    	Param (
            [Parameter(Mandatory=$true)]
            [string]$path
        )
    
        $logPath = $path + "/logs/" + ((Get-Date).ToUniversalTime()).ToString("yyyyMMddTHHmmssfffffffZ") + "_log.txt"
    	$ErrorActionPreference="SilentlyContinue"
    	Stop-Transcript | out-null
    	Start-Transcript -path $logPath -append
    }
 
    function ToSkip() {
    	Param (
    		[string]$Message,
            [bool]$DebugMode
    	)
    
    	if ($DebugMode){
    		Write-Host ($Message)

            $response = "y"
            
            while ($true) {
    		    $response = Read-Host ("Enter 'y' for yes (default), 'n' for no, 'a' to abort script")
                if (!$response) {$response = "y"}
                switch -Regex ($response) {
                    "(?i)^y(es)?$" {return $false}
                    "(?i)^n(o)?$" {return $true}
                    "(?i)^a(bort)?$" {exit}
                }
            }
    	}
    }
    
    function GetStorageName() {
    	Param (
    		[Parameter(Mandatory=$true)]
    		[string] $ResourceGroupName,
    		[Parameter(Mandatory=$true)]
    		[string] $Location,
            [bool]$ChooseStorage
    	)
    
    	$storageName = $null
    
    	if($ChooseStorage) {
    		Write-Host("Enter name for storage account for resource group '$ResourceGroupName' in location '$Location'")
            if (ToSkip "Use auto name generation?" $ChooseStorage) {
        		Write-Host("Name should contain only lowercase alphanumeric characters, at least 6 characters and maximum 24")
    		    $storageName = Read-Host ("Enter storage account name")

    			return $storageName
            }
    	} 
    
    	$storageName = $null
    
    	$charsOnly = $ResourceGroupName -replace '[^a-zA-Z0-9]', ''
    	$substring = $charsOnly.Substring(0, (($charsOnly.Length, 14) | measure -Minimum).Minimum)
    	$storageName = $substring.ToLower() + "diag" + (Get-Random -Maximum 999999).ToString("000000");
    
    	return $storageName
     }
    
    function GetDiagnosticsConfigPath() {
	    Param (
	    	[Parameter(Mandatory=$true)]
	    	[string]$Path,
	    	[Parameter(Mandatory=$true)]
	    	[string]$VmId,
	    	[Parameter(Mandatory=$true)]
            [string]$OsType
	    )
        
        $xmlConfigPath = $null

        switch -regex ($OsType) {
            "[Ww]indows" {$xmlConfigPath = $Path + "/winDiagConfig.xml"}
            "[Ll]inux" {$xmlConfigPath = $Path + "/linuxDiagConfig.xml"} 
            default {throw [System.InvalidOperationException] "$OsType is not supported. Allowed values are 'Windows' or 'Linux' "}
        }
        
	    $xmlConfig = [xml](Get-Content $xmlConfigPath)
	    $xmlConfig.WadCfg.DiagnosticMonitorConfiguration.Metrics.SetAttribute("resourceId", $VmId)
	    $tmpPath = [System.IO.Path]::GetTempFileName()
	    $xmlConfig.Save($tmpPath)

	    return $tmpPath
    }
    
    Export-ModuleMember -Function EnableLogging
    Export-ModuleMember -Function ToSkip
    Export-ModuleMember -Function GetStorageName
    Export-ModuleMember -Function GetDiagnosticsConfigPath

} | Import-Module