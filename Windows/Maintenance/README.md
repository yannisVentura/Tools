# Maintenance Windows (SFC + winget)

Maintenance hebdomadaire silencieuse d'un poste Windows 10/11 :

1. `DISM /Online /Cleanup-Image /RestoreHealth` (optionnel) ;
2. `sfc /scannow` ;
3. mise à jour des applications par winget, une application à la fois (`winget upgrade --id <Id> --exact`) : un échec isolé n'empêche pas les autres mises à jour et apparaît sur sa propre ligne de journal.

Le tout s'exécute via une tâche planifiée sous le compte `SYSTEM` : aucune fenêtre, aucune pop-up, aucune validation demandée à l'utilisateur du poste. Le résultat tient en une ligne de journal par commande.

| Fichier | Rôle |
|---|---|
| `Invoke-SystemMaintenance.ps1` | Exécute la maintenance et écrit le journal. |
| `Install-MaintenanceTask.ps1` | Copie le script dans un dossier protégé et crée la tâche planifiée. |
| `Uninstall-MaintenanceTask.ps1` | Supprime la tâche et, en option, le dossier d'installation. |

Spécifications : [docs/SPECIFICATIONS.md](docs/SPECIFICATIONS.md). Dépannage : [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Prérequis

- Windows 10 version 1809 (build 17763) ou ultérieure, ou Windows 11 ; Windows PowerShell 5.1. En dessous, winget n'est pas pris en charge : la ligne `Installation winget` passe en `ERREUR`.
- Console PowerShell **lancée en administrateur** (installation, désinstallation, test manuel).
- **Accès Internet** pendant l'installation (PowerShell Gallery, GitHub, `aka.ms`) : l'installeur provisionne winget et le runtime Visual C++.
- winget n'a pas besoin d'être présent à l'avance, y compris sur un Windows 10 fraîchement installé. S'il l'est déjà, il est mis à jour (l'option `--disable-interactivity`, toujours passée, exige la version 1.4 ou supérieure).

## Installation

Depuis le dossier `Windows/Maintenance`, dans une console administrateur :

```powershell
.\Install-MaintenanceTask.ps1
```

Le script :

- crée `%ProgramData%\SystemMaintenance`, coupe l'héritage des permissions et n'y autorise que `SYSTEM` et `Administrateurs` (contrôle total), `Utilisateurs` (lecture/exécution) ;
- y copie `Invoke-SystemMaintenance.ps1` et retire la marque « téléchargé depuis Internet » ;
- installe ou met à jour winget pour tous les utilisateurs en lançant `Invoke-SystemMaintenance.ps1 -InstallWingetOnly` dans la session administrateur (méthode recommandée par Microsoft) : ligne `Installation winget` dans le journal. Installe aussi le runtime Visual C++ s'il est absent (ligne `Installation VC++`). En cas d'échec, un simple avertissement s'affiche et l'installation continue ; la maintenance retentera ;
- crée ou remplace la tâche `\Maintenance hebdomadaire (SFC + winget)` : hebdomadaire, compte `SYSTEM`, privilèges les plus élevés, rattrapage si le poste était éteint, uniquement si le réseau est disponible, une seule instance, durée maximale 4 h, 2 relances espacées de 30 min en cas d'échec ;
- règle la compatibilité de la tâche (« Configurer pour ») d'après le système détecté : `Windows 10` sur Windows 10 et 11, `Windows 8`, `Windows 7` ou `Windows Vista` sur les systèmes plus anciens. La ligne `Installation tâche` du journal indique le choix, par exemple `OK compatibilité Windows 10 - Microsoft Windows 11 Professionnel (build 26300)` ;
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
| `-InstallWingetOnly` | absent | Installe ou répare uniquement winget et le runtime Visual C++, sans lancer la maintenance. |

Code de sortie (résultat de la tâche) : `0` si la maintenance a pu s'exécuter, même si certaines applications ont échoué à se mettre à jour, tant qu'au moins une a réussi (les échecs apparaissent en `ERREUR` dans le journal et sont à mettre à jour manuellement) ; `1` si SFC ou DISM est en erreur, si winget est introuvable ou non exécutable, ou si toutes les applications à mettre à jour ont échoué. Avec `-InstallWingetOnly` : `0` si winget est localisé et le runtime Visual C++ présent, sinon `1`.

`-InstallWingetOnly` effectue, sans invite : activation de TLS 1.2, installation du fournisseur NuGet (2.8.5.201 minimum) si absent, installation du module `Microsoft.WinGet.Client` (portée `AllUsers`, depuis `PSGallery`), puis `Repair-WinGetPackageManager -AllUsers -Latest -Force`. Hors compte `SYSTEM`, si winget n'est pas encore dans le `PATH`, la version la plus récente d'App Installer installée sur la machine est enregistrée pour l'utilisateur courant (`Add-AppxPackage -Register <InstallLocation>\AppxManifest.xml -DisableDevelopmentMode`, erreurs ignorées). Sans cela, l'utilisateur garde l'App Installer d'origine (sans winget) jusqu'à sa prochaine connexion.

Il installe ensuite, si absent, le Visual C++ Redistributable 2015-2022 dont winget a besoin sous `SYSTEM` : téléchargement de `https://aka.ms/vs/17/release/vc_redist.<x64|x86>.exe` dans le dossier du journal, installation `/install /quiet /norestart`, suppression de l'installeur.

Pendant la maintenance, si winget est introuvable, son installation est tentée une fois avant les mises à jour winget ; si le runtime Visual C++ est absent, son installation l'est aussi.

### `Uninstall-MaintenanceTask.ps1`

| Paramètre | Défaut | Description |
|---|---|---|
| `-TaskName` | `Maintenance hebdomadaire (SFC + winget)` | Tâche à supprimer. |
| `-InstallPath` | `%ProgramData%\SystemMaintenance` | Dossier d'installation. |
| `-RemoveFiles` | absent | Supprime aussi le dossier, le script et le journal. |

Accepte aussi `-WhatIf` et `-Confirm`.

## Journal

Emplacement : `%ProgramData%\SystemMaintenance\Maintenance.log` (un seul fichier, UTF-8).

Format : `date heure | commande | résultat`, une ligne par commande. Le résultat vaut `OK` ou `ERREUR` suivi du code retour en décimal et en hexadécimal (ou d'un message, par exemple pour `Installation winget`).

```text
04/11/2026 11:58:40 | Installation winget  | OK
04/11/2026 11:59:12 | Installation VC++    | OK
04/11/2026 12:00:01 | Installation tâche   | OK
04/11/2026 12:00:02 | sfc /scannow         | OK
04/11/2026 12:39:15 | winget upgrade       | OK Audacity.Audacity 3.7.9 -> 4.0.1
04/11/2026 12:39:40 | winget upgrade       | ERREUR EPSON.EpsonNetPrint 3.1.4.0 -> 3.3.1 : code -2145844844 (0x80190194)
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

- **Installation de winget sous `SYSTEM`** (secours pendant la maintenance) : comportement non garanti par Microsoft ([winget-cli #4271](https://github.com/microsoft/winget-cli/issues/4271)). En cas d'échec, relancer l'installation en administrateur (voir [dépannage](docs/TROUBLESHOOTING.md)).
- La désinstallation conserve winget, le module `Microsoft.WinGet.Client` et le runtime Visual C++ : ce sont des composants Windows utiles en dehors de cet outil.
- La tâche ne démarre que si le réseau est disponible et s'arrête au bout de 4 h.
- Les journaux d'installation et de désinstallation ajoutent une ligne sans réduire le fichier ; la réduction a lieu à l'exécution suivante de la maintenance.
