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
Quand `winget.exe` est absent du `PATH`, le script de maintenance doit utiliser le `winget.exe` du dossier `Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe` de version la plus élevée sous `%ProgramFiles%\WindowsApps`, en ne retenant que les dossiers dont la version est analysable et qui contiennent `winget.exe`.
- Vérification : démonstration (exécution via la tâche sous `SYSTEM`).
```gherkin
Étant donné la tâche planifiée exécutée sous SYSTEM
Quand ISM recherche winget
Alors winget est lancé et le journal ne contient pas "winget introuvable"
```

### REQ-MAINT-006 – winget introuvable
Si aucun `winget.exe` n'est trouvé après la tentative d'installation de secours (REQ-MAINT-022), alors le script de maintenance doit journaliser `winget upgrade --all | ERREUR winget introuvable`.
- Vérification : test.
```gherkin
Étant donné un poste sans App Installer et sans accès Internet
Quand ISM est exécuté
Alors la ligne "Installation winget" contient "ERREUR"
Et la ligne "winget upgrade --all" contient "ERREUR winget introuvable"
Et le code de sortie vaut 1
```

### REQ-MAINT-007 – Journal d'une ligne par commande
Le script de maintenance doit écrire une seule ligne par commande, au format `dd/MM/yyyy HH:mm:ss | <commande sur 20 caractères> | <résultat>`.
- Vérification : test.
```gherkin
Étant donné une exécution de ISM sans DISM, winget et le runtime Visual C++ étant présents
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
Le système doit s'exécuter sans fenêtre, pop-up ni demande de validation pour l'utilisateur du poste : tâche sous `SYSTEM` (`S-1-5-18`), PowerShell `-NonInteractive -WindowStyle Hidden`, commandes lancées en fenêtre masquée, winget `--silent --disable-interactivity`, runtime Visual C++ `/quiet /norestart`.
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

## Exigences fonctionnelles – provisionnement de winget

Un Windows 10 fraîchement installé n'a pas winget tant que le Microsoft Store n'a pas mis à jour App Installer.

### REQ-MAINT-021 – Provisionnement de winget à l'installation
Après la copie de ISM, le script d'installation doit lancer `ISM -InstallWingetOnly` dans la session administrateur, ce qui installe ou répare winget pour tous les utilisateurs sans invite : TLS 1.2, fournisseur NuGet 2.8.5.201 minimum, module `Microsoft.WinGet.Client` (portée `AllUsers`, depuis `PSGallery`), `Repair-WinGetPackageManager -AllUsers -Latest -Force`, puis l'enregistrement pour la session (REQ-MAINT-032) et le runtime Visual C++ (REQ-MAINT-030).
- Vérification : démonstration (Windows 10 fraîchement installé, accès Internet).
```gherkin
Étant donné un Windows 10 fraîchement installé sans winget, avec accès Internet
Quand IMT est exécuté en administrateur
Alors le journal contient "Installation winget" avec "OK"
Et la commande winget est disponible dans la console administrateur
```

### REQ-MAINT-022 – Réparation de secours pendant la maintenance
Si `winget.exe` est introuvable, alors le script de maintenance doit tenter une seule fois l'installation de winget (REQ-MAINT-021) avant `winget upgrade --all`.
- Vérification : test.
```gherkin
Étant donné un poste où winget est introuvable
Quand ISM est exécuté
Alors une ligne "Installation winget" précède la ligne "winget upgrade --all"
```

### REQ-MAINT-023 – Journalisation de l'installation de winget
Quand l'installation de winget est tentée, le script de maintenance doit journaliser `Installation winget` avec `OK` si winget est ensuite localisé, `ERREUR winget toujours introuvable après installation` s'il ne l'est pas, ou `ERREUR <message>` si l'installation échoue.
- Vérification : test.
```gherkin
Étant donné un poste sans accès à la PowerShell Gallery
Quand ISM est exécuté avec -InstallWingetOnly
Alors la ligne "Installation winget" contient "ERREUR"
Et le code de sortie vaut 1
```

### REQ-MAINT-024 – Conservation de winget à la désinstallation
Le script de désinstallation ne doit supprimer ni winget, ni le module `Microsoft.WinGet.Client`, ni le runtime Visual C++.
- Vérification : inspection.
```gherkin
Étant donné un poste où IMT a installé winget et le runtime Visual C++
Quand UMT est exécuté avec -RemoveFiles
Alors winget, le module Microsoft.WinGet.Client et le runtime Visual C++ sont toujours présents
```

### REQ-MAINT-025 – Échec de l'installation de winget non bloquant
Si `ISM -InstallWingetOnly` se termine avec un code différent de `0`, alors le script d'installation doit émettre un avertissement et poursuivre la création de la tâche.
- Vérification : test.
```gherkin
Étant donné un poste sans accès Internet
Quand IMT est exécuté en administrateur
Alors un avertissement "winget n'a pas pu être installé" s'affiche
Et la tâche planifiée est créée
```

## Exigences fonctionnelles – runtime Visual C++ et journal

Sur un Windows 10 neuf, `winget.exe` lancé sous `SYSTEM` échoue avec `0xC0000135` (DLL introuvable) tant que le Visual C++ Redistributable 2015-2022 n'est pas installé.

### REQ-MAINT-026 – Détection du runtime Visual C++
Le script de maintenance doit considérer le runtime Visual C++ présent si et seulement si la valeur `Installed` de `HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\<arch>` vaut `1` (`<arch>` = `x64` sur un OS 64 bits, sinon `x86`).
- Vérification : inspection.
```gherkin
Étant donné un Windows 64 bits où la valeur Installed de la clé x64 vaut 1
Quand ISM teste le runtime
Alors le runtime est considéré présent et aucune ligne "Installation VC++" n'est écrite
```

### REQ-MAINT-027 – Installation du runtime pendant la maintenance
Quand winget est localisé et que le runtime Visual C++ est absent, le script de maintenance doit installer le runtime (REQ-MAINT-028) avant `winget upgrade --all`.
- Vérification : test.
```gherkin
Étant donné un poste avec winget mais sans runtime Visual C++
Quand ISM est exécuté
Alors une ligne "Installation VC++" précède la ligne "winget upgrade --all"
```

### REQ-MAINT-028 – Installation silencieuse du runtime
Quand l'installation du runtime est tentée, le script de maintenance doit télécharger `https://aka.ms/vs/17/release/vc_redist.<arch>.exe` dans le dossier du journal (dossier protégé, pas `%TEMP%`), l'exécuter avec `/install /quiet /norestart`, considérer `0`, `3010` et `1638` comme des succès, puis supprimer l'installeur.
- Vérification : test.
```gherkin
Étant donné un poste sans runtime Visual C++, avec accès à aka.ms
Quand l'installation du runtime est tentée
Alors la ligne "Installation VC++" contient "OK"
Et vc_redist.<arch>.exe n'est plus présent dans le dossier du journal
```

