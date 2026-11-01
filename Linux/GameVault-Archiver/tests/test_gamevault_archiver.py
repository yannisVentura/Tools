"""Tests de GameVault Archiver, traçés vers docs/SPECIFICATIONS.md (REQ-GVA-xxx).

Exécution (bibliothèque standard uniquement) :
    python3 -m unittest discover -s tests -v
"""

import contextlib
import io
import json
import os
import re
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gamevault_archiver as gva  # noqa: E402

OLD = time.time() - 7 * 24 * 3600   # assez ancien pour passer min_age_minutes
DATE_1975 = 157_766_400             # 01/01/1975, antérieur à l'époque ZIP


def build(base, tree):
    """Crée une arborescence : {nom: contenu str | dict (dossier)}."""
    base.mkdir(parents=True, exist_ok=True)
    for name, content in tree.items():
        path = base / name
        if isinstance(content, dict):
            build(path, content)
        else:
            path.write_text(content, encoding="utf-8")


def age(path, when=OLD):
    """Vieillit récursivement path (fichiers puis dossiers) à la date when."""
    for dirpath, dirnames, filenames in os.walk(path, topdown=False):
        for name in filenames + dirnames:
            os.utime(Path(dirpath) / name, (when, when))
    os.utime(path, (when, when))


def snapshot(path):
    """Empreinte (chemin relatif -> (taille, mtime) ou None) d'une arborescence."""
    result = {}
    for p in sorted(path.rglob("*")):
        rel = p.relative_to(path).as_posix()
        result[rel] = None if p.is_dir() else (p.stat().st_size, p.stat().st_mtime)
    return result


class ArchiverTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.root = self.tmp / "PC"
        self.root.mkdir()

    def tearDown(self):
        self._tmp.cleanup()

    def config(self, **overrides):
        values = dict(
            root=self.root,
            categories=("RPG", "HnS", "Shooters", "Strat", "metroid Vania"),
            lock_file=self.tmp / "gva.lock",
        )
        values.update(overrides)
        return gva.Config(**values)

    def run_gva(self, dry_run=False, **overrides):
        cfg = self.config(**overrides)
        age(self.root)
        return gva.execute(gva.plan(cfg), cfg, dry_run=dry_run)

    def write_config(self, extra=""):
        path = self.tmp / "gva.ini"
        path.write_text(
            "[archiver]\n"
            f"root = {self.root}\n"
            "categories =\n    RPG\n    HnS\n"
            f"lock_file = {self.tmp / 'gva.lock'}\n" + extra,
            encoding="utf-8",
        )
        return path

    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = gva.main(list(args))
        return code, out.getvalue()

    @staticmethod
    def by_name(results, name):
        matches = [r for r in results if r.action.name == name]
        assert len(matches) == 1, f"{name}: {len(matches)} résultat(s)"
        return matches[0]

    @staticmethod
    def entries(archive):
        with zipfile.ZipFile(archive) as zf:
            return sorted(zf.namelist())


# --- Périmètre -------------------------------------------------------------


class TestPerimetre(ArchiverTestCase):
    def test_gva001_categorie_non_configuree_intacte(self):
        build(self.root, {"A tester": {"Jeu": {"jeu.exe": "x"}, "Osmos.exe": "x"},
                          "RPG": {}})
        age(self.root)
        before = snapshot(self.root / "A tester")
        self.run_gva()
        self.assertEqual(snapshot(self.root / "A tester"), before)

    def test_gva001_fichiers_racine_intacts(self):
        build(self.root, {"rename_zips.ps1": "x", "Figment.zip": "x", "RPG": {}})
        self.run_gva()
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ["Figment.zip", "RPG", "rename_zips.ps1"])

    def test_gva002_source_exclue(self):
        build(self.root, {"RPG": {"Cyberpunk 2077": {"game.exe": "x"}}})
        results = self.run_gva(exclude=("RPG/Cyberpunk 2077",))
        self.assertEqual(results, [])
        self.assertTrue((self.root / "RPG/Cyberpunk 2077/game.exe").exists())
        self.assertFalse((self.root / "RPG/Cyberpunk 2077.zip").exists())

    def test_gva003_zip_existant_intact(self):
        build(self.root, {"RPG": {}})
        existing = self.root / "RPG/Cyberpunk 2077 + DLC.zip"
        with zipfile.ZipFile(existing, "w") as zf:
            zf.writestr("a.txt", "contenu")
        age(self.root)
        before = (existing.read_bytes(), existing.stat().st_mtime)
        self.run_gva()
        self.assertEqual((existing.read_bytes(), existing.stat().st_mtime), before)

    def test_gva004_elements_systeme_ignores(self):
        build(self.root, {"RPG": {"@eaDir": {"t": "x"}, "#recycle": {"t": "x"},
                                  ".DS_Store": "x"}})
        results = self.run_gva()
        self.assertEqual(results, [])
        self.assertEqual(sorted(p.name for p in (self.root / "RPG").iterdir()),
                         ["#recycle", ".DS_Store", "@eaDir"])

    def test_gva004_fichier_non_gere(self):
        build(self.root, {"RPG": {"notes.txt": "x"}})
        result = self.by_name(self.run_gva(), "notes.txt")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "unsupported")
        self.assertTrue((self.root / "RPG/notes.txt").exists())


