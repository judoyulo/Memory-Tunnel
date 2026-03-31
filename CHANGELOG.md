# Changelog

All notable changes to Memory Tunnel are documented here.

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
