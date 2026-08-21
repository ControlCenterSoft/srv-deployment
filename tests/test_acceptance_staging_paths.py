import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "acceptance-1.1.yml"


class AcceptanceStagingPathsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding="utf-8")

    def test_staging_transport_does_not_use_expression_home(self):
        self.assertNotIn("${{ env.HOME }}", self.text)

    def test_staging_transport_uses_runner_temp_for_both_files(self):
        self.assertIn(
            "CONTROL_CENTER_STAGING_SSH_KEY_FILE: ${{ runner.temp }}/control-center-staging-ssh/id_control_center_staging",
            self.text,
        )
        self.assertIn(
            "CONTROL_CENTER_STAGING_KNOWN_HOSTS_FILE: ${{ runner.temp }}/control-center-staging-ssh/known_hosts",
            self.text,
        )
        self.assertIn('install -d -m 0700 "$RUNNER_TEMP/control-center-staging-ssh"', self.text)


if __name__ == "__main__":
    unittest.main()
