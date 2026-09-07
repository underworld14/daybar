# DayBar Midnight Native Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace DayBar's current light product page with the approved Midnight Native visual system while preserving all product facts, links, screenshots, accessibility, and static hosting behavior.

**Architecture:** Keep the site dependency-free and progressively enhanced: semantic content lives in `site/index.html`, and all visual atmosphere, layout, responsive behavior, and motion live in `site/styles.css`. Real DayBar PNG captures remain the visual proof; CSS pseudo-elements and decorative markup provide the futuristic spatial layer without Three.js or a JavaScript runtime.

**Tech Stack:** Static HTML5, modern CSS, existing PNG assets, Python standard-library smoke assertions, local HTTP server, Xcode test suite.

## Global Constraints

- Preserve the DayBar name, app icon, calm voice, existing product facts, and all current external destinations.
- Use the Midnight Native tokens and material rules from `DESIGN.md`.
- Keep the site self-contained with no framework, Three.js, external webfont, or new runtime dependency.
- Preserve the existing static GitHub Pages deployment contract under `site/`.
- Keep real screenshots undistorted and readable with their declared intrinsic dimensions.
- Preserve semantic landmarks, heading order, skip navigation, meaningful alt text, keyboard focus, and `prefers-reduced-motion`.
- Support 320px width without horizontal scrolling.
- Do not invent testimonials, metrics, customers, integrations, or commercial claims.

---

### Task 1: Restructure the landing narrative

**Files:**
- Modify: `site/index.html`

**Interfaces:**
- Consumes: Existing screenshot paths under `site/assets/screenshots/`, app icon, GitHub and release URLs.
- Produces: Semantic class hooks consumed by Task 2: `.ambient-grid`, `.site-header`, `.hero`, `.visual-stage`, `.proof-rail`, `.feature`, `.install`, `.trust`, and `.site-footer`.

- [ ] **Step 1: Record the current factual contract**

Run:

```bash
rg -n 'github.com/underworld14/daybar|macOS|menu bar|SwiftData|MIT|assets/screenshots' site/index.html
```

Expected: all download, source, platform, local-storage, license, and four screenshot references are present before editing.

- [ ] **Step 2: Replace the page composition while preserving facts**

Use this semantic outline in `site/index.html`:

```html
<body>
  <a class="skip-link" href="#main">Skip to main content</a>
  <div class="ambient-grid" aria-hidden="true"></div>
  <header class="site-header">...</header>
  <main id="main">
    <section class="hero" aria-labelledby="hero-heading">
      <div class="shell hero-layout">
        <div class="hero-copy">...</div>
        <div class="hero-visual" aria-label="DayBar product preview">
          <div class="visual-stage">...</div>
        </div>
      </div>
    </section>
    <section class="proof-rail" aria-label="Product highlights">...</section>
    <section id="features" class="features" aria-labelledby="features-heading">...</section>
    <section id="download" class="install" aria-labelledby="install-heading">...</section>
    <section class="trust" aria-labelledby="trust-heading">...</section>
  </main>
  <footer class="site-footer">...</footer>
</body>
```

The hero must retain the exact headline “Plan your day. Finish what you planned.”, the current lede, both CTAs, and the platform metadata. Each feature must receive its approved label (`01 / CARRY`, `02 / FOCUS`, `03 / REVIEW`) and keep its existing description and screenshot. Installation retains all three steps plus the Terminal disclosure. Privacy retains the SwiftData, no-account, no-cloud, and on-device Apple Intelligence claims.

- [ ] **Step 3: Verify the semantic and factual contract**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
html = Path('site/index.html').read_text()
required = [
    'id="main"', 'id="hero-heading"', 'id="features"', 'id="download"',
    'Plan your day. Finish what you planned.',
    'https://github.com/underworld14/daybar/releases/latest',
    'https://github.com/underworld14/daybar',
    'assets/screenshots/today-panel.png',
    'assets/screenshots/carry-over.png',
    'assets/screenshots/dayscape-focus.png',
    'assets/screenshots/end-of-day-review.png',
    'macOS&nbsp;14+', 'SwiftData', 'MIT',
]
missing = [value for value in required if value not in html]
assert not missing, missing
assert html.count('<h1') == 1
print('semantic contract: PASS')
PY
```

Expected: `semantic contract: PASS`.

- [ ] **Step 4: Commit the structural change**

```bash
git add site/index.html
git commit -m "feat(site): restructure Midnight Native landing"
```

### Task 2: Implement the Midnight Native visual system

**Files:**
- Modify: `site/styles.css`

**Interfaces:**
- Consumes: The class hooks produced by Task 1 and durable tokens from `DESIGN.md`.
- Produces: Desktop, tablet, mobile, hover/focus, and reduced-motion presentation with no JavaScript dependency.

- [ ] **Step 1: Replace tokens and global atmosphere**

Define the approved core variables and global layers:

```css
:root {
  --bg: #07080b;
  --surface: #10121a;
  --surface-glass: rgba(18, 20, 29, 0.72);
  --text: #f5f5f2;
  --text-secondary: #a7a9b2;
  --muted: #70737d;
  --line: rgba(255, 255, 255, 0.1);
  --grid-line: rgba(255, 255, 255, 0.035);
  --indigo: #7b82ff;
  --indigo-glow: rgba(123, 130, 255, 0.24);
  --cyan: #79d7ca;
  --shell: min(1180px, calc(100% - 3rem));
  color-scheme: dark;
}

