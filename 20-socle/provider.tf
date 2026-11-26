# Couche exécutée avec le jeton OpenTofu (créé par 10-amorcage) :
#   export PROXMOX_VE_API_TOKEN="$(tofu -chdir=10-amorcage output -raw jeton_tofu)"
#   unset PROXMOX_VE_PASSWORD

terraform {
  required_version = ">= 1.8"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
  }
}

locals {
  fiche    = yamldecode(file("${path.module}/../fiche.yml"))
  noeuds   = [for n in local.fiche.noeuds : n.nom] # ["pve1", "pve2", "pve3"]
  n1       = local.noeuds[0]                       # "pve1"
  mtu_back = local.fiche.front.mtu - 50            # 1450
}

provider "proxmox" {
  endpoint = "https://${local.fiche.noeuds[0].ip}:8006/"
  # api_token : lu dans PROXMOX_VE_API_TOKEN
  insecure = true # certificat auto-signé du lab
}
