import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "acceptance-1.1.yml"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")


class AcceptanceStagingTrustQATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding="utf-8")

    def test_manual_candidate_is_bound_to_canonical_or_frozen_identity(self):
        self.assertIn("workflow_dispatch:", self.text)
        self.assertIn("candidate_sha:", self.text)
        self.assertIn(
            'test "$(git rev-parse HEAD)" = "$CANDIDATE_SHA"',
            self.text,
            "acceptance identity check changed; re-evaluate this QA fixture",
        )
        binding_markers = (
            "refs/heads/1.1.x",
            "refs/remotes/origin/1.1.x",
            "GATE_FROZEN_SHA",
            "gate-frozen",
        )
        self.assertTrue(
            any(marker in self.text for marker in binding_markers),
            "manual candidate SHA is only self-verified and is not bound to canonical/GATE-FROZEN identity",
        )

    def test_security_sensitive_actions_are_pinned_to_full_commit_shas(self):
        mutable = []
        for line in self.text.splitlines():
            stripped = line.strip()
            if not stripped.startswith("- uses: actions/"):
                continue
            action_ref = stripped.removeprefix("- uses: ")
            action, _, ref = action_ref.partition("@")
            if not ref or not FULL_SHA.fullmatch(ref):
                mutable.append(action_ref)
        self.assertEqual(
            [],
            mutable,
            f"mutable GitHub Action refs remain in secrets-bearing acceptance path: {mutable}",
        )

    def test_checkout_credentials_are_not_persisted(self):
        checkout_count = self.text.count("uses: actions/checkout@")
        self.assertGreater(checkout_count, 0)
        hardened_count = self.text.count("persist-credentials: false")
        self.assertGreaterEqual(
            hardened_count,
            checkout_count,
            "every checkout in acceptance path must disable persisted GitHub credentials",
        )


if __name__ == "__main__":
    unittest.main()
