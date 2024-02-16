<#
.SYNOPSIS
    Script para deletar recursos órfãos do Azure
.DESCRIPTION
    Não é necessário fornecer nenhum input para o script, a analise dos recursos órfãos será feita em todo o ambiente

    Para iniciar, é necessário ter instalado o módulo Az e o módulo Az.ResourceGraph
        Install-Module -Name Az
        Install-Module -Name Az.ResourceGraph
        
    Recursos atualmente suportados pelo script:
        App Service Plans
        Application Gateways
        Availability Sets
        Disks
        Front Door WAF Policy
        IP Groups
        Load Balancers
        NAT Gateways
        Network Interfaces
        Network Security Groups
        Private DNS zones
        Private Endpoints
        Public IPs
        Route Tables
        SQL elastic pool
        Subnets
        Traffic Manager Profiles
        Virtual Networks

.EXAMPLE
    PS C:\> DeleteOrphanResources.ps1

    Com os parâmetros acima, o script irá listar todos os recursos órfãos do ambiente

.NOTES
    Filename: DeleteOrphanResources.ps1
    Author: Caio Souza do Carmo
    Modified date: 2024-02-06
    Version 1.0 - Deletar recursos
#>

function GetDate() {
    $TimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("E. South America Standard Time")
    $tCurrentTime = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $TimeZone)
    return Get-Date -Date $tCurrentTime -UFormat "%Y-%m-%d %H:%M:%S"
}

