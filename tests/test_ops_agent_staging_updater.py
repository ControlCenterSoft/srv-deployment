import hashlib
import pathlib
import subprocess
import tarfile
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "scripts" / "bootstrap-ops-agent-staging-updater.sh"
STAGE = ROOT / "scripts" / "stage-ops-agent-signed.sh"


def embedded_updater() -> str:
    text = BOOTSTRAP.read_text(encoding="utf-8")
    start = text.index("<<'WRAPPER'\n") + len("<<'WRAPPER'\n")
    end = text.index("\nWRAPPER\n", start)
    return text[start:end] + "\n"


class OpsAgentStagingUpdaterTests(unittest.TestCase):
    def test_shell_syntax(self):
        subprocess.run(["bash", "-n", str(BOOTSTRAP)], check=True)
        subprocess.run(["bash", "-n", str(STAGE)], check=True)
        with tempfile.TemporaryDirectory() as td:
            updater = pathlib.Path(td) / "updater.sh"
            updater.write_text(embedded_updater(), encoding="utf-8")
            subprocess.run(["bash", "-n", str(updater)], check=True)

    def test_privilege_boundary_is_dedicated_and_not_general_sudo(self):
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        updater = embedded_updater()
        self.assertIn('/usr/local/sbin/control-center-ops-agent-staging-update', bootstrap)
        self.assertIn("NOPASSWD: %s", bootstrap)
        self.assertNotIn("NOPASSWD: ALL", bootstrap)
        self.assertNotIn("sudo bash", bootstrap)
        self.assertNotIn("eval ", updater)
        self.assertNotIn("/bin/sh -c", updater)
        self.assertIn("--self-test", updater)
        self.assertIn("--package", updater)
        self.assertIn("package path rejected", updater)

    def test_package_trust_boundary_and_recovery_are_explicit(self):
        updater = embedded_updater()
        required = [
            'PUBLIC_KEY="/etc/control-center/staging-update-public.pem"',
            'component") != "control-center-ops-agent"',
            'source_repo") != "ControlCenterSoft/control-center-server-diagnostics"',
            'source_path") != "agent/ccops_agent_v3.py"',
            "manifest signature rejected",
            'tarfile.open(package, "r|gz")',
            "if tf.next() is not None",
            "artifact SHA-256 mismatch",
            "Git blob identity mismatch",
            "agent source version mismatch",
            "test-server product identity/preflight rejected",
            'systemctl stop "$AGENT_TIMER"',
            "rollback_agent()",
            'runuser -u "$AGENT_USER" -- /usr/bin/python3 "$AGENT_FILE" --register',
            'NoNewPrivileges --value',
            'root:ccdiag:660',
            "product identity/readiness changed after agent update",
            'current_stat="$(stat -c',
        ]
        for marker in required:
            self.assertIn(marker, updater)
        self.assertNotIn("getmembers()", updater)
        self.assertNotIn("extractall", updater)
        self.assertNotIn("service.restart", updater)
        self.assertNotIn("control-center-update", updater)
        self.assertNotIn("ccops_socket_broker.py", updater)

    def test_deployer_builds_exact_signed_component_package(self):
        with tempfile.TemporaryDirectory() as td_raw:
            td = pathlib.Path(td_raw)
            agent = td / "ccops_agent_v3.py"
            agent.write_text('AGENT_VERSION = "1.1.10"\n', encoding="utf-8")
            raw = agent.read_bytes()
            blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
            key = td / "key.pem"
            pub = td / "pub.pem"
            package = td / "package.tar.gz"
            subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(key)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(pub)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([
                "bash", str(STAGE),
                "--agent-file", str(agent),
                "--source-commit", "d4337bdd5f3111431ee06858fcd0d3338655751c",
                "--source-blob", blob,
                "--agent-version", "1.1.10",
                "--expected-product-version", "1.1.0-rc.6",
                "--expected-product-commit", "302eb6da97324d719849e7ae752fc10bdc557d9a",
                "--signing-key", str(key),
                "--build-only", str(package),
            ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            with tarfile.open(package, "r:gz") as tf:
                self.assertEqual(tf.getnames(), ["manifest.json", "manifest.sig", "ccops_agent_v3.py"])
                manifest = tf.extractfile("manifest.json").read()
                signature = tf.extractfile("manifest.sig").read()
                self.assertEqual(tf.extractfile("ccops_agent_v3.py").read(), raw)
            manifest_path = td / "manifest.json"
            sig_path = td / "manifest.sig"
            manifest_path.write_bytes(manifest)
            sig_path.write_bytes(signature)
            subprocess.run([
                "openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(pub), "-rawin",
                "-in", str(manifest_path), "-sigfile", str(sig_path),
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_deployer_rejects_source_blob_mismatch_before_signing(self):
        with tempfile.TemporaryDirectory() as td_raw:
            td = pathlib.Path(td_raw)
            agent = td / "ccops_agent_v3.py"
            agent.write_text('AGENT_VERSION = "1.1.10"\n', encoding="utf-8")
            key = td / "key.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(key)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            proc = subprocess.run([
                "bash", str(STAGE),
                "--agent-file", str(agent),
                "--source-commit", "d4337bdd5f3111431ee06858fcd0d3338655751c",
                "--source-blob", "0" * 40,
                "--agent-version", "1.1.10",
                "--expected-product-version", "1.1.0-rc.6",
                "--expected-product-commit", "302eb6da97324d719849e7ae752fc10bdc557d9a",
                "--signing-key", str(key),
                "--build-only", str(td / "package.tar.gz"),
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("source blob mismatch", proc.stderr)

    def test_deployer_rejects_unbound_source_commit_blob_pair(self):
        """A signed package must prove that source_blob belongs to source_commit/source_path.

        The authoritative diagnostics PR14 fixture is commit d4337... at
        agent/ccops_agent_v3.py blob 412ec9....  A caller-derived blob for different
        source content must not be accepted merely because it is internally
        self-consistent and carries the same claimed source commit.
        """
        authoritative_commit = "d4337bdd5f3111431ee06858fcd0d3338655751c"
        authoritative_blob = "412ec9e08432e34d82c64813af079a4177a6ac1e"
        with tempfile.TemporaryDirectory() as td_raw:
            td = pathlib.Path(td_raw)
            agent = td / "ccops_agent_v3.py"
            agent.write_text('AGENT_VERSION = "1.1.10"\n', encoding="utf-8")
            raw = agent.read_bytes()
            caller_blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
            self.assertNotEqual(caller_blob, authoritative_blob)
            key = td / "key.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", str(key)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            proc = subprocess.run([
                "bash", str(STAGE),
                "--agent-file", str(agent),
                "--source-commit", authoritative_commit,
                "--source-blob", caller_blob,
                "--agent-version", "1.1.10",
                "--expected-product-version", "1.1.0-rc.6",
                "--expected-product-commit", "302eb6da97324d719849e7ae752fc10bdc557d9a",
                "--signing-key", str(key),
                "--build-only", str(td / "package.tar.gz"),
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            self.assertNotEqual(
                proc.returncode,
                0,
                "release blocker: builder signed content whose caller-supplied blob is not the blob at the claimed source commit/path",
            )

    def test_remote_staging_has_read_only_preflight_before_upload(self):
        text = STAGE.read_text(encoding="utf-8")
        preflight = text.index("# Read-only preflight before package upload or sudo mutation.")
        selftest = text.index("--self-test", preflight)
        upload = text.index('scp "${scp_opts[@]}" "$package"', preflight)
        mutate = text.index("--package '$remote_package'", upload)
        self.assertLess(preflight, selftest)
        self.assertLess(selftest, upload)
        self.assertLess(upload, mutate)
        self.assertIn("StrictHostKeyChecking=yes", text)
        self.assertIn("UserKnownHostsFile=", text)
        self.assertNotIn("sudo bash", text)


if __name__ == "__main__":
    unittest.main()
