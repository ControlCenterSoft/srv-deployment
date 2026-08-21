import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "bootstrap-rc-staging-one-shot.sh"


class RCStagingOneShotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_pins_complete_platform_and_real_staging_sources(self):
        self.assertIn('PLATFORM_COMMIT="9ab8ea4acf46dedbf7309803c87da2b2f4632ceb"', self.text)
        self.assertIn('PLATFORM_BLOB="59cc26c72876d7e2d0a9b98205f26a8a5bdc77f9"', self.text)
        self.assertIn('STAGING_COMMIT="9ab8ea4acf46dedbf7309803c87da2b2f4632ceb"', self.text)
        self.assertIn('STAGING_BLOB="a4fbb16a3acc00213dfebc0a64a936c28b4e7350"', self.text)
        self.assertIn("pinned blob mismatch", self.text)

    def test_requires_exact_frozen_runtime_before_and_after(self):
        self.assertIn('EXPECTED_RUNTIME_VERSION="1.0.0"', self.text)
        self.assertIn('EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"', self.text)
        self.assertGreaterEqual(self.text.count("assert_frozen_runtime"), 4)

    def test_worker_stays_dormant_before_signed_rc(self):
        self.assertIn("assert_worker_dormant", self.text)
        self.assertIn("worker unexpectedly active before signed RC switch", self.text)
        self.assertIn("worker unexpectedly enabled before signed RC switch", self.text)
        self.assertIn("WORKER_ACTIVE=false", self.text)
        self.assertIn("WORKER_ENABLED=false", self.text)

    def test_sequence_is_platform_then_real_staging(self):
        platform = self.text.index('bash "$WORK/platform-complete.sh"')
        staging = self.text.index('bash "$WORK/real-staging.sh"')
        self.assertLess(platform, staging)

    def test_postconditions_cover_ops_and_staging_trust(self):
        self.assertIn("control-center-ops-broker.service", self.text)
        self.assertIn("control-center-platform-v2-prepare.service", self.text)
        self.assertIn("/usr/local/sbin/control-center-staging-update", self.text)
        self.assertIn("/etc/control-center/staging-update-public.pem", self.text)
        self.assertIn("/var/lib/control-center-staging-bootstrap/state.json", self.text)
        self.assertIn("REAL_STAGING_SECRETS=CONFIGURED", self.text)
        self.assertIn("PRIVATE_VALUES=NOT_PRINTED", self.text)

    def test_wrapper_does_not_embed_or_echo_secrets(self):
        self.assertNotIn("github_pat_", self.text)
        self.assertNotIn("ghp_", self.text)
        self.assertNotIn("PRIVATE KEY-----", self.text)
        self.assertNotIn("raw.githubusercontent.com", self.text)
        self.assertNotIn("curl ", self.text)


if __name__ == "__main__":
    unittest.main()
