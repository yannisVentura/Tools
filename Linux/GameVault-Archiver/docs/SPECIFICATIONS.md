# Spécifications – GameVault Archiver

Version 0.1 (brouillon) – 30/10/2026

## Contexte

La bibliothèque de jeux PC (GOG) est stockée sur un NAS Synology, dans le partage `PC` (`Z:\PC` sous Windows), et exposée par GameVault, hébergé sur TrueNAS. Chaque sous-dossier du partage est une **catégorie** (`RPG`, `Strat`, `Shooters`…). La structure cible est celle de `Z:\PC\Strat` : **une catégorie ne contient que des archives `.zip`, une par jeu, nommées d'après le jeu**.

GameVault Archiver est un script planifié par `cron` sur un Raspberry Pi 5. Le Pi monte le partage du NAS. Le script parcourt les catégories et transforme chaque jeu présent sous une autre forme (dossier, `.exe` isolé) en une archive `.zip`, sans intervention humaine.

Abréviations : `GVA` = GameVault Archiver ; « source » = élément à archiver (dossier de jeu, ou `.exe` avec ses fichiers `.bin`) ; « catégorie » = sous-dossier direct de la racine configurée.

### Structure cible (exemple `RPG`)

```
PC/RPG/                                   PC/RPG/
├── Hellpoint/                            ├── Blackguards_PC_FULL_1.5.zip   (inchangé)
│   ├── Hellpoint.exe                     ├── Hellpoint.zip
│   └── Hellpoint_Data/…          ──►     │     └── Hellpoint/Hellpoint.exe, Hellpoint_Data/…
├── Wasteland 2/…                         └── Wasteland 2.zip
└── Blackguards_PC_FULL_1.5.zip
PC/HnS/Torchlight.exe             ──►     PC/HnS/Torchlight.zip  (└── Torchlight.exe)
PC/Shooters/Archives/Prey.zip     ──►     PC/Shooters/Prey.zip
```

### Hors périmètre

- Les dossiers de la racine qui ne sont pas des catégories configurées (`A tester`, `Linux`, `Roms Jeux vidéo`, `temp_files`, `tmp`) et les fichiers de la racine : d'autres traitements sont en cours dessus.
- Les archives `.zip` existantes, en particulier `RPG/Cyberpunk 2077 + DLC.zip`, en cours de production par un autre agent.
- Le choix définitif de la méthode et du niveau de compression (voir OPEN-3).
- Le renommage « intelligent » des jeux (titre GOG, normalisation).

## Choix technique : Python 3

| Critère | Python 3 (retenu) | Bash + `zip`/`7z` |
|---|---|---|
| Disponibilité sur Raspberry Pi OS | préinstallé, bibliothèque standard suffisante | `zip`/`7z` à installer |
| Noms de fichiers avec espaces, `&`, `'`, accents | sans risque de quoting | source d'erreurs fréquente |
| Archives > 4 Go et > 65 535 fichiers (ZIP64) | natif (`zipfile`) | selon l'outil et sa version |
| Vérification CRC, écriture en flux | natif | possible, plus verbeux |
| Tests automatisés | `unittest`, sans dépendance, exécutables aussi sous Windows | `bats` à installer |

Limite connue : `zipfile` compresse sur un seul cœur. Si les mesures montrent que le CPU, et non le réseau, est le goulot d'étranglement, on envisagera un parallélisme entre jeux ou un compresseur externe (OPEN-3).

## Interface du module

Fichier unique `gamevault_archiver.py`, utilisable comme script (`python3 gamevault_archiver.py --config <fichier> [--dry-run]`) et comme module (pour les tests).