# --- Archivage -------------------------------------------------------------


class TestArchivage(ArchiverTestCase):
    def test_gva005_dossier_devient_zip(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}})
        result = self.by_name(self.run_gva(), "Hellpoint")
        self.assertEqual(result.status, "ok")
        self.assertEqual(result.action.kind, "zip_dir")
        self.assertTrue((self.root / "RPG/Hellpoint.zip").is_file())

    def test_gva006_contenu_archive_dossier(self):
        build(self.root, {"RPG": {"Hellpoint": {
            "Hellpoint.exe": "exe",
            "Hellpoint_Data": {"level0": "data"},
            "saves": {},
            "@eaDir": {"thumb": "x"},
        }}})
        self.run_gva()
        self.assertEqual(self.entries(self.root / "RPG/Hellpoint.zip"), [
            "Hellpoint/Hellpoint.exe",
            "Hellpoint/Hellpoint_Data/level0",
            "Hellpoint/saves/",
        ])

    def test_gva007_exe_isole(self):
        build(self.root, {"HnS": {"Torchlight.exe": "exe"}})
        result = self.by_name(self.run_gva(), "Torchlight.exe")
        self.assertEqual(result.action.kind, "zip_exe")
        self.assertEqual(self.entries(self.root / "HnS/Torchlight.zip"), ["Torchlight.exe"])

    def test_gva008_installeur_multiparties(self):
        build(self.root, {"HnS": {"setup_game.exe": "e", "setup_game-1.bin": "1",
                                  "setup_game-2.bin": "2"}})
        self.run_gva()
        self.assertEqual(self.entries(self.root / "HnS/setup_game.zip"),
                         ["setup_game-1.bin", "setup_game-2.bin", "setup_game.exe"])

    def test_gva009_bin_orphelin(self):
        build(self.root, {"HnS": {"lonely-1.bin": "x"}})
        result = self.by_name(self.run_gva(), "lonely-1.bin")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "orphan_bin")
        self.assertTrue((self.root / "HnS/lonely-1.bin").exists())

    def test_gva010_nom_conserve(self):
        name = "Alwa's Awakening & Co é"
        build(self.root, {"metroid Vania": {name: {"game.exe": "x"}}})
        self.run_gva()
        self.assertTrue((self.root / "metroid Vania" / f"{name}.zip").is_file())

    def test_gva011_cible_existante(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"},
                                  "Hellpoint.zip": "ancien"}})
        result = self.by_name(self.run_gva(), "Hellpoint")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "target_exists")
        self.assertEqual((self.root / "RPG/Hellpoint.zip").read_text(encoding="utf-8"), "ancien")
        self.assertTrue((self.root / "RPG/Hellpoint/Hellpoint.exe").exists())

    def test_gva012_archives_remontees(self):
        build(self.root, {"Shooters": {"Archives": {"Prey.zip": "zip"}}})
        result = self.by_name(self.run_gva(), "Prey.zip")
        self.assertEqual((result.action.kind, result.status), ("move_zip", "ok"))
        self.assertEqual((self.root / "Shooters/Prey.zip").read_text(encoding="utf-8"), "zip")
        self.assertFalse((self.root / "Shooters/Archives").exists())
        self.assertFalse((self.root / "Shooters/Archives.zip").exists())

    def test_gva012_archives_conflit(self):
        build(self.root, {"Shooters": {"Archives": {"Warsow.zip": "nouveau"},
                                       "Warsow.zip": "existant"}})
        result = self.by_name(self.run_gva(), "Warsow.zip")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "archives_conflict")
        self.assertEqual((self.root / "Shooters/Warsow.zip").read_text(encoding="utf-8"), "existant")
        self.assertTrue((self.root / "Shooters/Archives/Warsow.zip").exists())

    def test_gva013_dossier_vide(self):
        build(self.root, {"RPG": {"Vide": {"sous-dossier": {}}}})
        result = self.by_name(self.run_gva(), "Vide")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "empty")
        self.assertFalse((self.root / "RPG/Vide.zip").exists())

    def test_gva014_dates_avant_1980(self):
        build(self.root, {"RPG": {"Ultima 4": {"ULTIMA.EXE": "dos"}}})
        cfg = self.config()
        age(self.root)
        os.utime(self.root / "RPG/Ultima 4/ULTIMA.EXE", (DATE_1975, DATE_1975))
        result = self.by_name(gva.execute(gva.plan(cfg), cfg), "Ultima 4")
        self.assertEqual(result.status, "ok")
        self.assertEqual(self.entries(self.root / "RPG/Ultima 4.zip"), ["Ultima 4/ULTIMA.EXE"])

    def test_gva016_compression_configuree(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x" * 1000}}})
        self.run_gva(compression="lzma", compresslevel=None)
        with zipfile.ZipFile(self.root / "RPG/Hellpoint.zip") as zf:
            self.assertEqual(zf.getinfo("Hellpoint/Hellpoint.exe").compress_type,
                             zipfile.ZIP_LZMA)


# --- Sûreté ----------------------------------------------------------------


class TestSurete(ArchiverTestCase):
    def test_gva017_source_recente(self):
        build(self.root, {"RPG": {"Copie en cours": {"data": {"part1": "x"}}}})
        cfg = self.config(min_age_minutes=60)
        age(self.root)
        os.utime(self.root / "RPG/Copie en cours/data/part1", None)  # maintenant
        result = self.by_name(gva.execute(gva.plan(cfg), cfg), "Copie en cours")
        self.assertEqual(result.status, "skipped")
        self.assertEqual(result.action.reason, "recent")
        self.assertFalse((self.root / "RPG/Copie en cours.zip").exists())

    def test_gva018_aucun_zip_partiel_visible(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}})
        seen = []

        def spy(archive, action):
            seen.append((Path(archive).name, sorted(p.name for p in (self.root / "RPG").iterdir())))
            return True

        with mock.patch.object(gva, "verify_archive", side_effect=spy):
            self.run_gva()
        archive_name, listing = seen[0]
        self.assertEqual(archive_name, "Hellpoint.zip.gva-part")
        self.assertNotIn("Hellpoint.zip", listing)
        self.assertTrue((self.root / "RPG/Hellpoint.zip").is_file())

    def test_gva019_verification_echouee(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}})
        with mock.patch.object(gva, "verify_archive", return_value=False):
            result = self.by_name(self.run_gva(source_after_success="delete"), "Hellpoint")
        self.assertEqual(result.status, "error")
        self.assertEqual(sorted(p.name for p in (self.root / "RPG").iterdir()), ["Hellpoint"])
        self.assertTrue((self.root / "RPG/Hellpoint/Hellpoint.exe").exists())

    def test_gva019_archive_complete(self):
        build(self.root, {"RPG": {"Jeu": {"a.bin": "a" * 10, "sub": {"b.dat": "b" * 20}}}})
        self.run_gva()
        with zipfile.ZipFile(self.root / "RPG/Jeu.zip") as zf:
            self.assertIsNone(zf.testzip())
            files = [i for i in zf.infolist() if not i.is_dir()]
        self.assertEqual(len(files), 2)
        self.assertEqual(sum(i.file_size for i in files), 30)

    def test_gva020_source_conservee(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}})
        self.run_gva(source_after_success="keep")
        self.assertTrue((self.root / "RPG/Hellpoint.zip").is_file())
        self.assertTrue((self.root / "RPG/Hellpoint/Hellpoint.exe").exists())

    def test_gva020_source_supprimee(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}},
                          "HnS": {"setup_game.exe": "e", "setup_game-1.bin": "1"}})
        self.run_gva(source_after_success="delete")
        self.assertEqual([p.name for p in (self.root / "RPG").iterdir()], ["Hellpoint.zip"])
        self.assertEqual([p.name for p in (self.root / "HnS").iterdir()], ["setup_game.zip"])

    def test_gva021_espace_insuffisant(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x" * 100}}})
        full = mock.Mock(total=1000, used=1000, free=0)
        with mock.patch.object(gva.shutil, "disk_usage", return_value=full):
            result = self.by_name(self.run_gva(), "Hellpoint")
        self.assertEqual(result.status, "error")
        self.assertFalse((self.root / "RPG/Hellpoint.zip").exists())

    def test_gva022_residus_supprimes(self):
        build(self.root, {"RPG": {"Ancien.zip.gva-part": "partiel"}})
        self.run_gva()
        self.assertFalse((self.root / "RPG/Ancien.zip.gva-part").exists())

    def test_gva023_echec_isole(self):
        build(self.root, {"RPG": {"A": {"a.exe": "a"}, "B": {"b.exe": "b"}}})
        verify = lambda archive, action: action.name != "A"  # noqa: E731
        with mock.patch.object(gva, "verify_archive", side_effect=verify):
            results = self.run_gva()
        self.assertEqual(self.by_name(results, "A").status, "error")
        self.assertEqual(self.by_name(results, "B").status, "ok")
        self.assertTrue((self.root / "RPG/B.zip").is_file())

    @unittest.skipUnless(sys.platform.startswith("linux"), "verrou fcntl : Linux uniquement")
    def test_gva024_instance_unique(self):
        import fcntl
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}, "HnS": {}})
        age(self.root)
        config = self.write_config()
        with open(self.tmp / "gva.lock", "w") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            code, _ = self.run_main("--config", str(config))
        self.assertEqual(code, 3)
        self.assertFalse((self.root / "RPG/Hellpoint.zip").exists())

    def test_gva025_simulation(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}},
                          "HnS": {"Torchlight.exe": "x"},
                          "Shooters": {"Archives": {"Prey.zip": "z"}}})
        age(self.root)
        before = snapshot(self.root)
        results = self.run_gva(dry_run=True)
        self.assertEqual({r.status for r in results}, {"dry_run"})
        self.assertEqual(len(results), 3)
        self.assertEqual(snapshot(self.root), before)


