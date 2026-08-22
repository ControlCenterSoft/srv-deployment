import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "release_gate.py"
spec = importlib.util.spec_from_file_location("release_gate", MODULE_PATH)
release_gate = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(release_gate)


def pr_fixture(**overrides):
    base = {
        "state": "open",
        "draft": False,
        "changed_files": 2,
        "additions": 20,
        "deletions": 5,
        "user": {"login": "ControlCenterSoft"},
        "base": {"ref": "1.1.x"},
        "head": {
            "sha": "1" * 40,
            "repo": {"full_name": "ControlCenterSoft/srv-deployment"},
        },
    }
    base.update(overrides)
    return base


class ReleaseGatePolicyTests(unittest.TestCase):
    def test_low_risk_owner_pr_is_eligible(self):
        decision = release_gate.policy_decision(
            "ControlCenterSoft/srv-deployment",
            pr_fixture(),
            ["internal/dns/resolver.go", "tests/test_dns.py"],
        )
        self.assertTrue(decision.allowed, decision.reasons)

    def test_workflow_change_is_never_auto_approved(self):
        decision = release_gate.policy_decision(
            "ControlCenterSoft/srv-deployment",
            pr_fixture(),
            [".github/workflows/ci.yml"],
        )
        self.assertFalse(decision.allowed)
        self.assertTrue(any("protected path prefix .github/" in r for r in decision.reasons))

    def test_staging_script_change_is_never_auto_approved(self):
        decision = release_gate.policy_decision(
            "ControlCenterSoft/srv-deployment",
            pr_fixture(),
            ["scripts/staging-deploy.sh"],
        )
        self.assertFalse(decision.allowed)

    def test_auth_state_and_privileged_boundaries_are_protected(self):
        for path in (
            "internal/auth/service.go",
            "internal/state/store.go",
            "internal/privileged/worker.go",
            "internal/release/package.go",
        ):
            with self.subTest(path=path):
                self.assertIsNotNone(release_gate.protected_reason(path))

    def test_canonical_release_metadata_is_protected(self):
        for path in ("deployment.json", "go.mod", "go.sum", "SECURITY.md", ".gitmodules"):
            with self.subTest(path=path):
                self.assertIsNotNone(release_gate.protected_reason(path))

    def test_foreign_or_cross_repo_pr_is_rejected(self):
        foreign = pr_fixture(user={"login": "someone-else"})
        decision = release_gate.policy_decision(
            "ControlCenterSoft/srv-deployment", foreign, ["internal/dns/resolver.go"]
        )
        self.assertFalse(decision.allowed)

        fork = pr_fixture(
            head={"sha": "2" * 40, "repo": {"full_name": "someone/fork"}}
        )
        decision = release_gate.policy_decision(
            "ControlCenterSoft/srv-deployment", fork, ["internal/dns/resolver.go"]
        )
        self.assertFalse(decision.allowed)

    def test_draft_and_unknown_base_are_rejected(self):
        draft = pr_fixture(draft=True)
        self.assertFalse(
            release_gate.policy_decision(
                "ControlCenterSoft/srv-deployment", draft, ["internal/dns/resolver.go"]
            ).allowed
        )
        unknown = pr_fixture(base={"ref": "feature/x"})
        self.assertFalse(
            release_gate.policy_decision(
                "ControlCenterSoft/srv-deployment", unknown, ["internal/dns/resolver.go"]
            ).allowed
        )

    def test_size_caps_fail_closed(self):
        huge = pr_fixture(changed_files=release_gate.MAX_CHANGED_FILES + 1)
        self.assertFalse(
            release_gate.policy_decision(
                "ControlCenterSoft/srv-deployment", huge, ["internal/dns/resolver.go"]
            ).allowed
        )

    def test_required_ci_contract_is_branch_specific(self):
        self.assertEqual("integration-guard", release_gate.REQUIRED_CHECKS["main"])
        self.assertEqual("Fast development gate", release_gate.REQUIRED_CHECKS["1.1.x"])
        self.assertEqual("post-release-main", release_gate.REQUIRED_WORKFLOWS["main"])
        self.assertEqual(
            "Control Center 1.1.x Fast CI", release_gate.REQUIRED_WORKFLOWS["1.1.x"]
        )


if __name__ == "__main__":
    unittest.main()