```python
class ConfigError(Exception): ...

@dataclass(frozen=True)
class Config:
    root: Path
    categories: tuple[str, ...]
    exclude: tuple[str, ...] = ()            # entrées "Catégorie/Nom"
    min_age_minutes: int = 60
    source_after_success: str = "keep"       # "keep" | "delete"
    compression: str = "deflated"            # "stored" | "deflated" | "bzip2" | "lzma"
    compresslevel: int | None = 6
    lock_file: Path = Path("/run/lock/gamevault-archiver.lock")
    metrics_file: Path | None = None         # JSON Lines ; None = désactivé
    progress_interval_s: int = 300

@dataclass(frozen=True)
class Action:
    kind: str                  # "zip_dir" | "zip_exe" | "move_zip" | "skip"
    category: str
    name: str                  # nom de la source (dossier, .exe ou .zip)
    sources: tuple[Path, ...]  # fichiers/dossiers concernés
    target: Path | None        # archive .zip à produire ou destination du déplacement
    reason: str = ""           # pour "skip" : "target_exists" | "recent" | "empty"
                               #   | "unsupported" | "orphan_bin" | "archives_conflict"

@dataclass(frozen=True)
class Result:
    action: Action
    status: str                # "ok" | "skipped" | "error" | "dry_run"
    detail: str = ""
    metrics: dict | None = None  # mesures REQ-GVA-035, pour zip_dir / zip_exe réussis

THERMAL_PATH = Path("/sys/class/thermal/thermal_zone0/temp")

def load_config(path: Path) -> Config                     # lève ConfigError
def plan(config: Config, now: float | None = None) -> list[Action]   # aucune écriture
def verify_archive(archive: Path, action: Action) -> bool
def execute(actions: list[Action], config: Config, dry_run: bool = False) -> list[Result]
def classify_bottleneck(cpu_s: float, wall_s: float) -> str          # "cpu" | "io" | "mixed"
def system_context() -> dict                                         # REQ-GVA-037
def main(argv: list[str] | None = None) -> int   # options : --config, --dry-run, --only (répétable)
```

`execute` écrit lui-même les lignes de progression (REQ-GVA-039) sur la sortie standard ; `main` écrit les lignes `START`, d'action, `END` et `SUMMARY`. L'espace libre est lu avec `shutil.disk_usage` et l'outil `vcgencmd` est cherché avec `shutil.which`.

