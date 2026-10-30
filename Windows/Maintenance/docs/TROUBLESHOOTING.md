# Dépannage – Maintenance Windows

Format et emplacement du journal : [../README.md#journal](../README.md#journal).

## Lire le journal

```powershell
Get-Content "$env:ProgramData\SystemMaintenance\Maintenance.log" -Tail 20
```

Chaque exécution ajoute une ligne par commande. `OK` : rien à faire. `ERREUR` : voir le tableau ci-dessous.

## Résultats possibles

| Ligne du journal | Signification | Action |
|---|---|---|
| `sfc /scannow \| ERREUR code N` | SFC a détecté un problème ou n'a pas pu terminer. | Lire `%WINDIR%\Logs\CBS\CBS.log`, puis réinstaller avec `-WithDism` pour réparer l'image avant SFC. |
| `DISM /RestoreHealth \| ERREUR code N` | La réparation de l'image a échoué. | Lire `%WINDIR%\Logs\DISM\dism.log`. |
| `winget upgrade \| ERREUR <Id> <version> -> <version> : code N (0x...)` | La mise à jour de cette application a échoué ; les autres ont été traitées. Ex. `0x80190194` : fichier introuvable chez l'éditeur (404), se corrige quand le catalogue winget est mis à jour. Mise à jour bloquée (technologie d'installation différente) : désinstaller puis réinstaller l'application une fois. | Rechercher le code hexadécimal dans la [liste des codes retour winget](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md). |
| `winget upgrade \| ERREUR ... : code -1073741515 (0xC0000135)` | DLL introuvable : runtime Visual C++ manquant (voir la ligne `Installation VC++` juste avant, si présente). | Relancer l'installeur en administrateur (voir ci-dessous). |
| `winget upgrade \| ERREUR liste des mises à jour : ...` | winget n'a pas pu lister les mises à jour (source injoignable, sortie non reconnue). Aucune application n'a été mise à jour. | Lancer `winget upgrade` dans une console administrateur pour voir le message complet. |
| `winget upgrade \| ERREUR <Id> : identifiant tronqué` | L'identifiant affiché par winget est coupé ; l'application est ignorée. | Mettre l'application à jour manuellement : `winget upgrade --id <Id complet> --exact`. |
| `winget upgrade \| ERREUR winget introuvable` | winget absent et la tentative de secours a échoué (voir la ligne `Installation winget` juste avant). | Réinstaller winget en administrateur (voir ci-dessous). |
| `Installation winget \| ERREUR <message>` | Pas d'accès Internet, PowerShell Gallery ou GitHub inaccessible (proxy, pare-feu), ou échec sous `SYSTEM` lors de la tentative de secours ([winget-cli #4271](https://github.com/microsoft/winget-cli/issues/4271)). | Vérifier l'accès Internet, puis réinstaller winget en administrateur (voir ci-dessous). |
| `Installation winget \| ERREUR winget toujours introuvable après installation` | L'installation s'est terminée mais `winget.exe` n'est pas localisé. | Réinstaller winget en administrateur (voir ci-dessous), puis vérifier avec `winget --version`. |
| `Installation VC++ \| ERREUR ...` | Runtime Visual C++ non installé : `aka.ms` inaccessible (message), ou code retour d'échec de `vc_redist`. | Vérifier l'accès à `aka.ms`, puis relancer l'installeur en administrateur (voir ci-dessous). |
| `... \| ERREUR lancement impossible : <message>` | L'exécutable n'a pas pu être démarré. | Lire le message ; vérifier que le fichier existe. |
| `Installation tâche \| ERREUR <message>` | La tâche n'a pas pu être enregistrée. | Relancer l'installation dans une console administrateur. |

`0x8A15002B` (aucune mise à jour disponible) est volontairement journalisé `OK`.

## Réinstaller winget

L'installation de winget est fiable en session administrateur, pas sous `SYSTEM`. Dans une console PowerShell lancée en administrateur, avec accès Internet, relancer l'installeur depuis le dossier `Windows/Maintenance` :

```powershell
.\Install-MaintenanceTask.ps1
```

Ou, depuis `%ProgramData%\SystemMaintenance`, n'installer que winget et le runtime Visual C++ :

```powershell
.\Invoke-SystemMaintenance.ps1 -InstallWingetOnly
```

Le résultat est écrit dans les lignes `Installation winget` et `Installation VC++` du journal (code de sortie `0` si les deux sont OK).

## Aucune nouvelle ligne dans le journal

La tâche n'a pas tourné ou n'est pas allée au bout. Vérifier son dernier résultat :

```powershell
Get-ScheduledTaskInfo -TaskName 'Maintenance hebdomadaire (SFC + winget)'
```

| `LastTaskResult` | Signification |
|---|---|
| `0` | Maintenance exécutée. Des applications peuvent malgré tout être en `ERREUR` dans le journal (au moins une autre a réussi) : à mettre à jour manuellement. |
| `1` | SFC/DISM en erreur, winget introuvable ou non exécutable, ou toutes les applications à mettre à jour en erreur : voir le journal. |
| Autre valeur | Le script n'a pas abouti (tâche arrêtée par la limite de 4 h, poste éteint pendant l'exécution…). Lancer le test manuel décrit dans le [README](../README.md#test-manuel). |

Causes fréquentes d'absence d'exécution : poste sans réseau (condition de la tâche), poste éteint depuis l'échéance (la tâche rattrape au prochain démarrage).

## Une application n'est pas mise à jour

- Installée pour l'utilisateur seulement : winget sous `SYSTEM` ne la voit pas.
- Épinglée avec `winget pin add` : exclue volontairement.
