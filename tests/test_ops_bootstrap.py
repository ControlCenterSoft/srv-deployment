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
        self.assertEqual("2ea76c60cc6ce80a0594867004c32669f5f3944e", match.group(1))

    def test_all_bootstrap_files_have_exact_pinned_git_blob_ids(self):
        expected = {
            "agent/ccops_agent_v2.py": "8ee6a3001016e1f127cb6050b77a80eee186823c",
            "agent/ccops_agent_v3.py": "00fbfdde35425b97d46015b5794a38e3343dabc7",
            "agent/ccops_broker.py": "dcbeb90b5e78e2c77545a2a56468cd86e8a7327e",
            "agent/ccops_socket_broker.py": "d2245532af47b5ef12fcfc0a0cf1e88a9ff9a1dc",
            "install/install-ops-v3.sh": "4c82ab9c86ab2f1c9651de41e20934ef340672c4",
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

    def test_installs_unix_broker_agent_v3(self):
        self.assertIn("ccops_agent_v3.py", self.text)
        self.assertIn("ccops_socket_broker.py", self.text)
        self.assertIn("install-ops-v3.sh", self.text)
        self.assertIn("OPS_AGENT_VERSION=1.1.3", self.text)
        self.assertIn("ROOT_BOUNDARY=unix-so-peercred-root-broker", self.text)
        self.assertIn("SUDO_REQUIRED=false", self.text)

    def test_installation_requires_root_and_post_validates_runtime(self):
        self.assertIn('[[ ${EUID:-$(id -u)} -eq 0 ]]', self.text)
        self.assertIn("systemctl is-enabled --quiet control-center-ops-agent.timer", self.text)
        self.assertIn("systemctl is-active --quiet control-center-ops-broker.service", self.text)
        self.assertIn("/run/control-center-ops/broker.sock", self.text)
        self.assertIn("NoNewPrivileges", self.text)
        self.assertIn("ARBITRARY_SHELL=disabled", self.text)


if __name__ == "__main__":
    unittest.main()
