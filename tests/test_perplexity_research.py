import unittest

from scripts import perplexity_research


class PerplexityResearchTests(unittest.TestCase):
    def test_prompt_marks_diff_as_untrusted_and_truncates(self):
        diff = "x" * (perplexity_research.MAX_DIFF_CHARS + 10)
        prompt = perplexity_research.build_prompt(
            diff, "o/r", "PR #1", "abc", "systemd compatibility"
        )
        self.assertIn("<UNTRUSTED_DIFF>", prompt)
        self.assertIn("truncated", prompt)
        self.assertIn("systemd compatibility", prompt)
        self.assertNotIn("x" * (perplexity_research.MAX_DIFF_CHARS + 1), prompt)

    def test_extract_content(self):
        response = {
            "choices": [
                {"message": {"role": "assistant", "content": "grounded result"}}
            ]
        }
        self.assertEqual(
            perplexity_research.extract_content(response),
            "grounded result",
        )

    def test_extract_content_rejects_missing_choice(self):
        with self.assertRaises(ValueError):
            perplexity_research.extract_content({"choices": []})

    def test_sources_are_deduplicated_and_unsafe_urls_rejected(self):
        response = {
            "search_results": [
                {"title": "Official", "url": "https://example.com/docs", "date": "2026-08-20"},
                {"title": "Duplicate", "url": "https://example.com/docs"},
                {"title": "Unsafe", "url": "javascript:alert(1)"},
            ],
            "citations": [
                "https://example.com/docs",
                "https://example.org/security",
                "file:///tmp/local",
            ],
        }
        sources = perplexity_research.normalize_sources(response)
        self.assertEqual(
            [item["url"] for item in sources],
            ["https://example.com/docs", "https://example.org/security"],
        )

    def test_render_markdown_includes_sources_and_usage(self):
        rendered = perplexity_research.render_markdown(
            "## Findings\nNo material external findings.",
            "sonar-pro",
            [{"title": "Docs", "url": "https://example.com", "date": "2026-08-20"}],
            {"total_tokens": 42, "cost": {"total_cost": 0.01}},
        )
        self.assertIn("Perplexity external research", rendered)
        self.assertIn("[Docs](https://example.com)", rendered)
        self.assertIn("tokens=42", rendered)
        self.assertIn("reported_cost=0.01", rendered)


if __name__ == "__main__":
    unittest.main()
