# Spécifications – Maintenance Windows

## Contexte

Poste Windows 10 d'un particulier, destiné à fonctionner longtemps sans intervention. La maintenance (intégrité système + mises à jour des applications) doit rester invisible pour l'utilisateur du poste et laisser un journal lisible par un administrateur à distance ou lors d'un passage.

Usage et paramètres : [../README.md](../README.md).

Abréviations : `ISM` = `Invoke-SystemMaintenance.ps1`, `IMT` = `Install-MaintenanceTask.ps1`, `UMT` = `Uninstall-MaintenanceTask.ps1`.

## Exigences fonctionnelles

### REQ-MAINT-001 – Vérification des fichiers système
Le script de maintenance doit exécuter `sfc /scannow`.
- Vérification : test.
```gherkin
Étant donné un poste Windows 10 en état normal
Quand ISM est exécuté
Alors le journal contient une ligne "sfc /scannow" suivie de "OK" ou "ERREUR"
```

### REQ-MAINT-002 – Réparation DISM optionnelle
Où le paramètre `-WithDism` est présent, le script de maintenance doit exécuter `DISM /Online /Cleanup-Image /RestoreHealth` avant `sfc /scannow`.
- Vérification : test.
```gherkin
Étant donné ISM lancé avec -WithDism
Quand l'exécution se termine
Alors la ligne "DISM /RestoreHealth" précède la ligne "sfc /scannow" dans le journal
```

### REQ-MAINT-003 – Mise à jour des applications
Le script de maintenance doit exécuter `winget upgrade --all` avec `--silent`, `--accept-source-agreements`, `--accept-package-agreements` et `--disable-interactivity`.
- Vérification : inspection.
```gherkin
Étant donné le code de ISM
Quand on inspecte l'appel à winget
Alors les quatre options sont présentes
```

### REQ-MAINT-004 – Aucune mise à jour disponible
Si winget retourne `0x8A15002B` (aucune mise à jour applicable), alors le script de maintenance doit journaliser `OK`.
- Vérification : test.
```gherkin
Étant donné un poste dont toutes les applications sont à jour
Quand ISM est exécuté
Alors la ligne "winget upgrade --all" se termine par "OK"
```

### REQ-MAINT-005 – Localisation de winget sous SYSTEM
Quand `winget.exe` est absent du `PATH`, le script de maintenance doit utiliser le `winget.exe` du paquet `Microsoft.DesktopAppInstaller` de version la plus élevée sous `%ProgramFiles%\WindowsApps`.
- Vérification : démonstration (exécution via la tâche sous `SYSTEM`).
```gherkin
Étant donné la tâche planifiée exécutée sous SYSTEM
Quand ISM recherche winget
Alors winget est lancé et le journal ne contient pas "winget introuvable"
```

### REQ-MAINT-006 – winget introuvable
Si aucun `winget.exe` n'est trouvé, alors le script de maintenance doit journaliser `ERREUR winget introuvable (installer / mettre à jour App Installer)`.
- Vérification : test.
```gherkin
Étant donné un poste sans App Installer
Quand ISM est exécuté
Alors la ligne "winget upgrade --all" contient "ERREUR winget introuvable"
Et le code de sortie vaut 1
```

### REQ-MAINT-007 – Journal d'une ligne par commande
Le script de maintenance doit écrire une seule ligne par commande, au format `yyyy-MM-dd HH:mm:ss | <commande sur 20 caractères> | <résultat>`.
- Vérification : test.
```gherkin
Étant donné une exécution de ISM sans DISM
Quand elle se termine
Alors exactement deux lignes ont été ajoutées au journal
```

### REQ-MAINT-008 – Résultat explicite
Le script de maintenance doit journaliser `OK` si le code retour fait partie des codes de succès, sinon `ERREUR code <décimal> (0x<hexadécimal sur 8 chiffres>)`.
- Vérification : test.
```gherkin
Étant donné une commande qui retourne -1978335226
Quand sa ligne est journalisée
Alors elle se termine par "ERREUR code -1978335226 (0x8A150006)"
```

