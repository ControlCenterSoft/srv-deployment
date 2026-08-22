import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
STAGE = ROOT / "scripts" / "stage-ops-agent-signed.sh"


class OpsAgentStagingPreflightBoundaryTests(unittest.TestCase):
    def test_remote_preflight_does_not_require_direct_broker_socket_access(self):
        """The staging SSH identity must not need membership in the ccdiag group.

        The root-owned restricted updater already validates the broker socket
        existence and root:ccdiag:660 boundary in --self-test mode. Repeating
        those checks directly as the unprivileged staging user violates the
        least-privilege boundary because /run/control-center-ops is 0750.
        """
        text = STAGE.read_text(encoding="utf-8")
        start = text.index("# Read-only preflight before package upload or sudo mutation.")
        upload = text.index('scp "${scp_opts[@]}" "$package"', start)
        preflight = text[start:upload]

        self.assertIn(
            "sudo -n /usr/local/sbin/control-center-ops-agent-staging-update --self-test",
            preflight,
        )
        self.assertNotIn("test -S /run/control-center-ops/broker.sock", preflight)
        self.assertNotIn(
            "stat -Lc '%U:%G:%a' /run/control-center-ops/broker.sock",
            preflight,
        )


if __name__ == "__main__":
    unittest.main()
