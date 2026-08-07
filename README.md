# Azure Logic App Standard with Private Networking

[![CI](https://github.com/dwoitzik/azure-logic-app-standard-network/actions/workflows/tf-linter.yml/badge.svg)](https://github.com/dwoitzik/azure-logic-app-standard-network/actions/workflows/tf-linter.yml)

A production-ready Infrastructure as Code (IaC) template to deploy an **Azure Logic App Standard** with fully private networking using Terraform — VNet integration, a network-locked Storage Account, and all **four** Storage Private Endpoints (Blob, File, Queue, Table).

```
                        ┌───────────────────────────────┐
                        │        VNet (10.1.0.0/16)     │
                        │                               │
   ┌────────────────────┴─────┐         ┌───────────────┴─────────┐
   │  snet-integration        │         │  snet-privatelink       │
   │  (Microsoft.Web/         │         │                         │
   │   serverFarms)           │         │  pe-st-blob      │      │
   │  Logic App Standard ─────┼─────────┼── pe-st-file     │      │
   │                          │         │  pe-st-queue     │      │
   │                          │         │  pe-st-table     │      │
   └──────────────────────────┘         │  pe-logic-sites  │      │
                                        └───────────────────┴──────┘
                                                      │
                                            Storage Account
                                       publicNetworkAccess = Disabled
```

## 🚀 Features

- **VNet Integration** — dedicated subnet delegated to `Microsoft.Web/serverFarms`, all outbound traffic stays in your VNet (`vnet_route_all_enabled`)
- **Network-locked Storage** — `public_network_access_enabled = false`, default-deny network rules
- **All four Storage Private Endpoints** — `blob`, `file`, `queue`, `table` (see below — this is the detail that breaks otherwise)
- **Private Logic App endpoint** — `privatelink.azurewebsites.net`, no public hostname
- **Private DNS Zones + VNet links** — resolution works out of the box, no DNS edits
- **Workflow bootstrap** — minimal `host.json`/`connections.json` uploaded into the file share so the runtime boots with an empty definition
- **Keyless runtime** — System-Assigned Managed Identity with Storage data-plane RBAC
- **Optional Consumption workflow** — deploy a serverless `azurerm_logic_app_workflow` alongside the Standard one

## ⚠️ The Four Private Endpoints (403 Lesson)

A Logic App Standard is a Functions host under the hood. Its host runtime needs **four** Storage subresources privately reachable:

| Subresource | Used for |
|---|---|
| **File** | Content share (`host.json`, workflow definitions) |
| **Blob** | Extension-bundle cache, logs |
| **Queue** | Internal WebJobs coordination (scale controller) |
| **Table** | Internal WebJobs metadata |

Creating only the obvious two (File, Blob) leaves Queue/Table resolving to public IPs. Once the account is network-locked, Storage rejects every such request with **HTTP 403 Forbidden** — the host fails to boot about 600 ms after start, the portal designer shows a generic error, and the real cause stays hidden until you check Kudu. This template creates all four by default:

```hcl
resource "azurerm_private_endpoint" "storage" {
  for_each            = toset(["blob", "file", "queue", "table"])
  # ...
}
```

## 🛠️ Prerequisites

- Terraform `>= 1.5.0`
- Azure CLI (`az login`)
- An active Azure Subscription
- Contributor rights on the target Subscription

## 📖 Usage

**1. Clone the repository**

```bash
git clone https://github.com/dwoitzik/azure-logic-app-standard-network.git
cd azure-logic-app-standard-network/terraform
```

**2. Configure your variables**

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your environment values:

```hcl
name        = "workflows"
environment = "dev"
location    = "westeurope"
```

**3. Deploy**

```bash
terraform init
terraform plan
terraform apply
```

## 📁 Repository Structure

```
.
├── terraform/
│   ├── main.tf                  # VNet, Storage, Private Endpoints, Logic Apps
│   ├── variables.tf             # Input variable definitions
│   ├── outputs.tf               # IDs, hostnames, endpoints
│   ├── providers.tf             # Provider configuration
│   └── terraform.tfvars.example # Example configuration
├── .github/workflows/tf-linter.yml
└── README.md
```

## 📖 Deep Dive

Read the full story — the 403 postmortem, why four plausible fixes failed, and how the generic rebuild avoids the trap:

**[Azure Logic App Standard: Private Storage Needs Four Private Endpoints →](https://woitzik.dev/blog/azure-logic-app-standard-four-private-endpoints)**

---

## 📄 License

MIT — free to use, modify, and distribute.

*Built by [David Woitzik](https://woitzik.dev) · [LinkedIn](https://linkedin.com/in/david-woitzik)*
