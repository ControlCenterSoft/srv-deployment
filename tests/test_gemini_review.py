import json
import unittest

from scripts import gemini_review


class GeminiReviewTests(unittest.TestCase):
    def test_parse_fenced_json_and_normalize_line(self):
        payload = {
            "summary": "Found one issue",
            "verdict": "CHANGES_REQUIRED",
            "findings": [
                {
                    "severity": "high",
                    "path": "api/example.py",
                    "line": 0,
                    "title": "Unsafe behavior",
                    "description": "Failure is reachable.",
                    "recommendation": "Validate before use.",
                }
            ],
            "test_gaps": ["Add a regression test"],
            "security_notes": [],
        }
        review = gemini_review.parse_response_text(
            "```json\n" + json.dumps(payload) + "\n```"
        )
        self.assertEqual(review["findings"][0]["severity"], "HIGH")
        self.assertIsNone(review["findings"][0]["line"])

    def test_rejects_invalid_verdict(self):
        with self.assertRaises(ValueError):
            gemini_review.normalize_review(
                {"summary": "x", "verdict": "MAYBE", "findings": []}
            )

    def test_prompt_marks_diff_as_untrusted_and_truncates(self):
        diff = "x" * (gemini_review.MAX_DIFF_CHARS + 10)
        prompt = gemini_review.build_prompt(diff, "o/r", "PR #1", "abc")
        self.assertIn("<UNTRUSTED_DIFF>", prompt)
        self.assertIn("truncated", prompt)
        self.assertNotIn("x" * (gemini_review.MAX_DIFF_CHARS + 1), prompt)

    def test_markdown_escapes_table_pipes(self):
        review = {
            "summary": "summary",
            "verdict": "PASS_WITH_NOTES",
            "findings": [
                {
                    "severity": "LOW",
                    "path": "a.py",
                    "line": 7,
                    "title": "A | B",
                    "description": "desc",
                    "recommendation": "C | D",
                }
            ],
            "test_gaps": [],
            "security_notes": [],
        }
        rendered = gemini_review.render_markdown(review, "gemini-test")
        self.assertIn("A \\| B", rendered)
        self.assertIn("C \\| D", rendered)


if __name__ == "__main__":
    unittest.main()