# --- Exploitation ----------------------------------------------------------


class TestExploitation(ArchiverTestCase):
    LINE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \| (zip_dir|zip_exe|move_zip|skip)"
                      r" \| (ok|skipped|error|dry_run) \| [^|]+/[^|]+ \| .*$")
    SUMMARY = (r"^SUMMARY \| ok={ok} \| skipped={skipped} \| error={error}"
               r" \| src=\d+\.\d\dGiB \| zip=\d+\.\d\dGiB \| saved=-?\d+\.\d\dGiB \| wall=\d+(\.\d+)?s$")

    def test_gva026_format_journal(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}, "notes.txt": "x"},
                          "HnS": {}})
        age(self.root)
        _, out = self.run_main("--config", str(self.write_config()))
        lines = out.strip().splitlines()
        self.assertEqual(len(lines), 5)
        self.assertRegex(lines[0], r"^\S+ \| START \| run=")
        for line in lines[1:3]:
            self.assertRegex(line, self.LINE)
        self.assertRegex(lines[3], r"^\S+ \| END \| run=")
        self.assertRegex(lines[4], self.SUMMARY.format(ok=1, skipped=1, error=0))

    def test_gva027_code_succes(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}, "HnS": {}})
        age(self.root)
        code, _ = self.run_main("--config", str(self.write_config()))
        self.assertEqual(code, 0)

    def test_gva027_code_erreur(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}, "HnS": {}})
        age(self.root)
        with mock.patch.object(gva, "verify_archive", return_value=False):
            code, _ = self.run_main("--config", str(self.write_config()))
        self.assertEqual(code, 1)

    def test_gva028_lecture_configuration(self):
        path = self.write_config(
            "exclude =\n    RPG/Cyberpunk 2077\n"
            "min_age_minutes = 30\nsource_after_success = delete\n"
            "compression = lzma\n")
        cfg = gva.load_config(path)
        self.assertEqual(cfg.root, self.root)
        self.assertEqual(cfg.categories, ("RPG", "HnS"))
        self.assertEqual(cfg.exclude, ("RPG/Cyberpunk 2077",))
        self.assertEqual(cfg.min_age_minutes, 30)
        self.assertEqual(cfg.source_after_success, "delete")
        self.assertEqual(cfg.compression, "lzma")

    def test_gva028_configuration_invalide(self):
        cases = {
            "fichier absent": self.tmp / "absent.ini",
            "valeur invalide": self.write_config("source_after_success = purge\n"),
        }
        for label, path in cases.items():
            with self.subTest(label):
                code, _ = self.run_main("--config", str(path))
                self.assertEqual(code, 2)
        with self.subTest("racine inaccessible"):
            self.root.rmdir()
            code, _ = self.run_main("--config", str(self.write_config()))
            self.assertEqual(code, 2)

    def test_gva029_idempotence(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}},
                          "HnS": {"Torchlight.exe": "x"}})
        age(self.root)
        config = self.write_config("source_after_success = delete\n")
        self.run_main("--config", str(config))
        age(self.root)
        before = snapshot(self.root)
        code, out = self.run_main("--config", str(config))
        self.assertEqual(code, 0)
        self.assertEqual(snapshot(self.root), before)
        lines = out.strip().splitlines()
        self.assertEqual([l.split(" | ")[1] for l in lines[:-1]], ["START", "END"])
        self.assertRegex(lines[-1], self.SUMMARY.format(ok=0, skipped=0, error=0))


