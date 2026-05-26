$modulePath = Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Modules'

# Import the ArcGIS Common Modules
Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Common' `
            -ChildPath 'ArcGIS.Common.psm1'))

Import-Module -Name (Join-Path -Path $modulePath `
        -ChildPath (Join-Path -Path 'ArcGIS.Client' `
            -ChildPath 'ArcGIS.Client.Portal.psm1'))

<#
    .SYNOPSIS
        Creates a SelfSigned Certificate or Installs a SSL Certificated Provided and Configures it with Portal.
    .PARAMETER PortalHostName
        Portal Endpoint with which the Certificate will be associated.
    .PARAMETER SiteAdministrator
        A MSFT_Credential Object - Primary Site Administrator.
    .PARAMETER CertificateFileLocation
        Certificate Path from where to fetch the certificate to be installed.
    .PARAMETER CertificatePassword
        Sercret Certificate Password or Key.
    .PARAMETER WebServerCertificateAlias
        CName/Alias with which the Certificate will be associated.
	.PARAMETER SslRootOrIntermediate
        List of RootOrIntermediate Certificates
    .PARAMETER EnableHSTS
        Enable HTTP Strict Transport Security (HSTS)
#>

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
        [parameter(Mandatory = $True)]    
        [System.String]
        $Version,

		[parameter(Mandatory = $true)]
        [System.String]
		$PortalHostName
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

        [parameter(Mandatory = $true)]
        [System.String]
		$PortalHostName,

		[System.Management.Automation.PSCredential]
		$SiteAdministrator,
		
		[System.String]
		$CertificateFileLocation,

		[System.Management.Automation.PSCredential]
		$CertificatePassword,

        [System.String]
		$WebServerCertificateAlias,

        [System.String]
        $SslRootOrIntermediate,

        [System.Boolean]
        $EnableHSTS,

        [System.Boolean]
        $ImportCertificateChain = $true,

        [System.Boolean]
        $ForceImportCertificate = $false
	)

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
	
    $FQDN = if($PortalHostName) { Get-FQDN $PortalHostName} else { Get-FQDN $env:COMPUTERNAME }
    $PortalBaseURL = Get-ArcGISComponentBaseUrl -FQDN $FQDN -ComponentName "Portal"
    $Referer = $PortalBaseURL
    try{
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose

        $token = Get-PortalToken -URL $PortalBaseURL -Credential $SiteAdministrator -Referer $Referer 
    }catch{
        throw "[WARNING] Unable to get token:- $_"
    }
    if(-not($token.token)){
        throw "Unable to retrieve Portal Token for '$($SiteAdministrator.UserName)'"
    }else{
        Write-Verbose "Retrieved Portal Token"
    }

    $RestartRequired = $False
	# test and set RootOrIntermediateCertificate
    if($null -ne $SslRootOrIntermediate){
        $RestartRequired = Set-PortalRootAndIntermdiateCertificates -URL $PortalBaseURL `
                                                -Token $token.token -Referer $Referer -MachineName $FQDN `
                                                -SslRootOrIntermediate $SslRootOrIntermediate -Verbose
    }

    if($CertificateFileLocation) 
	{
        if($WebServerCertificateAlias -and $WebServerCertificateAlias -as [ipaddress]) {
            Write-Verbose "Adding Host mapping for $WebServerCertificateAlias"
            Add-HostMapping -hostname $WebServerCertificateAlias -ipaddress $WebServerCertificateAlias        
        }

        if((Test-Path $CertificateFileLocation))
        {
            try{
                $Certs = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN 
            }catch{
                throw "[WARNING] Unable to get SSL-CertificatesForPortal:- $_"
            }
            Write-Verbose "Current Alias for SSL Certificate:- '$($Certs.webServerCertificateAlias)' Certificates:- '$($Certs.sslCertificates -join ',')'"

            $ImportExistingCertFlag = $False
            $DeleteTempCert = $False
            if(-not($Certs.sslCertificates -icontains $WebServerCertificateAlias)){
                Write-Verbose "Importing SSL Certificate with alias $WebServerCertificateAlias"
                $ImportExistingCertFlag = $True
            }else{
                Write-Verbose "SSL Certificate with alias $WebServerCertificateAlias already exists"
                $CertForMachine = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -WebServerCertificateAlias $WebServerCertificateAlias.ToLower() -MachineName $FQDN 
                Write-Verbose "Examine certificate from $CertificateFileLocation"
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $cert.Import($CertificateFileLocation, $CertificatePassword.GetNetworkCredential().Password, 'DefaultKeySet')
                $NewCertThumbprint = $cert.Thumbprint
                Write-Verbose "Thumbprint for the supplied certificate is $NewCertThumbprint"
                if($CertForMachine.sha1Fingerprint -ine $NewCertThumbprint -or $ForceImportCertificate){
                    $ImportExistingCertFlag = $True
                    Write-Verbose "Force import certificate is: $ForceImportCertificate"
                    Write-Verbose "Importing exsting certificate with alias $($WebServerCertificateAlias)-temp"
                    try{
                        Import-ExistingCertificate -URL $PortalBaseURL -Token $token.token `
                                                    -Referer $Referer -CertAlias "$($WebServerCertificateAlias)-temp" -CertificateFilePath $CertificateFileLocation `
                                                    -CertificatePassword $CertificatePassword -MachineName $FQDN `
                                                    -Version $Version -ImportCertificateChain $ImportCertificateChain
                        $DeleteTempCert = $True
                    }catch{
                        throw "[WARNING] Error Import-ExistingCertificate:- $_"
                    }

                    try{
                        $RestartRequired = $False
                        Update-PortalSSLCertAliasOrHSTSSetting -URL $PortalBaseURL -Token $token.token `
                                            -Referer $Referer -CertAlias "$($WebServerCertificateAlias)-temp" `
                                            -MachineName $FQDN -Verbose
                        Write-Verbose "Updating to a temp SSL Certificate causes the web server to restart asynchronously. Waiting 60 seconds before health checks."
                        Start-Sleep -Seconds 60

                        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
                        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose
                    }catch{
                        throw "[WARNING] Unable to Update-PortalSSLCertificate:- $_"
                    }
                    try{
                        Write-Verbose "Deleting Portal Certificate with alias $WebServerCertificateAlias"
                        Invoke-DeletePortalCertificate -URL $PortalBaseURL -Token $token.token -Referer $Referer -WebServerCertificateAlias $WebServerCertificateAlias -MachineName $FQDN
                    }catch{
                        throw "[WARNING] Unable to Invoke-DeletePortalCertificate:- $_"
                    }
                }
            }

            if($ImportExistingCertFlag){
                Write-Verbose "Importing exsting certificate with alias $WebServerCertificateAlias"
                try{
                    Import-ExistingCertificate -URL $PortalBaseURL -Token $token.token `
                        -Referer $Referer -CertAlias $WebServerCertificateAlias `
                        -CertificateFilePath $CertificateFileLocation -CertificatePassword $CertificatePassword `
                        -MachineName $FQDN -Version $Version `
                        -ImportCertificateChain $ImportCertificateChain 
                }catch{
                    throw "[WARNING] Error Import-ExistingCertificate:- $_"
                }
            }
            
            $Certs = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN
            if(($Certs.webServerCertificateAlias -ine $WebServerCertificateAlias) -or $ForceImportCertificate) {
                $RestartRequired = $False
                Write-Verbose "Updating Alias to use $WebServerCertificateAlias"
                try{
                    Update-PortalSSLCertAliasOrHSTSSetting -URL $PortalBaseURL -Token $token.token  `
                                                        -Referer $Referer -CertAlias $WebServerCertificateAlias `
                                                        -MachineName $FQDN -Verbose
                    Write-Verbose "Updating an SSL Certificate causes the web server to restart asynchronously. Waiting 60 seconds before health checks."
                    Start-Sleep -Seconds 60
                    Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
                    Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose

                    if($DeleteTempCert){
                        Write-Verbose "Deleting Temp Certificate with alias $($WebServerCertificateAlias)-temp"
                        Invoke-DeletePortalCertificate -URL $PortalBaseURL -Token $token.token -Referer $Referer -WebServerCertificateAlias "$($WebServerCertificateAlias)-temp" -MachineName $FQDN 
                    }
                }catch{
                    throw "[WARNING] Unable to update certificate. $_"
                }
            }else{
                Write-Verbose "SSL Certificate alias $WebServerCertificateAlias is the current one"
            }     
            
            Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
            Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose
        }else{
            throw "[ERROR] CertificateFileLocation '$CertificateFileLocation' is not acccesible"
	    }
    }else{
        Write-Verbose "CertificateFileLocation not specified. Skipping web server certificate configuration"
	}

    $PortalMachineCertSettings = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN -ErrorAction SilentlyContinue
    if($PortalMachineCertSettings.HSTSEnabled -ine $EnableHSTS){
        $RestartRequired = $False
        Write-Verbose "Enabled HSTS doesn't match the expected state $EnableHSTS"
        Update-PortalSSLCertAliasOrHSTSSetting -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN -HSTSEnabled $EnableHSTS -Verbose
        Write-Verbose "Waiting 30 seconds as changing hsts setting will cause the web server to restart."
        Start-Sleep -Seconds 30
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose
    }else{
        Write-Verbose "Enabled HSTS matches the expected state $EnableHSTS"
    }

    if($RestartRequired){
        Write-Verbose "Restarting Portal for ArcGIS."
        Restart-ArcGISService -ComponentName "Portal" -Verbose
        Write-Verbose "Waiting 30 seconds before checking for initialization"
        Start-Sleep -Seconds 30
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
        Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose
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

        [parameter(Mandatory = $true)]
        [System.String]
		$PortalHostName,

		[System.Management.Automation.PSCredential]
		$SiteAdministrator,

		[System.String]
		$CertificateFileLocation,

		[System.Management.Automation.PSCredential]
		$CertificatePassword,

        [System.String]
		$WebServerCertificateAlias,

        [System.String]
        $SslRootOrIntermediate,

        [System.Boolean]
        $EnableHSTS,

        [System.Boolean]
        $ImportCertificateChain = $true,

        [System.Boolean]
        $ForceImportCertificate = $false
	)

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    $result = $True
    $FQDN = if($PortalHostName) { Get-FQDN $PortalHostName } else { Get-FQDN $env:COMPUTERNAME }
    $PortalBaseURL = Get-ArcGISComponentBaseUrl -FQDN $FQDN -ComponentName "Portal"
    $Referer = $PortalBaseURL

    Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "Portal" -Verbose
    Test-ArcGISComponentHealth -BaseURL $PortalBaseURL -ComponentName "PortalSharing" -Verbose
    
    $token = $null
    try{ 
        $token = Get-PortalToken -URL $PortalBaseURL -Credential $SiteAdministrator -Referer $Referer -MaxAttempts 30
    } catch {
        Write-Verbose "[WARNING] Unable to get token:- $_."
    }
	if(-not($token.token)) {
		throw "Unable to retrieve Portal Token for '$($SiteAdministrator.UserName)'"
	}else {
        Write-Verbose "Retrieved Portal Token"
    }

    if($WebServerCertificateAlias){
        Write-Verbose "Retrieve SSL Certificate for Portal from $FQDN and checking for Alias $WebServerCertificateAlias"
        $Certs = $null
        try{
            $Certs = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN
            Write-Verbose "Number of certificates:- $($Certs.sslCertificates.Length) Certificates:- '$($Certs.sslCertificates -join ',')' Current Alias :- '$($Certs.webServerCertificateAlias)'"   
        }catch{
            Write-Verbose "Error in Get-SSLCertificatesForPortal:- $_"
            throw $_
        }

        if(($null -ne $Certs) -and ($Certs.sslCertificates -iContains $WebServerCertificateAlias) -and ($Certs.webServerCertificateAlias -ieq $WebServerCertificateAlias)){
            Write-Verbose "Certificate $($Certs.webServerCertificateAlias) matches expected alias of '$WebServerCertificateAlias'"
            $CertForMachine = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -WebServerCertificateAlias $WebServerCertificateAlias -MachineName $FQDN
            if($CertificateFileLocation -and ($null -ne $CertificatePassword)) {
                Write-Verbose "Examine certificate from $CertificateFileLocation"
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $cert.Import($CertificateFileLocation, $CertificatePassword.GetNetworkCredential().Password, 'DefaultKeySet')
                $NewCertThumbprint = $cert.Thumbprint
                Write-Verbose "Thumbprint for the supplied certificate is $NewCertThumbprint"
                if($CertForMachine.sha1Fingerprint -ine $NewCertThumbprint){
                    Write-Verbose "Thumbprint for the supplied certificate doesn't match the existing one"
                    $result = $false
                }else{
                    Write-Verbose "Thumbprint for the supplied certificate matches the existing one"
                    $result = $True
                }
            }
        }
        else {
            Write-Verbose "Certificate $($Certs.webServerCertificateAlias) does not match expected alias of '$WebServerCertificateAlias'"
            $result = $False
        }
    }

    if($result -and $null -ne $SslRootOrIntermediate){
        $MissingCerts = Get-PortalRootAndIntermdiateCertificatesToUpdate -URL $PortalBaseURL `
                                                -Token $token.token -Referer $Referer -MachineName $FQDN `
                                                -SslRootOrIntermediate $SslRootOrIntermediate -Verbose
        $result = ($MissingCerts.Length -eq 0)
        if(-not($result)){
            Write-Verbose "One or more root and intermediate certificate needs an update."
        }
    }

    if ($result){
        $PortalMachineCertSettings = Get-SSLCertificatesForPortal -URL $PortalBaseURL -Token $token.token -Referer $Referer -MachineName $FQDN -ErrorAction SilentlyContinue
        if($PortalMachineCertSettings.HSTSEnabled -ine $EnableHSTS){
            Write-Verbose "Enabled HSTS doesn't match the expected state $EnableHSTS"
            $result = $false
        }else{
            Write-Verbose "Enabled HSTS matches the expected state $EnableHSTS"
        }
    }

    if ($ForceImportCertificate) {
        $result = $False
        Write-Verbose "Force import certificate is True"
    }

    $result
}

Export-ModuleMember -Function *-TargetResource