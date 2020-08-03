resource "azurerm_resource_group" "demo" {
  name = "demo"
  location = "France Central"
}

<%-
require 'yaml'
require 'base64'
result = kv('customers/', recurse: true)
result.each.with_index do |tuple, index|
  if index > 0
    ckey = tuple['Key'].gsub('customers/', '')
    if tuple['Value'].nil?
      yaml = []
    else
      yaml = YAML.load(Base64.decode64(tuple['Value']))
    end
-%>

########################
### BEGIN <%= ckey %>
########################
resource "azurerm_storage_account" "<%= ckey %>" {
  name                      = "my<%= ckey %>storageaccount"
  resource_group_name       = azurerm_resource_group.demo.name
  location                  = "francecentral"
  account_tier              = "Standard"
  account_kind              = "StorageV2"
  account_replication_type  = "LRS"
  enable_https_traffic_only = true
}

resource "vault_generic_secret" "demo-<%= ckey %>" {
  path = "customers/azure/accounts/<%= ckey %>"
  data_json = <<EOT
{
  "acces_key": "my<%= ckey %>storageaccount",
  "secret_key": "${azurerm_storage_account.<%= ckey %>.primary_access_key}"
}
EOT
}

<%-
      ['dev','qa','prod'].each do |environment|
-%>

resource "azurerm_storage_container" "<%= ckey %>-<%= environment %>" {
  name                  = "<%= environment %>"
  storage_account_name  = azurerm_storage_account.<%= ckey %>.name
  container_access_type = "private"
  depends_on = [azurerm_storage_account.<%= ckey %>]
}

resource "cloudflare_record" "cloudflare-dns-<%= ckey %>-<%= environment %>" {
  zone_id = "${var.cloudflare_zone_id}"
  name    = "<%= ckey %>.<%= environment %>"
  value   = "xxx.xxx.xxx.xxx"
  type    = "A"
  proxied = true
}

<%-
      end
-%>


resource "k8s_manifest" "zenko-account-<%= ckey %>" {
  content   = templatefile("/home/terraform/manifests/zenko.yaml", {
    account = "<%= ckey %>"
  })
  namespace = "customers"
  depends_on = [
    azurerm_storage_account.<%= ckey %>,
    azurerm_storage_container.<%= ckey %>-dev,
    azurerm_storage_container.<%= ckey %>-qa,
    azurerm_storage_container.<%= ckey %>-prod
  ]
}


<%-
    if yaml["enabled"] == true
-%>

resource "azurerm_availability_set" "<%= ckey %>" {
  name                = "<%= ckey %>"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name

  platform_fault_domain_count  = 2
  platform_update_domain_count = 5

  managed = true
}

resource "pingdom_check" "pingdom-check-<%= ckey %>" {
    type = "http"
    name = "<%= ckey %>"
    host = "<%= ckey %>.prod.mycompany.com"
    paused = true
    probefilters = "region:EU"
    resolution = 1
    sendnotificationwhendown = 4
    url = "/health"
    encryption = true
    notifyagainevery = 2
    notifywhenbackup = true
    lifecycle {
      ignore_changes = [
        paused,
        integrationids
      ]
    }
}

resource "k8s_manifest" "vmpool-<%= ckey %>" {
  content   = templatefile("/home/terraform/manifests/vmpool.yaml", {
    customer = "<%= ckey %>",
    provider = "azr"
  })

  namespace = "customers"

  depends_on = [
    azurerm_availability_set.<%= ckey %>
  ]
}

<%-
    end
  end
end
-%>
