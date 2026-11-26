# CyberSadiver — l'infrastructure en code

Ce dépôt reconstruit le cluster Proxmox VE `pve-cyber` de CyberSadiver à partir de zéro : 3 nœuds, stockage NFS, SDN back et labo, pare-feu, droits, modèle Debian 13, services cs-dns, cs-web et cs-bdd, sauvegarde, réplication et HA.

**Règle d'or : aucune modification manuelle.** Tout ce qui existe vient du dépôt. Les seules opérations manuelles sont l'installation de Proxmox VE, la copie de la clé SSH et la création du cluster (étape 1), puis l'activation du TOTP par chaque utilisateur.

---

## 0. Avancement (mis à jour le 26/11)

| Étape | Contenu | État |
|---|---|---|
| 0 — Dépôt | Couches, `fiche.exemple.yml`, `.gitignore`, README, verrous du provider (`.terraform.lock.hcl`) | ✅ Fait — reste : coffre `50-config/secrets.yml` (ansible-vault) et captures du Contrôle 0 |
| 1 — Nœuds | Réinstallation PVE 9, clé SSH, `00-hotes/hotes.yml`, création du cluster | 🟡 `hotes.yml` écrit (dépôts, mises à jour, chrony, /etc/hosts, dnsmasq, NFS, snippet agent QEMU) — à lancer deux fois ; cluster en cours de création |
| 2 — Amorçage | `10-amorcage/main.tf` et `outputs.tf` : rôle CS-Tofu, comptes et jetons `tofu` et `ansible` | 🟡 Code écrit et validé (`tofu validate`) — `apply` à lancer une fois le cluster créé |
| 3 — Socle | Stockage cs-nfs, SDN back et labo, droits, pare-feu | ⬜ À faire |
| 4 — Image | Image Debian 13, modèle 900 (le snippet `vendor-agent.yml` est déjà déposé par `hotes.yml`) | ⬜ À faire |
| 5 — Modules | `modules/vm`, `modules/ct` avec validations | ⬜ À faire |
| 6 — Services | cs-dns, cs-web, cs-bdd, sauvegarde, réplication, HA | ⬜ À faire |
| 7 — Configuration | Inventaire dynamique, rebond SSH, rôles unbound, web, mariadb | ⬜ À faire |
| 8 — Dérive et reconstruction | Démonstration et chronométrage | ⬜ À faire |

**Postes utilisés :** OpenTofu tourne sous Windows (poste du pilote, qui garde les fichiers `*.tfstate`). Ansible tourne sur un poste Linux/WSL d'un membre du groupe (Ansible ne fonctionne pas sous Windows).

**Écarts avec le dossier du TP1 :** le réseau de gestion et front est `172.19.0.0/16` (nœuds en `172.19.3.151` à `.153`, passerelle `172.19.3.254`) au lieu de `192.168.10.0/24`. Masque, DNS (`1.1.1.1`) et adresses des invités (`172.19.3.101`, `.102`) à confirmer.

---

## 1. Prérequis (poste qui lance les outils)

| Outil | Version | Vérifier |
|---|---|---|
| OpenTofu | ≥ 1.8 | `tofu version` |
| Provider `bpg/proxmox` | 0.123.1 (figé dans `.terraform.lock.hcl`) | `tofu -chdir=20-socle providers` |
| Ansible core | ≥ 2.17 | `ansible --version` |
| Collections | `community.proxmox`, `community.mysql` | `ansible-galaxy collection list` |
| Python (poste) | module `requests` (inventaire dynamique) | `python3 -c "import requests"` |
| Git | — | `git status` |
| Clé SSH | ed25519, copiée en root sur les 3 nœuds | `ssh root@<ip pve1> pveversion` |

Cible : Proxmox VE 9, 3 nœuds réinstallés avec les choix du TP1 (premier disque seulement, ZFS RAID0, `rpool` vu comme `local-zfs`).

---

## 2. Organisation du dépôt

```
.
├── fiche.exemple.yml     # modèle des valeurs du cluster (versionné, sans secret)
├── fiche.yml             # valeurs réelles (IGNORÉ par Git)
├── 00-hotes/             # Ansible  · nœuds : dépôts, chrony, hosts, dnsmasq, NFS, snippet
├── 10-amorcage/          # OpenTofu · root@pam : rôle, utilisateurs et jetons des outils
├── 20-socle/             # OpenTofu · stockage, SDN, droits, pare-feu
├── 30-image/             # OpenTofu · image cloud Debian 13 + modèle 900
├── modules/vm, modules/ct# OpenTofu · un invité = un appel de module
├── 40-services/          # OpenTofu · cs-dns, cs-web, cs-bdd + sauvegarde, réplication, HA
└── 50-config/            # Ansible  · unbound, nginx, MariaDB (inventaire dynamique, rebond SSH)
```

**Une couche = un dossier = un état OpenTofu.** Les couches s'exécutent dans l'ordre 00 → 50.

---

## 3. Secrets : où ils sont

| Secret | Où | Jamais dans Git |
|---|---|---|
| Mot de passe root des nœuds | `PROXMOX_VE_PASSWORD` (couche 10 seulement) | ✔ |
| Jeton OpenTofu | `PROXMOX_VE_API_TOKEN` ← `tofu -chdir=10-amorcage output -raw jeton_tofu` | ✔ |
| Jeton Ansible | `PROXMOX_TOKEN_SECRET` ← `tofu -chdir=10-amorcage output -raw secret_ansible` | ✔ |
| Mot de passe console des invités | `TF_VAR_mot_de_passe_console` | ✔ |
| Mots de passe de la base | `50-config/secrets.yml` **chiffré** par `ansible-vault` (versionné chiffré) | mot de passe du coffre : ✔ |
| États OpenTofu (`*.tfstate`) | sur le poste du pilote OpenTofu | ✔ |
| Clé SSH privée | `~/.ssh/` du poste (chemin dans `fiche.yml`) | ✔ |

