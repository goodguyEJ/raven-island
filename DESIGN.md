# Raven Island Design System

How Raven Island looks and moves. Sections 1 to 6 record the app as it is built today; section 7
(Motion) is the standard that new and changed animation follows. Where today's code does not yet
meet section 7, the gap is listed in 7.9. The presets live in `Sources/RavenIslandApp/Motion.swift`.

Platform: macOS 14+, SwiftUI inside an AppKit `NSPanel` that hangs from the notch. Pointer and
keyboard, no touch. Values are in points.

## 1. Visual Theme & Atmosphere

Raven Island is an extension of the hardware notch, so its canvas is the notch's own pure black.
The panel never looks like a window: no title bar, no shadow, no material. Its top corners curve
outward into the screen edge ("ears") so it reads as the notch growing.

On that black sit three things: white text at a handful of fixed opacities, one status colour per
session state, and 8-bit pixel ravens that act out what each session is doing. The ravens carry the
personality; everything around them stays quiet and dense, like a system HUD.

**Key characteristics**
- Pure black `#000000` surface, always dark, whatever the system appearance
- White at stepped opacities for all text and chrome; colour only means state
- Pixel-art ravens (personas) drawn on a `Canvas`, moving in whole sprite pixels
- Continuous-corner shapes throughout (`style: .continuous`)
- Capsule buttons, never bordered or bezelled controls, inside the panel
- Settings, setup and debug windows are plain system windows with stock controls

## 2. Colour Palette & Roles

### Surfaces
| Role | Value | Where |
|---|---|---|
| Panel | `#000000` | `NotchPanelShape` fill |
| Card | white 9% | Request card |
| Inset well | black 55% on card | Command, diff and plan boxes |
| Field | white 12% | `DarkField`, artwork placeholder |
| Row hover | white 12% | Session row under the pointer |
| Row attention | white 7% | Session row that needs you, not hovered |
| Chip | white 14% | Subagent count, "Clear N done", pager buttons |
| Option | white 7%, selected 16% | Question options |
| Day selected | white 10% | Week strip |
| Divider | white 12% (idle home) | 1pt rules |

### Text (white at fixed opacities)
| Step | Opacity | Use |
|---|---|---|
| Primary | 100% | Titles, project names |
| Strong | 85–90% | Active labels, event titles |
| Body | 75–80% | Header icons, marquee, command text |
| Secondary | 55–60% | Subtitles, paths, footer links |
| Tertiary | 45–50% | Timers, "+N more", empty states |
| Disabled | 30–40% | Disabled controls |

### Session state
| State | Colour | Glyph |
|---|---|---|
| Working | system blue | spinner arc |
| Needs approval | system orange | `exclamationmark.circle.fill`, pulsing |
| Waiting for input | system yellow | `ellipsis.bubble.fill`, pulsing |
| Done | system green | `checkmark.circle.fill` |
| Error | system red | `xmark.octagon.fill` |
| Idle | system gray | small dot |

### Semantic and accent
- Allow / confirm: green. Deny / destructive: red (`PillButton` tint)
- Diff: removed `rgb(255,133,128)`, added `rgb(128,230,143)`
- "More below" marker and warnings: system yellow, black text
- Today and calendar call to action: `rgb(10,133,255)`
- Music accent: the artwork's own tint; without artwork, or when the artwork is grey or near black, the player's colour
  (Spotify `#1DB954`, Music `#FA2D48`). Calendar bars use each calendar's own colour.

Colour is never the only signal: every state also has a glyph, a label and a raven pose.

## 3. Typography

SF Pro (system font) at fixed sizes; the panel is a fixed-size HUD and does not scale with Dynamic
Type (macOS has none). Numbers that tick use `.monospacedDigit()`.

| Role | Size | Weight |
|---|---|---|
| Plan heading | 14 | bold |
| Month label | 14 | semibold |
| Title (row, card, track) | 13 | semibold |
| Question / plan subheading | 12.5 | medium / semibold |
| Button, body, option | 12 | semibold / regular / medium |
| Subtitle, state label, footer | 11.5 | regular / medium |
| Code and diff | 11–11.5 | regular, monospaced |
| Chip, header, pager, marquee | 11 | medium / semibold |
| Timer, meta, clock | 10.5 | regular / semibold, monospaced digits |
| Shortcut hint, subagent count | 10 | medium |
| Weekday | 9.5 | semibold |

No italics, no custom fonts. Emphasis comes from weight and opacity.

## 4. Components

- **Collapsed notch wings.** 46pt each side of the notch with about 8pt kept clear at the outer edges, 1pt taller than the notch. Left: the most urgent
  session's raven (or a status glyph). Right: the time (no AM/PM), coloured by time of day: night blue, rose at dawn, gold in the morning, amber in the afternoon, violet at dusk. With "rotate the time, date and battery" on in Settings, every 15s the date (MM/DD) and then the battery percent (red to 20%, yellow to 50%, green above) show for 3s each (crossfade) before the time returns. With nothing
  running the time stays on the right, and on the left a strolling raven, or a listening raven /
  artwork with bars while music plays.
  Without a notch: a 26pt pill; with sessions running it shows the most urgent state and the time
  (or the rotation) in place of the old session count.