# --- Journalisation et mesures ---------------------------------------------


class TestMesures(ArchiverTestCase):
    DETAIL = re.compile(
        r"src=\d+\.\d\dGiB zip=\d+\.\d\dGiB ratio=\d+% saved=-?\d+\.\d\dGiB"
        r" wall=\d+\.\ds compress=\d+\.\ds verify=\d+\.\ds cpu=\d+% read=\d+\.\dMiB/s"
        r" bottleneck=(cpu|io|mixed) rss=(\d+MiB|n/a)$")

    def test_gva034_classification_goulot(self):
        cases = [(9.0, 10.0, "cpu"), (8.5, 10.0, "cpu"), (8.4, 10.0, "mixed"),
                 (5.1, 10.0, "mixed"), (5.0, 10.0, "io"), (1.0, 10.0, "io"),
                 (0.0, 0.0, "io")]
        for cpu_s, wall_s, expected in cases:
            with self.subTest(cpu_s=cpu_s, wall_s=wall_s):
                self.assertEqual(gva.classify_bottleneck(cpu_s, wall_s), expected)

    def test_gva035_mesures_par_archive(self):
        build(self.root, {"RPG": {"Jeu": {"a.bin": "a" * 1000, "sub": {"b.dat": "b" * 2000}}}})
        m = self.by_name(self.run_gva(), "Jeu").metrics
        zip_size = (self.root / "RPG/Jeu.zip").stat().st_size
        self.assertEqual((m["src_bytes"], m["src_files"], m["zip_bytes"]), (3000, 2, zip_size))
        self.assertAlmostEqual(m["ratio"], zip_size / 3000, places=3)
        self.assertEqual(m["saved_bytes"], 3000 - zip_size)
        for key in ("scan_s", "compress_s", "verify_s", "finalize_s", "wall_s", "cpu_s", "read_mib_s"):
            self.assertGreaterEqual(m[key], 0, key)
        phases = m["scan_s"] + m["compress_s"] + m["verify_s"] + m["finalize_s"]
        self.assertLessEqual(phases, m["wall_s"] + 0.01)
        self.assertGreaterEqual(m["cpu_use"], 0)
        self.assertIn(m["bottleneck"], {"cpu", "io", "mixed"})
        self.assertIn("max_rss_mib", m)
        self.assertEqual((m["compression"], m["compresslevel"]), ("deflated", 6))

    def test_gva036_mesures_dans_journal(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x" * 5000}}, "HnS": {}})
        age(self.root)
        _, out = self.run_main("--config", str(self.write_config()))
        line = next(l for l in out.splitlines() if "| RPG/Hellpoint |" in l)
        self.assertRegex(line.split(" | ")[-1], self.DETAIL)

    def test_gva037_contexte_start_end(self):
        build(self.root, {"RPG": {}, "HnS": {}})
        _, out = self.run_main("--config", str(self.write_config()))
        lines = out.splitlines()
        start = re.match(r"^\S+ \| START \| run=(\d{8}T\d{6}-\d+) \| host=.+ \| cpu=.+ x\d+"
                         r" \| load=\S+ \| temp=\S+ \| throttled=\S+ \| compression=deflated/6"
                         r" \| python=\d+\.\d+\.\d+$", lines[0])
        self.assertIsNotNone(start, lines[0])
        end = next(l for l in lines if " | END | " in l)
        self.assertRegex(end, rf"^\S+ \| END \| run={re.escape(start.group(1))}"
                              r" \| temp=\S+ \| throttled=\S+$")

    def test_gva037_contexte_indisponible(self):
        build(self.root, {"RPG": {}, "HnS": {}})
        with mock.patch.object(gva, "THERMAL_PATH", self.tmp / "absent"), \
                mock.patch.object(gva.shutil, "which", return_value=None):
            code, out = self.run_main("--config", str(self.write_config()))
        self.assertEqual(code, 0)
        self.assertIn("| temp=n/a |", out.splitlines()[0])
        self.assertIn("| throttled=n/a |", out.splitlines()[0])

    def test_gva038_fichier_mesures(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}, "notes.txt": "x"},
                          "HnS": {}})
        age(self.root)
        metrics = self.tmp / "metrics.jsonl"
        self.run_main("--config", str(self.write_config(f"metrics_file = {metrics}\n")))
        records = [json.loads(l) for l in metrics.read_text(encoding="utf-8").splitlines()]
        self.assertEqual([r["type"] for r in records], ["action", "action", "run"])
        self.assertEqual(len({r["run_id"] for r in records}), 1)
        actions = {r["name"]: r for r in records[:-1]}
        self.assertEqual(actions["Hellpoint"]["status"], "ok")
        self.assertIsInstance(actions["Hellpoint"]["src_bytes"], int)
        self.assertIsNone(actions["notes.txt"]["zip_bytes"])
        self.assertEqual(actions["notes.txt"]["reason"], "unsupported")
        run = records[-1]
        self.assertEqual((run["ok"], run["skipped"], run["error"], run["exit_code"]), (1, 1, 0, 0))
        self.assertFalse(run["dry_run"])
        for key in ("src_bytes", "zip_bytes", "wall_s", "temp_start_c", "temp_end_c",
                    "throttled_start", "throttled_end"):
            self.assertIn(key, run)

    def test_gva038_fichier_mesures_inaccessible(self):
        build(self.root, {"RPG": {"Hellpoint": {"Hellpoint.exe": "x"}}, "HnS": {}})
        age(self.root)
        code, out = self.run_main("--config", str(self.write_config(f"metrics_file = {self.tmp}\n")))
        self.assertEqual(code, 0)
        self.assertRegex(out, r"(?m)^WARNING \| metrics_file \| .+$")
        self.assertTrue((self.root / "RPG/Hellpoint.zip").is_file())

    def test_gva039_progression(self):
        build(self.root, {"RPG": {"Jeu": {"a": "a" * 100, "b": "b" * 100, "c": "c" * 100}}})
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.run_gva(progress_interval_s=0)
        progress = [l for l in out.getvalue().splitlines() if " | progress | " in l]
        self.assertGreaterEqual(len(progress), 1)
        for line in progress:
            self.assertRegex(line, r"^\S+ \| progress \| running \| RPG/Jeu \| \d+%"
                                   r" \d+\.\d\d/\d+\.\d\d GiB \d+\.\dMiB/s eta=\d+\.\ds$")

    def test_gva040_selection_sources(self):
        build(self.root, {"RPG": {"A": {"a.exe": "a"}, "B": {"b.exe": "b"}}, "HnS": {}})
        age(self.root)
        code, _ = self.run_main("--config", str(self.write_config()), "--only", "RPG/A")
        self.assertEqual(code, 0)
        self.assertTrue((self.root / "RPG/A.zip").is_file())
        self.assertFalse((self.root / "RPG/B.zip").exists())


if __name__ == "__main__":
    unittest.main()
