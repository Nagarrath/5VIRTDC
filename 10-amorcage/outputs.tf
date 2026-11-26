# Jeton complet (utilisateur@pve!nom=secret) : format attendu par PROXMOX_VE_API_TOKEN
output "jeton_tofu" {
  value     = proxmox_user_token.outil["tofu"].value
  sensitive = true
}

# Ansible veut le secret seul (la partie après « = »)
output "secret_ansible" {
  value     = split("=", proxmox_user_token.outil["ansible"].value)[1]
  sensitive = true
}
