# Configuration OpenBao avec SSO Authelia

## 🎯 Objectif
Configurer OpenBao comme client OIDC d'Authelia et migrer le backend de secrets d'Authelia depuis Kubernetes vers OpenBao

## 🧠 Contexte & Réflexions
- **Architecture actuelle** : OpenBao fonctionnel, Authelia fonctionne avec OIDC pour plusieurs clients (ArgoCD, Budibase, etc.)
- **Backend actuel Authelia** : ESO utilise ClusterSecretStore `kubevault` (backend Kubernetes)
- **Objectif** : OpenBao devient client OIDC d'Authelia + migration secrets Authelia vers OpenBao
- **Scope** : Limité à Authelia pour le moment

- **Point technique critique** : Circularité résolue ✅
  * OpenBao utilise ESO pour sa config (openbao-config.externalsecret.yaml) 
  * ESO utilise des secrets locaux K8s pour la config OpenBao (pas OpenBao lui-même)
  * → Pas de circularité, ESO peut utiliser OpenBao pour les secrets applicatifs

- **Topologie finale** : Structure mount simplifiée `amiya.akn/` 
  * Secrets Authelia → `amiya.akn/authelia/core` + `amiya.akn/authelia/oidc-clients/`
  * Organisation directe par app (plus simple que security/sso)
  * Auth method Kubernetes à configurer

- **ADR-002 & ADR-003 validées** ✅
  * Stratégie : mounts multiples par projet + mount `shared/`
  * Conventions de chemins Application-First + Function-Based pour le mount shared
  * Les secrets Authelia respecteront donc `/amiya.akn/authelia/{category}/{secret}` et `/shared/sso/oidc-client/{app}`

- **Configuration OpenBao** : Auth method Kubernetes + policies
  * Méthode : Configuration manuelle d'abord puis documentation
  * Root token disponible pour accès initial

## 📝 Historique des changements
- [15:30] Analyse de l'architecture existante OpenBao + Authelia
- [15:45] Identification circularité potentielle et stratégie de résolution
- [15:50] Analyse complète des secrets Authelia existants :
  * `security-sso-authelia` (session/storage encryption keys, LDAP auth)
  * `security-sso-authelia-aws-ses` (SMTP/SES credentials via Crossplane)
  * `security-sso-oidc-clients-*` (7 clients OIDC : ArgoCD, Budibase, etc.)
  * JWT/TLS certificates pour OIDC signing
- [15:55] Confirmation stratégie anti-circularité : garder config OpenBao sur backend K8s
- [16:00] Validation accès OpenBao : CLI `bao` + URL locale `vault.chezmoi.sh`
- [16:05] Préparation commandes CLI pour auth method Kubernetes + policies ESO
- [16:10] Création documentation complète dans `projects/amiya.akn/docs/openbao/OPENBAO_AUTHELIA_SETUP.md`
- [16:20] **CORRECTION** : Clarification structure secrets + suppression authelia-policy inutile
  * Authelia n'accède JAMAIS à OpenBao (c'est ESO qui lit pour Authelia)
  * Structure: `amiya.akn/authelia/{session,ldap,oidc,smtp,oidc-clients/*}`
  * Seule policy nécessaire : `eso-policy`
- [16:25] **RÉVISION STRUCTURE** : Analyse des secrets Authelia existants pour optimiser l'organisation
  * 4 ExternalSecrets actuels : authelia, authelia-ldap, authelia-oidc, authelia-smtp
  * Proposition : objets individuels plutôt que dossiers hiérarchiques
- [16:30] **STRUCTURE FINALE VALIDÉE** :
  * `amiya.akn/authelia/core` (session + storage + hmac_secret)
  * `amiya.akn/authelia/ldap` (ldap credentials)
  * `amiya.akn/authelia/smtp` (smtp credentials via Crossplane)
  * `amiya.akn/authelia/oidc-clients/{argocd,budibase,etc}` (7 clients séparés)
- [16:35] **DOCUMENTATION COMPLÉTÉE** : Phase 1 + Phase 2 entièrement documentées
  * Structure secrets avec commandes CLI complètes
  * Migration progressive : test → extraction → migration réelle
  * SecretStore OpenBao configuré pour remplacer backend K8s
- [16:40] **CORRECTION CLI** : Toutes les commandes corrigées pour utiliser `bao` au lieu de `openbao`
- [16:45] **PROBLÈME DÉTECTÉ** : Étape 1.3 utilise le token ESO comme token_reviewer_jwt (mauvaise pratique)
- [16:50] **CORRECTION APPLIQUÉE** : Option A ServiceAccount dédié choisi pour reproductibilité multi-cluster
- [16:52] **OPTIMISATION** : Commande mount KV optimisée (enable + description en une fois)
- [17:00] **ARCHITECTURE ÉVOLUÉE** : 
  * Ajout application ArgoCD pour déployer le SA token_reviewer sur chaque cluster
  * Auth methods séparés par cluster (auth -path=amiya.akn kubernetes)
  * Pattern `/defaults/kubernetes/openbao-agent/` pour les ressources K8s
