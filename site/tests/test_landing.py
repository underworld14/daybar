from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
import re
import unittest


SITE = Path(__file__).resolve().parents[1]
REPO = "https://github.com/underworld14/daybar"


class DocumentProbe(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.images: list[dict[str, str]] = []
        self.sources: list[dict[str, str]] = []
        self.scripts: list[dict[str, str]] = []
        self.stylesheets: list[str] = []
        self.text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {key: value or "" for key, value in attrs}
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "a" and "href" in values:
            self.links.append(values["href"])
        if tag == "img":
            self.images.append(values)
        if tag == "source":
            self.sources.append(values)
        if tag == "script":
            self.scripts.append(values)
        if tag == "link" and values.get("rel") == "stylesheet":
            self.stylesheets.append(values.get("href", ""))

    def handle_data(self, data: str) -> None:
        self.text.append(data)


def luminance(hex_color: str) -> float:
    channels = [int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(first: str, second: str) -> float:
    a, b = luminance(first), luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


class NativePlusLandingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.html = (SITE / "index.html").read_text()
        cls.css = (SITE / "styles.css").read_text()
        cls.script = (SITE / "site.js").read_text()
        cls.parser = (SITE / "quick-add.js").read_text()
        cls.document = DocumentProbe()
        cls.document.feed(cls.html)

    def theme_block(self, selector: str) -> dict[str, str]:
        match = re.search(re.escape(selector) + r"\s*\{(.*?)\}", self.css, re.S)
        self.assertIsNotNone(match, selector)
        return dict(re.findall(r"(--[\w-]+):\s*(#[0-9a-fA-F]{6})", match.group(1)))  # type: ignore[union-attr]

    def test_sections_and_in_page_anchors_exist(self) -> None:
        for section in ("main", "features", "keyboard", "install", "privacy", "demo-input", "theme-switch"):
            self.assertIn(section, self.document.ids)
        for link in self.document.links:
            if link.startswith("#"):
                self.assertIn(link[1:], self.document.ids, f"{link} has no target")

    def test_product_facts_and_links_are_preserved(self) -> None:
        for value in (
            "Plan your day.",
            "Finish what you planned.",
            "macOS&nbsp;14",
            "no account",
            "MIT licensed",
            "xattr -cr /Applications/DayBar.app",
            "DayBar-vX.Y.Z-macOS.zip",
            "Apple Reminders sync stays off",
        ):
            self.assertIn(value, self.html)
        for link in (f"{REPO}/releases/latest", REPO, f"{REPO}/blob/main/LICENSE"):
            self.assertIn(link, self.document.links)

    def test_screenshots_exist_have_dimensions_and_a_dark_variant(self) -> None:
        shots = [image for image in self.document.images if "assets/shots/" in image.get("src", "")]
        self.assertEqual(len(shots), 6)
        for image in shots:
            self.assertTrue((SITE / image["src"]).is_file(), image["src"])
            self.assertTrue(image.get("width") and image.get("height"), image["src"])
            self.assertGreater(len(image.get("alt", "")), 20, image["src"])
        dark = [source["srcset"] for source in self.document.sources if source.get("data-scheme") == "dark"]
        self.assertEqual(len(dark), len(shots))
        for path in dark:
            self.assertTrue((SITE / path).is_file(), path)
        self.assertNotIn("assets/screenshots/", self.html)

    def test_copy_has_no_dashes_and_few_middle_dots(self) -> None:
        for name, text in (("index.html", self.html), ("site.js", self.script), ("DESIGN.md", (SITE.parent / "DESIGN.md").read_text())):
            self.assertNotIn("—", text, f"em dash in {name}")
            self.assertNotIn("–", text, f"en dash in {name}")
        for line in self.html.splitlines():
            self.assertLessEqual(line.count("·"), 1, line)

    def test_no_external_runtime(self) -> None:
        for script in self.document.scripts:
            self.assertFalse(script.get("src", "").startswith(("http:", "https:", "//")))
        for href in self.document.stylesheets:
            self.assertFalse(href.startswith(("http:", "https:", "//")))
        combined = (self.html + self.css).lower()
        for forbidden in ("fonts.googleapis.com", "@import", "cdn."):
            self.assertNotIn(forbidden, combined)

    def test_demo_script_is_linked_and_uses_the_parser_port(self) -> None:
        modules = [script.get("src") for script in self.document.scripts if script.get("type") == "module"]
        self.assertEqual(modules, ["site.js"])
        self.assertIn('from "./quick-add.js"', self.script)
        self.assertIn("export function parseQuickAdd", self.parser)

    def test_both_themes_define_the_same_tokens(self) -> None:
        light = self.theme_block(":root")
        dark = self.theme_block(':root[data-theme="dark"]')
        system_dark = self.theme_block(':root:not([data-theme="light"])')
        self.assertEqual(dark, system_dark)
        self.assertEqual(set(light), set(dark))
        self.assertEqual(light["--canvas"].lower(), "#f6f6f8")
        self.assertEqual(dark["--canvas"].lower(), "#1c1c1f")
        self.assertIn("@media (prefers-reduced-motion: reduce)", self.css)
        self.assertIn(":focus-visible", self.css)

    def test_text_tokens_meet_wcag_aa_in_both_themes(self) -> None:
        for selector in (":root", ':root[data-theme="dark"]'):
            tokens = self.theme_block(selector)
            for background in ("--canvas", "--surface"):
                for foreground in ("--text", "--secondary", "--ink"):
                    ratio = contrast(tokens[foreground], tokens[background])
                    self.assertGreaterEqual(ratio, 4.5, f"{selector} {foreground} on {background}: {ratio:.2f}")
            self.assertGreaterEqual(contrast(tokens["--on-ink"], tokens["--ink"]), 4.5, f"{selector} button")
            self.assertGreaterEqual(contrast(tokens["--on-ink"], tokens["--ink-hover"]), 4.5, f"{selector} button hover")


if __name__ == "__main__":
    unittest.main()
