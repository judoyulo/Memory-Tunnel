# Design System — Memory Tunnel

## Product Context
- **What this is:** An iOS app that helps people who've moved cities or countries maintain relationships with friends from past life chapters, using photos as low-friction reasons to reconnect.
- **Who it's for:** Adults 25–40 who have lived in 2+ cities or countries and have meaningful relationships spread across multiple life chapters (expats, international students, third-culture kids).
- **Space/industry:** iOS photo / relationship-maintenance app. Peers: Day One (intimacy through restraint), Locket (ambient presence), Polarstep (memory contextualization). Deliberate departure from Unfold (over-styled) and Google Photos Memories (algorithmically curated).
- **Project type:** iOS native app (Swift / SwiftUI). No web frontend in v1 except the static invitation link preview page.

## Aesthetic Direction
- **Direction:** Intimate Minimal
- **Decoration level:** None. Photos are the only visual richness. No templates, no frames, no filters, no artistic treatments.
- **Mood:** The app feels like it lives inside the memory — warm, quiet, private. Like a film darkroom in the moment before the print is revealed. Not clinical white, not cold dark mode. Warm cream and near-black, with one precious accent that appears only when something matters.
- **Key insight:** The category mistake is over-decorating memories. The specificity of context ("Barcelona · 4 years ago") does the emotional work that templates and filters try to do artificially. Decoration IS context — not chrome.

## Color

- **Approach:** Restrained — one accent color used sparingly at emotional peaks only
- **Background:** `#F5EAD8` — warm cream; evokes a freshly developed photo print; clearly warm, never clinical
- **Surface (tiles, cards, inputs):** `#EDE0CC` — slightly deeper cream for elevation
- **Label (primary text, CTA fill):** `#1C1C1E` — iOS near-black; never pure black
- **Secondary text:** `#636366` — iOS secondary label
- **Tertiary text (dividers, meta, placeholders):** `#8E8E93` — iOS tertiary label
- **Accent:** `#C8956C` — warm amber; **PRECIOUS: appears ONLY at emotional peaks**
  - ✓ Memory sent confirmation (checkmark background)
  - Birthday card trigger indicator dot
  - Decay detection notification dot
  - Empty state SF Symbol
  - Nowhere else. If you're considering using accent for interactive state or highlight — don't. When amber appears, it must mean something.
- **Border / separator:** `rgba(28,28,30,0.08)` on cream backgrounds
- **Success:** `#4CAF79`
- **Error:** `#E04F4F`
- **Dark mode:** System-follow. Dark mode surfaces: `#1C1C1E` bg, `#2C2C2E` surface, `#FFFFFF` label, `#AEAEB2` secondary, `#636366` tertiary. Accent unchanged.

## Typography

**All text uses SF Pro (system font). No custom font imports. No font loading.**

Using SF Pro means:
- Zero loading time, zero flash, zero subset management
- Native iOS rendering at every Dynamic Type size
- Inherent familiarity and legibility on every iPhone

**Text style mappings:**

| Role | SF Pro Style | Size | Weight | Color |
|------|-------------|------|--------|-------|
| Daily card — name | Display | 28pt | Medium (600) | white |
| Daily card — sub (place · time) | Text | 15pt | Regular | white at 82% opacity |
| Button label | Text | 17pt | Semibold (600) | depends on button variant |
| Body / notification text | Text | 15pt | Regular | `#1C1C1E` |
| Caption / chapter divider | Text | 12pt | Regular | `#8E8E93` |
| Empty state title | Display | 22pt | Regular | `#1C1C1E` |
| Empty state body | Text | 15pt | Regular | `#636366` |

**Dynamic Type:** Use semantic text styles (`.title2`, `.body`, `.caption1`, etc.), not fixed point sizes. All labels must scale with user's Dynamic Type setting.

**Rules:**
- No all-caps. No tight letter-spacing except chapter dividers (`+0.04em`).
- Weight contrast over size contrast. The photo is the hero — type is subordinate.

## Spacing

- **Base unit:** 8pt
- **Scale:** 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64
- **Standard margin:** 16pt
- **Content inset:** 16pt horizontal on all screens
- **Daily card content padding:** 20pt horizontal, 28pt bottom
- **Chapter grid gap:** 2pt (tight — creates a mosaic feel, not a gallery)
- **Density:** Comfortable — not information-dense, not overly airy

## Layout