### REQ-MAINT-029 – Journalisation de l'installation du runtime
Quand l'installation du runtime est tentée, le script de maintenance doit journaliser `Installation VC++` avec `OK`, `ERREUR code <décimal> (0x<hexadécimal>)`, `ERREUR lancement impossible : <message>`, ou `ERREUR <message>` si le téléchargement échoue.
- Vérification : test.
```gherkin
Étant donné un poste sans runtime Visual C++ et sans accès à aka.ms
Quand ISM est exécuté avec -InstallWingetOnly
Alors la ligne "Installation VC++" contient "ERREUR"
```

### REQ-MAINT-030 – Runtime avec -InstallWingetOnly
Où `-InstallWingetOnly` est présent, le script de maintenance doit, après l'installation de winget et quel qu'en soit le résultat, installer le runtime Visual C++ s'il est absent, puis se terminer avec `0` seulement si winget est localisé et le runtime présent ou installé avec succès, sinon `1`.
- Vérification : test.
```gherkin
Étant donné un poste où winget s'installe mais pas le runtime Visual C++
Quand ISM est exécuté avec -InstallWingetOnly
Alors la ligne "Installation winget" contient "OK"
Et la ligne "Installation VC++" contient "ERREUR"
Et le code de sortie vaut 1
```

### REQ-MAINT-031 – Message multi-lignes aplati
Si un résultat à journaliser contient des retours à la ligne, alors le script de maintenance doit les remplacer, avec les espaces qui les entourent, par un seul espace.
- Vérification : test.
```gherkin
Étant donné une exception dont le message tient sur plusieurs lignes
Quand elle est journalisée
Alors le journal ne reçoit qu'une seule ligne
```

### REQ-MAINT-032 – Enregistrement de winget pour la session
Quand le compte courant n'est pas `SYSTEM` et que `winget.exe` est absent du `PATH` après `Repair-WinGetPackageManager`, le script de maintenance doit enregistrer pour l'utilisateur courant la version la plus récente de `Microsoft.DesktopAppInstaller` installée sur la machine (`Add-AppxPackage -Register <InstallLocation>\AppxManifest.xml -DisableDevelopmentMode`) et ignorer son échec.
- Vérification : test.
```gherkin
Étant donné une console administrateur où winget est déjà dans le PATH
Quand ISM est exécuté avec -InstallWingetOnly
Alors la ligne "Installation winget" contient "OK" et ne contient pas "0x80073D06"
```

## Matrice de traçabilité

