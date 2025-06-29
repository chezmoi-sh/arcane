# OpenBao Authelia SSO Configuration

> **⚠️ Documentation temporaire**\
> Ce document contient les commandes CLI manuelles pour configurer OpenBao avec Authelia SSO.\
> Ces configurations seront automatisées via Terraform/Ansible dans une version future.

## Table des matières

* [Vue d'ensemble](#vue-densemble)
* [Prérequis](#prérequis)
* [Phase 1 : Configuration OpenBao](#phase-1--configuration-openbao)
* [Phase 2 : Migration des secrets](#phase-2--migration-des-secrets)
* [Phase 3 : Configuration SSO](#phase-3--configuration-sso)
* [Troubleshooting](#troubleshooting)

## Vue d'ensemble

**Objectif** : Configurer OpenBao comme client OIDC d'Authelia et migrer le backend de secrets d'Authelia depuis Kubernetes vers OpenBao.

**Architecture cible** :

```text
┌─────────────┐    OIDC Auth    ┌──────────────┐
│   OpenBao   │ ◄────────────── │   Authelia   │
│             │  (client OIDC)  │              │
└─────────────┘                 └──────────────┘
       ▲                               ▲
       │ ESO lit secrets               │ ESO injecte secrets
       │                               │
   ┌─────────────────────────────────────────────┐
   │        External Secrets Operator            │
   │     (SEUL service accédant OpenBao)         │
   │        (Kubernetes auth method)             │
   └─────────────────────────────────────────────┘
```

**⚠️ Important** : Authelia n'accède JAMAIS directement à OpenBao. C'est ESO qui lit les secrets d'OpenBao et les injecte dans les pods Authelia.

**Topologie des secrets** ✅ **VALIDÉE** :

* Mount : `amiya.akn/` (KV v2)
* Structure optimisée (10 secrets) :
  * `amiya.akn/authelia/core` (session + storage encryption keys + hmac\_secret)
  * `amiya.akn/authelia/ldap` (ldap user/password)
  * `amiya.akn/authelia/smtp` (smtp credentials via Crossplane)
  * `amiya.akn/authelia/oidc-clients/argocd` (client ArgoCD)
  * `amiya.akn/authelia/oidc-clients/argocd-cli` (client ArgoCD CLI)
  * `amiya.akn/authelia/oidc-clients/budibase` (client Budibase)
  * `amiya.akn/authelia/oidc-clients/linkding` (client Linkding)
  * `amiya.akn/authelia/oidc-clients/mealie` (client Mealie)
  * `amiya.akn/authelia/oidc-clients/paperless-ngx` (client Paperless-NGX)
  * `amiya.akn/authelia/oidc-clients/proxmox` (client Proxmox)
* Policies : `eso-policy` (lecture seule) - ⚠️ Authelia n'accède PAS à OpenBao

## Prérequis

1. **Accès OpenBao** : Root token disponible
2. **Accès Kubernetes** : kubectl configuré pour amiya.akn
3. **Variables d'environnement** :
   ```bash
   export VAULT_ADDR="https://vault.chezmoi.sh"
   export VAULT_TOKEN="<your-root-token>"  # Export manuel
   ```

## Phase 1 : Configuration OpenBao

### Étape 1.1 : Vérification état actuel

```bash
# Vérifier l'état d'OpenBao
bao status

# Lister les auth methods existants
bao auth list

# Lister les mounts KV existants  
bao secrets list -detailed

# Lister les policies existantes
bao policy list
```

**Résultat attendu** : OpenBao opérationnel, pas d'auth method kubernetes, pas de mount amiya.akn

### Étape 1.2 : Création mount amiya.akn

```bash
# Créer le mount KV v2 pour amiya.akn
bao secrets enable -path=amiya.akn -description="dedicated kvstore for amiya.akn" kv-v2

# Vérifier la création
bao secrets list -detailed
```

**Résultat attendu** : Mount `amiya.akn/` visible avec type `kv-v2`

### Étape 1.3 : Configuration auth method Kubernetes

⚠️ **ARCHITECTURE ÉVOLUÉE** : ServiceAccount déployé automatiquement via ArgoCD

```bash
# Activer l'auth method avec path spécifique au cluster
bao auth enable -path=amiya.akn kubernetes

# Le ServiceAccount openbao-token-reviewer est maintenant déployé automatiquement
# via l'application ArgoCD openbao-agent dans le namespace openbao-agent-system

# Récupérer le CA certificate du cluster K8s
kubectl get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' > /tmp/k8s-ca.crt

# Récupérer le token du ServiceAccount déployé par ArgoCD
REVIEWER_TOKEN=$(kubectl create token openbao-token-reviewer -n openbao-agent-system)

# Configurer l'auth method avec les infos du cluster amiya.akn
bao write auth/amiya.akn/config \
  token_reviewer_jwt="$REVIEWER_TOKEN" \
  kubernetes_host="https://kubernetes.amiya.akn.chezmoi.sh:6443" \
  kubernetes_ca_cert="@/tmp/k8s-ca.crt"

# Nettoyer les fichiers temporaires
rm /tmp/k8s-ca.crt

# Vérifier la configuration
bao read auth/amiya.akn/config
```

**Résultat attendu** : Auth method kubernetes configuré avec l'endpoint du cluster

### Étape 1.4 : Création des policies

⚠️ **PATTERN MULTI-CLUSTER** : Policy spécifique par cluster (isolation + sécurité)

```bash
# Policy pour External Secrets Operator du cluster amiya.akn
cat > /tmp/amiya.akn-eso-policy.hcl << 'EOF'
# Policy for External Secrets Operator - amiya.akn cluster
# Allows reading secrets from amiya.akn mount only
path "amiya.akn/data/*" {
  capabilities = ["read"]
}

path "amiya.akn/metadata/*" {
  capabilities = ["read"]
}
EOF

# Créer la policy ESO spécifique au cluster
bao policy write amiya.akn-eso-policy /tmp/amiya.akn-eso-policy.hcl

# Nettoyer
rm /tmp/amiya.akn-eso-policy.hcl

# Lister les policies créées
bao policy list
```

**Résultat attendu** : Policy `eso-policy` visible

### Étape 1.5 : Configuration des roles Kubernetes

```bash
# Role pour External Secrets Operator du cluster amiya.akn
bao write auth/amiya.akn/role/eso \
  bound_service_account_names=kubernetes.amiya.akn.chezmoi.sh \
  bound_service_account_namespaces=kubevault-kvstore \
  policies=amiya.akn-eso-policy \
  ttl=24h

# Lister les roles créés
bao list auth/amiya.akn/role
```

**Résultat attendu** : Role `eso` configuré

***

## 📋 Pattern Multi-Cluster

### Avantages de cette architecture :

✅ **Reproductibilité** : Application ArgoCD `openbao-agent` déployable sur n'importe quel cluster\
✅ **Isolation** : Auth methods et policies séparés par cluster\
✅ **Sécurité** : Principe de moindre privilège avec accès restreint par cluster\
✅ **Maintenabilité** : Pattern standardisé dans `/defaults/kubernetes/openbao-agent/`

### Pour ajouter un nouveau cluster :

```bash
# 1. Activer l'auth method (ex: shodan.akn)
bao auth enable -path=shodan.akn kubernetes

# 2. Configurer avec le SA déployé par ArgoCD
REVIEWER_TOKEN=$(kubectl create token openbao-token-reviewer -n openbao-agent-system)
bao write auth/shodan.akn/config \
  token_reviewer_jwt="$REVIEWER_TOKEN" \
  kubernetes_host="https://kubernetes.shodan.akn.chezmoi.sh:6443" \
  kubernetes_ca_cert="@/tmp/k8s-ca.crt"

# 3. Créer la policy spécifique
bao policy write shodan.akn-eso-policy - << 'EOF'
path "shodan.akn/data/*" {
  capabilities = ["read"]
}
path "shodan.akn/metadata/*" {
  capabilities = ["read"]
}
EOF

# 4. Configurer le role
bao write auth/shodan.akn/role/eso \
  bound_service_account_names=kubernetes.shodan.akn.chezmoi.sh \
  bound_service_account_namespaces=kubevault-kvstore \
  policies=shodan.akn-eso-policy \
  ttl=24h
```

## Phase 2 : Migration des secrets

### Étape 2.1 : Création de la structure des secrets (test)

```bash
# Créer des secrets d'exemple pour valider la structure
# NOTE: Ces commandes seront adaptées avec les vraies valeurs lors de la migration

# 1. Secret core d'Authelia (session + storage + hmac)
bao kv put amiya.akn/authelia/core \
  session_encryption_key="temp-session-key" \
  storage_encryption_key="temp-storage-key" \
  hmac_secret="temp-hmac-secret"

# 2. Credentials LDAP
bao kv put amiya.akn/authelia/ldap \
  ldap_user="temp-ldap-user" \
  ldap_password="temp-ldap-password"

# 3. Credentials SMTP (seront remplis par Crossplane)
bao kv put amiya.akn/authelia/smtp \
  smtp_username="temp-smtp-user" \
  smtp_password="temp-smtp-password"

# 4. Clients OIDC (7 secrets)
bao kv put amiya.akn/authelia/oidc-clients/argocd \
  oidc_configuration="{\"temp\": \"argocd-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/argocd-cli \
  oidc_configuration="{\"temp\": \"argocd-cli-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/budibase \
  oidc_configuration="{\"temp\": \"budibase-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/linkding \
  oidc_configuration="{\"temp\": \"linkding-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/mealie \
  oidc_configuration="{\"temp\": \"mealie-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/paperless-ngx \
  oidc_configuration="{\"temp\": \"paperless-client\"}"

bao kv put amiya.akn/authelia/oidc-clients/proxmox \
  oidc_configuration="{\"temp\": \"proxmox-client\"}"

# Vérifier la structure créée
bao kv list amiya.akn/authelia/
bao kv list amiya.akn/authelia/oidc-clients/
```

**Résultat attendu** : 10 secrets créés (core, ldap, smtp, + 7 clients OIDC)

### Étape 2.2 : Extraction des secrets existants

```bash
# Extraire les vrais secrets depuis Kubernetes
# ATTENTION: Ces commandes révèlent des secrets sensibles !

# 1. Secrets core d'Authelia
kubectl get secret security-sso-authelia -n kubevault-kvstore -o jsonpath='{.data.session_encryption_key}' | base64 -d
kubectl get secret security-sso-authelia -n kubevault-kvstore -o jsonpath='{.data.storage_encryption_key}' | base64 -d
kubectl get secret security-sso-authelia -n kubevault-kvstore -o jsonpath='{.data.identity_providers_oidc_hmac_secret}' | base64 -d

# 2. Credentials LDAP  
kubectl get secret security-sso-authelia -n kubevault-kvstore -o jsonpath='{.data.authentication_backend_ldap_user}' | base64 -d
kubectl get secret security-sso-authelia -n kubevault-kvstore -o jsonpath='{.data.authentication_backend_ldap_password}' | base64 -d

# 3. Credentials SMTP
kubectl get secret security-sso-authelia-aws-ses -n kubevault-kvstore -o jsonpath='{.data.username}' | base64 -d
kubectl get secret security-sso-authelia-aws-ses -n kubevault-kvstore -o jsonpath='{.data.attribute\.ses_smtp_password_v4}' | base64 -d

# 4. Clients OIDC (7 secrets)
kubectl get secret security-sso-oidc-clients-argocd -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-argocd-cli -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-budibase -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-linkding -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-mealie -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-paperless-ngx -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
kubectl get secret security-sso-oidc-clients-proxmox -n kubevault-kvstore -o jsonpath='{.data.oidc_configuration}' | base64 -d
```

### Étape 2.3 : Migration réelle (avec vraies valeurs)

```bash
# ⚠️ REMPLACER LES VALEURS TEMPORAIRES PAR LES VRAIES VALEURS
# Utiliser les outputs de l'étape 2.2

# 1. Mettre à jour le secret core
bao kv put amiya.akn/authelia/core \
  session_encryption_key="<vraie-session-key>" \
  storage_encryption_key="<vraie-storage-key>" \
  hmac_secret="<vrai-hmac-secret>"

# 2. Mettre à jour LDAP
bao kv put amiya.akn/authelia/ldap \
  ldap_user="<vrai-ldap-user>" \
  ldap_password="<vrai-ldap-password>"

# 3. Mettre à jour SMTP  
bao kv put amiya.akn/authelia/smtp \
  smtp_username="<vrai-smtp-user>" \
  smtp_password="<vrai-smtp-password>"

# 4. Mettre à jour clients OIDC
bao kv put amiya.akn/authelia/oidc-clients/argocd \
  oidc_configuration="<vraie-config-argocd>"

# ... répéter pour les 6 autres clients
```

### Étape 2.4 : Création SecretStore OpenBao

```yaml
# Nouveau SecretStore pour remplacer kubevault
# À créer dans kubevault-kvstore namespace
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: openbao-authelia
  namespace: kubevault-kvstore
spec:
  provider:
    vault:
      server: "https://vault.chezmoi.sh"
      path: "amiya.akn"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso"
          serviceAccountRef:
            name: "kubernetes.amiya.akn.chezmoi.sh"
```

## Phase 3 : Configuration SSO

> **⚠️ À compléter après Phase 2**\
> Configuration d'OpenBao comme client OIDC d'Authelia

## Troubleshooting

### Erreurs communes

**Erreur : "permission denied"**

```bash
# Vérifier que le token root est exporté
echo $VAULT_TOKEN
```

**Erreur : auth method kubernetes**

```bash
# Vérifier la connectivité au cluster K8s
kubectl cluster-info
```

**Erreur : ServiceAccount introuvable**

```bash
# Vérifier l'existence du SA ESO
kubectl get serviceaccount kubernetes.amiya.akn.chezmoi.sh -n kubevault-kvstore
```

### Commandes de diagnostic

```bash
# État détaillé OpenBao
bao status -detailed

# Logs auth kubernetes
bao read sys/internal/counters/activity

# Test auth ESO
bao write auth/kubernetes/login \
  role=eso \
  jwt="$(kubectl get secret -n kubevault-kvstore \
    $(kubectl get serviceaccount kubernetes.amiya.akn.chezmoi.sh -n kubevault-kvstore -o jsonpath='{.secrets[0].name}') \
    -o jsonpath='{.data.token}' | base64 -d)"
```

## Notes d'implémentation

**Sécurité** :

* Root token utilisé uniquement pour setup initial
* Policies suivent le principe du moindre privilège
* Fichiers temporaires automatiquement nettoyés

**Future as-code** :

* Terraform provider OpenBao pour automation
* Policies versionnées dans Git
* CI/CD pour déploiement des configurations

**Rollback** :

* Plan de retour vers backend Kubernetes disponible
* Root token conservé en backup
* Tests avant suppression anciens secrets

***

*Documentation générée le 2025-01-28 - Version temporaire avant as-code*
