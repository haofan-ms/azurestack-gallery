function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricRuntimeUrl
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $setupDir = "E:\SFSetup"
    $ServiceFabricPowershellModulePath = Get-ServiceFabricModulePath -SetupDir $setupDir
    $ServiceFabricRunTimeDir = Join-Path $setupDir -ChildPath "SFRunTime"

    $returnValue = @{
        ServiceFabricPowershellModulePath      = $ServiceFabricPowershellModulePath
        ServiceFabricRunTimeDir                = $ServiceFabricRunTimeDir
    }

    return $returnValue
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricRuntimeUrl
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue
    
    Get-CommonModulePath | Import-Module -Verbose:$false

    #  SF deployment workflow stage 1.3: Host Provision: Download Service Fabric sdk and runtime packages
    #     Running on every node, preparing environment for service fabric installnation.

    # Store setup files on the disk.
    $setupDir = "E:\SFSetup"
    New-Item -Path $setupDir -ItemType Directory -Force
    cd $setupDir
    
    $outFile = Join-Path -Path $setupDir -ChildPath ServiceFabric.zip
    Download-SFPackage -packageUrl $serviceFabricUrl -outFile $outFile

    Expand-Archive (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -DestinationPath (Join-Path -Path $setupDir -ChildPath ServiceFabric) -Force

    # Expand SF Support Package.
    $toolsDir = Join-Path $SetupDir -ChildPath "ServiceFabric\Tools"
    Expand-Archive (Join-Path -Path $toolsDir -ChildPath Microsoft.Azure.ServiceFabric.WindowsServer.SupportPackage.zip) -DestinationPath (Join-Path -Path $toolsDir -ChildPath SupportPackage) -Force

    # Unpack and install Service fabric cmdlets to be able to connect to public cluster endpoint in order to determine if the cluster already exists.
    $ServiceFabricRunTimeDir = Join-Path $setupDir -ChildPath "SFRunTime"
    Set-ServiceFabricRuntimePackage -ServiceFabricRuntimeUrl $ServiceFabricRuntimeUrl -ServiceFabricRunTimeDir $ServiceFabricRunTimeDir

    # Setup env var for Service fabric SDK
    $serviceFabricDir = Join-Path $SetupDir -ChildPath "ServiceFabric"
    $DeployerBinPath = Join-Path $serviceFabricDir -ChildPath "DeploymentComponents"
    $env:path = "$($DeployerBinPath);" + $env:path

    # Unpack and install Service fabric cmdlets 
    $ServiceFabricPowershellModulePath = Get-ServiceFabricModulePath -SetupDir $setupDir
    Import-Module $ServiceFabricPowershellModulePath -Verbose:$false
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricRuntimeUrl
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    $setupDir = "E:\SFSetup"

    $serviceFabricDir = Join-Path $SetupDir -ChildPath "ServiceFabric"
    $DeployerBinPath = Join-Path $serviceFabricDir -ChildPath "DeploymentComponents"
    $ServiceFabricPowershellModulePath = Join-Path $DeployerBinPath -ChildPath "ServiceFabric.psd1"

    if(!(Test-Path $ServiceFabricPowershellModulePath))
    {
        return $false
    }

    $ServiceFabricRunTimeDir = Join-Path $setupDir -ChildPath "SFRunTime"
    if(!(Test-Path $ServiceFabricRunTimeDir))
    {
        return $false
    }

    return $true
}