function GetQueries() {
    $Queries = @{
        "App Service Plans"        = 'resources
        | where type =~ "microsoft.web/serverfarms"
        | where properties.numberOfSites == 0
        | project id, name, type, resourceGroup, subscriptionId, location';
        
        "Availability Sets"        = 'resources
        | where type =~ "microsoft.compute/availabilitysets"
        | where properties.virtualMachines == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "SQL elastic pool"         = 'resources
        | where type =~ "microsoft.sql/servers/elasticpools"
        | project elasticPoolId = tolower(id), id, name, resourceGroup, subscriptionId, location, properties
        | join kind=leftouter (resources
        | where type =~ "microsoft.sql/servers/databases"
        | project id, properties
        | extend elasticPoolId = tolower(properties.elasticPoolId)) on elasticPoolId
        | summarize databaseCount = countif(id != "") by id, name, resourceGroup, subscriptionId, location
        | where databaseCount == 0
        | project-away databaseCount'

        "Disks"                    = 'resources
        | where type has "microsoft.compute/disks"
        | where managedBy == ""
        | where not(name endswith "-ASRReplica" or name startswith "ms-asr-" or name startswith "asrseeddisk-")
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Public IPs"               = 'resources
        | where type == "microsoft.network/publicipaddresses"
        | where properties.ipConfiguration == "" and properties.natGateway == "" and properties.publicIPPrefix == ""
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Network Interfaces"       = 'resources
        | where type has "microsoft.network/networkinterfaces"
        | where isnull(properties.privateEndpoint)
        | where isnull(properties.privateLinkService)
        | where properties.hostedWorkloads == "[]"
        | where properties !has "virtualmachine"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Network Security Groups"  = 'resources
        | where type == "microsoft.network/networksecuritygroups" and isnull(properties.networkInterfaces) and isnull(properties.subnets)
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Route Tables"             = 'resources
        | where type == "microsoft.network/routetables"
        | where isnull(properties.subnets)
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Load Balancers"           = 'resources
        | where type == "microsoft.network/loadbalancers"
        | where properties.backendAddressPools == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Front Door WAF Policy"    = 'resources
        | where type == "microsoft.network/frontdoorwebapplicationfirewallpolicies"
        | where properties.frontendEndpointLinks== "[]" and properties.securityPolicyLinks == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Traffic Manager Profiles" = 'resources
        | where type == "microsoft.network/trafficmanagerprofiles"
        | where properties.endpoints == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Application Gateways"     = 'resources
        | where type =~ "microsoft.network/applicationgateways"
        | extend backendPoolsCount = array_length(properties.backendAddressPools),SKUName= tostring(properties.sku.name), SKUTier= tostring(properties.sku.tier),SKUCapacity=properties.sku.capacity,backendPools=properties.backendAddressPools , AppGwId = tostring(id)
        | project AppGwId, resourceGroup, location, subscriptionId, tags, name, SKUName, SKUTier, SKUCapacity
        | join (
            resources
            | where type =~ "microsoft.network/applicationgateways"
            | mvexpand backendPools = properties.backendAddressPools
            | extend backendIPCount = array_length(backendPools.properties.backendIPConfigurations)
            | extend backendAddressesCount = array_length(backendPools.properties.backendAddresses)
            | extend backendPoolName  = backendPools.properties.backendAddressPools.name
            | extend AppGwId = tostring(id)
            | summarize backendIPCount = sum(backendIPCount) ,backendAddressesCount=sum(backendAddressesCount) by AppGwId
        ) on AppGwId
        | project-away AppGwId1
        | where  (backendIPCount == 0 or isempty(backendIPCount)) and (backendAddressesCount==0 or isempty(backendAddressesCount))
        | extend Details = pack_all()
        | project id=AppGwId, name, resourceGroup, subscriptionId, location';

        "Virtual Networks"         = 'resources
        | where type == "microsoft.network/virtualnetworks"
        | where properties.subnets == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Subnets"                  = 'resources
        | where type =~ "microsoft.network/virtualnetworks"
        | extend subnet = properties.subnets
        | mv-expand subnet
        | extend ipConfigurations = subnet.properties.ipConfigurations
        | extend delegations = subnet.properties.delegations
        | where isnull(ipConfigurations) and delegations == "[]"
        | project id=subnet.id, name=tostring(subnet.name), type=subnet.type, resourceGroup, subscriptionId, location';

        "NAT Gateways"             = 'resources
        | where type == "microsoft.network/natgateways"
        | where isnull(properties.subnets)
        | project id, name, type, resourceGroup, subscriptionId, location';

        "IP Groups"                = 'resources
        | where type == "microsoft.network/ipgroups"
        | where properties.firewalls == "[]" and properties.firewallPolicies == "[]"
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Private DNS zones"        = 'resources
        | where type == "microsoft.network/privatednszones"
        | where properties.numberOfVirtualNetworkLinks == 0
        | project id, name, type, resourceGroup, subscriptionId, location';

        "Private Endpoints"        = 'resources
        | where type =~ "microsoft.network/privateendpoints"
        | extend Details = pack_all()
        | extend plsc = iff(array_length(properties.privateLinkServiceConnections) > 0, properties.privateLinkServiceConnections, properties.manualPrivateLinkServiceConnections)
        | extend plscStatus = plsc[0].properties.privateLinkServiceConnectionState.status
        | where plscStatus =~ "Disconnected"
        | project id, name, type, resourceGroup, subscriptionId, location';
    }

    return $Queries;
}

