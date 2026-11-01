# Obsolete – code legacy Windows

Scripts écrits en 2017 (code legacy), conservés pour l'historique. **Ils ne sont plus maintenus et ne doivent plus être utilisés tels quels.**
L'historique git de chaque fichier est conservé (déplacements via `git mv`).

| Dossier | Contenu | Raison de l'archivage | Remplaçant recommandé |
|---|---|---|---|
| `Windows_7/` | `changeKey.PS1` : changement de clé produit via `slmgr` | Windows 7 hors support depuis le 14/01/2020 ; `slmgr` en mode WScript affiche des pop-ups sans code retour exploitable ; clé affichée en clair. | À reconstruire : outil d'activation Windows 10/11 via WMI/CIM (`SoftwareLicensingService`), ou réinstallation avec licence numérique (« Je n'ai pas de clé de produit »). |
| `sfc_scan/` | `scannow.bat`, `verifyonly.bat`, `scanfile.bat` | Simples raccourcis d'une commande native, sans vérification des droits administrateur ni journal. `sfc /scannow` est désormais exécuté automatiquement par [`../Maintenance`](../Maintenance/README.md). | [`Windows/Maintenance`](../Maintenance/README.md) ; ponctuellement, `sfc /verifyonly` ou `sfc /scanfile=<fichier>` directement dans une console administrateur. |
| `Python/` | `pip_install_default.bat`, `set_python_env.bat` | Environnement Django d'étudiant : installation globale par `pip` (hors environnement virtuel), `nose` abandonné depuis 2015 et incompatible avec les Python récents, `set_python_env.bat` non fonctionnel (syntaxe Bash dans un `.bat`). | `py -m venv .venv`, `requirements.txt` ou `pyproject.toml`, `pytest` à la place de `nose`. |
| `Utilities/` (ex-`Utilitites/`) | `ZipFile.PS1`, `UnzipFile.PS1` | Recodent ce que Windows fournit nativement ; `LoadWithPartialName` est déprécié ; aucune validation des chemins. | Cmdlets natifs `Compress-Archive` / `Expand-Archive` (PowerShell 5.0+), ou `tar.exe` intégré à Windows 10 (1803+) et Windows 11. |
