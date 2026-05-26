$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the ArcGIS Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Common' `
            -ChildPath 'ArcGIS.Common.psm1'))

Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Client' `
            -ChildPath 'ArcGIS.Client.Server.psm1'))
<#
    .SYNOPSIS
        Makes a request to the installed Server to Register Existing External Cache Directories with existing Server Site
    .PARAMETER ServerHostName
        Optional Host Name or IP of the Machine on which the Server has been installed and is to be configured.
    .PARAMETER Ensure
        Ensure makes sure that a Cache Directories are registered to site if specified. Take the values Present or Absent. 
        - "Present" ensures that a server site is created or the server is joined to an existing site.
        - "Absent" ensures that existing server site is deleted (Not Implemented).
    .PARAMETER SiteAdministrator
        A MSFT_Credential Object - Primary Site Administrator
    .PARAMETER DirectoriesJSON
        List of Registered Directories in JSON Format
#>
function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
        [parameter(Mandatory = $false)]    
        [System.String]
        $ServerHostName,

        [parameter(Mandatory = $true)]
        [System.String]
        $DirectoriesJSON,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,    

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministrator
	)

	@{}
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
        [parameter(Mandatory = $false)]    
        [System.String]
        $ServerHostName,

        [parameter(Mandatory = $true)]
        [System.String]
        $DirectoriesJSON,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,    

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministrator       
	)

    $FQDN = if($ServerHostName){ Get-FQDN $ServerHostName }else{ Get-FQDN $env:COMPUTERNAME }
    Write-Verbose "Fully Qualified Domain Name :- $FQDN"
    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null

    $ServerBaseUrl = Get-ArcGISComponentBaseUrl -ComponentName "Server" -FQDN $FQDN
    $Referer = $ServerBaseUrl
	Write-Verbose "Waiting for Server '$($ServerBaseUrl)' to initialize"
    Test-ArcGISComponentHealth -BaseURL $ServerBaseUrl -ComponentName "Server"

    if($Ensure -ieq 'Present') {        
        $Referer = 'https://localhost' 
        try {  
            Write-Verbose "Getting the Token for site '$ServerBaseUrl'"
            $token = Get-ServerToken -URL $ServerBaseUrl -Credential $SiteAdministrator -Referer $Referer 
            if($null -ne $token.token -and $DirectoriesJSON) { #setting registered directories
                $responseDirectories = Get-SystemDirectories -URL $ServerBaseUrl -Token $token.token -Referer $Referer
                foreach ($dir in ($DirectoriesJSON | ConvertFrom-Json)) 
                {
                    Write-Verbose "Testing for Directory $($dir.name)"
                    if(($responseDirectories | Where-Object { ($responseDirectories.directories.name -icontains $($dir.name))}  | Measure-Object).Count -gt 0) {
                        Write-Verbose "Directory $($dir.name) already registered > no Action required"
                    } else {
                        Write-Verbose "Directory $($dir.name) not registered > registering directory"
                        $response = Register-SystemDirectory -URL $ServerBaseUrl -Token $token.token -Referer $Referer -Name $dir.name -PhysicalPath $dir.physicalPath -DirectoryType $dir.directoryType
                        Write-Verbose "Register-SystemDirectory Response :-$response"
                    }
                }
            }else{
                throw "[Error] No Token Returned"
            }
        }
        catch {
            throw "[ERROR] GetToken returned:- $_"
        }
    }
    elseif($Ensure -ieq 'Absent') {
        #Unregister Registered Directories
        Write-Verbose "TO BE IMPLEMENTED"
    }
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
        [parameter(Mandatory = $false)]    
        [System.String]
        $ServerHostName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DirectoriesJSON,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,    

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministrator  
	)

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    $FQDN = if($ServerHostName){ Get-FQDN $ServerHostName }else{ Get-FQDN $env:COMPUTERNAME }
    Write-Verbose "Fully Qualified Domain Name :- $FQDN" 
    $ServerBaseUrl = Get-ArcGISComponentBaseUrl -ComponentName "Server" -FQDN $FQDN
    $Referer = $ServerBaseUrl
    $result = $true
    Write-Verbose "Getting the Token for site '$ServerBaseUrl'"
    $token = Get-ServerToken -URL $ServerBaseUrl -Credential $SiteAdministrator -Referer $Referer 
    try {  
        if($null -ne $token.token -and $DirectoriesJSON) { #setting registered directories
            $responseDirectories = Get-SystemDirectories -URL $ServerBaseUrl -Token $token.token -Referer $Referer
            ForEach ($dir in ($DirectoriesJSON | ConvertFrom-Json)) 
            {
                Write-Verbose "Testing for Directory $($dir.name)"
                if(($responseDirectories | Where-Object { ($responseDirectories.directories.name -icontains $($dir.name))}  | Measure-Object).Count -gt 0) {
                    Write-Verbose "Directory $($dir.name) already registered"
                } else {
                    Write-Verbose "Directory $($dir.name) not registered"
                    $result = $false
                    break
                }
            }
        }
        else{
            throw "No Token Returned"
        }
    }
    catch {
        throw "[ERROR] GetToken returned:- $_"
    }
   
    if($Ensure -ieq 'Present') {
	       $result   
    }
    elseif($Ensure -ieq 'Absent') {        
        (-not($result))
    }
}

Export-ModuleMember -Function *-TargetResource
