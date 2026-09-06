# DayBar Landing-Page Screenshot Assets

**Date:** 2026-09-06  
**Issue:** `daybar-l84`

## Goal

Replace the landing page's four illustrative screenshot placeholders with polished assets built from captures of the real DayBar interface. The images must communicate the product quickly, contain only fictional demo content, and preserve the user's existing DayBar data.

## Chosen approach

Use curated hybrid compositions: capture the native DayBar UI without altering it, crop away unrelated desktop chrome, and place the captures on a consistent neutral canvas with restrained spacing and shadow. This keeps the product representation authentic while matching the existing landing-page aspect ratios.

## Asset set

| Asset | Product state shown | Target canvas |
|---|---|---|
| `today-panel` | Today's habits, active todos, completed work, progress, and focus controls | 640 x 720 |
| `carry-over` | Unfinished tasks carried across several days with calm aging indicators | 560 x 420 |
| `dayscape-focus` | Seven-day focus history and a visible focus streak | 560 x 420 |
| `end-of-day-review` | Leftover-task decisions, a short reflection, and a selected mood | 560 x 420 |

Final files will use PNG so the landing page displays real raster captures rather than reconstructed illustrations. The HTML references and accessible alt text will be updated to match.

## Demo content

All visible content will be fictional, concise, and in English to match the landing page. The dataset will include believable tasks such as preparing a launch note, reviewing a design, taking a short walk, and planning tomorrow. It will include a mix of active, completed, carried-over, and future work, plus habits, focus sessions, and an end-of-day reflection.

No real reminders, notes, calendar data, names, or personal content may appear in the captures.

## Data-safety flow

1. Quit DayBar and copy its complete SwiftData store files to a timestamped backup outside the repository.
2. Launch DayBar with a controlled demo dataset containing only fictional values.
3. Capture each required state and generate the four final landing-page compositions.
4. Quit DayBar, restore the original store files exactly, and relaunch the installed app.
5. Verify that the restored store files match the backup and that DayBar opens successfully.

The backup remains recoverable until the final verification has passed.

## Capture and composition rules

- Capture at Retina resolution from the installed Release app.
- Keep the native typography, colors, corner radii, and controls unchanged.
- Exclude the macOS menu bar, notch, wallpaper, cursor, notifications, and unrelated windows.
- Do not add feature claims, annotations, fake controls, or decorative content inside the app UI.
- Use one consistent light neutral background and subtle shadow across all four compositions.
- Preserve legibility at the rendered sizes used by `site/index.html`.

## Verification

- Visually inspect each PNG at full size and at its landing-page rendered size.
- Confirm all four HTML image paths resolve and no placeholder wording remains.
- Run the site's available validation or a local static-server smoke check.
- Confirm the installed DayBar process is healthy after restoring the original data.
- Confirm the worktree contains only the intended spec, asset, and landing-page reference changes, aside from the user's pre-existing untracked files.