- **Approach:** Grid-disciplined (iOS HIG baseline)
- **Chapter view:** 2-column grid, square tiles (1:1 crop), 2pt gap
- **Daily card:** Full-bleed (no margins, no padding, edge-to-edge)
- **All other screens:** 16pt horizontal margins, standard iOS navigation bar
- **Max content width:** N/A — iPhone-only; content fills screen width
- **Landscape:** Daily card shows portrait-centered with blurred photo background. No separate landscape layout.
- **iPad:** iPhone compatibility mode (centered). Not optimized in v1.

## Border Radius

| Element | Radius |
|---------|--------|
| Daily card / web preview photo | 0 — edge-to-edge, no rounding |
| Chapter memory tiles | 2pt — nearly square, mosaic feel |
| Buttons | 8pt |
| Chapter view, notification pill | 12pt |
| Avatar pill | 9999pt (circle) |
| Tier visibility badge | 20pt |

## Daily Card Gradient

- Applied over full-bleed photo on the daily card screen
- `rgba(0,0,0,0)` at 70% from top → `rgba(0,0,0,0.55)` at bottom edge
- Achieves minimum 4.5:1 contrast for white text at any photo lightness
- Bottom 30% of card height carries the gradient
- No gradient on any other screen

## Motion

- **Approach:** Minimal-functional — only transitions that aid comprehension
- **Photo fade-in (daily card load):** 200ms ease-out
- **Card exit after send:** 300ms ease-out, slides down and fades
- **"✓ Memory sent" confirmation:** fades in over 300ms, holds 1s, fades out 200ms
- **Tile appearance (chapter view):** stagger 30ms per tile, 150ms ease-out each
- **Easing:** `ease-out` for entrances, `ease-in` for exits, `ease-in-out` for state changes
- **Reduce Motion:** respect `UIAccessibility.isReduceMotionEnabled`. All animations become instant cross-fades or instant transitions. No slide, no spring.

## Buttons

| Variant | Background | Label color | Use case |
|---------|-----------|-------------|----------|
| Primary | `#1C1C1E` | `#F5EAD8` | Send Memory, Choose a photo, Continue |
| Ghost | transparent, `#1C1C1E` border 1.5pt | `#1C1C1E` | + Add Memory, secondary actions |
| Accent | `#C8956C` | `#1C1C1E` | ✓ Memory sent (only) — emotional peak only |
| Destructive | `#E04F4F` | white | Delete, remove — only in destructive flows |

No blue buttons. No green buttons. The primary CTA earns attention through placement and weight, not color.

## Accessibility

- **Touch targets:** minimum 44×44pt for all interactive elements
- **VoiceOver — daily card focus order:** photo description → name + reason → Send button
- **Photo accessibilityLabel:** "Photo of [Name] from [place], [N] years ago"
- **Send button accessibilityLabel:** "Send memory to [Name]" — not just "Send"
- **Chapter tile accessibilityLabel:** "[Owner name]'s photo, [date if available]"
- **Face confirmation buttons:** "Yes, this is [Name]" / "No, pick someone else"
- **Color contrast:** All text on cream background meets 4.5:1 minimum. Gradient overlay text meets 4.5:1. Verify on each release.
- **Dynamic Type:** All text labels scale. No fixed-size text containers that clip.

## Empty States

**Pattern:** Single SF Symbol in `#C8956C` (accent). No custom illustration. No stock photography. No multi-step onboarding.

**Copy pattern:**
- Title: action-oriented ("Send your first memory") — never negative ("You have no memories yet")
- Body: one sentence of context, not a feature list
- CTA: single action button

**Never:**
- "No items found."
- Multi-step "get started" instructions
- App logo + tagline as empty state content

## AI Slop Anti-Patterns (never use)

