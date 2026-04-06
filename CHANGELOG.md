# Changelog

All notable changes to Memory Tunnel are documented here.

## [0.2.0.0] — 2026-04-02

Chapter timeline redesign and smart Today tab. The chapter detail view is now a bilateral conversation timeline (your memories on the left, theirs on the right). The Today tab adapts to user state instead of showing "Come back tomorrow" to new users.

### Added

- **Conversation Timeline** — bilateral left/right layout in chapter detail view. Variable-height photos, animated voice waveforms, styled text cards, location check-in tiles. Date section headers group memories by month. Center timeline line with dots connecting memories.
- **On This Day** — floating card at the top of the timeline when a memory from the same calendar date in a prior year exists. "1 year ago today at La Boqueria."
- **Relationship age counter** — subtle "4y 2m" display in chapter navigation bar computed from first shared memory.
- **Photo detail view** — tap any photo for full-bleed viewer with daily card gradient overlay, metadata, and horizontal swipe between chapter photos.
- **Voice recorder redesign** — hold-to-record with haptic feedback (.medium impact), real-time waveform visualization (Timer at 0.1s), 60-second progress ring, 1-second minimum with discard animation.
- **Text composer** — warm cream sheet with large text area, placeholder text, expandable detent.
- **Smart Today tab** — three states: (1) no chapters: personalized warm onramp with time-of-day greeting + "Start a chapter" CTA, (2) has chapters but no card: chapter preview cards with health dots (green/tertiary/accent) + "Send a memory" shortcut per chapter, (3) has daily card: existing full-bleed card view (unchanged).
- **Welcome daily card** — queued immediately on first memory ever sent. Uses new `welcome` trigger type with highest priority. Tracked via `welcomed_at` timestamp on users table.
- **Chapter health indicators** — green (#4CAF79) for active (<30 days), tertiary for quiet (30-89 days), accent (#C8956C) for going cold (90+ days). Matches existing decay dot pattern.
- **Time-of-day greeting** — "Good morning/afternoon/evening, [name]" on the Today tab empty states.

### Changed

- **Memories API returns all memories ASC** — removed pagination from `memories#index` (1:1 chapters are bounded). Sort order flipped from DESC to ASC for timeline consumption.
- **Daily card persists all day** — removed `delivered_at: nil` filter from `daily_card#show`. Cards stay visible on reopening the app. `delivered_at` is analytics-only now.
- **AppState stores chapters array** — `hasChapters` is now a computed property. Fixes race condition where Smart Start created a chapter but the boolean flag stayed false until app restart.
- **S3 presigner cached at class level** — single client instance reused across all `signed_url` calls. Eliminates per-call instantiation overhead.

### Fixed

- `hasChapters` stale flag: AppState now updates immediately when chapters are created via Smart Start or InviteFlow.
- Daily card vanishing on second app open (delivered_at filter removed).

### Backend

- Migration: `event_date`, `emotion_tags` (array), `width`, `height` on memories. `welcomed_at` on users.
- `welcome` trigger type on DailyCardQueueEntry (priority 0, highest).
- `effective_date` prefers `event_date` over `taken_at`.

### Tests

- 4 new RSpec tests: welcome card queue on first memory, no duplicate welcome, new timeline fields accepted, memories index ASC without pagination.
- Total: 19 examples, 0 failures.

## [0.1.0.0] — 2026-03-31

First shippable build. Core loop: OTP auth, Smart Start onboarding, chapter management, photo + voice memories, birthday detection, daily card.

### Features

- **Smart Start onboarding** — face-suggested chapter creation from camera roll. On-device Vision scan of 150 most-recent photos, top 5 frequent faces surfaced as chapter suggestions. No biometric data leaves device.
- **Voice clips** — M4A recording up to 60s, waveform animation, in-chapter playback
- **Face tagging** — link untagged faces to chapter partners from within chapter detail
- **Birthday detection** — on-device Contacts scan, server-side birthday card queuing via signal endpoint (no birthday date transmitted)
- **Daily card** — one proactive card per day (decay or birthday trigger), full memory grid preview
- **App icon + launch animation** — The Tunnel wordmark, spring motion system, `.mtSlide` transitions
- **Invite flow** — Branch.io deep link preservation through App Store install

### Security

- `s3_key` path traversal guard: validates prefix + rejects `../` components
- `birthday_signal` idempotency: `rescue ActiveRecord::RecordNotUnique` prevents 500 on duplicate signals
- `opened_at` write-once: only set on first open, not overwritten on subsequent calls
- `not_found` handler sanitizes ActiveRecord error messages (no SQL schema disclosure)
- Rate limiting on OTP endpoints

### Bug Fixes

- `isDecayed` nil guard: chapters with no memories no longer show decay dot
- `AVAudioSession` teardown: session deactivated on recording stop/cancel (releases microphone indicator)
- Voice playback: downloads S3 audio to temp file before passing to `AVAudioPlayer` (remote URLs not supported)
- `APIClient` force-unwrap: `response as! HTTPURLResponse` replaced with guard-let
- Face index + birthday index moved to `Application Support` with `isExcludedFromBackup = true` (not backed up to iCloud)
- `PHImageResultIsInCloudKey` guard prevents `withCheckedContinuation` hang on iCloud-only assets
- SendFlow double-tap send guard
- FaceIndexService deduplication for untagged faces
- BirthdayService month-boundary logic fixed
- InviteFlow invitation failure non-fatal (matches SendFlow pattern)

### Design System

- All tokens from `DESIGN.md`: `mtBackground` #F5EAD8, `mtLabel` #1C1C1E, `mtAccent` #C8956C (emotional peaks only)
- 24 design violations fixed: accent misuse, missing tokens, error color, typography, ghost borders, touch target, animation tokens
- `mtButton` font (17pt semibold), `mtCaption` (12pt), `mtDisplay` (28pt medium)

### Tests

- RSpec: 20 examples, 0 failures
- Coverage: chapters create, OTP auth, memories API (s3_key security + destroy authorization), birthday signal, daily card endpoints
