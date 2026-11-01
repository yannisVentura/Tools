# Spécifications – Activation Windows

> **Statut : brouillon à valider.** Aucune exigence n'est encore implémentée.

## Contexte

Remplaçant moderne de `Windows/Obsolete/Windows_7/changeKey.PS1` (2017). Usage : consulter l'état d'activation d'un poste Windows 10/11 et, si besoin, installer une clé de produit puis activer Windows, notamment après une réinstallation chez un proche.

Recommandations Microsoft retenues (audit `microsoft-advisor`) :
- passer par l'API WMI/CIM du service de licences (`SoftwareLicensingService`, `SoftwareLicensingProduct`) plutôt que `slmgr.vbs`, qui affiche des pop-ups sans code retour exploitable ;
- ne jamais afficher ni journaliser la clé complète ;
- privilégier la **licence numérique** : après une réinstallation de la même édition, Windows s'active seul en ligne, sans clé.

Abréviations : `GWA` = `Get-WindowsActivation.ps1`, `SWA` = `Set-WindowsActivation.ps1`.

## Exigences fonctionnelles

### REQ-ACT-001 – Consultation de l'état d'activation
`GWA` doit afficher, pour le produit Windows installé : l'édition, l'état d'activation en clair, le canal de licence (Retail, OEM, Volume…), les 5 derniers caractères de la clé installée et le délai de grâce restant en jours.
- Vérification : test.
```gherkin
Étant donné un poste Windows 11 activé par licence numérique
Quand GWA est exécuté
Alors il affiche l'état "Activé", l'édition et les 5 derniers caractères de la clé
```

### REQ-ACT-002 – Consultation sans droits administrateur
`GWA` doit fonctionner sans droits administrateur et ne rien modifier sur le poste.
- Vérification : test.

### REQ-ACT-003 – Sortie exploitable
`GWA` doit retourner un objet PowerShell (propriétés `Edition`, `Status`, `StatusCode`, `Channel`, `PartialKey`, `GraceDays`) utilisable dans le pipeline.
- Vérification : test.
```gherkin
Étant donné un poste activé
Quand on exécute (GWA).StatusCode
Alors la valeur vaut 1
```

### REQ-ACT-004 – Modes exclusifs
`SWA` doit proposer quatre modes mutuellement exclusifs :
- `-ProductKey <clé>` : installer la clé fournie puis activer ;
- `-PromptForKey` : demander la clé en saisie masquée (REQ-ACT-017), puis l'installer et activer ;
- `-UseFirmwareKey` : installer la clé OEM inscrite dans le firmware (BIOS/UEFI) puis activer ;
- `-ActivateOnly` : activer la clé déjà installée (cas de la licence numérique).
- Vérification : test.

### REQ-ACT-005 – Validation du format de la clé
Si la clé fournie ne respecte pas le format `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (lettres majuscules et chiffres), alors `SWA` doit refuser de s'exécuter avant toute modification.
- Vérification : test.

### REQ-ACT-006 – Clé du firmware absente
Si `-UseFirmwareKey` est utilisé et qu'aucune clé n'est inscrite dans le firmware, alors `SWA` doit journaliser `ERREUR aucune clé dans le firmware` et s'arrêter sans modification.
- Vérification : test (poste non OEM ou VM).

### REQ-ACT-007 – Installation de la clé
`SWA` doit installer la clé par `SoftwareLicensingService.InstallProductKey`, puis rafraîchir l'état des licences (`RefreshLicenseStatus`).
- Vérification : inspection et test.

### REQ-ACT-008 – Activation conditionnelle
`SWA` ne doit lancer l'activation en ligne (`SoftwareLicensingProduct.Activate`) que si l'installation de la clé a réussi (ou en mode `-ActivateOnly`).
- Vérification : test.
```gherkin
Étant donné une clé refusée par le service de licences
Quand SWA est exécuté avec -ProductKey
Alors la ligne "Installation clé" est en ERREUR
Et aucune ligne "Activation" n'est écrite
```

### REQ-ACT-009 – Effacement de la clé du registre
Après une installation de clé réussie, `SWA` doit effacer la clé du registre (`ClearProductKeyFromRegistry`, équivalent de `slmgr /cpky`), recommandation Microsoft contre le vol de clé.
- Vérification : inspection.

### REQ-ACT-010 – Vérification finale
À la fin, `SWA` doit relire l'état d'activation et journaliser `Vérification | OK Activé` ou `ERREUR <état>`.
- Vérification : test.

### REQ-ACT-011 – Journal
`SWA` doit écrire une ligne par étape dans `%ProgramData%\WindowsActivation\Activation.log`, au même format que l'outil de maintenance : `dd/MM/yyyy HH:mm:ss | <étape sur 20 caractères> | OK | ERREUR <motif> : code <décimal> (0x<hexadécimal>)`, plafonné à 500 lignes.
- Vérification : test.

### REQ-ACT-012 – Code de sortie
`SWA` doit se terminer avec `0` si Windows est activé à la fin, sinon `1`.
- Vérification : test.

## Exigences non fonctionnelles

### REQ-ACT-013 – Confidentialité de la clé
La clé complète ne doit apparaître ni dans le journal, ni à l'écran, ni dans les messages d'erreur : seuls ses 5 derniers caractères peuvent être affichés.
- Vérification : inspection et test (recherche de la clé dans le journal après exécution).

### REQ-ACT-014 – Droits et confirmation
`SWA` doit exiger les droits administrateur (`#Requires -RunAsAdministrator`) et prendre en charge `-WhatIf` / `-Confirm`.
- Vérification : test.

### REQ-ACT-015 – Aucune pop-up
Aucun des deux scripts ne doit afficher de fenêtre ou de pop-up (pas de `slmgr.vbs`, pas de `WScript.Shell`).
- Vérification : inspection.

### REQ-ACT-016 – Compatibilité
Les scripts doivent fonctionner sur Windows 10 et 11, sous Windows PowerShell 5.1, quelle que soit la langue du système, et être encodés en UTF-8 avec BOM.
- Vérification : test sur VM Windows 10 et poste Windows 11.

### REQ-ACT-017 – Saisie masquée de la clé
Où `-PromptForKey` est utilisé à la place de `-ProductKey`, `SWA` doit demander la clé en saisie masquée (`Read-Host -AsSecureString`), afin qu'elle n'apparaisse ni à l'écran ni dans l'historique de la console. La clé saisie doit respecter REQ-ACT-005.
- Vérification : test.
```gherkin
Étant donné SWA lancé avec -PromptForKey
Quand l'utilisateur saisit sa clé
Alors seuls des astérisques s'affichent
Et la clé n'apparaît pas dans Get-History
```

### REQ-ACT-018 – Redémarrage optionnel
Après une installation de clé réussie, `SWA` doit journaliser `Redémarrage | recommandé` ; où `-Restart` est présent, il doit redémarrer le poste à la fin de l'exécution (après confirmation, sauf `-Confirm:$false`).
- Vérification : test.

## À confirmer

1. **Clé du firmware** : la propriété `OA3xOriginalProductKey` n'est documentée que par la communauté Microsoft Learn (pas sur une page de référence) ; comportement à vérifier sur un PC OEM.

## Matrice de traçabilité

| Exigence | Implémentation | Statut |
|---|---|---|
| REQ-ACT-001 à 018 | – | Non implémentée |
