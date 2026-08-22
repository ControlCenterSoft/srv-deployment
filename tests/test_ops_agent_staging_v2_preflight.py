import hashlib
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts" / "stage-ops-agent-signed.sh"
WRAPPER = ROOT / "scripts" / "stage-ops-agent-signed-v2.sh"
EXPECTED_SOURCE_BLOB = "82e12eeaed1df8d35fbec382a36f6870a8ceb019"


def git_blob(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


class OpsAgentStagingV2PreflightTests(unittest.TestCase):
    def test_wrapper_and_source_shell_syntax(self):
        subprocess.run(["bash", "-n", str(SOURCE)], check=True)
        subprocess.run(["bash", "-n", str(WRAPPER)], check=True)

    def test_wrapper_is_pinned_to_reviewed_canonical_source(self):
        self.assertEqual(git_blob(SOURCE.read_bytes()), EXPECTED_SOURCE_BLOB)
        text = WRAPPER.read_text(encoding="utf-8")
        self.assertIn(f'EXPECTED_SOURCE_BLOB="{EXPECTED_SOURCE_BLOB}"', text)
        self.assertIn("expected inaccessible staging-user socket probe not found exactly once", text)
        self.assertIn("restricted root updater self-test missing from preflight", text)

    def test_patch_removes_only_nonroot_socket_probe_and_keeps_restricted_selftest(self):
        source = SOURCE.read_text(encoding="utf-8")
        needle = (
            "   test -S /run/control-center-ops/broker.sock && \\\n"
            "   test \\\"\\$(stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock)\\\" = 'root:ccdiag:660' && \\\n"
        )
        self.assertEqual(source.count(needle), 1)
        patched = source.replace(needle, "", 1)
        preflight = patched.index("# Read-only preflight before package upload or sudo mutation.")
        upload = patched.index('scp "${scp_opts[@]}" "$package"', preflight)
        block = patched[preflight:upload]
        self.assertNotIn("test -S /run/control-center-ops/broker.sock", block)
        self.assertNotIn("stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock", block)
        self.assertIn("systemctl is-active --quiet control-center-ops-broker.service", block)
        self.assertIn("systemctl is-active --quiet control-center-ops-agent.timer", block)
        self.assertIn("NoNewPrivileges --value", block)
        self.assertIn("/api/v1/health", block)
        self.assertIn("/api/v1/readiness", block)
        self.assertIn("/api/v1/version", block)
        self.assertIn("sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --self-test", block)
        self.assertLess(
            block.index("sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --self-test"),
            len(block),
        )

    def test_build_only_path_stays_functional_through_wrapper(self):
        fixture = ROOT / "tests" / "fixtures" / "ccops_agent_v3_d4337bdd.py"
        with tempfile.TemporaryDirectory() as td_raw:
            td = pathlib.Path(td_raw)
            key = td / "key.pem"
            package = td / "package.tar.gz"
            subprocess.run(
                ["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(key)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            subprocess.run(
                [
                    "bash",
                    str(WRAPPER),
                    "--agent-file",
                    str(fixture),
                    "--source-commit",
                    "d4337bdd5f3111431ee06858fcd0d3338655751c",
                    "--source-blob",
                    "412ec9e08432e34d82c64813af079a4177a6ac1e",
                    "--agent-version",
                    "1.1.10",
                    "--expected-product-version",
                    "1.1.0-rc.7",
                    "--expected-product-commit",
                    "ca0d610aca75d3838c5d10eb841182529a95fc4d",
                    "--signing-key",
                    str(key),
                    "--build-only",
                    str(package),
                ],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertTrue(package.is_file())
            self.assertGreater(package.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
