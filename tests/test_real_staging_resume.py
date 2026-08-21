import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "resume-real-staging-after-port-sigpipe.sh"


class RealStagingResumeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_pins_exact_failed_bootstrap_source(self):
        self.assertIn('SOURCE_COMMIT="c951511c164707e57b9ac9cd670893e62a254e4d"', self.text)
        self.assertIn('SOURCE_BLOB="a4fbb16a3acc00213dfebc0a64a936c28b4e7350"', self.text)
        self.assertIn('SOURCE_PATH="scripts/bootstrap-real-staging.sh"', self.text)

    def test_patch_is_exactly_scoped_to_sshd_port_sigpipe(self):
        self.assertIn("text.count(old) != 1", self.text)
        self.assertIn("text.replace(old, new, 1)", self.text)
        self.assertIn("unsafe sshd early-exit pipeline remains after patch", self.text)
        self.assertIn("sshd_effective=", self.text)
        self.assertIn("END {if (port == \"\") exit 1; print port}", self.text)

    def test_runtime_remains_frozen_and_worker_dormant(self):
        self.assertIn('EXPECTED_RUNTIME_VERSION="1.0.0"', self.text)
        self.assertIn('EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"', self.text)
        self.assertGreaterEqual(self.text.count("assert_frozen_runtime"), 3)
        self.assertGreaterEqual(self.text.count("assert_worker_dormant"), 3)

    def test_requires_existing_typed_ops_channel(self):
        self.assertIn("control-center-ops-broker.service", self.text)
        self.assertIn("control-center-ops-agent.timer", self.text)
        self.assertIn("control-center-platform-v2-prepare.service", self.text)

    def test_postconditions_require_staging_trust_and_schema3_evidence(self):
        self.assertIn("/usr/local/sbin/control-center-staging-update", self.text)
        self.assertIn("/etc/control-center/staging-update-public.pem", self.text)
        self.assertIn("/var/lib/control-center-staging-bootstrap/state.json", self.text)
        self.assertIn("payload.get('schema') == 3", self.text)
        self.assertIn("REAL_STAGING_SECRETS=CONFIGURED", self.text)

    def test_no_secret_material_or_arbitrary_shell_transport(self):
        self.assertNotIn("github_pat_", self.text)
        self.assertNotIn("ghp_", self.text)
        self.assertNotIn("eval ", self.text)
        self.assertNotIn("bash -c", self.text)
        self.assertIn("PRIVATE_VALUES=NOT_PRINTED", self.text)


if __name__ == "__main__":
    unittest.main()
