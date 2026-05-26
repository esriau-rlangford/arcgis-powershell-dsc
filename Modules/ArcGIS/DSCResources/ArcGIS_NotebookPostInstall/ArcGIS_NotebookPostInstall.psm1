$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the ArcGIS Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Common' `
            -ChildPath 'ArcGIS.Common.psm1'))

function Get-TargetResource {
    [CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
    (
        [parameter(Mandatory = $true)]
		[System.String]
        $SiteName,

        [parameter(Mandatory = $False)]    
        [System.Array]
        $ContainerImagePaths,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ExtractSamples = $False,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ForceRestart
    )
    
    return @{}
}

function Set-TargetResource {
    [CmdletBinding()]
	param
    (
        [parameter(Mandatory = $true)]
		[System.String]
        $SiteName,

        [parameter(Mandatory = $False)]    
        [System.Array]
        $ContainerImagePaths,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ExtractSamples = $False,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ForceRestart
    )

    if($ForceRestart){
        Restart-ArcGISService -ComponentName "NotebookServer" -RestartDelay 60
    }
    
    if($ContainerImagePaths.Length -gt 0){
        foreach ($ImagePath in $ContainerImagePaths) {
            try{
                Write-Verbose "Loading container image at path $ImagePath"
                Invoke-PostInstallUtility -Arguments "-l $ImagePath" -Verbose
                Write-Verbose "Container image at path $ImagePath loaded."
            }catch{
                Write-Verbose "[WARNING] Error Loading Container Image at path - $ImagePath - $_"
            }
        }
    }
    else
    {
        Write-Verbose "No Container Images to Load."
    }
    if($ExtractSamples){
        try{
            Write-Verbose "Extracting Notebook Server Samples Data"
            Invoke-PostInstallUtility -Arguments "-x" -Verbose
            Write-Verbose "Notebook Server Samples Data extracted."
        }catch{
            throw "[ERROR] Error extracting Notebook Server Samples Data - $_"
        }
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
	[OutputType([System.Boolean])]
	param
    (
        [parameter(Mandatory = $true)]
		[System.String]
        $SiteName,
        
        [parameter(Mandatory = $False)]    
        [System.Array]
        $ContainerImagePaths,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ExtractSamples = $False,

        [parameter(Mandatory = $False)]    
        [System.Boolean]
        $ForceRestart
    )

    $Result = $True
    try{
        if($ContainerImagePaths.Length -gt 0){
            try{
                Invoke-PostInstallUtility -Arguments "-d" -Verbose
            }catch{
                throw "[ERROR] Error with Docker Configuration - $_"
            }
            $Result = $False
            Write-Verbose "Trying to intall images if not already installed."
        }
        if($ExtractSamples){
            $Result = $False
            Write-Verbose "Trying to extract Notebook Server Samples Data if not already extracted."
        }
        if($Result -and $ForceRestart){
            $Result = $False
        }
    }catch{
        throw $_
    }

    $Result
}

function Invoke-PostInstallUtility
{
    [CmdletBinding()]
	param
    (
        [System.String]
        $Arguments
    )

    $InstallDir = (Get-ArcGISComponentVersionAndInstallDirectory -ComponentName 'NotebookServer').InstallDir
    $PostInstallUtilityToolPath = (Join-Path $InstallDir ( Join-Path 'tools' ( Join-Path 'postInstallUtility' 'PostInstallUtility.bat')))
    if(-not(Test-Path $PostInstallUtilityToolPath)){
        throw "Post Install Utility Tool not found."
    }    
    try{
        $op = Invoke-StartProcess -ExecPath $PostInstallUtilityToolPath -Arguments $Arguments -EnvVariables @{ "AGSNOTEBOOK" = $null } -Verbose
        if($op -icontains 'error' -or $op -icontains 'failed') { throw "$op"}
    }catch{
        throw "Post install utility run failed. Error - $_"
    }
}

Export-ModuleMember -Function *-TargetResource