Fichier de configuration (INI, section `[archiver]`, listes à raison d'une valeur par ligne) :

```ini
[archiver]
root = /mnt/nas/PC
categories =
    Action Aventure
    Deck Builder
    Gestion
    HnS
    metroid Vania
    Plateformer
    Point & Click
    RogLite
    RPG
    Shooters
    ShootThemUp
    Strat
exclude =
    RPG/Cyberpunk 2077
min_age_minutes = 60
source_after_success = keep
compression = deflated
compresslevel = 6
lock_file = /run/lock/gamevault-archiver.lock
metrics_file = /mnt/nas/logs/gamevault-archiver/metrics.jsonl
progress_interval_s = 300
```

## Exigences fonctionnelles – périmètre

### REQ-GVA-001 – Catégories traitées
GVA ne doit lire et modifier que les catégories listées dans `categories`. Les autres dossiers et les fichiers de la racine restent inchangés. Une catégorie configurée mais absente du disque est ignorée sans erreur.
- Vérification : test.
```gherkin
Étant donné une racine contenant les catégories "RPG" (configurée) et "A tester" (non configurée), ainsi qu'un fichier "rename_zips.ps1"
Quand GVA est exécuté
Alors le contenu de "A tester" et le fichier "rename_zips.ps1" sont inchangés
```

### REQ-GVA-002 – Exclusions
GVA ne doit produire aucune action pour une source listée dans `exclude` (`Catégorie/Nom`).
- Vérification : test.
```gherkin
Étant donné "RPG/Cyberpunk 2077" listé dans exclude
Quand GVA est exécuté
Alors le dossier "RPG/Cyberpunk 2077" est inchangé et "RPG/Cyberpunk 2077.zip" n'existe pas
```

### REQ-GVA-003 – Archives existantes intactes
GVA ne doit ni modifier, ni renommer, ni déplacer, ni supprimer une archive `.zip` située à la racine d'une catégorie.
- Vérification : test.
```gherkin
Étant donné "RPG/Cyberpunk 2077 + DLC.zip"
Quand GVA est exécuté
Alors son contenu et sa date de modification sont inchangés
```

### REQ-GVA-004 – Éléments ignorés
GVA doit ignorer, sans les journaliser, les éléments dont le nom commence par `.`, `@` ou `#` (`@eaDir`, `#recycle` de Synology). Tout autre fichier qui n'est ni `.zip`, ni `.exe`, ni `.bin` produit une action `skip` de motif `unsupported` et reste en place.
- Vérification : test.
```gherkin
Étant donné "RPG/@eaDir", "RPG/#recycle" et "RPG/notes.txt"
Quand GVA est exécuté
Alors aucune archive n'est créée pour ces éléments
Et seul "notes.txt" apparaît dans les résultats, avec le statut "skipped"
```

## Exigences fonctionnelles – archivage

### REQ-GVA-005 – Un dossier, une archive
Pour chaque sous-dossier d'une catégorie, GVA doit créer l'archive `<Catégorie>/<NomDuDossier>.zip`.
- Vérification : test.
```gherkin
Étant donné le dossier "RPG/Hellpoint"
Quand GVA est exécuté
Alors l'archive "RPG/Hellpoint.zip" existe
```

### REQ-GVA-006 – Contenu d'une archive de dossier
L'archive d'un dossier doit contenir ce dossier comme unique élément racine (`<NomDuDossier>/…`) : tous ses fichiers et sous-dossiers, y compris vides, à l'exception des dossiers `@eaDir`.
- Vérification : test.
```gherkin
Étant donné "RPG/Hellpoint" contenant "Hellpoint.exe", "Hellpoint_Data/level0", un dossier vide "saves" et "@eaDir/thumb"
Quand GVA est exécuté
Alors "Hellpoint.zip" contient "Hellpoint/Hellpoint.exe", "Hellpoint/Hellpoint_Data/level0" et "Hellpoint/saves/"
Et ne contient aucune entrée "@eaDir"
```

### REQ-GVA-007 – Exécutable isolé
Pour chaque fichier `.exe` situé à la racine d'une catégorie, GVA doit créer l'archive `<Catégorie>/<NomSansExtension>.zip`, qui contient l'exécutable à sa racine.
- Vérification : test.
```gherkin
Étant donné le fichier "HnS/Torchlight.exe"
Quand GVA est exécuté
Alors "HnS/Torchlight.zip" existe et contient uniquement "Torchlight.exe"
```

### REQ-GVA-008 – Installeur en plusieurs parties
Quand des fichiers `<NomSansExtension>-<n>.bin` accompagnent un `.exe` à la racine d'une catégorie, GVA doit les inclure dans l'archive de cet exécutable.
- Vérification : test.
```gherkin
Étant donné "HnS/setup_game.exe", "HnS/setup_game-1.bin" et "HnS/setup_game-2.bin"
Quand GVA est exécuté
Alors "HnS/setup_game.zip" contient exactement ces trois fichiers
```

### REQ-GVA-009 – Fichier .bin orphelin
Si un fichier `.bin` à la racine d'une catégorie ne se rattache à aucun `.exe`, alors GVA doit le laisser en place et produire une action `skip` de motif `orphan_bin`.
- Vérification : test.

### REQ-GVA-010 – Nom conservé
Le nom de l'archive doit être le nom de la source à l'identique (casse, espaces, ponctuation, accents), suivi de `.zip`.
- Vérification : test.
```gherkin
Étant donné le dossier "metroid Vania/Alwa's Awakening & Co é"
Quand GVA est exécuté
Alors l'archive "metroid Vania/Alwa's Awakening & Co é.zip" existe
```

### REQ-GVA-011 – Archive cible déjà présente
Si l'archive cible existe déjà, alors GVA doit laisser la source et l'archive inchangées et produire une action `skip` de motif `target_exists`.
- Vérification : test.

### REQ-GVA-012 – Sous-dossier « Archives »
GVA ne doit jamais archiver un sous-dossier nommé `Archives`. Il doit déplacer chaque `.zip` qu'il contient à la racine de la catégorie, puis supprimer `Archives` s'il est vide. Si une archive du même nom existe déjà à la racine, alors GVA doit laisser le fichier en place et produire une action `skip` de motif `archives_conflict`.
- Vérification : test.
```gherkin
Étant donné "Shooters/Archives/Prey.zip" et "Shooters/Archives/Warsow.zip", et "Shooters/Warsow.zip" déjà présent
Quand GVA est exécuté
Alors "Shooters/Prey.zip" existe
Et "Shooters/Archives/Warsow.zip" est toujours présent, avec un résultat "skipped"
```

### REQ-GVA-013 – Dossier vide
Si un dossier source ne contient aucun fichier, alors GVA ne doit pas l'archiver et doit produire une action `skip` de motif `empty`.
- Vérification : test.

### REQ-GVA-014 – Dates antérieures à 1980
GVA doit archiver sans erreur les fichiers dont la date de modification est antérieure au 1er janvier 1980, une date que le format ZIP ne sait pas représenter (jeux DOS).
- Vérification : test.

### REQ-GVA-015 – Grandes archives
GVA doit produire des archives valides au-delà de 4 Go et de 65 535 entrées (ZIP64).
- Vérification : inspection (ZIP64 activé) et test manuel sur `RPG/The council` (17 395 fichiers) et un jeu de plus de 4 Go.

### REQ-GVA-016 – Compression configurable
GVA doit utiliser la méthode `compression` et le niveau `compresslevel` de la configuration. Les valeurs par défaut (`deflated`, 6) sont provisoires (OPEN-3).
- Vérification : test.

## Exigences fonctionnelles – sûreté

### REQ-GVA-017 – Source en cours de modification
Si l'élément le plus récemment modifié d'une source, en parcourant ses fichiers et dossiers, date de moins de `min_age_minutes`, alors GVA doit l'ignorer et produire une action `skip` de motif `recent`. Cela couvre une copie ou un traitement en cours par un autre outil.
- Vérification : test.

### REQ-GVA-018 – Écriture atomique
GVA doit écrire l'archive sous le nom temporaire `<Nom>.zip.gva-part`, dans le dossier de la catégorie, puis la renommer en `<Nom>.zip` une fois vérifiée. Une archive `.zip` incomplète ne doit jamais être visible.
- Vérification : test.

### REQ-GVA-019 – Vérification de l'archive
Avant de renommer une archive, GVA doit vérifier :
- le CRC de toutes ses entrées ;
- que son nombre de fichiers est égal à celui de la source ;
- que la taille totale décompressée est égale à celle de la source.

Si la vérification échoue, alors GVA doit supprimer le fichier temporaire, laisser la source intacte et produire un résultat `error`.
- Vérification : test.

### REQ-GVA-020 – Sort de la source
Quand une archive a été vérifiée puis renommée, GVA doit supprimer la source si `source_after_success = delete`, et la conserver si `source_after_success = keep` (valeur par défaut, OPEN-1).
- Vérification : test.

### REQ-GVA-021 – Espace disque
Si l'espace libre du volume de la catégorie est inférieur à la taille de la source, alors GVA ne doit pas l'archiver et doit produire un résultat `error`.
- Vérification : test.

### REQ-GVA-022 – Résidus d'une exécution interrompue
Au début de chaque exécution, GVA doit supprimer les fichiers `*.zip.gva-part` présents à la racine des catégories configurées.
- Vérification : test.

### REQ-GVA-023 – Échec isolé
Si le traitement d'une source échoue, alors GVA doit poursuivre avec les sources suivantes.
- Vérification : test.

### REQ-GVA-024 – Exécution unique
Si une autre instance détient le verrou `lock_file`, alors GVA doit s'arrêter sans rien modifier, avec le code de sortie 3.
- Vérification : test (Linux).

### REQ-GVA-025 – Simulation
Où l'option `--dry-run` est présente, GVA doit journaliser les actions prévues, avec le statut `dry_run`, sans rien modifier sur le disque.
- Vérification : test.

## Exigences fonctionnelles – exploitation

### REQ-GVA-026 – Journal
GVA doit écrire sur la sortie standard, dans cet ordre :
1. une ligne `<horodatage> | START | run=<run_id> | <contexte>` (REQ-GVA-037) ;
2. une ligne par action, au format `<horodatage> | <kind> | <status> | <Catégorie>/<Nom> | <détail>`, entrecoupée des lignes de progression (REQ-GVA-039) ;
3. une ligne `<horodatage> | END | run=<run_id> | <contexte de fin>` ;
4. une ligne finale `SUMMARY | ok=<n> | skipped=<n> | error=<n> | src=<GiB> | zip=<GiB> | saved=<GiB> | wall=<s>s`.

L'horodatage est au format `AAAA-MM-JJTHH:MM:SS`, en heure locale. Le `<détail>` d'une action est :
- les mesures de REQ-GVA-036 pour une archive réussie ;
- le motif pour une action `skip` ;
- le message d'erreur pour une action en erreur.

`run_id` vaut `AAAAMMJJTHHMMSS-<pid>` et identifie l'exécution dans toutes ses lignes.
- Vérification : test.

### REQ-GVA-027 – Codes de sortie
GVA doit se terminer avec le code :
- `0` si aucune action n'est en erreur ;
- `1` si au moins une action est en erreur ;
- `2` en cas de configuration invalide ou de racine inaccessible ;
- `3` si une autre instance est en cours.
- Vérification : test.

### REQ-GVA-028 – Configuration
GVA doit lire sa configuration dans le fichier INI passé par `--config`. Si le fichier est absent, si une valeur est invalide ou si `root` n'est pas un dossier accessible, alors GVA doit s'arrêter avec le code 2 sans rien modifier.
- Vérification : test.

### REQ-GVA-029 – Idempotence
Une nouvelle exécution sur une arborescence déjà traitée ne doit rien modifier et doit se terminer avec le code 0.
- Vérification : test.

## Exigences fonctionnelles – journalisation et mesures

Objectif : rendre mesurable la limite connue de `zipfile`, qui ne compresse que sur un cœur. Chaque archive doit permettre de répondre à trois questions :
- Combien de place a-t-on gagné ?
- Combien de temps l'archivage a-t-il pris, et dans quelle phase ?
- Le goulot d'étranglement est-il le processeur (un cœur saturé) ou les entrées-sorties (réseau ou NAS) ?

### REQ-GVA-034 – Classification du goulot d'étranglement
GVA doit classer chaque compression à partir du taux d'occupation CPU de la phase de compression, `cpu_use = temps CPU du processus / durée réelle` :
- `cpu` si `cpu_use ≥ 0,85` : un cœur est saturé, et la compression mono-cœur est la limite ;
- `io` si `cpu_use ≤ 0,50` : le processus attend surtout le réseau ou le disque ;
- `mixed` entre les deux.

Si la durée réelle est nulle, alors le résultat est `io`.
- Vérification : test.

### REQ-GVA-035 – Mesures par archive
Pour chaque action `zip_dir` ou `zip_exe` réussie, GVA doit relever les mesures suivantes :

| Mesure | Définition | Unité |
|---|---|---|
| `src_bytes`, `src_files` | taille totale et nombre de fichiers de la source | octets, nombre |
| `zip_bytes` | taille de l'archive finale | octets |
| `ratio` | `zip_bytes / src_bytes` | 0 à 1 |
| `saved_bytes` | `src_bytes − zip_bytes` | octets (peut être négatif) |
| `scan_s`, `compress_s`, `verify_s`, `finalize_s` | durée réelle de chaque phase : inventaire de la source, écriture de l'archive, vérification (REQ-GVA-019), renommage et sort de la source | secondes |
| `wall_s` | durée totale de l'action | secondes |
| `cpu_s` | temps CPU du processus pendant la compression | secondes |
| `cpu_use` | `cpu_s / compress_s` | 0 à 1 |
| `read_mib_s` | `src_bytes / compress_s` | Mio/s |
| `bottleneck` | REQ-GVA-034 | `cpu`, `io` ou `mixed` |
| `max_rss_mib` | pic de mémoire résidente du processus (vide si le système ne le fournit pas) | Mio |
| `compression`, `compresslevel` | réglages utilisés | |

- Vérification : test.

### REQ-GVA-036 – Mesures dans le journal
Le `<détail>` d'une archive réussie doit suivre l'exemple ci-dessous :

`src=8.61GiB zip=7.95GiB ratio=92% saved=0.66GiB wall=812.4s compress=640.2s verify=150.1s cpu=97% read=13.8MiB/s bottleneck=cpu rss=38MiB`

Format des valeurs :
- tailles en Gio, avec deux décimales ;
- durées et débit avec une décimale ;
- `ratio` et `cpu` en pourcentage entier ;
- `rss` en Mio entier, ou `rss=n/a` si la mesure est indisponible.
- Vérification : test.

### REQ-GVA-037 – Contexte d'exécution
Les lignes `START` et `END` doivent indiquer le contexte qui conditionne les mesures. Une valeur indisponible vaut `n/a` et ne provoque jamais d'erreur.
- **`START`** : `host`, `cpu` (modèle et nombre de cœurs), `load` (charge moyenne sur 1 minute), `temp` (°C, lu dans `THERMAL_PATH`), `throttled` (sortie de `vcgencmd get_throttled`), `compression` (`<méthode>/<niveau>`), `python`.
- **`END`** : `temp` et `throttled`, pour savoir si le Pi a été bridé thermiquement pendant l'exécution.

Exemples :
```
2026-10-31T03:00:00 | START | run=20261031T030000-4242 | host=rpi5 | cpu=Cortex-A76 x4 | load=0.12 | temp=48.3 | throttled=0x0 | compression=deflated/6 | python=3.11.2
2026-10-31T05:12:40 | END | run=20261031T030000-4242 | temp=71.9 | throttled=0x0
```
- Vérification : test.
```gherkin
Étant donné un système sans capteur thermique ni vcgencmd
Quand GVA est exécuté
Alors la ligne START contient "temp=n/a" et "throttled=n/a"
Et le code de sortie n'est pas affecté
```

### REQ-GVA-038 – Fichier de mesures
Où `metrics_file` est renseigné, GVA doit ajouter à ce fichier, au format JSON Lines (un objet JSON par ligne, UTF-8) :
- un objet `{"type": "action", "run_id": …}` par action, avec `kind`, `status`, `category`, `name`, `reason`, `detail` et les mesures de REQ-GVA-035 (`null` quand elles ne s'appliquent pas) ;
- en fin d'exécution, un objet `{"type": "run", "run_id": …}` avec :
  - le contexte de début et de fin (REQ-GVA-037) ;
  - `dry_run` ;
  - les compteurs `ok`, `skipped` et `error` ;
  - les totaux `src_bytes`, `zip_bytes` et `wall_s` ;
  - `exit_code`.

Si le fichier ne peut pas être écrit, alors GVA doit journaliser une ligne `WARNING | metrics_file | <message>` et poursuivre, sans modifier le code de sortie. Le fichier est destiné au NAS, hors de la carte SD (REQ-GVA-031).
- Vérification : test.

### REQ-GVA-039 – Progression
Pendant l'écriture d'une archive, GVA doit écrire une ligne de progression, par exemple `2026-10-31T03:05:00 | progress | running | RPG/Hellpoint | 37% 3.19/8.61 GiB 13.6MiB/s eta=408.0s`, chaque fois que `progress_interval_s` secondes se sont écoulées depuis la ligne précédente. La condition est évaluée après chaque fichier archivé. Ces lignes permettent de suivre une archive de plusieurs heures (`Cyberpunk 2077`, 90 Go).
- Vérification : test.

### REQ-GVA-040 – Sélection de sources
Où l'option `--only <Catégorie>/<Nom>` est présente (répétable), GVA ne doit traiter que les sources désignées. Cette option sert notamment aux campagnes de mesure.
- Vérification : test.

## Protocole de mesure de la compression (OPEN-3)

Il s'appuie sur les mesures précédentes. Il est à exécuter sur le Pi, `metrics_file` renseigné, avec trois jeux représentatifs :

| Jeu | Taille | Profil |
|---|---|---|
| `RPG/Dragonsphere` | 0,09 Go, 85 fichiers | jeu DOS, petits fichiers |
| `RPG/Hellpoint` | 8,6 Go, 1 609 fichiers | moteur Unity, gros fichiers de données |
| `RPG/The council` | 22,3 Go, 17 395 fichiers | très nombreux fichiers |

1. Pour chaque jeu, lancer `--only <jeu>` avec successivement :
   - `stored` (aucune compression : donne le **débit plafond du réseau et du NAS**) ;
   - `deflated` niveaux 6 puis 9 ;
   - `bzip2` ;
   - `lzma`.

   Supprimer l'archive produite entre deux essais, la source étant conservée (`keep`).
2. Comparer dans `metrics.jsonl` : `ratio`, `compress_s`, `read_mib_s`, `bottleneck`, et la température en fin d'exécution.
3. Règles de décision :
   - **La compression mono-cœur est la limite** si `bottleneck = cpu` et que `read_mib_s` est inférieur à 50 % du débit `stored`. Dans ce cas, paralléliser entre jeux ou passer à un compresseur multi-cœur est justifié.
   - **Une méthode plus forte vaut le coût** si elle réduit `zip_bytes` d'au moins 5 % par rapport à `deflated` 6, pour une durée totale compatible avec la fenêtre de nuit.
   - **La méthode `lzma` ou `bzip2` doit être lisible par GameVault et son client** : à vérifier avant de la retenir.
   - **Les mesures sont invalides** si `throttled` signale un bridage en fin d'exécution : il faut alors refroidir le Pi et recommencer.

## Exigences non fonctionnelles

### REQ-GVA-030 – Plateforme
GVA doit fonctionner sur Raspberry Pi OS 64 bits (Debian Bookworm ou plus récent), avec Python ≥ 3.11 et uniquement la bibliothèque standard.
- Vérification : inspection et démonstration sur le Pi.

### REQ-GVA-031 – Préservation de la carte SD
GVA ne doit écrire aucun fichier temporaire sur le stockage local du Pi. Les archives temporaires sont écrites sur le NAS (REQ-GVA-018) et le journal part vers la sortie standard.
- Vérification : inspection.

### REQ-GVA-032 – Mémoire bornée
GVA doit écrire les archives en flux, sans charger un fichier entier en mémoire. La mémoire résidente doit rester inférieure à 200 Mo pendant l'archivage de `RPG/Cyberpunk 2077`.
- Vérification : test manuel (`/usr/bin/time -v`).

### REQ-GVA-033 – Planification
GVA doit pouvoir être planifié quotidiennement par `cron`, en basse priorité CPU et disque (`nice`, `ionice`). Le README documente la ligne crontab et le montage du partage.
- Vérification : démonstration.

## Points ouverts

| ID | Question | Hypothèse retenue en attendant |
|---|---|---|
| OPEN-1 | Faut-il supprimer la source après archivage ? | `keep` par défaut ; passer à `delete` après validation des premières archives |
| OPEN-2 | Exclure le dossier `RPG/Cyberpunk 2077`, source probable du zip en cours chez l'autre agent ? | exclu dans la configuration d'exemple |
| OPEN-3 | Méthode et niveau de compression, parallélisme | `deflated` niveau 6 ; à trancher avec le protocole de mesure ci-dessus |
| OPEN-4 | Que faire des dossiers `*_installers` (ex. Bloodstained) ? | traités comme un dossier ordinaire : `…_installers.zip` |
| OPEN-5 | Remonter les zips de `Archives\` à la racine de la catégorie ? | oui (REQ-GVA-012) |
| OPEN-6 | Montage du NAS sur le Pi (SMB ou NFS, point de montage) | `/mnt/nas/PC` |

## Matrice de traçabilité

| Exigence | Test(s) – `tests/test_gamevault_archiver.py` |
|---|---|
| REQ-GVA-001 | `test_gva001_categorie_non_configuree_intacte`, `test_gva001_fichiers_racine_intacts` |
| REQ-GVA-002 | `test_gva002_source_exclue` |
| REQ-GVA-003 | `test_gva003_zip_existant_intact` |
| REQ-GVA-004 | `test_gva004_elements_systeme_ignores`, `test_gva004_fichier_non_gere` |
| REQ-GVA-005 | `test_gva005_dossier_devient_zip` |
| REQ-GVA-006 | `test_gva006_contenu_archive_dossier` |
| REQ-GVA-007 | `test_gva007_exe_isole` |
| REQ-GVA-008 | `test_gva008_installeur_multiparties` |
| REQ-GVA-009 | `test_gva009_bin_orphelin` |
| REQ-GVA-010 | `test_gva010_nom_conserve` |
| REQ-GVA-011 | `test_gva011_cible_existante` |
| REQ-GVA-012 | `test_gva012_archives_remontees`, `test_gva012_archives_conflit` |
| REQ-GVA-013 | `test_gva013_dossier_vide` |
| REQ-GVA-014 | `test_gva014_dates_avant_1980` |
| REQ-GVA-015 | inspection + test manuel |
| REQ-GVA-016 | `test_gva016_compression_configuree` |
| REQ-GVA-017 | `test_gva017_source_recente` |
| REQ-GVA-018 | `test_gva018_aucun_zip_partiel_visible` |
| REQ-GVA-019 | `test_gva019_verification_echouee`, `test_gva019_archive_complete` |
| REQ-GVA-020 | `test_gva020_source_conservee`, `test_gva020_source_supprimee` |
| REQ-GVA-021 | `test_gva021_espace_insuffisant` |
| REQ-GVA-022 | `test_gva022_residus_supprimes` |
| REQ-GVA-023 | `test_gva023_echec_isole` |
| REQ-GVA-024 | `test_gva024_instance_unique` |
| REQ-GVA-025 | `test_gva025_simulation` |
| REQ-GVA-026 | `test_gva026_format_journal` |
| REQ-GVA-027 | `test_gva027_code_erreur`, `test_gva027_code_succes` |
| REQ-GVA-028 | `test_gva028_lecture_configuration`, `test_gva028_configuration_invalide` |
| REQ-GVA-029 | `test_gva029_idempotence` |
| REQ-GVA-030 à 033 | inspection, démonstration, test manuel |
| REQ-GVA-034 | `test_gva034_classification_goulot` |
| REQ-GVA-035 | `test_gva035_mesures_par_archive` |
| REQ-GVA-036 | `test_gva036_mesures_dans_journal` |
| REQ-GVA-037 | `test_gva037_contexte_start_end`, `test_gva037_contexte_indisponible` |
| REQ-GVA-038 | `test_gva038_fichier_mesures`, `test_gva038_fichier_mesures_inaccessible` |
| REQ-GVA-039 | `test_gva039_progression` |
| REQ-GVA-040 | `test_gva040_selection_sources` |
