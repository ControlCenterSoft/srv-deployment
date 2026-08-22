import pathlib
import re
import unittest

from scripts import perplexity_routine


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "perplexity-routine.yml"


class PerplexityRoutineTests(unittest.TestCase):
    def test_prompt_bounds_task_and_enforces_advisory_scope(self):
        task = "x" * (perplexity_routine.MAX_TASK_CHARS + 10)
        prompt = perplexity_routine.build_prompt(task, "o/r", "issue #1", "sonar-pro")
        self.assertIn("<UNTRUSTED_TASK_CONTEXT>", prompt)
        self.assertIn("OUT_OF_SCOPE", prompt)
        self.assertIn("advisory", prompt.lower())
        self.assertIn("truncated", prompt)
        self.assertNotIn("x" * (perplexity_routine.MAX_TASK_CHARS + 1), prompt)

    def test_detects_common_secret_shapes_without_committing_secret_like_literals(self):
        samples = (
            "-----BEGIN " + "PRIVATE KEY-----",
            "github" + "_pat_" + "a" * 32,
            "gh" + "p_" + "a" * 32,
            "s" + "k-" + "a" * 24,
            "AK" + "IA" + "A" * 16,
            "Bearer " + "a" * 24,
        )
        for sample in samples:
            with self.subTest(sample=sample[:8]):
                self.assertTrue(perplexity_routine.contains_potential_secret(sample))

    def test_normal_routine_task_does_not_match_secret_guard(self):
        self.assertFalse(
            perplexity_routine.contains_potential_secret(
                "Check systemd-resolved compatibility and propose negative tests."
            )
        )

    def test_render_markdown_is_explicitly_advisory(self):
        rendered = perplexity_routine.render_markdown(
            "## Status\nREADY\n\n## Result\nChecked.",
            "sonar-pro",
            [{"title": "Docs", "url": "https://example.com", "date": "2026-08-21"}],
            {"total_tokens": 20},
        )
        self.assertIn("Perplexity routine engineer", rendered)
        self.assertIn("[Docs](https://example.com)", rendered)
        self.assertIn("advisory", rendered.lower())
        self.assertIn("Security", rendered)
        self.assertIn("Integrator", rendered)

    def test_workflow_keeps_issue_activation_in_default_branch_dispatcher(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("workflow_call:", text)
        self.assertIn("workflow_dispatch:", text)
        self.assertNotRegex(text, re.compile(r"(?m)^\s{2}issues:\s*$"))
        self.assertIn("Validate immutable implementation ref", text)
        self.assertIn("^[0-9a-f]{40}$", text)
        self.assertIn("persist-credentials: false", text)


if __name__ == "__main__":
    unittest.main()
