import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "bootstrap-ops-agent.sh"


class OpsBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_private_source_is_pinned_to_exact_commit(self):
        match = re.search(r'^DIAG_COMMIT="([0-9a-f]{40})"$', self.text, re.MULTILINE)
        self.assertIsNotNone(match)
        self.assertEqual("94aad6b079ec9a7dff52e6187bed5f551f59672e", match.group(1))

    def test_all_bootstrap_files_have_pinned_git_blob_ids(self):
        for path in ["agent/ccops_agent.py", "agent/ccops_broker.py", "install/install-ops.sh"]:
            pattern = re.escape(f'"{path}": ("{path}", "') + r'[0-9a-f]{40}'
            self.assertRegex(self.text, pattern)

    def test_existing_diagnostics_token_is_reused(self):
        self.assertIn('TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"', self.text)
        self.assertNotIn("read -r -s", self.text)

    def test_token_is_not_passed_to_curl_or_echoed(self):
        self.assertNotIn("curl", self.text)
        self.assertNotRegex(self.text, r'echo[^\n]*\$TOKEN')
        self.assertNotRegex(self.text, r'printf[^\n]*\$TOKEN')

    def test_installation_requires_root_and_post_validates_timer(self):
        self.assertIn('[[ ${EUID:-$(id -u)} -eq 0 ]]', self.text)
        self.assertIn("systemctl is-enabled --quiet control-center-ops-agent.timer", self.text)
        self.assertIn("ARBITRARY_SHELL=disabled", self.text)


if __name__ == "__main__":
    unittest.main()
