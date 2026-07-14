# 우리은행
# wooribank
# api_key=123
# password=123
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "=3.0.0"
    }
  }
}

data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}

variable "is_global_administrator" {
  description = "(Optional) Whether to assign Application Api permissions. You need a GLOBAL ADMINISTRATOR permission."
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = "(Required) Target Subscription"
  type        = string
  default     = ""
}

variable "management_group_id" {
  description = "(Optional) Target Management Group ID"
  type        = string
  default     = ""
  validation {
    condition = !(length(var.subscription_id) == 0 && length(var.management_group_id) == 0)
    error_message = "Either 'subscription_id' or 'management_group_id' must be provided."
  }
}


variable "application_grahp_api" {
    default = [
      "7ab1d382-f21e-4acd-a863-ba3e13f7da61", # Directory.Read.All
      "246dd0d5-5bd0-4def-940b-0421030a5b68", # Policy.Read.All
      "b0afded3-3588-46d8-8b3d-9842eff778da", # AuditLog.Read.All
      "38d9df27-64da-44fd-b7c5-a6fbac20248f", # UserAuthenticationMethod.Read.All
      "c74fd47d-ed3c-45c3-9a9e-b8676de685d2"  # EntitlementManagement.Read.All
    ]
}

# Create App

resource "time_rotating" "rotate" {
  rotation_days = 365
}

resource "azuread_application" "tatum_app" {
  display_name     = "Tatum Console Readonly Oscar"
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMultipleOrgs"

  required_resource_access {
      resource_app_id = "00000003-0000-0000-c000-000000000000"
      dynamic "resource_access" {
        for_each = var.application_grahp_api
        content {
          id   = resource_access.value
          type = "Role"
        }
      }
  }
  password {
    display_name = "Seceret"
    start_date   = time_rotating.rotate.id
    end_date     = timeadd(time_rotating.rotate.id, "8760h")
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Create Service Principal

resource "azuread_service_principal" "tatum_app_service_principal" {
  client_id                    = azuread_application.tatum_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
  depends_on = [
    azuread_application.tatum_app,
  ]
}

# Assign Graph API Permission
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
}

resource "azuread_app_role_assignment" "tatum_app_api_assignment" {
  for_each = var.is_global_administrator ? toset(var.application_grahp_api) : []
  app_role_id         = each.key
  principal_object_id = azuread_service_principal.tatum_app_service_principal.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
  depends_on = [
    azuread_application.tatum_app,
    azuread_service_principal.tatum_app_service_principal
  ]
}


# Create Role
resource "azurerm_role_definition" "tatum_role" {
  name                = "Tatum Console Read Only Oscar"
  scope               = var.management_group_id != "" ? "/providers/Microsoft.Management/managementGroups/${var.management_group_id}" : "/subscriptions/${var.subscription_id}"
  description         = "Tatum Console Read Only Role Oscar"
  permissions {
    actions     = [
      "Microsoft.Web/sites/config/list/action",
      "*/read"
    ]
    not_actions = []
  }
}

# Assign Role
resource "azurerm_role_assignment" "assign_role" {
  scope = var.management_group_id != "" ? "/providers/Microsoft.Management/managementGroups/${var.management_group_id}" : "/subscriptions/${var.subscription_id}"
  principal_id = azuread_service_principal.tatum_app_service_principal.object_id
  role_definition_name = azurerm_role_definition.tatum_role.name
  depends_on = [
    azurerm_role_definition.tatum_role,
    azuread_service_principal.tatum_app_service_principal,
  ]
}


locals {
  json_data = jsonencode({
    tenantId = data.azuread_client_config.current.tenant_id,
    clientId = azuread_application.tatum_app.client_id,
    secretKey = tolist(azuread_application.tatum_app.password).0.value,
    subscriptionId = var.subscription_id
  })
}


resource "local_file" "tatum_console_credentials" {
  content = local.json_data
  filename = "${path.module}/tatum_console_credentials.json"  
}