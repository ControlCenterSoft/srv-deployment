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

    def test_manual_candidate_is_bound_to_canonical_gate_frozen_identity(self):
        self.assertIn("workflow_dispatch:", self.text)
        self.assertIn("candidate_sha:", self.text)
        self.assertIn('CANONICAL_REF: refs/remotes/origin/1.1.x', self.text)
        self.assertIn('GATE_FROZEN_SHA="$(git rev-parse "$CANONICAL_REF")"', self.text)
        self.assertIn('test "$GATE_FROZEN_SHA" = "$CANDIDATE_SHA"', self.text)
        self.assertIn('test "$(git rev-parse HEAD)" = "$CANDIDATE_SHA"', self.text)

    def test_frozen_identity_is_rechecked_before_secret_bearing_stages(self):
        package_recheck = self.text.index("Recheck GATE-FROZEN identity before secrets")
        package_secrets = self.text.index("Detect remote staging configuration")
        remote_recheck = self.text.index("Recheck GATE-FROZEN identity before SSH secrets")
        remote_secrets = self.text.index("Configure pinned SSH transport")
        self.assertLess(package_recheck, package_secrets)
        self.assertLess(remote_recheck, remote_secrets)
        self.assertGreaterEqual(
            self.text.count('test "$GATE_FROZEN_SHA" = "$CANDIDATE_SHA"'),
            3,
            "canonical identity must be checked at validation and again before both secret-bearing stages",
        )

    def test_security_sensitive_actions_are_pinned_to_full_commit_shas(self):
        mutable = []
        for line in self.text.splitlines():
            stripped = line.strip()
            if not stripped.startswith("- uses: actions/"):
                continue
            action_ref = stripped.removeprefix("- uses: ")
            _, _, ref = action_ref.partition("@")
            if not ref or not FULL_SHA.fullmatch(ref):
                mutable.append(action_ref)
        self.assertEqual(
            [],
            mutable,
            f"mutable GitHub Action refs remain in secrets-bearing acceptance path: {mutable}",
        )

    def test_checkout_credentials_are_not_persisted(self):
        checkout_count = self.text.count("uses: actions/checkout@")
        self.assertEqual(6, checkout_count, "checkout topology changed; re-evaluate trust fixture")
        hardened_count = self.text.count("persist-credentials: false")
        self.assertGreaterEqual(
            hardened_count,
            checkout_count,
            "every checkout in acceptance path must disable persisted GitHub credentials",
        )


if __name__ == "__main__":
    unittest.main()
