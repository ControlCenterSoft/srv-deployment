import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "staging-deploy.sh"


class StagingExactActiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_exact_active_requires_version_and_commit(self):
        self.assertIn('\\"version\\":\\"${CANDIDATE_VERSION}\\"', self.text)
        self.assertIn('\\"commit\\":\\"${CANDIDATE_SHA}\\"', self.text)
        self.assertIn('STAGING_EXACT_ACTIVE=PASSED', self.text)

    def test_exact_active_requires_full_dual_runtime_state(self):
        preflight = self.text.index('if ssh "${ssh_opts[@]}" "$remote"')
        upload = self.text.index('scp "${scp_opts[@]}"')
        section = self.text[preflight:upload]
        self.assertIn('systemctl is-active --quiet control-center-privileged-worker.service', section)
        self.assertIn('systemctl is-enabled --quiet control-center-privileged-worker.service', section)
        self.assertIn('test -S /run/control-center/privileged-worker.sock', section)
        self.assertIn("root:control-center:660", section)
        self.assertIn('/api/v1/health', section)
        self.assertIn('/api/v1/readiness', section)

    def test_preflight_is_before_upload_and_restricted_updater_remains_fallback(self):
        preflight = self.text.index('STAGING_EXACT_ACTIVE=PASSED')
        upload = self.text.index('scp "${scp_opts[@]}"')
        updater = self.text.index('sudo -n /usr/local/sbin/control-center-staging-update --package')
        self.assertLess(preflight, upload)
        self.assertLess(upload, updater)
        self.assertNotIn('--allow-downgrade', self.text)

    def test_post_apply_acceptance_also_pins_commit(self):
        updater = self.text.index('sudo -n /usr/local/sbin/control-center-staging-update --package')
        post = self.text[updater:]
        self.assertIn('\\"version\\":\\"${CANDIDATE_VERSION}\\"', post)
        self.assertIn('\\"commit\\":\\"${CANDIDATE_SHA}\\"', post)


if __name__ == "__main__":
    unittest.main()