- **Expanded panel.** 600pt wide, bottom corners 22pt, ears into the screen edge. Header: left, the mini
  player (track title as the button that opens the player, play/pause) while sessions run and
  music plays, otherwise today's date and the next event; right, "Clear N done", battery, sound
  and settings. Then content. Battery: a menu-bar-style battery filled to the level,
  then the percent (left out while "Clear N done" shows, so the row stays clear of the notch); green with a bolt while plugged in, red at 20% or below; hidden on Macs without one.
- **Session row.** 50pt tall in a 54pt slot, 12pt corners, raven 34pt, title + subtitle, state and
  elapsed time right, a clear button for rows without a waiting decision. Up to 5 rows, then a pager.
- **Request card.** 14pt corners, white 9%. Permission (226pt), plan (350pt) or question (up to
  360pt). A review box that must be scrolled to the end before Allow works; buttons stay inert for
  a short arming delay after the card appears.
- **Pill button.** 26pt capsule, 12pt semibold. Quiet: tint 16% (26% hover). Prominent: tint 90%
  (100% hover) with black text. Disabled 40%.
- **Header icon button.** 24×22, white 75% (100% hover) on a white 16% circle when hovered.
- **Idle home.** 96pt tall. Music half: 56pt artwork (22% corner radius) or spinning record, player
  badge, title, artist, progress, transport. Calendar half: month, week strip, up to two events; or
  a calendar prompt card.
- **Pixel ravens.** Frame-stepped sprites; strolling ravens move in whole sprite pixels and flip at
  each end. Headphones go on while music plays. In the idle notch each raven stops every 45s (staggered), turns to face
  us and waves for 4s, then walks on; still under Reduce Motion. The header track title is the
  button that opens the player.
- **Settings / setup / debug.** Stock `Form`, `TabView`, `Toggle`, `Picker` in titled windows.

## 5. Layout

- Spacing steps in use: 2, 4, 6, 8, 12, 18. Panel side padding 18; rows and cards inset 8.
- Radius scale: 7–9 (wells, fields, options, day), 12 (row), 14 (card), 22 (panel bottom),
  capsule (buttons, chips), circle (icon hover).
- The window is exactly the size of the shape, so everything outside it stays clickable. It grows
  before the shape animates open and shrinks only after the shape has finished closing.

## 6. Depth & Elevation

Flat. No shadows, no blur, no materials. Depth is white-opacity steps on black: panel → card (9%)
→ inset well (black 55%). The panel sits above the menu bar and is hidden from screen capture by
default.

## 7. Motion

### 7.1 Principles
1. **The panel is the notch.** Size changes are one continuous spring of the black shape; content
   fades inside it. Nothing slides in from outside the shape.
2. **Motion explains a change, never decorates one.** If a state change is not animated, it should
   be because it is instant by design (hover delay, typing), not by omission.
3. **Brief, and quieter the more often it happens.** Hover and press feedback are the shortest
   motions in the app. The panel opens on every hover, so its spring does not bounce.
4. **Never in the way.** Animations do not block or delay input and can be interrupted: a hover
   during a collapse reopens from where the shape is. The one deliberate delay is the request
   card's arming delay, which is a safety rule, not an animation.
5. **Motion is optional.** Every animation has a Reduce Motion fallback (7.8).

### 7.2 Durations
| Token | Value | Use |
|---|---|---|
| `quick` | 0.12s | Hover highlight, press, release |
| `standard` | 0.20s | Crossfades, symbol swaps, selection, Reduce Motion fades |
| `panelSettle` | 0.45s | How long the window waits for the panel spring before shrinking |

### 7.3 Springs and easing
| Token | Value | Use |
|---|---|---|
| `panel` | spring, response 0.36, damping 0.82 | Expand, collapse, any change of panel size, list reflow, card arrival |
| `press` | spring, response 0.25, damping 0.9 | Press scale and release |
| `hover` | ease-out, `quick` | Hover fill and text opacity |
| `fade` | ease-in-out, `standard` | Content crossfade, selection, enable/disable |

No bare `.spring()` and no per-view literals: views take these from one shared place in code.
No bounce below 0.8 damping; the surface is small and sits in peripheral vision.