- Blue or green CTA buttons
- Rounded card containers with drop shadows for the daily card (it's edge-to-edge)
- Notification badges as the primary engagement mechanic (badge = unread Memories only)
- Infinite scroll in Chapter view (it has a bottom — the earliest memory)
- Share / Like / Comment affordances on memories (not a social network)
- Onboarding carousel with 3 feature slides
- Confetti or celebration animations after send (amber check + "Come back tomorrow" only)
- Dark mode as the only or default mode (photos need warm light)
- Custom fonts loaded at runtime

## Web Preview Page (Invitation Link)

The receiver's first experience — no install required.

- No app chrome, no navigation, no footer
- Photo fills the full width (edge-to-edge on mobile)
- Sender name + avatar below photo
- Single CTA: "See all memories you share with [Name]" → App Store link
- Background: `#F5EAD8` (matches app palette)
- Font: system-ui (matches SF Pro feel on iOS)
- Desktop: same layout + QR code to App Store

## User Journey

### Activation Sequence (Install → First Exchange)

The sequence is linear and deliberate. Each step has one purpose and one action.

```
Install
  └─ OTP Onboarding: Phone → Code → Name (new users only)
       └─ Permissions: Push notifications requested after Name step
            └─ Empty home state: Chapters tab shows "Start your first chapter"
                 └─ InviteFlow: Name → Pick Photo → Caption → Send & invite → Share link
                      └─ Partner installs via Branch.io link, OTP with invitation token
                           └─ Chapter activates: both users see each other's chapter
                                └─ Daily card cycle (see below)
```

**Empty home is not a dead end.** The "Invite someone" CTA on the Chapters empty state
IS the activation — it opens InviteFlowView and walks the user through creating their
first chapter with a photo in hand.

### Daily Card Engagement Loop

```
Daily card queued (server-side) → User opens card → "Send a memory back" CTA
  → SendFlowView: pick photo → caption → send (amber ✓ confirmation)
  → "Come back tomorrow." message
  → Partner's daily card queued
  → [loop]
```

Decay trigger (>90 days inactive): server queues a decay card; red dot appears on
chapter tile before user opens app.

Birthday trigger: server queues a birthday card when partner's birthday matches
(requires Contacts permission; see below).

### Permission Request Timing

| Permission | When to request | Rationale |
|---|---|---|
| Push notifications | After Name step in onboarding | User has committed (gave name); push makes the loop work |
| Photos | On first "Choose a photo" tap (implicit via PhotosPicker) | Request at the moment of need; never cold-ask |
| Contacts | After first chapter activates | Birthday detection only makes sense once there's someone to detect for |
| Camera | Not used in v1 | — |

**Principle:** request the minimum set needed for the next immediate step.
Never batch permissions at launch. Never explain a permission before the user
has context for why it matters.

### Face Indexing UX

After a memory is successfully uploaded, face detection and embedding run on-device
in the background (non-blocking). If unrecognized faces are found, a prompt appears
at the bottom of ChapterDetailView the next time the user visits that chapter.

**Prompt pattern — one face at a time:**
- Face crop (circular, 56pt) centered in a warm-surface card
- Headline: `"Who's in this photo?"` (22pt Regular)
- Primary button: `"Yes, that's [Partner name]"` (Primary variant — `#1C1C1E` fill)
- Ghost button: `"Skip"` (Ghost variant — transparent, `#1C1C1E` border)

**Rules:**
- Never modal or full-screen — always a dismissable banner at the bottom
- One face per prompt, never a grid of unknowns
- Skipped faces are not re-prompted on the same session; they reappear after 7 days
- No face data, embeddings, or crops ever leave the device
- Once tagged, future photos with that person are auto-recognized silently (no prompt)

### Voice Clips (v1.1 — not yet implemented)

Voice clips follow the same send flow as photos with adapted UI:

- Replace PhotosPicker with a hold-to-record button (microphone icon, 72pt touch target)
- Waveform visualization: thin vertical bars, animated in real-time, `#C8956C` accent color
- Playback: tap-to-play inline in the chapter grid (waveform scrubber, no fullscreen)
- Duration limit: 60 seconds (progress ring around the record button)
- Caption: optional, same field as photo flow

In the chapter grid, voice clips render as a distinct tile: waveform thumbnail on
`#EDE0CC` surface, duration badge in bottom-right corner.

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-03-21 | Background: `#F5EAD8` warm cream | Less pure than `#FFFBF7`, evokes film print paper, clearly intentional warmth |
| 2026-03-21 | Daily card: edge-to-edge photo | Photo is the emotional anchor; no chrome dilutes it |
| 2026-03-21 | Accent (#C8956C) only at emotional peaks | When it appears, it signals "this moment matters." Precious through rarity. |
| 2026-03-21 | Post-send: return to daily card, "Come back tomorrow." | One-card constraint is honest; message frames it as anticipation not limitation |
| 2026-03-21 | Chapter tiles: 24pt avatar pill identity, mixed chronological | No column split; shared timeline IS the bilateral experience |
| 2026-03-21 | SF Pro system font, no imports | Native iOS, zero loading, Dynamic Type support free |
| 2026-03-21 | No blue / accent on interactive elements | Every tap feels intentional, not like form-filling |
| 2026-03-21 | Empty states: SF Symbol in accent, action-oriented copy | In-system, precious; no custom illustration required |
| 2026-03-21 | Gradient: rgba(0,0,0,0.55) bottom 30% | 4.5:1 contrast over any photo lightness |
