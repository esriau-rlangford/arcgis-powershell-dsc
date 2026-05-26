$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the ArcGIS Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Common' `
            -ChildPath 'ArcGIS.Common.psm1'))

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $True)]    
        [System.String]
        $Version,

        [System.String] 
        [parameter(Mandatory = $True)]
        $PortalInstallDirectory,

        [ValidateSet('Import', 'Export')]
        [parameter(Mandatory = $True)]
        [System.String]
        $Action,

        [parameter(Mandatory = $True)]
        [System.String]
        $PropertiesFilePath,

        [parameter(Mandatory = $False)]
        [System.Int32] 
        $TimeoutInMinutes = 3600 # 10 hours
    )

    @{}
}
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $True)]    
        [System.String]
        $Version,

        [System.String] 
        [parameter(Mandatory = $True)]
        $PortalInstallDirectory,

        [ValidateSet('Import', 'Export')]
        [parameter(Mandatory = $True)]
        [System.String]
        $Action,

        [parameter(Mandatory = $True)]
        [System.String]
        $PropertiesFilePath,

        [parameter(Mandatory = $False)]
        [System.Int32] 
        $TimeoutInMinutes = 3600 # 10 hours
    )

    $WebGISToolPath = Join-Path -Path $PortalInstallDirectory 'tools\webgisdr\webgisdr.bat'
    if(-not(Test-Path $WebGISToolPath -PathType Leaf)){
        throw "$WebGISToolPath not found"
    }

    if(-not(Test-Path $PropertiesFilePath -PathType Leaf)){
        throw "$PropertiesFilePath not found"
    }

    Write-Verbose "WebGIS DR $($Action) started by user $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)."

    $Arguments = $null
    # Code to set the desired state
    if($Action -eq 'Import') {
        $Arguments = " --import --file `"$($PropertiesFilePath)`""
    }elseif($Action -eq 'Export') {
        $Arguments = " --export --file `"$($PropertiesFilePath)`""
    }else {
        throw "Invalid Action"
    }

    try{
        Invoke-StartProcess -ExecPath $WebGISToolPath -Arguments $Arguments -EnvVariables @{"AGSPORTAL" = $null } -TimeOutInMinutes $TimeOutInMinutes -Verbose
        Write-Verbose "WebGIS DR $($Action) run successful."
    }catch{
        throw "WebGIS DR $($Action) failed. Error - $($_)"
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $True)]    
        [System.String]
        $Version,

        [System.String] 
        [parameter(Mandatory = $True)]
        $PortalInstallDirectory,

        [ValidateSet('Import', 'Export')]
        [parameter(Mandatory = $True)]
        [System.String]
        $Action,

        [parameter(Mandatory = $True)]
        [System.String]
        $PropertiesFilePath,

        [parameter(Mandatory = $False)]
        [System.Int32] 
        $TimeoutInMinutes = 3600 # 10 hours
    )

    $False
}

Export-ModuleMember -Function *-TargetResource