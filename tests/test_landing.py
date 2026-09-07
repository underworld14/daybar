from html.parser import HTMLParser
from pathlib import Path
import re
import unittest


SITE = Path(__file__).resolve().parents[1]


class DocumentProbe(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.classes: set[str] = set()
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.images: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        self.classes.update((values.get("class") or "").split())
        if values.get("id"):
            self.ids.add(values["id"] or "")
        if tag == "a" and values.get("href"):
            self.links.append(values["href"] or "")
        if tag == "img" and values.get("src"):
            self.images.append(values["src"] or "")


class MidnightNativeLandingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.html = (SITE / "index.html").read_text()
        cls.css = (SITE / "styles.css").read_text()
        cls.document = DocumentProbe()
        cls.document.feed(cls.html)

    def test_midnight_native_structure_is_present(self) -> None:
        required_classes = {
            "ambient-grid",
            "hero-layout",
            "product-capture",
            "proof-rail",
            "feature-index",
            "feature-capture",
            "install-steps",
            "trust-inner",
        }
        self.assertFalse(required_classes - self.document.classes)
        self.assertIn("main", self.document.ids)
        self.assertIn("features", self.document.ids)
        self.assertIn("download", self.document.ids)

    def test_product_facts_links_and_real_screenshots_are_preserved(self) -> None:
        required_copy = (
            "Plan your day. Finish what you planned.",
            "macOS&nbsp;14+",
            "SwiftData",
            "no account",
            "MIT",
        )
        for value in required_copy:
            self.assertIn(value, self.html)

        self.assertIn(
            "https://github.com/underworld14/daybar/releases/latest",
            self.document.links,
        )
        self.assertIn("https://github.com/underworld14/daybar", self.document.links)
        self.assertEqual(
            {
                "assets/screenshots/today-panel-direct.jpg",
                "assets/screenshots/carry-over-direct.jpg",
                "assets/screenshots/dayscape-focus-direct.jpg",
                "assets/screenshots/end-of-day-review-direct.jpg",
            },
            {src for src in self.document.images if "screenshots/" in src},
        )

    def test_product_captures_have_no_nested_card_chrome(self) -> None:
        forbidden_classes = {
            "visual-stage",
            "stage-corner",
            "stage-coordinate",
            "feature-stage",
            "feature-stage-label",
        }
        self.assertFalse(forbidden_classes & self.document.classes)

        forbidden_selectors = (
            ".visual-stage",
            ".stage-corner",
            ".stage-coordinate",
            ".feature-stage",
            ".feature-stage-label",
        )
        for selector in forbidden_selectors:
            self.assertNotIn(selector, self.css)

    def test_css_uses_approved_tokens_and_has_no_external_runtime(self) -> None:
        required_css = (
            "--bg: #07080b",
            "--surface: #10121a",
            "--indigo: #7b82ff",
            "--cyan: #79d7ca",
            "color-scheme: dark",
            "@media (prefers-reduced-motion: reduce)",
            "@media (max-width: 900px)",
            "@media (max-width: 640px)",
            ":focus-visible",
        )
        for value in required_css:
            self.assertIn(value, self.css)

        combined = (self.html + self.css).lower()
        for forbidden in ("three.js", "three.min.js", "fonts.googleapis.com", "@import"):
            self.assertNotIn(forbidden, combined)

    def test_muted_text_token_meets_wcag_aa_on_the_canvas(self) -> None:
        def token(name: str) -> str:
            match = re.search(rf"{re.escape(name)}:\s*(#[0-9a-fA-F]{{6}})", self.css)
            self.assertIsNotNone(match, name)
            return match.group(1)  # type: ignore[union-attr]

        def luminance(hex_color: str) -> float:
            channels = [int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
            linear = [
                value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
                for value in channels
            ]
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]

        foreground = luminance(token("--muted"))
        background = luminance(token("--bg"))
        ratio = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
        self.assertGreaterEqual(ratio, 4.5)


if __name__ == "__main__":
    unittest.main()