### REQ-MAINT-009 – Échec de lancement
Si une commande ne peut pas être lancée, alors le script de maintenance doit journaliser `ERREUR lancement impossible : <message>` et poursuivre avec la commande suivante.
- Vérification : test.
```gherkin
Étant donné sfc.exe inaccessible
Quand ISM est exécuté
Alors la ligne "sfc /scannow" contient "ERREUR lancement impossible"
Et la ligne "winget upgrade --all" est quand même écrite
```

### REQ-MAINT-010 – Code de sortie
Le script de maintenance doit se terminer avec le code `0` si toutes les commandes sont OK, sinon `1`.
- Vérification : test.
```gherkin
Étant donné une exécution où une commande est en ERREUR
Quand ISM se termine
Alors le code de sortie vaut 1
```

### REQ-MAINT-011 – Installation protégée
Le script d'installation doit copier ISM dans `-InstallPath` (défaut `%ProgramData%\SystemMaintenance`) et en retirer la marque de téléchargement.
- Vérification : démonstration.
```gherkin
Étant donné IMT exécuté en administrateur
Quand l'installation se termine
Alors ISM est présent dans %ProgramData%\SystemMaintenance
```

### REQ-MAINT-012 – Tâche planifiée hebdomadaire
Le script d'installation doit créer ou remplacer la tâche `-TaskName` à la racine `\`, hebdomadaire au jour `-DayOfWeek` et à l'heure `-At` (défaut mercredi 12:00).
- Vérification : démonstration.
```gherkin
Étant donné IMT exécuté sans paramètre
Quand on consulte le Planificateur de tâches
Alors la tâche "Maintenance hebdomadaire (SFC + winget)" se déclenche chaque mercredi à 12:00
```

### REQ-MAINT-013 – Robustesse de la tâche
La tâche planifiée doit démarrer dès que possible après une échéance manquée, uniquement si le réseau est disponible, aussi sur batterie, en une seule instance, pendant 4 h au plus, avec 2 relances espacées de 30 min.
- Vérification : inspection.
```gherkin
Étant donné la tâche créée par IMT
Quand on inspecte ses paramètres
Alors chaque réglage listé est présent
```

### REQ-MAINT-014 – Trace d'installation et de suppression
Quand la tâche est enregistrée, le script d'installation doit journaliser `Installation tâche` avec `OK` ou `ERREUR <message>` ; quand la tâche est supprimée sans `-RemoveFiles`, le script de désinstallation doit journaliser `Suppression tâche | OK`.
- Vérification : test.
```gherkin
Étant donné une tâche installée
Quand UMT est exécuté sans -RemoveFiles
Alors la dernière ligne du journal est "Suppression tâche" avec "OK"
```

### REQ-MAINT-015 – Désinstallation
Le script de désinstallation doit supprimer la tâche si elle existe et, où `-RemoveFiles` est présent, supprimer `-InstallPath` et son contenu.
- Vérification : démonstration.
```gherkin
Étant donné une tâche installée
Quand UMT est exécuté avec -RemoveFiles
Alors la tâche et le dossier %ProgramData%\SystemMaintenance n'existent plus
```

## Exigences non fonctionnelles