Les blocs nommés de `IMT` correspondent à ses commentaires de section (`--- Dossier protégé ---`, `--- winget ---`, `--- Tâche planifiée ---`).

| Exigence | Implémentation | Statut |
|---|---|---|
| REQ-MAINT-001 | `ISM` : région Exécution (étape `sfc /scannow`), `Invoke-Step` | Implémentée |
| REQ-MAINT-002 | `ISM` : région Exécution (bloc `if ($WithDism)`) | Implémentée |
| REQ-MAINT-003 | `ISM` : région Exécution (étape `winget upgrade --all`) | Implémentée |
| REQ-MAINT-004 | `ISM` : `$WingetSuccessCodes`, `Invoke-Step` | Implémentée |
| REQ-MAINT-005 | `ISM` : `Get-WingetPath` | Implémentée |
| REQ-MAINT-006 | `ISM` : région Exécution (branche `else` de `if ($wingetPath)`) | Implémentée |
| REQ-MAINT-007 | `ISM` : `Write-Log` | Implémentée |
| REQ-MAINT-008 | `ISM` : `Invoke-Step`, `Format-Error` | Implémentée |
| REQ-MAINT-009 | `ISM` : `Invoke-Step` (bloc `catch`) | Implémentée |
| REQ-MAINT-010 | `ISM` : région Exécution (`exit [int](-not $allOk)`) | Implémentée |
| REQ-MAINT-011 | `IMT` : bloc `Copier le script de maintenance` | Implémentée |
| REQ-MAINT-012 | `IMT` : bloc Tâche planifiée (`New-ScheduledTaskTrigger`, `Register-ScheduledTask`) | Implémentée |
| REQ-MAINT-013 | `IMT` : bloc Tâche planifiée (`New-ScheduledTaskSettingsSet`) | Implémentée |
| REQ-MAINT-014 | `IMT` : bloc Tâche planifiée (`finally`) ; `UMT` : bloc `Supprimer la tâche planifiée` | Implémentée |
| REQ-MAINT-015 | `UMT` : blocs `Supprimer la tâche planifiée` et `Supprimer le dossier et son contenu` | Implémentée |
| REQ-MAINT-016 | `IMT` : bloc Tâche planifiée (`$arguments`, `New-ScheduledTaskPrincipal`) ; `ISM` : `Invoke-Step`, `Install-Winget` (`-Force`), `Invoke-VCRedistSetup`, étape `winget upgrade --all` | Implémentée |
| REQ-MAINT-017 | `IMT` : bloc Dossier protégé | Implémentée |
| REQ-MAINT-018 | `ISM` : `Limit-LogSize` | Implémentée (`IMT`/`UMT` ajoutent une ligne sans réduire) |
| REQ-MAINT-019 | `ISM` : `Write-Log` (bloc `catch`) | Implémentée |
| REQ-MAINT-020 | `ISM` : `Get-NativeSystemDirectory` ; `IMT` : bloc Dossier protégé (SID) | Implémentée |
| REQ-MAINT-021 | `IMT` : bloc winget ; `ISM` : bloc `if ($InstallWingetOnly)`, `Invoke-WingetSetup`, `Install-Winget` | Implémentée (sous `SYSTEM`, non garanti : winget-cli #4271) |
| REQ-MAINT-022 | `ISM` : région Exécution (bloc `if (-not $wingetPath)`), `Invoke-WingetSetup` | Implémentée |
| REQ-MAINT-023 | `ISM` : `Invoke-WingetSetup` | Implémentée |
| REQ-MAINT-024 | `UMT` : absence de suppression (cf. `.DESCRIPTION`) | Implémentée |
| REQ-MAINT-025 | `IMT` : bloc winget (test de `$LASTEXITCODE`, `Write-Warning`) | Implémentée |
| REQ-MAINT-026 | `ISM` : `Test-VCRedist` | Implémentée |
| REQ-MAINT-027 | `ISM` : région Exécution (bloc `if ($wingetPath -and -not (Test-VCRedist))`), `Invoke-VCRedistSetup` | Implémentée |
| REQ-MAINT-028 | `ISM` : `Invoke-VCRedistSetup`, `Invoke-Step` | Implémentée |
| REQ-MAINT-029 | `ISM` : `Invoke-VCRedistSetup` (bloc `catch`), `Invoke-Step`, `Format-Error` | Implémentée |
| REQ-MAINT-030 | `ISM` : bloc `if ($InstallWingetOnly)`, `Test-VCRedist`, `Invoke-VCRedistSetup` | Implémentée |
| REQ-MAINT-031 | `ISM` : `Write-Log` | Implémentée |
| REQ-MAINT-032 | `ISM` : `Install-Winget` (bloc `Add-AppxPackage`) | Implémentée |
