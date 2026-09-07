# DayBar Midnight Native Landing Page Design

## Objective

Redesign the existing DayBar product page using the approved Midnight Native direction. The page should feel related to the supplied KilasLab reference through its dark editorial canvas, subtle grid, indigo atmosphere, precise technical labels, and sense of depth, while remaining unmistakably DayBar: calm, native to macOS, lightweight, and centered on real UI evidence.

## Scope

The redesign covers `site/index.html` and `site/styles.css`. It preserves the existing product facts, real screenshots, app icon, download and GitHub destinations, installation steps, privacy statement, license, and static GitHub Pages deployment. No application code, release packaging, or screenshot contents change.

## Chosen Approach

Use a code-first, dependency-free implementation. The real Today panel replaces the reference's 3D cube scene as the hero centerpiece. CSS supplies the surrounding depth through a glass stage, grid, glow, orbital lines, and a few abstract squares. This keeps the page fast and product-led while carrying the reference's futuristic atmosphere.

Two alternatives were considered and rejected:

- A full Three.js hero would be more interactive but slower, less accessible, and less relevant than showing the actual product.
- A dark hero with light content sections would preserve more of the old page but weaken the new visual world's continuity.

## Page Structure

### Header

A restrained translucent header contains the DayBar icon and name, anchor links for features and install, and a GitHub link. Hairlines and backdrop blur establish depth without becoming a floating pill-heavy navigation system.

### Hero

The first viewport uses a two-column composition on desktop:

- An eyebrow identifies DayBar as a native macOS daily planner.
- A large multiline headline keeps “Plan your day. Finish what you planned.”
- The existing explanatory copy, primary download CTA, secondary GitHub CTA, and platform metadata remain.
- The real Today panel sits inside a dark glass stage with a focused indigo glow, fine construction lines, corner marks, and lightweight CSS geometric accents.

On mobile, copy appears before the visual, CTAs remain comfortably tappable, and decorative geometry is reduced.

### Product Rhythm

A narrow proof rail summarizes the product's factual operating model: menu-bar native, local-first, and no account. It bridges the hero into the feature story without inventing metrics.

### Feature Chapters

The three existing features become numbered editorial chapters:

1. `01 / CARRY` — gentle carry-over and aging states.
2. `02 / FOCUS` — Dayscape and the focus streak.
3. `03 / REVIEW` — triage, reflection, and optional mood.

Each chapter pairs concise copy with its real screenshot inside a bordered stage. The composition alternates on desktop and remains a single logical reading order on mobile.

### Installation

Installation remains prominent and practical. The three steps become a numbered horizontal sequence on wide screens and a vertical sequence on narrow screens. The terminal alternative stays in a disclosure element with readable code contrast.

### Privacy and Footer

The local-and-private message becomes the final large statement, supported by a concise list of factual assurances. The footer retains MIT license, source link, and copyright.

## Visual System

The durable tokens and material rules are recorded in `DESIGN.md`. The core canvas is near-black with off-white type, muted grey copy, thin white hairlines, DayBar indigo glow, and a restrained cyan supporting accent. Native system typography keeps the site fast and aligned with the macOS product.

## Interaction and Motion

- Buttons lift by only a few pixels and gain a controlled indigo highlight.
- The hero panel drifts slowly within its stage; geometric accents move at lower amplitude.
- Navigation and disclosure controls keep visible keyboard focus.
- `prefers-reduced-motion` disables decorative movement and smooth scrolling.
- No custom cursor, autoplay media, scroll hijacking, or heavy JavaScript dependency is introduced.

## Responsive Behavior

- Desktop uses an expansive two-column hero and alternating feature chapters.
- Tablet tightens type and stage dimensions without hiding product information.
- Mobile uses a single column, full-width CTAs where helpful, reduced atmosphere, no clipped screenshots, and safe-area-aware header spacing.
- The page must remain usable at 320px width and avoid horizontal scrolling.

## Accessibility and Performance

- Preserve semantic landmarks, heading order, skip link, meaningful alt text, and keyboard reachability.
- Maintain WCAG AA contrast for text and controls.
- Decorative elements are hidden from assistive technology and never communicate required information.
- Keep the site self-contained: HTML, CSS, current PNG assets, and no new runtime framework or webfont request.
- Existing screenshot dimensions remain declared to prevent layout shift.

## Verification

Implementation is complete when:

1. All current links, facts, screenshots, and install instructions remain present.
2. Desktop and mobile screenshots show no clipping, overlap, unreadable contrast, or horizontal scroll.
3. Keyboard focus and reduced-motion behavior work.
4. The static site serves every referenced asset successfully.
5. The Impeccable mechanical detector reports no unresolved high-confidence issues.
6. `git diff --check` and the project test suite pass before completion.
