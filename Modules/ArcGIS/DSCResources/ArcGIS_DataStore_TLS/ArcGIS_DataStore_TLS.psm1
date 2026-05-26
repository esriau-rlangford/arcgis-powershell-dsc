$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the ArcGIS Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Common' `
            -ChildPath 'ArcGIS.Common.psm1'))

Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Client' `
            -ChildPath 'ArcGIS.Client.DataStore.psm1'))

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
        [parameter(Mandatory = $true)]    
        [System.String]
        $DatastoreMachineHostName,

        [parameter(Mandatory = $true)]    
        [System.String]
        $Version,

        [parameter(Mandatory = $true)]
        [ValidateSet("WebServer","Relational","GraphStore","ObjectStore","TileCache")] 
        [System.String]
        $CertificateType,

        [parameter(Mandatory = $true)]
        [System.String]
		$CName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateFileLocation,
        
        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $CertificatePassword
	)

	@{}
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
        [parameter(Mandatory = $true)]    
        [System.String]
        $DatastoreMachineHostName,

        [parameter(Mandatory = $true)]    
        [System.String]
        $Version,

        [parameter(Mandatory = $true)]
        [ValidateSet("WebServer","Relational","GraphStore","ObjectStore","TileCache")] 
        [System.String]
        $CertificateType,

        [parameter(Mandatory = $true)]
        [System.String]
		$CName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateFileLocation,
        
        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $CertificatePassword
    )

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    
    $MachineFQDN = if($DatastoreMachineHostName){ Get-FQDN $DatastoreMachineHostName }else{ Get-FQDN $env:COMPUTERNAME }

    $DataStoreInstallDirectory = (Get-ArcGISComponentVersionAndInstallDirectory -ComponentName 'DataStore').InstallDir

    Test-ArcGISComponentHealth -BaseURL "https://$($MachineFQDN):2443/arcgis" -ComponentName "DataStore" -MaxWaitTimeInSeconds 180 -SleepTimeInSeconds 5 -Verbose


    if($CertificateType -ieq 'WebServer'){
        $CertificateTest = Test-DataStoreCertificate -CertificateFileLocation $CertificateFileLocation `
                                                -CertificatePassword $CertificatePassword `
                                                -MachineFQDN $MachineFQDN -Verbose
        if(-not($CertificateTest)){
            Write-Verbose "Thumbprint of certificate configured with datastore doesn't matches the certificate provided. Updating it."
            if([version]$Version -ge "11.3"){
                Invoke-DataStoreReplaceSSLCertificateTool -DataStoreInstallDirectory $DataStoreInstallDirectory `
                                                    -CertificateFileLocation $CertificateFileLocation -CertificateType "webserver" `
                                                    -CertificatePassword $CertificatePassword -CName $CName -Verbose
            }else{
                Invoke-DataStoreUpdateSSLCertificateTool -DataStoreInstallDirectory $DataStoreInstallDirectory `
                                                    -CertificateFileLocation $CertificateFileLocation `
                                                    -CertificatePassword $CertificatePassword -CName $CName -Verbose
            }
            Write-Verbose "Certificate update successful."
        }else{
            Write-Verbose "Thumbprint of certificate configured with datastore matches the certificate provided"
        }
    }else{
        if([version]$Version -ge "11.3"){
            Write-Verbose "Updating Certificate of type $CertificateType which is supported for ArcGIS Data Store version $Version"
            $CertType = $CertificateType.ToLower()
            if($CertificateType -ieq 'GraphStore'){
                $CertType = 'graph'
            }elseif($CertificateType -ieq 'ObjectStore'){
                $CertType = 'object'
            }elseif($CertificateType -ieq 'TileCache'){
                $CertType = 'tileCache'
            }

            Invoke-DataStoreReplaceSSLCertificateTool -DataStoreInstallDirectory $DataStoreInstallDirectory `
                                                    -CertificateFileLocation $CertificateFileLocation -CertificateType $CertType `
                                                    -CertificatePassword $CertificatePassword -CName $CName -Verbose
        }else{
             throw "Updating Certificate of type $CertificateType is not supported for ArcGIS Data Store version $Version"
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
        $DatastoreMachineHostName,

        [parameter(Mandatory = $true)]    
        [System.String]
        $Version,

        [parameter(Mandatory = $true)]
        [ValidateSet("WebServer","Relational","GraphStore","ObjectStore","TileCache")] 
        [System.String]
        $CertificateType,

        [parameter(Mandatory = $true)]
        [System.String]
		$CName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateFileLocation,
        
        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $CertificatePassword
    )

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null

    $MachineFQDN = if($DatastoreMachineHostName){ Get-FQDN $DatastoreMachineHostName }else{ Get-FQDN $env:COMPUTERNAME }
    Test-ArcGISComponentHealth -BaseURL "https://$($MachineFQDN):2443/arcgis" -ComponentName "DataStore" -MaxWaitTimeInSeconds 180 -SleepTimeInSeconds 5 -Verbose

    if($CertificateType -ieq 'WebServer'){
        $result = $true
        $CertificateTest = Test-DataStoreCertificate -CertificateFileLocation $CertificateFileLocation `
                                                -CertificatePassword $CertificatePassword -Verbose `
                                                -MachineFQDN $MachineFQDN
        if(-not($CertificateTest)){
            Write-Verbose "Thumbprint of certificate configured with datastore doesn't matches the certificate provided."
            $result = $False
        }else{
            Write-Verbose "Thumbprint of certificate configured with datastore matches the certificate provided"
        }
    }else{
        if([version]$Version -ge "11.3"){
            Write-Verbose "Skipping validation for Certificate of type $CertificateType which is supported for ArcGIS Data Store version $Version"
        }else{
            throw "Updating certificate of type $CertificateType is not supported for ArcGIS Data Store version $Version"
        }
        $result = $false
    }

    $result
}

