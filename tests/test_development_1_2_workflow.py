import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "development-1.2.yml"


class Development12WorkflowTests(unittest.TestCase):
    def test_pull_request_scope_uses_merge_base_not_base_tip(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('BASE_TIP="${{ github.event.pull_request.base.sha }}"', text)
        self.assertIn('HEAD_SHA="${{ github.event.pull_request.head.sha }}"', text)
        self.assertIn('git merge-base "${BASE_TIP}" "${HEAD_SHA}"', text)
        self.assertNotIn('BASE_SHA="${{ github.event.pull_request.base.sha }}"', text)

    def test_release_acceptance_is_not_chained_from_1_2_lane(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn("acceptance-1.1-protected", text)
        self.assertNotIn("workflow_run:", text)
        self.assertIn("Release acceptance remains explicit and isolated", text)


if __name__ == "__main__":
    unittest.main()
