import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "bootstrap-platform-v2-staging-complete.sh"


class StagingCompleteBootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_pins_accepted_bridge_and_ops_bootstrap(self):
        self.assertIn('BRIDGE_COMMIT="e3eb433684b8dc9dc82e02489f2b57f31d11bdb7"', self.text)
        self.assertIn('BRIDGE_BLOB="9213d736c05686a0b581d5a5c909cec07dc7b266"', self.text)
        self.assertIn('OPS_COMMIT="2369cca3cf9bee6e428e946bbe72a239baa7b444"', self.text)
        self.assertIn('OPS_BLOB="bd5ac39a8c4353cf19260879be8e2ee888bc5197"', self.text)

    def test_frozen_runtime_identity_is_fail_closed(self):
        self.assertIn('EXPECTED_RUNTIME_VERSION="1.0.0"', self.text)
        self.assertIn('EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"', self.text)
        self.assertGreaterEqual(self.text.count("assert_frozen_runtime"), 4)

    def test_worker_stays_dormant_until_signed_switch(self):
        self.assertIn("assert_worker_dormant", self.text)
        self.assertIn("control-center-privileged-worker.service", self.text)
        self.assertIn("worker unexpectedly active before signed package-v2 switch", self.text)
        self.assertIn("worker unexpectedly enabled before signed package-v2 switch", self.text)

    def test_bridge_runs_before_ops_agent_upgrade(self):
        bridge = self.text.index('bash "$WORK/platform-v2-bridge.sh"')
        ops = self.text.index('bash "$WORK/ops-bootstrap.sh"')
        self.assertLess(bridge, ops)

    def test_requires_typed_platform_prepare_after_upgrade(self):
        self.assertIn("control-center-platform-v2-prepare.service", self.text)
        self.assertIn("OPS_AGENT_VERSION=1.1.6", self.text)
        self.assertIn("PLATFORM_PREPARE_V2=typed-oneshot", self.text)
        self.assertIn("ROOT_INTERACTION_COMPLETE=true", self.text)

    def test_no_unpinned_raw_downloads(self):
        self.assertNotIn("raw.githubusercontent.com", self.text)
        self.assertNotIn("curl ", self.text)
        self.assertIn("pinned blob mismatch", self.text)


if __name__ == "__main__":
    unittest.main()
