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
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DNSService,

        [parameter(Mandatory = $true)]
        [System.String]
        $RepairManager,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackupRestoreService,

        [Parameter(Mandatory = $true)]
        [string] $AdminUserName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AdminClientCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $NonAdminClientCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ReverseProxyCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.String[]]
        $NonAdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $DisableContainers,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $StandaloneDeployment,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityApplicationId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ArmEndpoint,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultDnsSuffix,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultServiceEndpointResourceId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityTenantId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityCertCommonName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $SubscriptionName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $DSCAgentConfig,

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    Get-CommonModulePath | Import-Module -Verbose:$false

    if ([string]::IsNullOrEmpty($ClusterCertificateThumbprint))
    {
        $ClusterCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ClusterCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($ServerCertificateThumbprint))
    {
        $ServerCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ServerCertificateCommonName"
    }

    Write-Verbose "Trying to connect to Service Fabric cluster $ClientConnectionEndpoint" -Verbose

    # Define location of setup files on Temp disk.
    $setupDir = "E:\SFSetup"
 
    $ServiceFabricPowershellModulePath = Get-ServiceFabricPowershellModulePath -SetupDir $SetupDir
    Import-Module $ServiceFabricPowershellModulePath -ErrorAction SilentlyContinue -Verbose:$false

    # Work around error: Argument 'Connect-ServiceFabricCluster' is not recognized as a cmdlet: Unable to load DLL 'FabricCommon.dll': The specified module could not be found.
    # https://github.com/microsoft/service-fabric-issues/issues/794
    $env:Path += ";C:\Program Files\Microsoft Service Fabric\bin\fabric\Fabric.Code"

    $timeoutTimeInMin = 1
    $timeoutTime = (Get-Date).AddMinutes($timeoutTimeInMin)
    
    $connectSucceeded = $false
    do
    {
        try
        {   
            # Connecting to secure cluster: 
            # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-connect-to-secure-cluster#connect-to-a-secure-cluster-using-a-client-certificate
            $connection = Connect-ServiceFabricCluster -X509Credential `
                                    -ConnectionEndpoint $ClientConnectionEndpoint `
                                    -ServerCertThumbprint $ServerCertificateThumbprint `
                                    -StoreLocation "LocalMachine" `
                                    -StoreName "My" `
                                    -FindValue $ClusterCertificateThumbprint `
                                    -FindType FindByThumbprint `
                                    -TimeoutSec 10
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "Connection failed because: $lastException. Retrying until $timeoutTime." -Verbose
            Write-Verbose "Waiting for 30 seconds..." -Verbose
            Start-Sleep -Seconds 30
        }
    } while(-not $connectSucceeded -and (Get-Date) -lt $timeoutTime)

    return $connection
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
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DNSService,

        [parameter(Mandatory = $true)]
        [System.String]
        $RepairManager,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackupRestoreService,

        [Parameter(Mandatory = $true)]
        [string] $AdminUserName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AdminClientCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $NonAdminClientCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ReverseProxyCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.String[]]
        $NonAdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $DisableContainers,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $StandaloneDeployment,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityApplicationId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ArmEndpoint,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultDnsSuffix,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultServiceEndpointResourceId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityTenantId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityCertCommonName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $SubscriptionName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $DSCAgentConfig,

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    Get-CommonModulePath | Import-Module -Verbose:$false

    $setTargetResourceInternalParam = @{
        DeploymentNodeIndex = $DeploymentNodeIndex
        ClusterName = $ClusterName
        VMNodeTypePrefix = $VMNodeTypePrefix
        VMNodeTypeInstanceCounts = $VMNodeTypeInstanceCounts
        CurrentVMNodeTypeIndex = $CurrentVMNodeTypeIndex
        SubnetIPFormat = $SubnetIPFormat
        ClientConnectionEndpointPort = $ClientConnectionEndpointPort
        HTTPGatewayEndpointPort = $HTTPGatewayEndpointPort
        ReverseProxyEndpointPort = $ReverseProxyEndpointPort
        EphemeralStartPort = $EphemeralStartPort
        EphemeralEndPort = $EphemeralEndPort
        ApplicationStartPort = $ApplicationStartPort
        ApplicationEndPort = $ApplicationEndPort
        ConfigPath = $ConfigPath
        CertificateStoreValue = $CertificateStoreValue
        ClientConnectionEndpoint = $ClientConnectionEndpoint
        DNSService = $DNSService
        RepairManager = $RepairManager
        BackupRestoreService = $BackupRestoreService
        ClusterCertificateCommonName = $ClusterCertificateCommonName
        ServerCertificateCommonName = $ServerCertificateCommonName
        ReverseProxyCertificateCommonName = $ReverseProxyCertificateCommonName
        AdminClientCertificateCommonName = $AdminClientCertificateCommonName
        NonAdminClientCertificateCommonName = $NonAdminClientCertificateCommonName
        ClusterCertificateThumbprint = $ClusterCertificateThumbprint
        ServerCertificateThumbprint = $ServerCertificateThumbprint
        ReverseProxyCertificateThumbprint = $ReverseProxyCertificateThumbprint
        AdminClientCertificateThumbprint = $AdminClientCertificateThumbprint
        NonAdminClientCertificateThumbprint = $NonAdminClientCertificateThumbprint
        DisableContainers = $DisableContainers
        BRSDisableKVAuthorityValidation = $BRSDisableKVAuthorityValidation
    }

    $DSCResourceName = "xSfClusterCreateOps"

    if (-not $StandaloneDeployment) {
        Set-TargetResourceInternalWrapper `
            -ProviderIdentityApplicationId $ProviderIdentityApplicationId `
            -ArmEndpoint $ArmEndpoint `
            -AzureKeyVaultDnsSuffix $AzureKeyVaultDnsSuffix `
            -AzureKeyVaultServiceEndpointResourceId $AzureKeyVaultServiceEndpointResourceId `
            -ProviderIdentityTenantId $ProviderIdentityTenantId `
            -ProviderIdentityCertCommonName $ProviderIdentityCertCommonName `
            -SubscriptionName $SubscriptionName `
            -DSCResourceName $DSCResourceName `
            -SetTargetResourceInternalParam $setTargetResourceInternalParam `
            -AdminUserName $AdminUserName `
            -DSCAgentConfig $DSCAgentConfig
     } else {
        Set-TargetResourceInternal @setTargetResourceInternalParam
     }

}

