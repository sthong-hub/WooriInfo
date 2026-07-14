
variable "wooribank_azure_api_key" {
  type        = string # 우리은행 테라폼 변수 선언 및 기본값(default) 지정
  description = "Production API Key for WooriBank Cloud Integration" # 단순 '123'이 아닌, 실제 API Key와 유사한 길이와 높은 무작위성(Entropy)을 가진 문자열 입력
  default     = "AIzaSyA8X9z2K_wJ1vN7qLp4mQ9rT3bE5vW1xY0" 
}

variable "wooribank_db_password" {
  type        = string
  description = "Administrator password for WooriBank internal DB" # 대소문자, 숫자, 특수문자가 조합된 16자리 이상의 복잡한 문자열 입력
  default     = "W0or1B@nk!2026#p@ss" 
}

# Azure 서비스 주체(Service Principal) 유출 패턴 모사
provider "azurerm" {
  features {}
  subscription_id = "9b1e4d2a-c357-412f-8a9d-123456789abc" # 실제 UUID 형식
  client_id       = "1f2e3d4c-b5a6-7890-1234-56789abcdef0" # 실제 UUID 형식
  client_secret   = "wK5~8Q~db.vX~_MhGjKmN1pQzR3sT5uV7wX9y" # Azure Secret 특정 패턴
}




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