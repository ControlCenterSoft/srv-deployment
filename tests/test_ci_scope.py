import unittest

from scripts.ci_scope import classify


class CIScopeTests(unittest.TestCase):
    def test_docs_only(self):
        result = classify(["docs/adr/ADR-0008.md", "README.md"])
        self.assertTrue(result["docs"])
        self.assertFalse(result["runtime"])
        self.assertFalse(result["go"])

    def test_go_runtime(self):
        result = classify(["internal/httpserver/server.go"])
        self.assertTrue(result["go"])
        self.assertTrue(result["runtime"])
        self.assertFalse(result["docs"])

    def test_shell_runtime(self):
        result = classify(["install/update.sh"])
        self.assertTrue(result["shell"])
        self.assertTrue(result["runtime"])

    def test_ai_only(self):
        result = classify(["scripts/perplexity_research.py", "tests/test_perplexity_research.py"])
        self.assertTrue(result["ai"])
        self.assertFalse(result["runtime"])
        self.assertFalse(result["go"])

    def test_shared_ai_gateway_is_ai_only(self):
        result = classify(["scripts/ai_gateway.py", "tests/test_ai_gateway.py"])
        self.assertTrue(result["ai"])
        self.assertFalse(result["runtime"])
        self.assertFalse(result["go"])

    def test_perplexity_routine_paths_are_ai(self):
        result = classify(
            [
                "scripts/perplexity_routine.py",
                "tests/test_perplexity_routine.py",
                ".github/workflows/perplexity-routine.yml",
            ]
        )
        self.assertTrue(result["ai"])
        self.assertFalse(result["runtime"])
        self.assertFalse(result["go"])

    def test_pipeline_yaml_routes_python_policy_regressions(self):
        result = classify([".github/workflows/development-1.1.yml"])
        self.assertTrue(
            result["ai"],
            "workflow-only changes must execute the Python regression/policy suite",
        )
        self.assertFalse(result["runtime"])
        self.assertFalse(result["go"])
        self.assertFalse(result["shell"])
        self.assertFalse(result["docs"])


if __name__ == "__main__":
    unittest.main()