### 7.4 Panel and element transitions
| Change | Motion |
|---|---|
| Collapsed ↔ expanded | Shape springs (`panel`); old content fades out, new content fades in |
| Panel grows or shrinks while open | Shape springs (`panel`); window resizes before growing, after shrinking |
| Request card arrives | Slides in from the trailing edge + fade, on `panel` |
| Request card answered | Fades out as the panel resizes (`panel`); the next card arrives as above |
| Session row added / removed | Fade + the list reflows on `panel` |
| Session rows reorder | Rows move on `panel` |
| Page change | Rows crossfade (`fade`) |
| Focused session ↔ show all | Shape springs; rows fade |
| Note field ↔ decision buttons | Crossfade (`fade`) |
| Text or number changes in place (state label, counts, track title) | Crossfade (`fade`); numbers use numeric content transition |
| Symbol swaps in place (play/pause, sound on/off, clear check) | Symbol replace transition |
| Day selection | Highlight moves on `panel` (fades under Reduce Motion); event rows crossfade |
| Artwork / tint change | Crossfade (`fade`) |

### 7.5 Press, hover and gesture feedback
- **Hover:** fill and text opacity ease on `hover`. Never a scale; the pointer is precise and the
  targets are small.
- **Press:** capsule and icon buttons dip to 96% scale and 85% opacity on `press` while the mouse
  is down, and release on the same spring. The action fires on mouse-up inside, as system buttons do.
- **Disabled → enabled** (Allow after review, arming): opacity eases on `fade`.
- **Gestures:** tap and hover only. No drag, swipe or long-press; the panel sits where system
  gestures live. Everything reachable by pointer is also labelled for VoiceOver, and Allow / Deny
  have global shortcuts.

### 7.6 Loading, success and error
| State | Motion |
|---|---|
| Working | Spinner arc, 0.9s per turn, linear; raven work loop (0.22–0.4s frames) |
| Needs you (approval, input) | Glyph opacity pulse 1 → 0.45, 0.8s ease-in-out, autoreversing; panel auto-opens |
| Done | Green check; one symbol bounce when a row first becomes done |
| Decision sent | Card fades out; no extra confirmation animation, the session row's state is the confirmation |
| Music playing | Bars step every 0.28s; record turns 180°/s and holds its angle when paused |
| Long title | Marquee at 25pt/s after a 1.5s pause |

Ravens, bars, record and marquee are driven by a clock (`TimelineView`); the spinner and pulse are repeating animations. No loop uses a spring.

### 7.7 Haptics
None today. macOS haptics exist only on Force Touch trackpads, and the HIG reserves them for
discrete, meaningful events. If adopted, the only candidates are SwiftUI `sensoryFeedback`
`.levelChange` when a decision is sent by click and `.alignment` on day selection; sounds remain
the primary non-visual feedback. Never on hover, never on auto-open.

### 7.8 Reduce Motion
Read live from the system setting, not once at launch.

| Normal | Reduce Motion |
|---|---|
| Panel spring | Shape changes size at once; the content inside it fades over `standard` |
| Card slide + fade | Fade only |
| Row moves and reflow | Short ease (`fade`), no spring |
| Press scale | Opacity only |
| Symbol replace / bounce, rolling digits | Plain swap or fade |
| Spinner, pulse, bars, record, marquee, ravens | Still: static arc, steady glyph, resting bars, truncated text, each raven's most telling frame |

Hover fades stay; they are opacity only.

### 7.9 Known gaps (today's code vs this section)
- Still unanimated: calendar prompt ↔ week, the crew caption, question option selection, hover on
  day buttons, footer links and option rows.
- Collapsed and expanded content fade on the panel spring, not staged.
- On a tint change the artist text fades, but the progress clock and bar change colour in one step.
- Clock-tied loop timings (bars 0.28s, raven frames, marquee, record) live in their own views.
- Under Reduce Motion a collapse is mostly a snap: the outgoing content is clipped by the small shape.
- No animation, and no Reduce Motion path, has been checked by eye yet.

## 8. Do's and Don'ts

### Do
- Keep the panel pure black and flat
- Use white opacity steps for hierarchy and colour only for state
- Take every duration and curve from the shared motion presets
- Give every animation a Reduce Motion path, and check it
- Keep hit targets ≥ 22pt tall with their full frame clickable (`contentShape`)
- Run untrusted text through `TextSafety.visible`

### Don't
- Don't add shadows, blur, materials or gradients to the panel
- Don't bounce: no spring below 0.8 damping
- Don't animate hover with scale or movement
- Don't delay or block input for an animation
- Don't add drag or swipe gestures to the panel
- Don't use colour alone to carry meaning
- Don't restyle the settings or setup windows; they are system UI

## 9. Accessibility & Platform Behaviour

- **Reduce Motion:** section 7.8.
- **VoiceOver:** rows and cards combine their children; glyphs and ravens carry labels; decorative
  art is hidden.
- **Keyboard:** the panel never takes focus on its own; it becomes key only when a text field is
  clicked. Allow ⌃⌥Y and Deny ⌃⌥N work globally and are off while a note is being typed.
- **Pointer:** hover opens the panel, leaving closes it after 0.35s; first click counts even though
  the panel is not key.
- **Displays:** with a notch the panel hangs from it; without one it is a floating pill and an
  ordinary rounded panel.
- **Screen sharing:** the panel is excluded from capture unless the user turns that off.