function Set-TargetResourceInternal
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DNSService,

        [parameter(Mandatory = $true)]
        [System.String]
        $RepairManager,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackupRestoreService,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AdminClientCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $NonAdminClientCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ReverseProxyCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.String[]]
        $NonAdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $DisableContainers,

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    Get-CommonModulePath | Import-Module -Verbose:$false

    #  SF deployment workflow stage 2/1: Service Fabric Cluster Deployment
    #        The installation happens on the first node of vmss ('master' node), scale out happens on newly added node.

    if ([string]::IsNullOrEmpty($ClusterCertificateThumbprint))
    {
        $ClusterCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ClusterCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($ServerCertificateThumbprint))
    {
        $ServerCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ServerCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($ReverseProxyCertificateThumbprint))
    {
        $ReverseProxyCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ReverseProxyCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($AdminClientCertificateThumbprint))
    {
        $AdminClientCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$AdminClientCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($NonAdminClientCertificateThumbprint))
    {
        $NonAdminClientCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$NonAdminClientCertificateCommonName"
    }

    # Define location of setup files on Temp disk.
    $setupDir = "E:\SFSetup"
    cd $setupDir

    $ServiceFabricPowershellModulePath = Get-ServiceFabricPowershellModulePath -SetupDir $SetupDir
    Import-Module $ServiceFabricPowershellModulePath -ErrorAction SilentlyContinue -Verbose:$false

    $ServiceFabricRunTimeDir = Join-Path $setupDir -ChildPath "SFRunTime"
    $fabricRuntimePackagePath = Get-ChildItem $ServiceFabricRunTimeDir -Filter *.cab -Recurse | % { $_.FullName }

    # NodeType name, Node name are required to use upper case to avoid case sensitive issues
    $VMNodeTypePrefix = $VMNodeTypePrefix.ToUpper()

    # Check if Cluster already exists on Master node and if this is a addNode scenario.
    $clusterExists = ConnectClusterWithRetryAndExceptionSwallowed -SetupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
        -TimeoutTimeInMin 1 `
        -TimeoutBetweenProbsInSec 15

    if($clusterExists)
    {
        # If Cluster exist on Master node it is a addNode scenario, just return.
        return
    }

    # Check if current Node is master node.
    $isMasterNode = IsMasterNode -DeploymentNodeIndex $DeploymentNodeIndex -VMNodeTypePrefix $VMNodeTypePrefix -CurrentVMNodeTypeIndex $CurrentVMNodeTypeIndex

    # Return in case the current node is not the deployment node, else continue with SF deployment on deployment node.
    if(-not $isMasterNode)
    {
        Write-Verbose "Service Fabric deployment runs on Node with index: '$CurrentVMNodeTypeIndex'." -Verbose
        Write-Verbose "Wait for 30 min until Service Fabric deployment finished on Master Node." -Verbose
        
        # If Cluster not exist on non-Master node, need to wait untill the cluster is created from Master node.
        try
        {
            $clusterConnectable = ConnectClusterWithRetryAndExceptionThrown -SetupDir $setupDir `
                -ClientConnectionEndpoint $ClientConnectionEndpoint `
                -ServerCertificateThumbprint $ServerCertificateThumbprint `
                -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
                -TimeoutTimeInMin 30 `
                -TimeoutBetweenProbsInSec 30 `
                | Out-Null
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "Connection false because $lastException. The exception is swallowed." -Verbose
        }

        return
    }

    # Create Service fabric configuration file locally and update.
    $params = @{
        DeploymentNodeIndex = $DeploymentNodeIndex
        ClusterName = $ClusterName
        VMNodeTypePrefix = $VMNodeTypePrefix
        VMNodeTypeInstanceCounts = $VMNodeTypeInstanceCounts 
        CurrentVMNodeTypeIndex = $CurrentVMNodeTypeIndex
        SubnetIPFormat = $SubnetIPFormat
        ClientConnectionEndpointPort = $ClientConnectionEndpointPort
        HTTPGatewayEndpointPort = $HTTPGatewayEndpointPort
        ReverseProxyEndpointPort = $ReverseProxyEndpointPort
        EphemeralStartPort = $EphemeralStartPort
        EphemeralEndPort = $EphemeralEndPort
        ApplicationStartPort = $ApplicationStartPort
        ApplicationEndPort = $ApplicationEndPort
        ConfigPath = $ConfigPath
        ClientConnectionEndpoint = $ClientConnectionEndpoint
        CertificateStoreValue = $CertificateStoreValue
        DNSService = $DNSService
        RepairManager = $RepairManager
        BackupRestoreService = $BackupRestoreService
        ClusterCertificateThumbprint = $ClusterCertificateThumbprint
        ServerCertificateThumbprint = $ServerCertificateThumbprint
        ReverseProxyCertificateThumbprint = $ReverseProxyCertificateThumbprint
        DisableContainers = $DisableContainers
        SetupDir = $setupDir
    }

    if (-not [string]::IsNullOrEmpty($AdminClientCertificateThumbprint))
    {
        $params += @{ AdminClientCertificateThumbprint = $AdminClientCertificateThumbprint }
    }
    
    if (-not [string]::IsNullOrEmpty($NonAdminClientCertificateThumbprint))
    {
        $params +=  @{ NonAdminClientCertificateThumbprint = $NonAdminClientCertificateThumbprint }
    }

    $ConfigFilePath = Create-ServiceFabricConfiguration @params

    # Validate and Deploy Service Fabric Configuration
    New-ServiceFabricDeployment -ConfigFilePath $ConfigFilePath -FabricRuntimePackagePath $fabricRuntimePackagePath

    # Validations. TODO: Put the validation in Test-TargetResource
    Write-Verbose "Validating Service Fabric deployment." -Verbose
    Test-ServiceFabricDeployment -setupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint
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
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DNSService,

        [parameter(Mandatory = $true)]
        [System.String]
        $RepairManager,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackupRestoreService,

        [Parameter(Mandatory = $true)]
        [string] $AdminUserName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AdminClientCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $NonAdminClientCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ReverseProxyCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.String[]]
        $NonAdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $DisableContainers,

        [parameter(Mandatory = $true)]
        [System.Boolean]
        $StandaloneDeployment,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityApplicationId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ArmEndpoint,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultDnsSuffix,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $AzureKeyVaultServiceEndpointResourceId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityTenantId,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $ProviderIdentityCertCommonName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $SubscriptionName,
        
        [Parameter(Mandatory = $false)]
        [System.String]
        $DSCAgentConfig,

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    Get-CommonModulePath | Import-Module -Verbose:$false

    if ([string]::IsNullOrEmpty($ClusterCertificateThumbprint))
    {
        $ClusterCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ClusterCertificateCommonName"
    }

    if ([string]::IsNullOrEmpty($ServerCertificateThumbprint))
    {
        $ServerCertificateThumbprint = Get-CertLatestThumbPrintByCommonName -subjectName "CN=$ServerCertificateCommonName"
    }

    # Define location of setup files on Temp disk.
    $setupDir = "E:\SFSetup"

    # Only when "No cluster endpoint is reachable" exception thrown, should DSC start SF cluster installation.
    # In other cases, the deployment shouldn't be triggered. Exp: FABRIC_E_SERVER_AUTHENTICATION_FAILED exception thrown because of secret rotation failed.
    try
    {
        ConnectClusterWithRetryAndExceptionThrown -SetupDir $setupDir `
            -ClientConnectionEndpoint $ClientConnectionEndpoint `
            -ServerCertificateThumbprint $ServerCertificateThumbprint `
            -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
            -TimeoutTimeInMin 1 `
            -TimeoutBetweenProbsInSec 10 `
            | Out-Null
    }
    catch [System.Fabric.FabricException]
    {
        $lastException = $_.Exception
        Write-Verbose "Connection false because $lastException. ErrorCode: $($lastException.ErrorCode). Message: $($lastException.Message)." -Verbose
        if ($lastException.ErrorCode -eq "CommunicationError") {
            Write-Verbose "CommunicationError indicates the cluster doesn't exist. Starts cluster deployment." -Verbose
            return $false
        }
    }
    catch
    {
        $lastException = $_.Exception
        Write-Verbose "Connection false because $lastException. The exception is swallowed." -Verbose
    }
    
    return $true
}

# Provision util functions
function Create-ServiceFabricConfiguration
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypePrefix,

        [parameter(Mandatory = $true)]
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $CurrentVMNodeTypeIndex,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DNSService,

        [parameter(Mandatory = $true)]
        [System.String]
        $RepairManager,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackupRestoreService,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateThumbprint,

        [System.String]
        $ReverseProxyCertificateThumbprint,

        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [System.String[]]
        $NonAdminClientCertificateThumbprint = @(),

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $DisableContainers,

        [parameter(Mandatory = $false)]
        [System.String]
        $setupDir,

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # Get Service fabric configuration file locally for update.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Verbose "Get Service fabric configuration from '$ConfigPath'" -Verbose
    $request = Invoke-RestMethod -UseBasicParsing -Uri $ConfigPath
    $configContent = ConvertTo-Json $request -Depth 99
    
    $ConfigFilePath = Join-Path -Path $setupDir -ChildPath 'ClusterConfig.json'
    $configContent | Out-File $ConfigFilePath

    Write-Verbose "Creating service fabric config file at: '$ConfigFilePath'" -Verbose

    # Add Nodes configuration.
    Add-ServiceFabricNodeConfiguration -ConfigFilePath $ConfigFilePath `
                                       -ClusterName $ClusterName `
                                       -InstanceCounts $VMNodeTypeInstanceCounts `
                                       -VMNodeTypePrefix $VMNodeTypePrefix `
                                       -SubnetIPFormat $SubnetIPFormat

    # Add NodeType configuration.
    Add-ServiceFabricNodeTypeConfiguration -ConfigFilePath $ConfigFilePath `
                                           -VMNodeTypePrefix $VMNodeTypePrefix `
                                           -NodeTypeCounts $VMNodeTypeInstanceCounts.Count`
                                           -ClientConnectionEndpointPort $ClientConnectionEndpointPort `
                                           -HTTPGatewayEndpointPort $HTTPGatewayEndpointPort `
                                           -ReverseProxyEndpointPort $ReverseProxyEndpointPort `
                                           -EphemeralStartPort $EphemeralStartPort `
                                           -EphemeralEndPort $EphemeralEndPort `
                                           -ApplicationStartPort $ApplicationStartPort `
                                           -ApplicationEndPort $ApplicationEndPort

    # Add Deiagnostics configuration.
    Add-ServiceFabricDiagnosticsConfiguration -ConfigFilePath $ConfigFilePath

    # Add Security configuration.
    Add-ServiceFabricSecurityConfiguration -ConfigFilePath $ConfigFilePath `
                                           -CertificateStoreValue $CertificateStoreValue `
                                           -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
                                           -ServerCertificateThumbprint $ServerCertificateThumbprint `
                                           -ReverseProxyCertificateStoreValue $CertificateStoreValue `
                                           -ReverseProxyCertificateThumbprint $ReverseProxyCertificateThumbprint `
                                           -AdminClientCertificateThumbprint $AdminClientCertificateThumbprint `
                                           -NonAdminClientCertificateThumbprint $NonAdminClientCertificateThumbprint

    # Add Optional Features (if Any)
    Add-OptionalFeaturesConfiguration -ConfigFilePath $ConfigFilePath `
                                      -DNSService $DNSService `
                                      -RepairManager $RepairManager `
                                      -BackupRestoreService $BackupRestoreService `
                                      -DisableContainers $DisableContainers `
                                      -BRSDisableKVAuthorityValidation $BRSDisableKVAuthorityValidation

    return $ConfigFilePath
}

function Add-ServiceFabricNodeConfiguration
{
    param
    (
        [String] $ConfigFilePath,

        [String] $ClusterName,

        [System.UInt32[]] $InstanceCounts,

        [String] $VMNodeTypePrefix,

        [String] $SubnetIPFormat
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    $configContent.name = "$ClusterName"

    # Adding Nodes to the configuration.
    $sfnodes = @()
    $tagIpFormat =  $SubnetIPFormat.Substring(0,$SubnetIPFormat.IndexOf('[')) + '*'

    try
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force 
        
        for($j = 0; $j -lt $InstanceCounts.Count; $j++)
        {
            $InstanceCount = $InstanceCounts[$j]
            $VMNodeTypeName = "$VMNodeTypePrefix$j"

            for($i = 0; $i -lt $InstanceCount; $i++)
            {
                [String] $base36Index = (ConvertTo-Base36 -decNum $i)

                $computerName = $VMNodeTypeName + $base36Index.PadLeft(6, "0")
                $nodeName = Get-NodeName -VMNodeTypeName $VMNodeTypeName -NodeIndex $i

                Write-Verbose "Retriving ip for $computerName (nodename $nodeName) ..." -Verbose

                $ip = Invoke-Command -ScriptBlock {
                        $nodeIpAddressLable = (Get-NetIPAddress).IPv4Address | ? {$_ -like $Using:tagIpFormat}
                        $nodeIpAddress = ([String]$nodeIpAddressLable).Trim(' ')
                        return $nodeIpAddress
                                    } -ComputerName $computerName

                Write-Verbose "IP for Node '$computerName (nodename $nodeName)' is: '$($ip.ToString())'" -Verbose
            
                $nodeScaleSetDecimalIndex = $i
                $fdIndex = $nodeScaleSetDecimalIndex

                $node = New-Object PSObject
                $node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $nodeName
                $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $($ip.ToString())
                $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$VMNodeTypeName"
                $node | Add-Member -MemberType NoteProperty -Name "faultDomain" -Value "fd:/$fdIndex"
                $node | Add-Member -MemberType NoteProperty -Name "upgradeDomain" -Value "$nodeScaleSetDecimalIndex"

                Write-Verbose "Adding Node to configuration: '$nodeName'" -Verbose
                $sfnodes += $node
            }
        }
    }
    finally
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "" -Force
    }

    $configContent.nodes = $sfnodes

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricNodeTypeConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $VMNodeTypePrefix,

        [System.UInt32] $NodeTypeCounts,

        [System.String]
        $ClientConnectionEndpointPort,

        [System.String]
        $HTTPGatewayEndpointPort,

        [System.String]
        $ReverseProxyEndpointPort,

        [System.String]
        $EphemeralStartPort,

        [System.String]
        $EphemeralEndPort,

        [System.String]
        $ApplicationStartPort,

        [System.String]
        $ApplicationEndPort
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Node Type to the configuration.
    Write-Verbose "Creating node type." -Verbose
    $nodeTypes =@()

    for($i=0; $i -lt $NodeTypeCounts; $i++)
    {
        $VMNodeTypeName = "$VMNodeTypePrefix$i"
        $nodeType = New-Object PSObject
        $nodeType | Add-Member -MemberType NoteProperty -Name "name" -Value "$VMNodeTypeName"
        $nodeType | Add-Member -MemberType NoteProperty -Name "clientConnectionEndpointPort" -Value "$ClientConnectionEndpointPort"
        $nodeType | Add-Member -MemberType NoteProperty -Name "clusterConnectionEndpointPort" -Value "19001"
        $nodeType | Add-Member -MemberType NoteProperty -Name "leaseDriverEndpointPort" -Value "19002"
        $nodeType | Add-Member -MemberType NoteProperty -Name "serviceConnectionEndpointPort" -Value "19003"
        $nodeType | Add-Member -MemberType NoteProperty -Name "httpGatewayEndpointPort" -Value "$HTTPGatewayEndpointPort"
        $nodeType | Add-Member -MemberType NoteProperty -Name "reverseProxyEndpointPort" -Value "$ReverseProxyEndpointPort"

        $applicationPorts = New-Object PSObject
        $applicationPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$ApplicationStartPort"
        $applicationPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$ApplicationEndPort"

        $ephemeralPorts = New-Object PSObject
        $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$EphemeralStartPort"
        $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$EphemeralEndPort"

        $nodeType | Add-Member -MemberType NoteProperty -Name "applicationPorts" -Value $applicationPorts
        $nodeType | Add-Member -MemberType NoteProperty -Name "ephemeralPorts" -Value $ephemeralPorts

        if($i -eq 0)
        {
            $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $true
        }
        else
        {
            $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $false
        }

        Write-Verbose "Adding Node Type to configuration." -Verbose
        $nodeTypes += $nodeType
    }

    $configContent.properties.nodeTypes = $nodeTypes

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricDiagnosticsConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Diagnostics store settings to the configuration.
    $diagStorePath = "E:\SFDiagnosticsStore"
    Write-Verbose "Setting diagnostics store to local Path: '$diagStorePath'" -Verbose
    
    $configContent.properties.diagnosticsStore.connectionstring = $diagStorePath
    $configContent.properties.diagnosticsStore.storeType = "FileShare"
    $configContent.properties.diagnosticsStore.dataDeletionAgeInDays = "7"
 
    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricSecurityConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $CertificateStoreValue,

        [System.String]
        $ClusterCertificateThumbprint,

        [System.String]
        $ServerCertificateThumbprint,

        [System.String]
        $ReverseProxyCertificateThumbprint,

        [System.String[]]
        $AdminClientCertificateThumbprint = @(),

        [System.String[]]
        $NonAdminClientCertificateThumbprint = @()
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Security settings to the configuration.
    Write-Verbose "Adding security settings for Service Fabric Configuration." -Verbose
    $configContent.properties.security.CertificateInformation.ClusterCertificate.Thumbprint = $ClusterCertificateThumbprint
    $configContent.properties.security.CertificateInformation.ClusterCertificate.X509StoreName = $certificateStoreValue

    $configContent.properties.security.CertificateInformation.ServerCertificate.Thumbprint = $ServerCertificateThumbprint
    $configContent.properties.security.CertificateInformation.ServerCertificate.X509StoreName = $certificateStoreValue

    if(-not [string]::IsNullOrEmpty($ReverseProxyCertificateThumbprint))
    {
        $configContent.properties.security.CertificateInformation.ReverseProxyCertificate.Thumbprint = $ReverseProxyCertificateThumbprint
        $configContent.properties.security.CertificateInformation.ReverseProxyCertificate.X509StoreName = $CertificateStoreValue
    }
    else
    {
        $configContent.properties.security.CertificateInformation.ReverseProxyCertificate = $null
    }

    Write-Verbose "Creating Client Certificate Thumbprint data." -Verbose
    $ClientCertificateThumbprints = @()

    $AdminClientCertificateThumbprint | % {
            $thumbprint = $_.Trim()
            if(-not [String]::IsNullOrEmpty($thumbprint))
            {
                $adminClientCertificate = New-Object PSObject
                $adminClientCertificate | Add-Member -MemberType NoteProperty -Name "CertificateThumbprint" -Value "$thumbprint"
                $adminClientCertificate | Add-Member -MemberType NoteProperty -Name "IsAdmin" -Value $true
                $ClientCertificateThumbprints += $adminClientCertificate    
            }
        }

    $NonAdminClientCertificateThumbprint | % {
            $thumbprint = $_.Trim()
            if(-not [String]::IsNullOrEmpty($thumbprint))
            {
                $nonAdminClientCertificate = New-Object PSObject
                $nonAdminClientCertificate | Add-Member -MemberType NoteProperty -Name "CertificateThumbprint" -Value "$thumbprint"
                $nonAdminClientCertificate | Add-Member -MemberType NoteProperty -Name "IsAdmin" -Value $false
                $ClientCertificateThumbprints += $nonAdminClientCertificate
            }
        }

    if($ClientCertificateThumbprints.Length -eq 0)
    {
        $configContent.properties.security.CertificateInformation.ClientCertificateThumbprints = $null
    }
    else
    {
        $configContent.properties.security.CertificateInformation.ClientCertificateThumbprints = $ClientCertificateThumbprints
    }

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-OptionalFeaturesConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $DNSService,

        [System.String]
        $RepairManager,

        [System.String]
        $BackupRestoreService,

        [System.Boolean]
        $DisableContainers,

        [System.Boolean]
        $BRSDisableKVAuthorityValidation
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Optional Add-On feature to the configuration.
    Write-Verbose "Adding Optional Add-On feature for Service Fabric Configuration." -Verbose

    $addOnFeatures = @()

    if($DNSService -eq "Yes")
    {
        $addOnFeatures += "DnsService"
    }

    if($RepairManager -eq "Yes")
    {
        $addOnFeatures += "RepairManager"
    }

    if($BackupRestoreService -eq "Yes")
    {
        $addOnFeatures += "BackupRestoreService"
    }

    if($addOnFeatures.Length -eq 0)
    {
        $configContent.properties.addOnFeatures = $null
    }
    else
    {
        $configContent.properties.addOnFeatures = $addOnFeatures
    }

    if($DisableContainers)
    {
        Write-Verbose "Adding Optional DisableContainers configuration for Service Fabric Hosting settings." -Verbose

        $hostingDisableContainersParameter = New-Object PSObject
        $hostingDisableContainersParameter | Add-Member -MemberType NoteProperty -Name "name" -Value "DisableContainers"
        $hostingDisableContainersParameter | Add-Member -MemberType NoteProperty -Name "value" -Value $true

        $hostingParameters = @()
        $hostingParameters += $hostingDisableContainersParameter

        $hostingSettings = New-Object PSObject
        $hostingSettings | Add-Member -MemberType NoteProperty -Name "name" -Value "Hosting"
        $hostingSettings | Add-Member -MemberType NoteProperty -Name "parameters" -Value $hostingParameters

        $configContent.properties.fabricSettings += $hostingSettings
    }

    # This setting should prevent SF nodes warning that the machines cannot access CRL distribution endpoint of some CA signed certificate
    # https://github.com/microsoft/service-fabric/issues/48

    Write-Verbose "Adding SlowApiThreshold configuration for Service Fabric Security settings." -Verbose

    $slowApiThresholdParameter = New-Object PSObject
    $slowApiThresholdParameter | Add-Member -MemberType NoteProperty -Name "name" -Value "SlowApiThreshold"
    $slowApiThresholdParameter | Add-Member -MemberType NoteProperty -Name "value" -Value 60

    $securityParameters = @()
    $securityParameters += $slowApiThresholdParameter

    $securitySettings = New-Object PSObject
    $securitySettings | Add-Member -MemberType NoteProperty -Name "name" -Value "Security"
    $securitySettings | Add-Member -MemberType NoteProperty -Name "parameters" -Value $securityParameters

    $configContent.properties.fabricSettings += $securitySettings

    if($BackupRestoreService -eq "Yes" -and $BRSDisableKVAuthorityValidation -and $BRSDisableKVAuthorityValidation -eq $true)
    {
        Write-Verbose "Adding optional DisableKVAuthorityValidation configuration for Service Fabric BackupRestoreService settings." -Verbose

        $brsDisableKVAuthorityValidationParameter = New-Object psobject
        $brsDisableKVAuthorityValidationParameter | Add-Member -MemberType NoteProperty -Name "name" -Value "DisableKVAuthorityValidation"
        $brsDisableKVAuthorityValidationParameter | Add-Member -MemberType NoteProperty -Name "value" -Value $BRSDisableKVAuthorityValidation
    
        $brsParameters = @()
        $brsParameters += $brsDisableKVAuthorityValidationParameter

        $brsSettings = New-Object psobject
        $brsSettings | Add-Member -MemberType NoteProperty -Name "name" -Value "BackupRestoreService"
        $brsSettings | Add-Member -MemberType NoteProperty -Name "parameters" -Value $brsParameters

        $configContent.properties.fabricSettings += $brsSettings
    }

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function New-ServiceFabricDeployment
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $FabricRuntimePackagePath
    )
    
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # Deployment
    Write-Verbose "Validating Service Fabric input configuration" -Verbose
    $output = .\ServiceFabric\TestConfiguration.ps1 -ClusterConfigFilePath $ConfigFilePath -Verbose

    $passStatus = $output | % {if($_ -like "Passed*"){$_}}
    $del = " ", ":"
    $configValidationresult = ($passStatus.Split($del, [System.StringSplitOptions]::RemoveEmptyEntries))[1]

    if($configValidationresult -ne "True")
    {
        throw ($output | Out-String)
    }

    try
    {
        $output = .\ServiceFabric\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $ConfigFilePath -FabricRuntimePackagePath $FabricRuntimePackagePath -AcceptEULA -Verbose
    }
    catch
    {
        throw (($output | Out-String) + "`n Fabric runtime deployment failed with error: $_.")
    }
 
    Write-Verbose "Done with Fabric runtime deployment." -Verbose
}

function Test-ServiceFabricDeployment
{
    param
    (
        [System.String]
        $setupDir,
        
        [System.String]
        $ClientConnectionEndpoint,

        [System.String]
        $ServerCertificateThumbprint,

        [System.String]
        $ClusterCertificateThumbprint
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    $VerbosePreference = [System.Management.Automation.ActionPreference]::Continue

    # Test Connection

    $connectSucceeded = ConnectClusterWithRetryAndExceptionSwallowed -SetupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint

    if(-not $connectSucceeded)
    {
        throw "Cluster connection failed. Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }
        
    # Test Cluster health

    $isHealthy = IsClusterHealthy -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint

    if(-not $isHealthy)
    {
        throw "Cluster health validation failed, cluster unhealthy. Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }

    # Test Cluster upgrade status

    $upgradeComplete = IsClusterUpgradeComplete -SetupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
        -TargetVersion "1.0.0"

    if(-not $upgradeComplete)
    {
        throw "Cluster upgrade validation failed. Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }
}

function Get-CommonModulePath
{
    $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
    $commonModulePath = "$PSModulePath\xSfClusterDSC.Common\xSfClusterDSC.Common.psm1"

    return $commonModulePath
}

Export-ModuleMember -Function *