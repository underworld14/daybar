# DayBar Visual System

## Direction: Native+ web

The landing page should feel like the app it sells. DayBar is a native macOS menu-bar planner, so the
page uses the Mac's own type, follows the visitor's light or dark setting, and keeps its surfaces quiet.
Real screenshots and one working piece of the product (the quick-add field) carry the page. Nothing is
decorated for its own sake.

Dial: ENERGY 2 / RHYTHM 2 / MOTION 1

- ENERGY 2: one bold element (the live quick-add demo in the hero). Everything around it is calm.
- RHYTHM 2: every section shares the same left edge, heading style and gutter. The composition changes
  where the content needs it: split hero, two-column ledger, full-bleed board, asymmetric pair.
- MOTION 1: motion only answers the visitor (focus rings, a 150ms chip change in the demo). No scroll
  reveals, no ambient animation. Everything stops under `prefers-reduced-motion`.

## Color

| Token | Light | Dark | Use |
|---|---|---|---|
| `--canvas` | `#F6F6F8` | `#1C1C1F` | Page. A cool grey like a macOS window, never cream, never `#111`. |
| `--surface` | `#FFFFFF` | `#26262A` | Inputs, code, keycaps, the details panel. |
| `--text` | `#17181C` | `#F2F2F4` | Headings and body. |
| `--secondary` | `#5B5E69` | `#A6A8B2` | Supporting copy. AA on canvas and surface. |
| `--hairline` | 10% text | 12% text | Dividers and field borders. |
| `--ink` | `#4F55E3` | `#8C91FF` | The only accent: priority bars, links, the primary button, focus rings. |

Green, blue and amber appear only inside screenshots, where they are real product states.

## Typography

The system stack (`-apple-system`, SF Pro on a Mac) so the page reads like the screenshots next to it and
loads no font files. Display 600 with tight tracking (-0.022em); body 17px on 1.55 leading, lines under
65 characters. Monospace appears only for text a person types: quick-add syntax and Terminal commands.
Sentence case everywhere, no uppercase labels, no eyebrows.

## Shape

- Buttons and inputs: 8px radius. Keycaps and code: 6px.
- Chips: full pill, the same shape the app uses for its quick-add chips.
- Window screenshots keep their own macOS corners (alpha masked); strips cropped from inside a window
  get a 12px radius and a hairline so they read as a cut-out of the panel.
- Shadow only on whole-window screenshots, because those windows float on macOS too.

## Identity motif

The three priority bars (one, two or three filled in ink). They appear where priority is real: the demo's
priority chip and the legend that explains them. They never become ornament.

## Composition

1. Header: logo, Features, Install, GitHub.
2. Hero, split: headline, one-line lede, the live quick-add field, download. The tray screenshot on the right.
3. Ledger rows (heading left, content right): manual order with the priority legend, then the Now card and focus.
4. Full-bleed board screenshot with a short caption above it.
5. Asymmetric pair: carry-over strip and copy on the left, the end-of-day review on the right.
6. Keyboard: two lists of real shortcuts, panel and main window.
7. Install: three numbered steps (a real sequence), the Terminal alternative, update and backup notes.
8. Privacy: only claims the code supports.
9. Footer: license, source, appearance switch (Auto, Light, Dark).

## Boundaries

- No em or en dashes in copy. At most one middle dot per line.
- No grid, glow, orbit, noise, gradient wash or glass.
- No invented numbers, testimonials, integrations or platform claims.
- Never recolor, distort or mock up the screenshots. Recapture them from the app (see `.build/qa.sh`).
- Static hosting: no framework, no external runtime, no font requests.