.ambient-grid {
  position: fixed;
  inset: 0;
  pointer-events: none;
  background-image:
    linear-gradient(var(--grid-line) 1px, transparent 1px),
    linear-gradient(90deg, var(--grid-line) 1px, transparent 1px);
  background-size: 80px 80px;
  mask-image: linear-gradient(to bottom, #000 0%, transparent 90%);
}
```

Keep all content above decorative layers and use a subtle inline noise texture at no more than `0.025` opacity.

- [ ] **Step 2: Build hero and product stage styling**

Implement a spacious two-column hero, tight editorial heading, clear actions, and a bordered glass stage. Use pseudo-elements for indigo atmosphere, construction corners, and lightweight squares. The screenshot must use `object-fit: contain`, stay uncropped, and remain the highest-contrast object in the stage.

Required behavior:

```css
.hero-layout {
  display: grid;
  grid-template-columns: minmax(0, 1.05fr) minmax(420px, 0.95fr);
  align-items: center;
}

.visual-stage {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--line);
  border-radius: 28px;
  background: linear-gradient(180deg, rgba(255,255,255,.035), rgba(255,255,255,.008));
}

.shot-hero {
  width: min(100%, 520px);
  object-fit: contain;
  filter: drop-shadow(0 32px 60px rgba(0,0,0,.42));
}
```

- [ ] **Step 3: Style proof, features, install, privacy, and footer**

Use one coherent system of hairlines, restrained glass surfaces, numbered labels, and alternating feature layouts. Do not turn every section into a floating rounded card. Installation step numbers should align as a sequence on desktop; the trust statement should use larger type and fewer visual containers than the feature chapters.

- [ ] **Step 4: Add responsive and interaction states**

Use breakpoints near `900px` and `640px`. Below `900px`, collapse the hero and feature chapters to one column. Below `640px`, use `--shell: min(100% - 1.5rem, 1180px)`, make primary actions easy to tap, hide non-essential geometry, and reduce display sizes. Include:

```css
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

Every interactive element must retain a visible `:focus-visible` outline.

- [ ] **Step 5: Run static checks and commit**

Run:

```bash
git diff --check
node /Users/izzadev/.agents/skills/impeccable/scripts/detect.mjs --json site/index.html site/styles.css
```

Expected: no whitespace errors and no unresolved high-confidence design findings.

Commit:

```bash
git add site/styles.css site/index.html
git commit -m "feat(site): apply Midnight Native visual system"
```

### Task 3: Perform bounded visual and release verification

**Files:**
- Modify if defects are found: `site/index.html`
- Modify if defects are found: `site/styles.css`

**Interfaces:**
- Consumes: Completed static site from Tasks 1–2.
- Produces: Verified desktop/mobile landing page and a pushed `main` commit.

- [ ] **Step 1: Serve the page and verify all resources**

Run:

```bash
python3 -m http.server 8765 --directory site
```

In another shell, request `/`, `/styles.css`, the icon, and all four screenshots. Expected: HTTP 200 for every resource.

- [ ] **Step 2: Capture one bounded visual QA round**

Inspect at desktop `1440×1000` and mobile `390×844`. Check the hero fold, screenshot legibility, button states, feature alternation, installation flow, privacy ending, footer, horizontal overflow, and reduced-motion emulation. Record all defects from both sizes before editing.

- [ ] **Step 3: Apply one consolidated correction batch**

Fix every defect from the first QA round in `site/index.html` and `site/styles.css`. Do not introduce new sections, claims, dependencies, or unapproved imagery.

- [ ] **Step 4: Confirm with one final visual round**

Re-capture desktop and mobile once. Expected: no clipping, overlap, horizontal scroll, illegible copy, weak focus state, or screenshot distortion.

- [ ] **Step 5: Run final gates**

Run:

```bash
git diff --check
xcodebuild -project DayBar.xcodeproj -scheme DayBar -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

Expected: `** TEST SUCCEEDED **` and `252 tests, with 0 failures` or the current higher test count with zero failures.

- [ ] **Step 6: Close Beads task, commit corrections, and push**

```bash
bd close daybar-7p6 --reason="Midnight Native landing shipped with desktop/mobile QA and verification."
bd export -o .beads/issues.jsonl
git add .beads/issues.jsonl .beads/interactions.jsonl site/index.html site/styles.css
git commit -m "feat(site): ship Midnight Native landing page"
git pull --rebase
git push
git status --short --branch
```

Expected: `main...origin/main` with no tracked changes. Preserve unrelated `.env` and `.venv/` files.
