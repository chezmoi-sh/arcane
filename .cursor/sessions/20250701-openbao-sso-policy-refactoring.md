# Refactorisation des politiques SSO OpenBao

## 🎯 Objectif
Refactoriser le mécanisme de gestion des secrets SSO pour améliorer la sécurité en supprimant le partage global via `/shared/sso/*` et implémenter un modèle où le SSO est configuré au niveau de l'application avec une politique Authelia spécifique.

## 🧠 Contexte & Réflexions
- Le mécanisme actuel partage les informations SSO via `/shared/sso/*`, ce qui pose des problèmes de sécurité
- L'authentification est un sujet critique et le partage global des données d'authentification représente un risque
- Une approche plus sécurisée consisterait à:
  - Déplacer la configuration SSO dans le cluster de chaque application
  - Créer une politique Authelia qui peut lire uniquement les secrets spécifiques de type `/{project}/+/sso/oidc-client`
- Cette approche respecte davantage le principe de moindre privilège
- Impact sur les ADRs existants: 
  - ADR-003: Modification de la structure des chemins pour les secrets SSO
  - ADR-004: Ajustement des politiques pour refléter le nouveau modèle d'accès

## 📝 Historique des changements
- [10:00] Création de la session pour documenter le travail à faire
- [10:10] Analyse des ADRs existants (003 et 004) concernant les conventions de nommage et politiques

## ⚠️ Points d'attention
- Migration des secrets existants: planifier une stratégie de migration sans interruption de service
- Cohérence avec les principes Zero Trust établis dans les ADRs précédents
- Assurer que tous les services qui dépendent actuellement de `/shared/sso/*` puissent fonctionner avec la nouvelle structure

## 🔄 Prochaines étapes
- [ ] Modifier ADR-003 pour redéfinir la structure des chemins SSO
- [ ] Modifier ADR-004 pour définir une nouvelle politique Authelia spécifique aux clients OIDC
- [ ] Concevoir un plan de migration pour les secrets SSO existants
- [ ] Tester le nouveau modèle avec une application pilote

## 📊 Modifications prévues

### ADR-003: Modifications prévues
- Supprimer ou redéfinir la section `/shared/sso/*` 
- Ajouter une structure pour les secrets SSO au niveau de l'application: `/{project}/{app}/sso/oidc-client/*`
- Mettre à jour les exemples et les patterns recommandés

### ADR-004: Modifications prévues
- Créer une nouvelle politique pour Authelia: `{project-name}-sso-policy`
- Définir le scope: `/{project}/+/sso/oidc-client/*` (pour permettre à Authelia de lire les secrets client OIDC de toutes les applications)
- Ajuster la matrice des politiques pour inclure cette nouvelle politique
- Mettre à jour les rationales et les conséquences 