function Test-DataStoreCertificate
{
    [CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
        [System.String]
        $CertificateFileLocation,

        [System.String]
        $MachineFQDN,

        [System.Management.Automation.PSCredential]
        $CertificatePassword
    )

    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $Cert.Import($CertificateFileLocation, $CertificatePassword.GetNetworkCredential().Password, 32)

    $webRequest = [Net.WebRequest]::Create("https://$($MachineFQDN):2443/arcgis/datastoreadmin/configure?f=json")
    try { $_d = $webRequest.GetResponse() } catch {}
    
    return $webRequest.ServicePoint.Certificate.GetCertHashString() -ieq $Cert.Thumbprint
}

function Invoke-DataStoreUpdateSSLCertificateTool
{
    [CmdletBinding()]
    param(
        [System.String]
        $DataStoreInstallDirectory,

        [System.String]
        $CertificateFileLocation,
        
        [System.Management.Automation.PSCredential]
		$CertificatePassword,

        [System.String]
		$CName
    )

    $UpdateDataStoreSSLCertificateToolPath = Join-Path $DataStoreInstallDirectory 'tools\updatesslcertificate.bat'
    
    if(-not(Test-Path $UpdateDataStoreSSLCertificateToolPath -PathType Leaf)){
        throw "$UpdateDataStoreSSLCertificateToolPath not found"
    }
    $RandomString = -join((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_})
    $CertAlias = "$($RandomString)$($CName)"
    $Arguments = "`"$($CertificateFileLocation)`" `"$($CertificatePassword.GetNetworkCredential().Password)`" $CertAlias --prompt no"
    Invoke-StartProcess -ExecPath $UpdateDataStoreSSLCertificateToolPath -Arguments $Arguments -EnvVariables @{ "AGSDATASTORE" = $null } -Verbose
}

function Invoke-DataStoreReplaceSSLCertificateTool
{
    [CmdletBinding()]
    param(
        [System.String]
        $DataStoreInstallDirectory,

        [System.String]
        $CertificateFileLocation,
        
        [System.Management.Automation.PSCredential]
		$CertificatePassword,

        [System.String]
		$CName,

        [System.String]
        $CertificateType
    )

    $DataStoreReplaceSSLCertificateToolPath = Join-Path $DataStoreInstallDirectory 'tools\replacesslcertificate.bat'
    
    if(-not(Test-Path $DataStoreReplaceSSLCertificateToolPath -PathType Leaf)){
        throw "$DataStoreReplaceSSLCertificateToolPath not found"
    }
    $RandomString = -join((65..90) + (97..122) | Get-Random -Count 5 | % {[char]$_})
    $CertAlias = "$($RandomString)$($CName)"

    $Arguments = "`"$($CertificateFileLocation)`" `"$($CertificatePassword.GetNetworkCredential().Password)`" $CertAlias --option $CertificateType --prompt no"
    Invoke-StartProcess -ExecPath $DataStoreReplaceSSLCertificateToolPath -Arguments $Arguments -EnvVariables @{ "AGSDATASTORE" = $null } -Verbose
}

Export-ModuleMember -Function *-TargetResource
