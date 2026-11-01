# Blocage de la mise à niveau Windows 11

Maintient un poste Windows 10 sur Windows 10 : plus de proposition de mise à niveau vers Windows 11 ni d'évaluation de compatibilité lancée en arrière-plan.

| Fichier | Rôle |
|---|---|
| `Block-Windows11Upgrade.ps1` | Applique le blocage, ou l'annule avec `-Revert`. |

## Ce que fait le script

1. **Stratégie Windows Update** (méthode documentée par Microsoft) sous `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` :

   | Valeur | Type | Donnée |
   |---|---|---|
   | `TargetReleaseVersion` | DWORD | `1` |
   | `ProductVersion` | Chaîne | `Windows 10` |
   | `TargetReleaseVersionInfo` | Chaîne | `22H2` |

   Windows Update ne propose plus Windows 11 et reste sur Windows 10 22H2. Les mises à jour de qualité (sécurité) restent installées. Fonctionne aussi sur l'édition Famille.
2. **Tâches planifiées désactivées** (une tâche absente sur le poste est ignorée) :
   - `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser` et `… Appraiser Exp` : l'évaluateur de compatibilité (processus `CompatTelRunner.exe`) ;
   - `\Microsoft\Windows\Application Experience\ProgramDataUpdater` ;
   - `\Microsoft\Windows\UpdateOrchestrator\UpdateAssistant*` : relance de l'Assistant Mise à jour.
3. **Arrêt de `CompatTelRunner.exe`** s'il tourne au moment de l'exécution.

## Utilisation

Dans une console PowerShell **lancée en administrateur**, depuis ce dossier :

```powershell
.\Block-Windows11Upgrade.ps1 -WhatIf   # simulation : affiche ce qui serait fait
.\Block-Windows11Upgrade.ps1           # applique le blocage
.\Block-Windows11Upgrade.ps1 -Revert   # annule le blocage
```

Si l'exécution des scripts est bloquée :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Block-Windows11Upgrade.ps1
```

Chaque action affiche une ligne `OK`, `IGNORÉ` ou `ERREUR`. Code de sortie : `0` si tout a réussi, `1` sinon. Le script refuse de s'exécuter sur un poste déjà sous Windows 11.

## Vérification

- `Paramètres > Mise à jour et sécurité > Windows Update` affiche « *Certains paramètres sont gérés par votre organisation* » et ne propose plus Windows 11.
- `Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\'` : les tâches Appraiser sont `Disabled`.

## Limites

- **Windows 10 n'est plus pris en charge** depuis le 14 octobre 2025 ; le programme ESU grand public s'est arrêté le 13 octobre 2026. Le poste ne reçoit plus de correctifs de sécurité. Si le matériel est compatible, la mise à niveau vers Windows 11 reste la recommandation de Microsoft : ce blocage est une solution d'attente.
- Certaines tâches de `UpdateOrchestrator` sont protégées et peuvent être refusées même à un administrateur (ligne `ERREUR`). La stratégie Windows Update suffit à bloquer la mise à niveau proposée par Windows Update.
- Une mise à jour cumulative de Windows peut réactiver une tâche planifiée : relancer le script si l'évaluation réapparaît.
- Une mise à niveau lancée volontairement (Assistant d'installation Windows 11, support d'installation) n'est pas bloquée.
