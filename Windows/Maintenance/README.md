# Maintenance Windows (SFC + winget)

Maintenance hebdomadaire silencieuse d'un poste Windows 10/11 :

1. `DISM /Online /Cleanup-Image /RestoreHealth` (optionnel) ;
2. `sfc /scannow` ;
3. `winget upgrade --all`.

Le tout s'exécute via une tâche planifiée sous le compte `SYSTEM` : aucune fenêtre, aucune pop-up, aucune validation demandée à l'utilisateur du poste. Le résultat tient en une ligne de journal par commande.

| Fichier | Rôle |
|---|---|
| `Invoke-SystemMaintenance.ps1` | Exécute la maintenance et écrit le journal. |
| `Install-MaintenanceTask.ps1` | Copie le script dans un dossier protégé et crée la tâche planifiée. |
| `Uninstall-MaintenanceTask.ps1` | Supprime la tâche et, en option, le dossier d'installation. |

Spécifications : [docs/SPECIFICATIONS.md](docs/SPECIFICATIONS.md). Dépannage : [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Prérequis

- Windows 10 ou 11, Windows PowerShell 5.1.
- Console PowerShell **lancée en administrateur** (installation, désinstallation, test manuel).
- App Installer (winget) **version 1.4 ou supérieure** : l'option `--disable-interactivity` est toujours passée.

## Installation

Depuis le dossier `Windows/Maintenance`, dans une console administrateur :

```powershell
.\Install-MaintenanceTask.ps1
```

Le script :

- crée `%ProgramData%\SystemMaintenance`, coupe l'héritage des permissions et n'y autorise que `SYSTEM` et `Administrateurs` (contrôle total), `Utilisateurs` (lecture/exécution) ;
- y copie `Invoke-SystemMaintenance.ps1` et retire la marque « téléchargé depuis Internet » ;
- crée ou remplace la tâche `\Maintenance hebdomadaire (SFC + winget)` : hebdomadaire, compte `SYSTEM`, privilèges les plus élevés, rattrapage si le poste était éteint, uniquement si le réseau est disponible, une seule instance, durée maximale 4 h, 2 relances espacées de 30 min en cas d'échec ;
- écrit la ligne `Installation tâche` dans le journal.

Exemple avec options :

```powershell
.\Install-MaintenanceTask.ps1 -DayOfWeek Sunday -At '10:30' -WithDism -RunNow
```

## Paramètres

### `Install-MaintenanceTask.ps1`

| Paramètre | Défaut | Description |
|---|---|---|
| `-InstallPath` | `%ProgramData%\SystemMaintenance` | Dossier d'installation (script + journal). |
| `-TaskName` | `Maintenance hebdomadaire (SFC + winget)` | Nom de la tâche (à la racine `\`). |
| `-DayOfWeek` | `Wednesday` | Jour d'exécution. |
| `-At` | `12:00` | Heure d'exécution. |
| `-WithDism` | absent | Ajoute l'étape DISM avant SFC. |
| `-RunNow` | absent | Démarre la tâche juste après sa création. |

Accepte aussi `-WhatIf` et `-Confirm`.

### `Invoke-SystemMaintenance.ps1`

| Paramètre | Défaut | Description |
|---|---|---|
| `-WithDism` | absent | Exécute DISM `/RestoreHealth` avant SFC. |
| `-LogPath` | `%ProgramData%\SystemMaintenance\Maintenance.log` | Fichier journal. |
| `-MaxLogLines` | `500` | Lignes conservées (10 à 100 000), les plus anciennes sont supprimées. |

Code de sortie : `0` si toutes les commandes sont OK, `1` si au moins une est en erreur.

### `Uninstall-MaintenanceTask.ps1`

| Paramètre | Défaut | Description |
|---|---|---|
| `-TaskName` | `Maintenance hebdomadaire (SFC + winget)` | Tâche à supprimer. |
| `-InstallPath` | `%ProgramData%\SystemMaintenance` | Dossier d'installation. |
| `-RemoveFiles` | absent | Supprime aussi le dossier, le script et le journal. |

Accepte aussi `-WhatIf` et `-Confirm`.

## Journal

Emplacement : `%ProgramData%\SystemMaintenance\Maintenance.log` (un seul fichier, UTF-8).

Format : `date heure | commande | résultat`, une ligne par commande. Le résultat vaut `OK` ou `ERREUR` suivi du code retour en décimal et en hexadécimal.

```text
2026-11-04 12:00:01 | Installation tâche   | OK
2026-11-04 12:00:02 | sfc /scannow         | OK
2026-11-04 12:38:47 | winget upgrade --all | ERREUR code -1978335226 (0x8A150006)
```

Le fichier est réduit aux `500` dernières lignes à la fin de chaque exécution : pas d'accumulation. Lecture des erreurs : [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Test manuel

Exécution directe, dans une console administrateur (affiche les lignes du journal) :

```powershell
.\Invoke-SystemMaintenance.ps1 -Verbose
```

Exécution via la tâche, dans les conditions réelles (compte `SYSTEM`) :

```powershell
Start-ScheduledTask -TaskName 'Maintenance hebdomadaire (SFC + winget)'
```

```powershell
Get-Content "$env:ProgramData\SystemMaintenance\Maintenance.log" -Tail 5
```

`sfc /scannow` dure souvent plus de 30 minutes : le journal n'est écrit qu'à la fin de chaque commande.

## Désinstallation

Supprimer la tâche seule (le journal reçoit la ligne `Suppression tâche`) :

```powershell
.\Uninstall-MaintenanceTask.ps1
```

Supprimer la tâche, le script et le journal :

```powershell
.\Uninstall-MaintenanceTask.ps1 -RemoveFiles
```

## Limites connues

- **winget sous `SYSTEM`** ne met à jour que les applications installées pour la machine (portée *machine*). Les applications installées dans le profil d'un utilisateur ne sont pas concernées.
- **winget peut fermer une application ouverte** pour la mettre à jour. Pour exclure une application sensible, l'épingler :

  ```powershell
  winget pin add --id <id>
  ```

- La tâche ne démarre que si le réseau est disponible et s'arrête au bout de 4 h.
- Les journaux d'installation et de désinstallation ajoutent une ligne sans réduire le fichier ; la réduction a lieu à l'exécution suivante de la maintenance.
