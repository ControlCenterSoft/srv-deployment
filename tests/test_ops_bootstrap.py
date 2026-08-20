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
        self.assertEqual("efad992ca9147fa9b751221d332a4837defa0c53", match.group(1))

    def test_all_bootstrap_files_have_exact_pinned_git_blob_ids(self):
        expected = {
            "agent/ccops_agent_v2.py": "8ee6a3001016e1f127cb6050b77a80eee186823c",
            "agent/ccops_broker.py": "dcbeb90b5e78e2c77545a2a56468cd86e8a7327e",
            "install/install-ops-v2.sh": "6327cbfe18e2ce371279114d21ab148f1d709881",
        }
        for path, blob in expected.items():
            self.assertIn(f'"{path}": ("{path}", "{blob}")', self.text)

    def test_existing_diagnostics_token_is_reused(self):
        self.assertIn('TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"', self.text)
        self.assertNotIn("read -r -s", self.text)

    def test_token_is_not_passed_to_curl_or_echoed(self):
        self.assertNotIn("curl", self.text)
        self.assertNotRegex(self.text, r'echo[^\n]*\$TOKEN')
        self.assertNotRegex(self.text, r'printf[^\n]*\$TOKEN')

    def test_installs_redirect_fixed_agent_v2(self):
        self.assertIn("ccops_agent_v2.py", self.text)
        self.assertIn("install-ops-v2.sh", self.text)
        self.assertIn("OPS_AGENT_VERSION=1.1.1", self.text)

    def test_installation_requires_root_and_post_validates_timer(self):
        self.assertIn('[[ ${EUID:-$(id -u)} -eq 0 ]]', self.text)
        self.assertIn("systemctl is-enabled --quiet control-center-ops-agent.timer", self.text)
        self.assertIn("ARBITRARY_SHELL=disabled", self.text)


if __name__ == "__main__":
    unittest.main()