function ShowMenu() {
    param (
        [Parameter()][hashtable]
        $ResourceList
    )

    $TotalResources = 0;
    foreach ($Option in ($ResourceList.Keys | Sort-Object)) {
        $QttyResources = $ResourceList[$Option]["Result"].Count;
        $TotalResources += $QttyResources;
        Write-Host "Digite `"$($Option)`" para deletar todos os $($QttyResources) $($ResourceList[$Option]["ResourceType"]) órfãos" -ForegroundColor White;
    }

    Write-Host "Digite `"Z`" para deletar todos os $($TotalResources) recursos órfãos" -ForegroundColor White;
    Write-Host "Digite `"0`" (zero) para listar todos os $($TotalResources) recursos órfãos" -ForegroundColor Gray;
    Write-Host "Digite `"1`" (um) para listar todas as opções" -ForegroundColor Gray;
    Write-Host "Digite `"9`" para sair" -ForegroundColor Gray;
}

function ShowResources() {
    param (
        [Parameter()][hashtable]
        $ResourceList
    )

    Clear-Host;

    foreach ($Option in ($ResourceList.Keys | Sort-Object)) {
        Write-Host ("$($ResourceList[$Option]["ResourceType"])") -ForegroundColor DarkYellow;
        $ResourceList[$Option]["Result"] | Format-Table -Property @{Name = 'Name'; Expression = { $_.name } }, @{Name = 'Resource Group'; Expression = { $_.resourceGroup } }, @{Name = 'Subscription Id'; Expression = { $_.subscriptionId } }
    }

    ShowMenu -ResourceList $ResourceList;
}

function DeleteResources() {
    param (
        [Parameter()][hashtable]
        $ResourceList,

        [Parameter()][string]
        $UserOption
    )

    if ($ResourceList.Keys -icontains $UserOption -or $UserOption -ieq "Z") {
        foreach ($Option in $ResourceList.Keys) {
            if ($Option -ieq $UserOption -or $UserOption -ieq "Z") {
                Write-Host "Deletando recursos órfãos do tipo `"$($ResourceList[$Option]["ResourceType"])`""  -ForegroundColor DarkYellow;
                foreach ($Resource in $ResourceList[$Option]["Result"]) {
                    Write-Host "Deletando: $($Resource.name)" -ForegroundColor Yellow;
                    Remove-AzResource -ResourceId $Resource.id -Force -ErrorAction SilentlyContinue -ErrorVariable ResourceNotDeleted | Out-Null;
                    if (!$ResourceNotDeleted) {
                        Write-Host "Recurso `"$($Resource.name)`" deletado" -ForegroundColor Green;
                    }
                    else {
                        Write-Host "Erro ao deletar o recurso `"$($Resource.name)`"" -ForegroundColor Red;
                    }
                }
                Write-Host "`n";
            }
        }
    }
    else {
        Write-Host ("[$(GetDate)] Opção inválida`n") -ForegroundColor DarkRed;
    }

    ShowMenu -ResourceList $ResourceList;
}

$Queries = (GetQueries);
$ResourceList = @{};
$Counter = 65;

foreach ($ResourceType in $Queries.Keys) {
    Write-Host ("[$(GetDate)] Listando recursos órfãos do tipo `"$($ResourceType)`"") -ForegroundColor Yellow;
    $Query = $Queries[$ResourceType];
    #Limitado à 1000 recursos, mas se encontrar alguém com mais recursos órfãos do que isso eu implemento a paginação
    #https://learn.microsoft.com/en-us/azure/governance/resource-graph/paginate-powershell
    $GraphResult = Search-AzGraph -Query $Query -First 1000;
    Write-Host ("[$(GetDate)] $($GraphResult.Count) recursos do tipo `"$($ResourceType)`" foram encontrados") -ForegroundColor DarkYellow;
    if ($GraphResult.Count -gt 0) {
        $ResourceList[[char]$Counter] = @{"ResourceType" = $ResourceType; "Result" = $GraphResult };
        $Counter++;
    }
}

if ($ResourceList.Count -eq 0) {
    Write-Host ("[$(GetDate)] Nenhum recurso órfão encontrado") -ForegroundColor Green;
    return;
}

ShowMenu -ResourceList $ResourceList;

$UserOption = -1;

do {
    $UserOption = Read-Host "`nDigite aqui";
    if ($UserOption -match "^[a-zA-Z]$") {
        DeleteResources -ResourceList $ResourceList -UserOption $UserOption.ToUpper();
    }
    elseif ($UserOption -eq 0) {
        ShowResources -ResourceList $ResourceList;
    }
    elseif ($UserOption -eq 1) {
        ShowMenu -ResourceList $ResourceList;
    }
    elseif ($UserOption -eq 9) {
        Write-Host ("[$(GetDate)] Agradecemos a preferência") -ForegroundColor Cyan;
    }
    else {
        Write-Host ("`n[$(GetDate)] Opção inválida`n") -ForegroundColor DarkRed;
        ShowMenu -ResourceList $ResourceList;
    }
} while ($UserOption -ne 9);