---

## 4. Reconstruire (ordre d'exécution)

Toutes les commandes se lancent **depuis la racine du dépôt**, sauf Ansible (depuis le dossier de sa couche).

### 4.0 Préparer le poste
```bash
cp fiche.exemple.yml fiche.yml          # puis remplir avec le dossier du TP1
ansible-galaxy collection install -r 50-config/requirements.yml
tofu -chdir=10-amorcage init
tofu -chdir=20-socle init
tofu -chdir=30-image init
tofu -chdir=40-services init
```

### 4.1 Étape 1 — Nœuds (manuel, puis Ansible)
1. **À la main** : installer Proxmox VE 9 sur les 3 nœuds (choix du TP1).
2. **À la main** : copier la clé SSH.
   ```bash
   ssh-copy-id root@<ip pve1>      # adresses dans fiche.yml
   ssh-copy-id root@<ip pve2>
   ssh-copy-id root@<ip pve3>
   ```
3. Couche 00, **deux fois** (le 2e passage doit afficher `changed=0`) :
   ```bash
   cd 00-hotes && ansible-playbook hotes.yml && ansible-playbook hotes.yml && cd ..
   ```
4. **Redémarrer les 3 nœuds** (nouveau noyau possible), **puis** créer le cluster à la main :
   ```bash
   root@pve1:~# pvecm create pve-cyber --link0 <ip pve1>
   root@pve2:~# pvecm add <ip pve1> --link0 <ip pve2>
   root@pve3:~# pvecm add <ip pve1> --link0 <ip pve3>
   root@pve1:~# pvecm status        # Quorate: Yes, 3 votes
   ```

### 4.2 Étape 2 — Amorçage (root@pam, une seule fois)
```bash
export PROXMOX_VE_PASSWORD='…'
tofu -chdir=10-amorcage apply
```

### 4.3 Passer aux jetons (à refaire dans chaque nouveau terminal)
```bash
export PROXMOX_VE_API_TOKEN="$(tofu -chdir=10-amorcage output -raw jeton_tofu)"
export PROXMOX_TOKEN_SECRET="$(tofu -chdir=10-amorcage output -raw secret_ansible)"
export PROXMOX_URL="https://<ip pve1>:8006"
export TF_VAR_mot_de_passe_console='…'
unset PROXMOX_VE_PASSWORD
```

### Sous Windows (PowerShell) — OpenTofu seulement
```powershell
$env:PROXMOX_VE_PASSWORD = '…'                                           # couche 10 seulement
tofu -chdir=10-amorcage apply
$env:PROXMOX_VE_API_TOKEN = tofu -chdir=10-amorcage output -raw jeton_tofu
$env:PROXMOX_TOKEN_SECRET = tofu -chdir=10-amorcage output -raw secret_ansible
$env:PROXMOX_URL = "https://<ip pve1>:8006"
Remove-Item Env:PROXMOX_VE_PASSWORD
```
Ansible ne tourne pas sous Windows : les couches 00 et 50 se lancent depuis un poste Linux, macOS ou WSL.

### 4.4 Étapes 3 à 6 — Socle, image, services
```bash
tofu -chdir=20-socle apply    && tofu -chdir=20-socle plan      # "No changes"
tofu -chdir=30-image apply    && tofu -chdir=30-image plan
tofu -chdir=40-services apply && tofu -chdir=40-services plan
```
⚠️ Avant `20-socle` : le réseau des postes d'administration doit être dans `postes_admin` (IPSet `management`), sinon le pare-feu vous ferme l'API et SSH.

### 4.5 Étape 7 — Configuration des services (deux fois)
```bash
cd 50-config
ansible-inventory --graph                       # vérifier les groupes dns, web, bdd
ansible-playbook services.yml --ask-vault-pass
ansible-playbook services.yml --ask-vault-pass  # changed=0
cd ..
```

---

## 5. Détruire (ordre inverse, l'amorçage reste)

```bash
tofu -chdir=40-services destroy
cd 00-hotes && ansible-playbook nettoyage.yml && cd ..     # restes de réplication ZFS
tofu -chdir=30-image destroy
tofu -chdir=20-socle apply -var pare_feu_actif=false       # 1. couper le pare-feu
tofu -chdir=20-socle destroy                               # 2. puis détruire
```

---

## 6. Contrôle du dépôt (étape 0)

```bash
git status --short                      # vide après un tofu init
git log -p | grep -inE 'password|secret|token|BEGIN .*PRIVATE KEY' | grep -v '\$ANSIBLE_VAULT'
```
Les fichiers `.terraform.lock.hcl` créés par `tofu init` **sont à commiter** : ils figent la version du provider.

---

## 7. Équipe et rôles (tournent à chaque étape)

| Étape | Pilote OpenTofu | Rédacteurs Ansible | Contrôleur / preuves | README & note d'archi | Chronométreur |
|---|---|---|---|---|---|
| 0–1 | | | | | |
| 2–4 | | | | | |
| 5–6 | | | | | |
| 7–8 | | | | | |
