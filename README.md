## Scripts para deletar recursos órfãos no Azure

O objetivo desse script é fornecer uma maneira fácil e automatizada de remover recursos órfãos do Azure

<img src="https://caio.work/orphan/Vid001.gif" width="650">

Atualmente os recursos suportados são:
- App Service Plans
- Application Gateways
- Availability Sets
- Disks
- Front Door WAF Policy
- IP Groups
- Load Balancers
- NAT Gateways
- Network Interfaces
- Network Security Groups
- Private DNS zones
- Private Endpoints
- Public IPs
- Route Tables
- SQL elastic pool
- Subnets
- Traffic Manager Profiles
- Virtual Networks

As queries foram adaptadas a partir do [Workbook de recursos órfãos](https://github.com/dolevshor/azure-orphan-resources)