function Set-ServiceFabricRuntimePackage
{
    param
    (
        [System.String]
        $ServiceFabricRuntimeUrl,

        [System.String]
        $ServiceFabricRunTimeDir
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    if(Test-Path -path $ServiceFabricRunTimeDir)
    {
        Remove-Item –path $ServiceFabricRunTimeDir -Recurse
    }

    New-Item -Path $ServiceFabricRunTimeDir -ItemType Directory -Force

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # if no ServiceFabricRuntimeUrl, download the latest from Internet
    Write-Verbose "Input runtime $ServiceFabricRuntimeUrl" -Verbose
 
    $WebClient = [System.Net.WebClient]::new()
        
    if($ServiceFabricRuntimeUrl -eq 'N/A')
    {
        $runtimePackageDetails = Get-ServiceFabricRuntimeSupportedVersion -Latest
        $runtimeCabFilename = "MicrosoftAzureServiceFabric." + $runtimePackageDetails.GoalRuntimeVersion + ".cab"
        $serviceFabricRunTimeCabFilePath = Join-Path $ServiceFabricRunTimeDir -ChildPath $runtimeCabFilename
        $version = $runtimePackageDetails.GoalRuntimeVersion
        
        Write-Verbose "Runtime package version $version was not found in DeploymentRuntimePackages folder and needed to be downloaded."
        
        Download-SFPackage -packageUrl $runtimePackageDetails.GoalRuntimeLocation -outFile $serviceFabricRunTimeCabFilePath

        Write-Verbose "Runtime package has been successfully downloaded to $serviceFabricRunTimeCabFilePath."
    }
    else
    {
        $serviceFabricRunTimeCabFilePath = Join-Path -Path $ServiceFabricRunTimeDir -ChildPath (Split-Path $ServiceFabricRuntimeUrl -Leaf)

        # For a given ServiceFabricRuntimeUrl, download the runtime cab file
        Write-Verbose "Downloading specified service fabric runtime...$ServiceFabricRuntimeUrl with TLS 1.2 negotiation" -Verbose
        
        Download-SFPackage -packageUrl $ServiceFabricRuntimeUrl -outFile $serviceFabricRunTimeCabFilePath

        Write-Verbose "Download finished, runtime package path: $serviceFabricRunTimeCabFilePath" -Verbose
    }
}

function Get-ServiceFabricModulePath
{
    param 
    (
        [string] $SetupDir
    )

    $serviceFabricDir = Join-Path $SetupDir -ChildPath "ServiceFabric"
    $DeployerBinPath = Join-Path $serviceFabricDir -ChildPath "DeploymentComponents"
    if(!(Test-Path $DeployerBinPath))
    {
        $DCAutoExtractorPath = Join-Path $serviceFabricDir "DeploymentComponentsAutoextractor.exe"
        if(!(Test-Path $DCAutoExtractorPath)) 
        {
            throw "Standalone package DeploymentComponents and DeploymentComponentsAutoextractor.exe are not present local to the script location."
        }

        #Extract DeploymentComponents
        $DCExtractArguments = "/E /Y /L `"$serviceFabricDir`""
        $DCExtractOutput = cmd.exe /c "$DCAutoExtractorPath $DCExtractArguments && exit 0 || exit 1"
        if($LASTEXITCODE -eq 1)
        {
            throw "Extracting DeploymentComponents Cab ran into an issue: $DCExtractOutput"
        }
        else
        {
            Write-Verbose "DeploymentComponents extracted." -Verbose
        }
    }

    $SystemFabricModulePath = Join-Path $DeployerBinPath -ChildPath "System.Fabric.dll"
    if(!(Test-Path $SystemFabricModulePath)) 
    {
        throw "Could not find System.Fabric.dll at path: '$SystemFabricModulePath'."
    }

    $ServiceFabricPowershellModulePath = Join-Path $DeployerBinPath -ChildPath "ServiceFabric.psd1"

    return $ServiceFabricPowershellModulePath
}

function Get-CommonModulePath
{
    $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
    $commonModulePath = "$PSModulePath\xSfClusterDSC.Common\xSfClusterDSC.Common.psm1"

    return $commonModulePath
}

function Download-SFPackage
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $packageUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $outFile
    )

    $packageName = Split-Path $packageUrl -Leaf

    Write-Verbose "Downloading Service Fabric '$packageName' package from: '$packageUrl' with TLS 1.2 negotiation" -Verbose
    
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $WebClient = [System.Net.WebClient]::new()
    
    $totalRetries = 3 #set the maximum number of retry in case the download will never succeed.
    $retryCount = 0
    do {
        try
        {
            $WebClient.Downloadfile($packageUrl, $outFile)
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "SF '$packageName' package download failed because: $lastException. Trying again (attempt $($totalRetries - $retryCount)/$totalRetries)." -Verbose

            #Remove file if package partially downloaded
            if (Test-Path $outFile) { Remove-Item $outFile }

            Start-Sleep -Seconds 10
        }
        finally
        {
            $WebClient.Dispose()
        }
        
        $retryCount++
    } while (((Test-Path $outFile) -eq $false) -and ($retryCount -le $totalRetries))

}

Export-ModuleMember -Function *-TargetResource