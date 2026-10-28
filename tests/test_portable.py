"""Exercise portable skill installation without calling a model provider."""

import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("on_loop_export", str(ROOT / "bin/on-loop-export"))
spec = importlib.util.spec_from_loader(loader.name, loader)
exporter = importlib.util.module_from_spec(spec)
loader.exec_module(exporter)


class PortableSkillsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)

    def test_each_host_gets_all_workflows_and_self_contained_context(self):
        for tool, relative in exporter.SKILL_PATHS.items():
            with self.subTest(tool=tool):
                project = self.project / tool
                skills, count, written = exporter.export(tool, project)
                self.assertEqual(skills, project / relative)
                self.assertEqual(count, 22)
                self.assertGreater(written, count)
                self.assertEqual(len(list(skills.glob("*/SKILL.md"))), count)
                for skill in skills.iterdir():
                    fields, body = exporter.split_document(skill / "SKILL.md")
                    self.assertEqual(fields["name"], skill.name)
                    self.assertIn("Portable runtime rules", body)
                    self.assertTrue((skill / "references/agents/coding.md").is_file())
                    self.assertTrue((skill / "references/commands/on-loop.md").is_file())
                    self.assertTrue((skill / "references/skills/quality-gate/SKILL.md").is_file())
                    self.assertTrue((skill / "references/shared/AGENT_PERSONA.md").is_file())
                    self.assertTrue((skill / "LICENSE").is_file())
                workflow = (skills / "on-test/SKILL.md").read_text()
                self.assertIn("Standalone test generation", workflow)
                self.assertIn("Generate a session name", workflow)

    def test_export_uses_host_models_and_preserves_role_limits(self):
        skills, _, _ = exporter.export("codex", self.project)
        for path in skills.rglob("*.md"):
            text = path.read_text()
            self.assertNotIn("model: opus", text)
            self.assertNotIn("model: sonnet", text)
            self.assertNotIn("Co-Authored-By: Claude", text)
        reviewer = (skills / "on-review/references/agents/reviewer.md").read_text()
        self.assertIn("do NOT modify", reviewer)
        runtime = (skills / "on-loop/SKILL.md").read_text()
        self.assertIn("perform the roles sequentially", runtime)
        self.assertIn("Use the model and provider selected in the host", runtime)

    def test_repeated_export_leaves_existing_files_unchanged(self):
        skills, _, _ = exporter.export("codex", self.project)
        skill = skills / "on-loop/SKILL.md"
        before = skill.stat().st_mtime_ns
        _, count, written = exporter.export("codex", self.project)
        self.assertEqual((count, written), (22, 0))
        self.assertEqual(skill.stat().st_mtime_ns, before)

    def test_conflict_is_reported_before_any_files_are_written(self):
        conflict = self.project / ".agents/skills/on-test/SKILL.md"
        conflict.parent.mkdir(parents=True)
        conflict.write_text("User's existing skill\n")
        with self.assertRaisesRegex(ValueError, "Existing file differs"):
            exporter.export("codex", self.project)
        self.assertEqual(conflict.read_text(), "User's existing skill\n")
        self.assertFalse((self.project / ".agents/skills/on-loop").exists())

    def test_symlinked_directories_are_not_followed(self):
        outside = self.project / "outside"
        outside.mkdir()
        (self.project / ".agents").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            exporter.export("codex", self.project)
        self.assertEqual(list(outside.iterdir()), [])

    def test_file_where_directory_is_expected_is_preserved(self):
        conflict = self.project / ".agents"
        conflict.write_text("keep me")
        with self.assertRaisesRegex(ValueError, "Expected directory"):
            exporter.export("codex", self.project)
        self.assertEqual(conflict.read_text(), "keep me")

    def test_cli_rejects_unknown_tool_and_requires_destination(self):
        for arguments in (["--tool", "unknown"], ["--tool", "codex"]):
            result = subprocess.run(
                [sys.executable, str(ROOT / "bin/on-loop-export"), *arguments],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertFalse((self.project / ".agents").exists())


if __name__ == "__main__":
    unittest.main()
