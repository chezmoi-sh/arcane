# OpenBao Configuration Standards

## 🎯 Objectif
Définir des standards de configuration OpenBao adaptés au contexte homelab/solo : conventions de path, naming, structure des secrets et patterns d'accès.

## 🧠 Contexte & Réflexions
- **Contexte spécifique** : Homelab, utilisation solo, pas de collaboration multi-équipes
- **Simplification possible** : Pas besoin de conventions complexes pour multi-tenancy
- **Focus pragmatique** : Standards simples mais évolutifs pour une utilisation personnelle
- **Question initiale** : Commencer par path/naming puis étendre vers standard global
- **Architecture existante** : Build sur ADR-002 (mount topology déjà décidée)

### Retours utilisateur sur les path conventions :
- **Organisation préférée** : Par application (secrets liés à une app spécifique)
- **Problème dépendances croisées** : SSO entre ArgoCD/Authelia casse la séparation par mount
- **Solution retenue** : Utiliser `/shared/` pour les dépendances croisées
- **Structure finale** : `/{mount}/application/service/type` (ex: `/amiya-akn/argocd/postgres/admin`)

### Clarifications sur Crossplane et sécurité :
- **Crossplane access problem** : Multi-KV necessaire casse le zero trust (full RW sur tous les mounts)
- **Alternative demandée** : Solution simple sans casser la séparation des mounts
- **Principle established** : Pas de cross-mount access, utiliser `/shared/` pour les cas spéciaux

### Questions techniques importantes :
- **Secret management** : Les configs sensibles (JWT, certificates) sont considérées comme des secrets ✅
- **Crossplane secrets** : Clés API générées par Crossplane à stocker dans le mount de l'app qui l'utilise
- **Secret moving** : Question sur mécanisme d'alias ou déplacement de secrets
- **Discovery** : Pas de besoin identifié, l'UI suffit

### Derniers retours utilisateur :
- **Owner-based rejeté** : Casse la séparation des mount points par cluster
- **Shared mount validé** : Plus approprié pour les dépendances croisées
- **Organisation shared** : Besoin de définir comment organiser les secrets dans `/shared/`
- **Cross-mount concerns** : Pas chaud pour donner droits aux clusters distants
- **Secret movement** : Question sur mécanismes d'alias/déplacement
- **Path structure confirmed** : `/amiya-akn/{app}/{service}/{type}` validé

### Feedback sur l'organisation `/shared/` :
- **Structure préférée** : `/shared/sso/oidc-client/argocd` avec metadata `owner: amiya.akn/authelia`
- **Metadata owner** : Permet de tracer le créateur sans polluer le path
- **JWT signing** : Reste privé (pas dans shared) car spécifique à une app
- **Certificats PKI** : Question sur génération via OpenBao PKI engine pour cert-manager
- **Organisation par service** : Préfère par fournisseur/service plutôt que par "owner"
  - `/aws/iam/APP` vs `/crossplane/aws-iam/`
  - Granularité fine : `/aws/s3/bucket-name/APP` pour zero trust
  - Alternative simple : `/aws/iam/APP` + metadata `x-aws-services=s3,ses`
- **Crossplane mount** : Observation que mount dédié = similaire au shared mount

### Solutions Crossplane rejetées :
- **Copy/distribution** : Pas d'action en dehors d'OpenBao
- **ExternalSecret reference** : Casse le silotage des multi-mount
- **Mount dédié** : Finalement similaire au shared mount

### Validation finale de l'organisation shared :
- **Organisation validée** : Structure par service/fournisseur approuvée
- **Question metadata** : Clarification demandée sur `x-apps` dans les exemples
- **PKI clarification** : Pas CA interne, mais utiliser Let's Encrypt avec OpenBao comme proxy pour dispatch automatique
- **AWS structure** : Confirmation `/aws/iam/APP` + metadata préféré car une app = plusieurs services AWS
- **Rationale** : Éviter multiplication des access/secret keys par service AWS

### Clarifications et recherches ACME :
- **Question x-apps metadata** : Convention pour indiquer quelles apps utilisent un secret
- **Recherche ACME/PKI** : Vérification si OpenBao peut faire proxy ACME vers Let's Encrypt
  - **Résultat** : OpenBao ne semble pas supporter ACME proxy (contrairement à Vault Enterprise)
  - **Solution alternative** : Cert-Manager génère wildcard → ESO stocke dans `/shared/certificates/*.chezmoi.sh`
- **Validation shared mount** : Structure par service/fournisseur validée et appréciée

### Correction structure shared mount :
- **Feedback** : Organisation par fournisseur pas optimale
- **Préférence** : Grouper par **fonction/type** plutôt que par fournisseur
- **3 grandes catégories** :
  1. **sso** : Authentification partagée
  2. **certificates** : Certificats partagés  
  3. **third-parties** : Services externes (cloud providers, etc.)

### Finalisation metadata extensions :
- **Extensions rejetées** : Trop complexes pour contexte homelab/solo
  - `x-environment`, `x-criticality` : Pas de multi-env
  - `x-rotation-frequency`, `x-last-rotated`, `x-expires-at` : Gestion manuelle suffisante
  - `x-health-check`, `x-backup-strategy` : Overhead inutile
- **Extensions retenues** : Utiles et pragmatiques pour le contexte

## 📝 Historique des changements
- [15:20] Création du document de session et analyse des besoins
- [15:25] Début des suggestions path/naming pour contexte homelab
- [15:40] Feedback utilisateur sur organisation par app + questions dépendances croisées
- [15:50] Clarifications sur Crossplane, zero trust, et metadata requirements
- [16:00] Questions sur secrets vs config, placement Crossplane, discovery
- [16:10] Validation shared mount, questions sur organisation et secret movement

## 📊 Avancement
- Path conventions per-cluster : ✅ 100%
- Shared mount organization : ✅ 100%
- Metadata schema : ✅ 100%
- PKI/Certificate strategy : ✅ 100%
- AWS/Cloud providers paths : ✅ 100%
- **ADR-003 Creation** : ✅ 100%

## 🔄 Prochaines étapes
- [x] Définir structure path per-cluster
- [x] Organiser shared mount par service/fournisseur  
- [x] Résoudre stratégie certificats (CM + ESO)
- [x] Récapitulatif complet de la discussion
- [x] Extensions metadata recommandées
- [x] **Création ADR-003 final**

## ✅ Objectif Atteint
**ADR-003 "OpenBao Path and Naming Conventions" créé avec succès !**

Le document couvre :
- Structure path application-first + function-based shared
- Metadata schema pragmatique avec **exemples flexibles** (pas de contraintes strictes)
- Toutes les alternatives considérées et rejetées
- Stratégie certificats et dépendances croisées
- Références et justifications complètes

### Améliorations finales :
- **Metadata flexible** : Valeurs présentées comme exemples plutôt que contraintes strictes
- **Évolutivité** : Permet d'ajouter de nouvelles sources/méthodes sans casser le standard
- **Pragmatisme** : Garde la flexibilité tout en fournissant des guidelines claires
- **Terminologie finale** : "origin" préféré à "source" pour la sémantique (d'où viennent les secrets)

Format épuré inspiré de l'ADR-002 nettoyé, focalisé sur la décision architecturale.

## ⚠️ Points d'attention
- **ACME/PKI limitation** : OpenBao ne fait pas proxy ACME, utiliser CM + ESO
- **AWS organization** : `/aws/iam/APP` + metadata préféré vs granularité fine
- **Zero Trust** : Structure par service maintient l'isolation 