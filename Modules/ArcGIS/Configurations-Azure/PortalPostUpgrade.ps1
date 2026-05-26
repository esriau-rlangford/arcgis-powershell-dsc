Configuration PortalPostUpgrade{

    param(
        [parameter(Mandatory = $true)]
        [System.String]
        $PortalLicenseFileName,

        [Parameter(Mandatory=$false)]
        [System.String]
        $PortalLicenseUserTypeId,
        
        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential,
        
        [parameter(Mandatory = $false)]
        [System.String]
        $Version,

        [Parameter(Mandatory=$True)]
        [System.Management.Automation.PSCredential]
        $DeploymentArtifactCredentials,
		
		[Parameter(Mandatory=$false)]
        [System.Boolean]
        $DebugMode		
    )

	Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DSCResource -ModuleName ArcGIS
    Import-DscResource -Name ArcGIS_PortalUpgrade 
    Import-DscResource -Name ArcGIS_RemoteFile

    Node localhost {
        LocalConfigurationManager
        {
			ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'    
            RebootNodeIfNeeded = $false
        }

        $DependsOn = @()
        if($PortalLicenseFileName) {
            ArcGIS_RemoteFile "PortalLicenseFileDownload"
            {
                Source = $PortalLicenseFileName
                Destination = (Join-Path $(Get-Location).Path $PortalLicenseFileName)
                FileSourceType = "AzureSASUri"
                Credential = $DeploymentArtifactCredentials
                Ensure = 'Present'
            }
            $DependsOn += '[ArcGIS_RemoteFile]PortalLicenseFileDownload'
        }

        ArcGIS_PortalUpgrade PortalUpgrade
        {
            PortalAdministrator = $SiteAdministratorCredential 
            PortalHostName = $env:ComputerName
            LicenseFilePath = (Join-Path $(Get-Location).Path $PortalLicenseFileName) 
            Version = $Version
            ImportExternalPublicCertAsRoot = $True
            EnableUpgradeSiteDebug = $DebugMode
            DependsOn = $DependsOn
        }
    }
}
