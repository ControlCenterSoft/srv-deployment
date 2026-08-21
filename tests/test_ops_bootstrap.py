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
        self.assertEqual("1db11c0874b4fab5319a12f623c0da92c5a991fd", match.group(1))

    def test_all_bootstrap_files_have_exact_pinned_git_blob_ids(self):
        expected = {
            "agent/ccops_agent_v2.py": "8ee6a3001016e1f127cb6050b77a80eee186823c",
            "agent/ccops_agent_v3.py": "4e63be0651ce5030c6c21b9a02194f710d9e7cd1",
            "agent/ccops_broker.py": "de14cd6b0686d7fdd09fc76adbdc40db2cb17085",
            "agent/ccops_socket_broker.py": "318f7f165d99eb0349745120e680b91017b5d06c",
            "install/install-ops-v3.sh": "6d80aa9855d61f00d75a7963897174bbef3fd868",
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

    def test_installs_accepted_remote_agent_1_1_5_bundle(self):
        self.assertIn("ccops_agent_v3.py", self.text)
        self.assertIn("ccops_socket_broker.py", self.text)
        self.assertIn("install-ops-v3.sh", self.text)
        self.assertIn("REMOTE_AGENT_RELEASE=1.1.5", self.text)
        self.assertIn("OPS_AGENT_VERSION=1.1.4", self.text)
        self.assertIn("BROKER_CORE_VERSION=1.1.5", self.text)
        self.assertIn("BROKER_TRANSPORT_VERSION=1.1.4", self.text)
        self.assertIn("ROOT_BOUNDARY=unix-so-peercred-root-broker", self.text)
        self.assertIn("SUDO_REQUIRED=false", self.text)

    def test_registration_contract_matches_accepted_agent(self):
        self.assertIn("payload.get('agent_version') == '1.1.4'", self.text)
        self.assertIn("payload.get('broker_transport') == 'unix'", self.text)
        self.assertIn("payload.get('arbitrary_shell') is False", self.text)
        self.assertIn("payload.get('sudo_required') is False", self.text)

    def test_installation_requires_root_and_post_validates_runtime(self):
        self.assertIn('[[ ${EUID:-$(id -u)} -eq 0 ]]', self.text)
        self.assertIn("systemctl is-enabled --quiet control-center-ops-agent.timer", self.text)
        self.assertIn("systemctl is-active --quiet control-center-ops-broker.service", self.text)
        self.assertIn("/run/control-center-ops/broker.sock", self.text)
        self.assertIn("NoNewPrivileges", self.text)
        self.assertIn("ARBITRARY_SHELL=disabled", self.text)


if __name__ == "__main__":
    unittest.main()
