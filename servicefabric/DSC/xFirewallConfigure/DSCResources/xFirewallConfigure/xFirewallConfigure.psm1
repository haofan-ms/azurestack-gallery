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
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint
    )
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
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint
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

    $setupDir = "E:\SFSetup"
    
    # SF deployment workflow stage 1.2: Host Provision: Configure firewall rules
    #     Running on every node, preparing environment for service fabric installnation.

    # Enable File and Printer Sharing for Network Discovery (Port 445)
    Write-Verbose "Opening TCP firewall port 445 for networking." -Verbose
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
    Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true

    # Add remote IP address for 'Windows Remote Management (HTTP-In)'
    # This enables every node have access to the nodes behind different sub domains
    # IP range got from paramater should in a format of 10.0.[].0/24
    
    #Get VM Node Type Instance Counts from SF cluster configuration because the size can be changed after scale-in/out.
    $VMNodeTypeInstanceCountsFromClusterConfig = Get-VMNodeTypeInstanceCountsFromClusterConfig -SetupDir $setupDir `
        -ClientConnectionEndpoint $ClientConnectionEndpoint `
        -ServerCertificateThumbprint $ServerCertificateThumbprint `
        -ClusterCertificateThumbprint $ClusterCertificateThumbprint `
        -InitialClusterSize $VMNodeTypeInstanceCounts `
        -TimeoutTimeInMin 1 `
        -TimeoutBetweenProbsInSec 15

    Write-Verbose "Add remote IP addresses for Windows Remote Management (HTTP-In) for different sub domain." -Verbose
    $IParray = @()
    for($i = 0; $i -lt $VMNodeTypeInstanceCountsFromClusterConfig.Count; $i ++)
    {
        $IParray += $SubnetIPFormat.Replace("[]", $i)
    }

    Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -RemoteAddress $IParray
    Write-Verbose "Subnet IPs enabled in WINRM-HTTP-In-TCP-PUBLIC: $IParray"

    # Enable SF client endpoint firewall rule
    $sfServerPortFirewallRule = Get-NetFirewallRule -DisplayName "Service Fabric Server Port $ClientConnectionEndpointPort" -ErrorAction Ignore
    if ($null -eq $sfServerPortFirewallRule)
    {
        Write-Verbose "Set firewall rule for Service Fabric management port: $ClientConnectionEndpointPort" -Verbose
        New-NetFirewallRule -DisplayName "Service Fabric Server Port $ClientConnectionEndpointPort" -Direction Outbound -LocalPort $ClientConnectionEndpointPort -Protocol TCP -Action Allow
    }
    else
    {
        Write-Verbose "Firewall rule for for Service Fabric management port: $ClientConnectionEndpointPort already exists" -Verbose
    }
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
        [System.UInt32[]]
        $VMNodeTypeInstanceCounts,

        [parameter(Mandatory = $true)]
        [System.String]
        $SubnetIPFormat,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpoint,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ClusterCertificateCommonName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ServerCertificateCommonName,

        [parameter(Mandatory = $false)]
        [System.String]
        $ClusterCertificateThumbprint,

        [parameter(Mandatory = $false)]
        [System.String]
        $ServerCertificateThumbprint
    )

    # Creating the SF client endpoint firewall rule is the last step, check if the rule exist. If it exists all policies have been applied
    $remotePSFirewallRule = Get-NetFirewallRule -DisplayName "Service Fabric Server Port $ClientConnectionEndpointPort" -ErrorAction Ignore
    $result = $null -ne $remotePSFirewallRule

    return $result
}

function Get-CommonModulePath
{
    $PSModulePath = $Env:PSModulePath -split ";" | Select-Object -Index 1
    $commonModulePath = "$PSModulePath\xSfClusterDSC.Common\xSfClusterDSC.Common.psm1"

    return $commonModulePath
}

Export-ModuleMember -Function *-TargetResource