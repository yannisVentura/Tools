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
| `winget upgrade --all \| ERREUR code N (0x8A15....)` | Au moins une mise à jour a échoué. | Rechercher le code hexadécimal dans la [liste des codes retour winget](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md). |
| `winget upgrade --all \| ERREUR code -1073741515 (0xC0000135)` | DLL introuvable : runtime Visual C++ manquant (voir la ligne `Installation VC++` juste avant, si présente). | Relancer l'installeur en administrateur (voir ci-dessous). |
| `winget upgrade --all \| ERREUR winget introuvable` | winget absent et la tentative de secours a échoué (voir la ligne `Installation winget` juste avant). | Réinstaller winget en administrateur (voir ci-dessous). |
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
| `0` | Toutes les commandes sont OK. |
| `1` | Au moins une commande en erreur : voir le journal. |
| Autre valeur | Le script n'a pas abouti (tâche arrêtée par la limite de 4 h, poste éteint pendant l'exécution…). Lancer le test manuel décrit dans le [README](../README.md#test-manuel). |

Causes fréquentes d'absence d'exécution : poste sans réseau (condition de la tâche), poste éteint depuis l'échéance (la tâche rattrape au prochain démarrage).

## Une application n'est pas mise à jour

- Installée pour l'utilisateur seulement : winget sous `SYSTEM` ne la voit pas.
- Épinglée avec `winget pin add` : exclue volontairement.