- [17:05] **FICHIERS CRÉÉS** :
  * `defaults/kubernetes/openbao-agent/kustomize/kustomization.yaml`
  * `defaults/kubernetes/openbao-agent/kustomize/serviceaccount.yaml`
  * `defaults/kubernetes/openbao-agent/kustomize/rbac.yaml`
  * `projects/amiya.akn/src/apps/*argocd/shoot.apps/openbao-agent.application.yaml`
- [17:10] **PATTERN FINALISÉ** : Pattern reproductible pour tous futurs clusters avec isolation sécurisée
- [17:15] **ADR FORMALISÉES** : Adoption officielle des ADR-002 (topologie) et ADR-003 (naming conventions)
- [17:20] **PROCÉDURE TOKEN CURSOR** : Définition d'une procédure standard pour générer un token admin éphémère (TTL 30 min, display-name « cursor ») destiné aux tests automatisés
- [17:35] **PHASE 1.1 TERMINÉE** : Vérification état actuel exécutée, état conforme
- [17:40] **PHASE 1.2 TERMINÉE** : Mount `amiya.akn/` KV v2 créé et validé
- [17:55] **NOUVELLE TÂCHE** : définir conventions de nommage des policies Vault (réf. [article de Sunil Tailor](https://sunil-tailor.medium.com/scaling-hashicorp-vault-policy-sprawl-part-1-1b0f599b6eae)) et les documenter dans ADR-003

## ⚠️ Points d'attention
- **Circularité critique** : Ne pas migrer la config OpenBao vers OpenBao lui-même
- **Backup** : Root token OpenBao disponible en cas de perte d'accès Authelia
- **Test** : Vérifier l'accès Authelia avant de supprimer les anciens secrets
- **Rollback** : Plan de retour sur backend Kubernetes si problème

## 🔄 Prochaines étapes

### ✅ Phase 0 : Analyse et préparation
- [x] Clarifier la "circularité" → ✅ Résolue, pas de circularité
- [x] Analyser topologie → ✅ Mount `amiya.akn/` + organisation par app
- [x] Préparer commandes CLI complètes
- [x] Créer documentation temporaire → ✅ `docs/OPENBAO_AUTHELIA_SETUP.md`

### 🚀 Phase 1 : Configuration OpenBao (PRÊT - ARCHITECTURE ÉVOLUÉE)
- [x] **1.1** : Exécuter commandes vérification état actuel
- [x] **1.2** : Créer mount `amiya.akn/` KV v2
- [ ] **1.3** : Configurer auth method Kubernetes ✅ **PATH SPÉCIFIQUE + SA ARGOCD**
  * `bao auth enable -path=amiya.akn kubernetes`
  * ServiceAccount `openbao-token-reviewer` déployé via ArgoCD
- [ ] **1.4** : Créer policy `amiya.akn-eso-policy` (spécifique par cluster)
- [ ] **1.5** : Configurer role `eso` pour ESO sur auth path `amiya.akn`

### 📋 Phase 2 : Migration secrets Authelia (PRÊT)
- [ ] **2.1** : Créer structure secrets de test (10 secrets total)
- [ ] **2.2** : Extraire secrets existants depuis K8s (commandes détaillées)
- [ ] **2.3** : Migration réelle avec vraies valeurs
- [ ] **2.4** : Créer SecretStore OpenBao pour ESO

### ⏳ Phase 3 : Configuration SSO OpenBao ↔ Authelia  
- [ ] **3.1** : Configurer OpenBao comme client OIDC d'Authelia
- [ ] **3.2** : Tester l'authentification OpenBao via Authelia
- [ ] **3.3** : Validation complète de l'intégration

### 📝 Documentation et Gouvernance
- [ ] **D.1** : Ajouter section « Vault Policy Naming Conventions » à `docs/decisions/003-openbao-path-naming-conventions.md` (inspirée de l'article Sunil Tailor)

## 📜 Commandes CLI exécutées
*Section pour tracker toutes les commandes OpenBao CLI avec root token*

### Phase 1 : Configuration auth method Kubernetes

**Étape 1 : Vérification état actuel**
```bash
# Export manual du token root (non tracké)
export VAULT_ADDR="https://vault.chezmoi.sh"

# Vérifier l'état d'OpenBao
bao status

# Lister les auth methods existants
bao auth list

# Lister les mounts KV existants  
bao secrets list -detailed

# Lister les policies existantes
bao policy list
```

**Étape 2 : Création mount amiya.akn**
```bash
# Créer le mount KV v2 pour amiya.akn
bao secrets enable -path=amiya.akn kv-v2

# Configurer les options du mount (versions, TTL)
bao secrets tune -max-versions=10 amiya.akn/

# Vérifier la création
bao secrets list -detailed
```

**Étape 3 : Configuration auth method Kubernetes**
```bash
# Activer l'auth method Kubernetes
bao auth enable kubernetes

# Récupérer le CA certificate du cluster K8s (depuis ta machine locale)
kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' > /tmp/k8s-ca.crt

# Récupérer le token du ServiceAccount ESO (temporaire pour config)
kubectl get secret -n kubevault-kvstore \
  $(kubectl get serviceaccount kubernetes.amiya.akn.chezmoi.sh -n kubevault-kvstore -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.token}' | base64 -d > /tmp/k8s-token

# Configurer l'auth method avec les infos du cluster amiya.akn
bao write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /tmp/k8s-token)" \
  kubernetes_host="https://kubernetes.amiya.akn.chezmoi.sh:6443" \
  kubernetes_ca_cert="$(cat /tmp/k8s-ca.crt)"

# Nettoyer les fichiers temporaires sensibles
rm /tmp/k8s-token /tmp/k8s-ca.crt

# Vérifier la configuration
bao read auth/kubernetes/config
```

**Étape 4 : Création des policies ESO**
```bash
# Policy pour External Secrets Operator - lecture des secrets
cat > /tmp/eso-policy.hcl << 'EOF'
# Policy for External Secrets Operator
# Allows reading secrets from amiya.akn mount
path "amiya.akn/data/*" {
  capabilities = ["read"]
}

path "amiya.akn/metadata/*" {
  capabilities = ["read"]
}
EOF

# Créer la policy ESO
bao policy write eso-policy /tmp/eso-policy.hcl

# Nettoyer
rm /tmp/eso-policy.hcl

# Lister les policies créées
bao policy list
```

**Étape 5 : Configuration des roles Kubernetes**
```bash
# Role pour External Secrets Operator (seul service à accéder OpenBao)
bao write auth/kubernetes/role/eso \
  bound_service_account_names=kubernetes.amiya.akn.chezmoi.sh \
  bound_service_account_namespaces=kubevault-kvstore \
  policies=eso-policy \
  ttl=24h

# Lister les roles créés
bao list auth/kubernetes/role
```

### 🏗️ Phase 0bis : Déploiement Application ArgoCD (NOUVEAU)
- [x] **0.1** : Créer application `openbao-agent.application.yaml` 
- [x] **0.2** : Créer ressources par défaut dans `/defaults/kubernetes/openbao-agent/`
- [x] **0.3** : Configurer ServiceAccount + RBAC pour token reviewer
- [ ] **0.4** : Commit + Push pour déclencher le déploiement ArgoCD
- [ ] **0.5** : Vérifier déploiement du namespace `openbao-agent-system`

## 🔗 Références
- **Documentation CLI** : `projects/amiya.akn/docs/openbao/OPENBAO_AUTHELIA_SETUP.md`
- **OpenBao Kubernetes Auth** : https://openbao.org/docs/auth/kubernetes/
- ADR-002: OpenBao Secrets Mount Topology
- **Policy Sprawl & Naming Conventions** : https://sunil-tailor.medium.com/scaling-hashicorp-vault-policy-sprawl-part-1-1b0f599b6eae
- Configuration OpenBao actuelle: `projects/amiya.akn/src/apps/*vault/`
- Configuration Authelia actuelle: `projects/amiya.akn/src/apps/*sso/authelia/`

## 🎯 Architecture Multi-Cluster Finalisée

### Pattern reproductible :
1. **ArgoCD Application** : `openbao-agent` déploie automatiquement le SA token_reviewer
2. **Auth Methods isolés** : `auth -path=<cluster> kubernetes` pour chaque cluster
3. **Policies séparées** : `<cluster>-eso-policy` pour isolation sécurisée
4. **Reproductibilité** : Copy-paste du pattern pour nouveaux clusters

### Avantages obtenus :
- ✅ **Sécurité** : Isolation par cluster, principe de moindre privilège
- ✅ **Simplicité** : SA géré par ArgoCD, plus de configuration manuelle  
- ✅ **Maintenabilité** : Pattern standardisé dans `/defaults/`
- ✅ **Reproductibilité** : Facilement applicable à shodan.akn, maison, etc. 
