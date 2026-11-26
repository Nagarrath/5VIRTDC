# 10-amorcage — identités des outils (seule couche lancée en root@pam).
# Le provider et la lecture de fiche.yml sont dans provider.tf.

locals {
  # Rôle personnalisé d'OpenTofu : uniquement les privilèges dont les couches 20 à 40 ont besoin.
  roles = {
    "CS-Tofu" = [
      "Datastore.Allocate", "Datastore.AllocateSpace", "Datastore.AllocateTemplate", "Datastore.Audit",
      "Group.Allocate", "Permissions.Modify", "Pool.Allocate", "Pool.Audit",
      "Realm.AllocateUser", "SDN.Allocate", "SDN.Audit", "SDN.Use",
      "Sys.Audit", "Sys.Console", "Sys.Modify", "User.Modify",
      "VM.Allocate", "VM.Audit", "VM.Backup", "VM.Clone",
      "VM.Config.CDROM", "VM.Config.CPU", "VM.Config.Cloudinit", "VM.Config.Disk",
      "VM.Config.HWType", "VM.Config.Memory", "VM.Config.Network", "VM.Config.Options",
      "VM.Console", "VM.GuestAgent.Audit", "VM.Migrate", "VM.PowerMgmt", "VM.Replicate",
    ]
  }

  # Un utilisateur par outil -> son rôle
  outils = {
    tofu    = "CS-Tofu"
    ansible = "PVEAuditor" # inventaire dynamique : lecture seule
  }
}

resource "proxmox_virtual_environment_role" "outil" {
  for_each   = local.roles
  role_id    = each.key
  privileges = each.value
}

resource "proxmox_virtual_environment_user" "outil" {
  for_each = local.outils
  user_id  = "${each.key}@pve"
  comment  = "Compte technique ${each.key} (géré par OpenTofu)"
  # pas de mot de passe : ce compte ne se connecte que par jeton
}

resource "proxmox_user_token" "outil" {
  for_each              = local.outils
  user_id               = proxmox_virtual_environment_user.outil[each.key].user_id
  token_name            = each.key
  privileges_separation = true # le jeton n'a QUE les droits de son ACL
}

# Piège : avec la séparation des privilèges, il faut une ACL pour l'utilisateur ET une pour le jeton
# (les droits effectifs du jeton = intersection des deux).
resource "proxmox_acl" "utilisateur" {
  for_each   = local.outils
  path       = "/"
  role_id    = each.value
  user_id    = proxmox_virtual_environment_user.outil[each.key].user_id
  propagate  = true
  depends_on = [proxmox_virtual_environment_role.outil]
}

resource "proxmox_acl" "jeton" {
  for_each   = local.outils
  path       = "/"
  role_id    = each.value
  token_id   = proxmox_user_token.outil[each.key].id
  propagate  = true
  depends_on = [proxmox_virtual_environment_role.outil]
}
