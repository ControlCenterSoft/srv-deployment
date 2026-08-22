import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROTECTED = ROOT / ".github" / "workflows" / "acceptance-1.1-protected.yml"


class ProtectedAcceptanceControlPlaneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = PROTECTED.read_text(encoding="utf-8")

    def test_reusable_only_no_direct_dispatch(self):
        self.assertIn("workflow_call:", self.text)
        self.assertNotIn("workflow_dispatch:", self.text)

    def test_reuses_reviewed_deterministic_acceptance_without_secret_inherit(self):
        self.assertIn(
            "uses: ControlCenterSoft/srv-deployment/.github/workflows/acceptance-1.1.yml@"
            "2b6cd5b4925e704e25dac9ac47c6b22e12df615f",
            self.text,
        )
        self.assertNotIn("secrets: inherit", self.text)

    def test_every_secret_bearing_staging_job_uses_protected_environment(self):
        for job_name in ("staging-package", "remote-staging"):
            match = re.search(
                rf"^  {re.escape(job_name)}:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)",
                self.text,
                flags=re.MULTILINE | re.DOTALL,
            )
            self.assertIsNotNone(match, job_name)
            body = match.group("body")
            self.assertIn("environment: staging", body)
            self.assertIn("Recheck exact canonical GATE-FROZEN identity", body)

    def test_actions_are_full_sha_pinned_and_checkout_drops_credentials(self):
        uses = re.findall(r"uses: (actions/[^@\s]+)@([^\s]+)", self.text)
        self.assertTrue(uses)
        for action, ref in uses:
            self.assertRegex(ref, r"^[0-9a-f]{40}$", action)
        checkout_count = self.text.count("uses: actions/checkout@")
        self.assertGreaterEqual(checkout_count, 2)
        self.assertGreaterEqual(self.text.count("persist-credentials: false"), checkout_count)

    def test_staging_fails_closed_when_environment_credentials_are_missing(self):
        self.assertIn("Require protected staging environment credentials", self.text)
        self.assertIn("missing protected staging credential", self.text)
        self.assertNotIn("configured=false", self.text)

    def test_artifact_name_binds_version_and_candidate_sha(self):
        artifact = "control-center-protected-staging-${{ env.CANDIDATE_VERSION }}-${{ env.CANDIDATE_SHA }}"
        self.assertGreaterEqual(self.text.count(artifact), 2)
        self.assertIn("sha256sum -c control-center-staging.tar.gz.sha256", self.text)


if __name__ == "__main__":
    unittest.main()
