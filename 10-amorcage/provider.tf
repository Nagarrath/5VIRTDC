# 10-amorcage — SEULE couche qui utilise root@pam.
# Mot de passe root passé par l'environnement, jamais dans un fichier :
#   export PROXMOX_VE_PASSWORD='…'

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
  fiche = yamldecode(file("${path.module}/../fiche.yml"))
}

provider "proxmox" {
  endpoint = "https://${local.fiche.noeuds[0].ip}:8006/"
  username = "root@pam"
  # password : lu dans PROXMOX_VE_PASSWORD
  insecure = true # certificat auto-signé du lab
}