### REQ-MAINT-016 – Exécution silencieuse
Le système doit s'exécuter sans fenêtre, pop-up ni demande de validation pour l'utilisateur du poste : tâche sous `SYSTEM` (`S-1-5-18`), PowerShell `-NonInteractive -WindowStyle Hidden`, commandes lancées en fenêtre masquée, winget `--silent --disable-interactivity`.
- Vérification : démonstration (session utilisateur ouverte pendant l'exécution de la tâche).
```gherkin
Étant donné un utilisateur connecté au poste
Quand la tâche s'exécute
Alors aucune fenêtre ni invite UAC n'apparaît
```

### REQ-MAINT-017 – Dossier protégé
Le script d'installation doit couper l'héritage des permissions de `-InstallPath` et n'accorder que : `SYSTEM` et `Administrateurs` contrôle total, `Utilisateurs` lecture/exécution, propriétaire `Administrateurs`.
- Vérification : inspection (`Get-Acl`).
```gherkin
Étant donné un utilisateur standard
Quand il tente de modifier ISM dans le dossier d'installation
Alors l'accès est refusé
```

### REQ-MAINT-018 – Journal plafonné
Quand le journal dépasse `-MaxLogLines` lignes (défaut `500`, plage 10 à 100 000), le script de maintenance doit ne conserver que les `-MaxLogLines` dernières.
- Vérification : test.
```gherkin
Étant donné un journal de 600 lignes
Quand ISM se termine
Alors le journal contient 500 lignes, les plus récentes
```

### REQ-MAINT-019 – Journal non bloquant
Si l'écriture du journal échoue, alors le script de maintenance doit émettre un avertissement et poursuivre les commandes.
- Vérification : test.
```gherkin
Étant donné un -LogPath non accessible en écriture
Quand ISM est exécuté
Alors toutes les commandes sont exécutées
```

### REQ-MAINT-020 – Compatibilité
Le système doit fonctionner sous Windows 10/11 avec Windows PowerShell 5.1, quelle que soit la langue de Windows (groupes désignés par SID) et depuis un processus 32 bits (accès à `System32` via `Sysnative`).
- Vérification : inspection + démonstration sur Windows 10 français.
```gherkin
Étant donné un Windows 10 en français
Quand IMT puis la tâche sont exécutés
Alors l'installation réussit et le journal contient "sfc /scannow"
```

## Matrice de traçabilité

| Exigence | Implémentation | Statut |
|---|---|---|
| REQ-MAINT-001 | `ISM` : bloc Exécution (l. 170), `Invoke-Step` | Implémentée |
| REQ-MAINT-002 | `ISM` : bloc Exécution (l. 165-168) | Implémentée |
| REQ-MAINT-003 | `ISM` : bloc Exécution (l. 174-176) | Implémentée |
| REQ-MAINT-004 | `ISM` : `$WingetSuccessCodes` (l. 50), `Invoke-Step` | Implémentée |
| REQ-MAINT-005 | `ISM` : `Get-WingetPath` | Implémentée |
| REQ-MAINT-006 | `ISM` : bloc Exécution (l. 178-181) | Implémentée |
| REQ-MAINT-007 | `ISM` : `Write-Log` | Implémentée |
| REQ-MAINT-008 | `ISM` : `Invoke-Step`, `Format-Error` | Implémentée |
| REQ-MAINT-009 | `ISM` : `Invoke-Step` (bloc `catch`) | Implémentée |
| REQ-MAINT-010 | `ISM` : l. 185 | Implémentée |
| REQ-MAINT-011 | `IMT` : l. 92-95 | Implémentée |
| REQ-MAINT-012 | `IMT` : l. 104-105, 123-125 | Implémentée |
| REQ-MAINT-013 | `IMT` : l. 108-116 | Implémentée |
| REQ-MAINT-014 | `IMT` : l. 132-135 ; `UMT` : l. 40-43 | Implémentée |
| REQ-MAINT-015 | `UMT` : l. 33-55 | Implémentée |
| REQ-MAINT-016 | `IMT` : l. 99, 107 ; `ISM` : `Invoke-Step`, l. 175 | Implémentée |
| REQ-MAINT-017 | `IMT` : l. 70-90 | Implémentée |
| REQ-MAINT-018 | `ISM` : `Limit-LogSize` | Implémentée (`IMT`/`UMT` ajoutent une ligne sans réduire) |
| REQ-MAINT-019 | `ISM` : `Write-Log` (bloc `catch`) | Implémentée |
| REQ-MAINT-020 | `ISM` : `Get-NativeSystemDirectory` ; `IMT` : l. 70-72 | Implémentée |
