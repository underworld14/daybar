# DayBar Visual System

## Direction: Midnight Native

Midnight Native combines a near-black editorial canvas with the quiet depth, rounded geometry, and legibility of a native macOS utility. It borrows the reference's atmosphere—grid, glow, technical rhythm, and spatial composition—without copying its interactive cube scene or turning DayBar into a generic AI landing page.

## Color

- Canvas: `#07080B`
- Raised surface: `#10121A`
- Glass surface: `rgba(18, 20, 29, 0.72)`
- Primary text: `#F5F5F2`
- Secondary text: `#A7A9B2`
- Muted text: `#7C7F89` (5.01:1 against the canvas for small-text accessibility)
- Hairline: `rgba(255, 255, 255, 0.10)`
- Soft grid: `rgba(255, 255, 255, 0.035)`
- DayBar indigo: `#7B82FF`
- Indigo glow: `rgba(123, 130, 255, 0.24)`
- Supporting cyan: `#79D7CA`
- Existing green and amber remain reserved for real product states shown inside screenshots.

## Typography

Use the native system stack so the page feels at home on macOS and loads without a font dependency. Display headlines use medium weight, very tight tracking, and compact line height. Labels use small uppercase text with generous tracking. Body copy stays comfortably sized and never becomes low-contrast decoration.

## Geometry and Material

- A 72–80px page grid fades before the footer and never competes with text.
- Structural surfaces use thin white hairlines, restrained blur, and subtle inset highlights.
- Corners remain rounded like macOS panels, generally 18–28px.
- Indigo glow identifies important product areas; it is not sprayed across every card.
- Lightweight orbital lines echo the reference's spatial language behind real screenshots.
- Product captures are the only visible surface in their visual column: never place a screenshot inside another card, canvas, frame, or labeled stage.
- Noise is nearly imperceptible and implemented inline without another asset request.

## Composition

The hero pairs a bold, multiline promise with a direct native screenshot floating over ambient glow. Subsequent sections alternate copy and unframed UI evidence across a numbered technical rail. Installation is a practical sequence, and privacy closes the narrative as a confident statement rather than a generic feature tile.

## Motion

Motion communicates depth: a slow hero drift, subtle glow breathing, and small hover translation on actionable elements. There is no custom cursor and no heavy 3D runtime. All non-essential motion stops under `prefers-reduced-motion`.

## Boundaries

- Never recolor, distort, or obscure the real DayBar screenshots.
- Never introduce invented metrics, testimonials, integrations, or platform claims.
- Avoid neon cyberpunk, excessive glass blur, dense dashboards, or glowing every border.
- Preserve semantic HTML, keyboard focus, responsive reading order, and static hosting.
