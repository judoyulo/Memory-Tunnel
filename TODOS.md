# TODOS

## ✓ DONE — Before first iOS screen

### ~~Create DESIGN.md~~ — COMPLETE (2026-03-21)
DESIGN.md written to repo root. Background: `#F5EAD8` warm cream. Full token set locked. See [DESIGN.md](./DESIGN.md).

---

## P1 — Required before App Store submission

### Account deletion + data purge
**What:** Implement cascading account deletion that purges all user data.
**Why:** Required for App Store submission (Apple Developer Program guidelines) and GDPR compliance. Without it, the app cannot be publicly launched.
**Pros:** Compliance, user trust, legal protection.
**Cons:** ~1 week human / ~30min CC. S3 media purge requires async job (can't be synchronous for large accounts).
**Context:** Deletion must cascade: User → Chapter memberships → owned Memories (S3 objects deleted via background job) → Invitations. Chapters where the deleted user is `member_b` revert to `status: pending` (member_b = NULL). The other member should be notified. Data purge job must be idempotent (can re-run safely if it fails partway through). See design doc for data model.
**Effort:** S (human: 1 week / CC: ~30min)
**Priority:** P1
**Depends on:** Core D3 server implementation must exist first.

---

## Found During Smart Start / Ship Pass (2026-03-31)

### Orphaned chapter on upload failure — P2
`SmartStartViewModel.send()` creates the chapter before the S3 upload. Upload failure leaves a `pending` chapter with no memory.
**Fix:** `DELETE /api/v1/chapters/:id` endpoint + rollback on iOS upload error.
**File:** `ios/MemoryTunnel/Views/Onboarding/SmartStartView.swift:116`

### ~~Voice playback silent failure~~ — PARTIALLY FIXED (2026-04-05)
CinematicVoicePlayer now shows "Tap to retry" on download failure or expired URL. Handles 403 (expired presign) explicitly.
**Remaining:** Proactive URL refresh before expiry (see Signed URL TTL below).
**File:** `ios/MemoryTunnel/Views/Chapter/CinematicMemoryCard.swift`

### Signed URL TTL not tracked client-side — P2
Media URLs expire after ~60 min. `refresh_url` endpoint exists but iOS never calls it proactively.
**Fix:** Track `signedAt` timestamp on `Memory`, call `refresh_url` when TTL > 50 min.
**File:** `ios/MemoryTunnel/Models/Models.swift`

### ~~Face index migration on update~~ — RESOLVED
FaceIndexService deleted entirely, replaced by FaceEmbeddingService. No migration needed — fresh embeddings are generated on first scan.

### ~~AVAudioSession not deactivated after playback~~ — FIXED (2026-04-05)
`CinematicVoicePlayer.stopPlayback()` now calls `setActive(false, options: .notifyOthersOnDeactivation)`.
**File:** `ios/MemoryTunnel/Views/Chapter/CinematicMemoryCard.swift`

### Branch.io SPM package must be added to Xcode project — P1
Code is wired (`MemoryTunnelApp.swift` imports `BranchSDK`, `AppDelegate` calls `Branch.getInstance().initSession`).
**Remaining:** Add `https://github.com/BranchMetrics/ios-branch-sdk-spm` as an SPM dependency in Xcode.
Also add Branch key to `Info.plist` (`branch_key` → live/test key from Branch dashboard).
Also add Associated Domains capability for Universal Links (`applinks:memorytunnel.app.link`).
**Why:** Can't be done from code alone — requires Xcode project settings.

### APNs credentials must be provisioned — P1
Code is complete (`ApnsService`, push jobs, iOS push registration all wired).
**Remaining:** Generate an APNs key in Apple Developer, fill `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_P8_KEY` in `.env` / production env.
Boot check initializer (`apns_check.rb`) logs a warning if these are missing.
**Why:** Without these, push notifications silently no-op.

---

## Deferred from Chapter Timeline Redesign (2026-04-01)

### Auto-play voice clip preview on scroll — P3
**What:** When scrolling past a voice clip in the timeline, play a 2-second preview at low volume.
**Why:** Makes the timeline feel alive, ambient presence. Creates a soundscape of the friendship.
**Pros:** Emotional depth, differentiation from other apps.
**Cons:** Risk of annoyance if not tuned. Complex scroll tracking + audio ducking.
**Context:** Requires scroll position monitoring via `onAppear`/`onDisappear` on voice cards, AVAudioPlayer with ducked volume, managing multiple clips. Needs real user testing to validate desirability.
**Effort:** M (human: ~2 weeks / CC: ~1 hr)
**Priority:** P3
**Depends on:** Chapter timeline redesign (voice card implementation)

### Map dot visualization — P2
**What:** Toggleable mini-map showing dots for every memory with a location. Tap a dot to jump to that memory in the timeline.
**Why:** Visual representation of shared geography. "We've been to 12 cities together."
**Pros:** Beautiful, emotional, no competitor has this.
**Cons:** Needs real location data to be meaningful. MapKit dot clustering is non-trivial.
**Context:** Uses existing `latitude`/`longitude` fields on memories. Requires MapKit + `MKAnnotation` clustering + timeline navigation via `ScrollViewReader`.
**Effort:** M (human: ~2 weeks / CC: ~1 hr)
**Priority:** P2
**Depends on:** Chapter timeline redesign (timeline view + location data)

### Chapter color derived from photos — P3
**What:** Compute dominant color palette from a chapter's photos. Subtle tint on chapter header. Each chapter feels chromatically unique.
**Why:** Visual personality per chapter. "The Barcelona chapter is warm amber, the Tokyo chapter is cool blue."
**Pros:** Differentiation, delight, each chapter feels unique.
**Cons:** Image analysis at load time, caching strategy needed, design decisions about tint subtlety.
**Context:** Use `CIAreaAverage` filter on first 5 photos. Cache result in UserDefaults keyed by chapter ID. Apply as 8% opacity tint on chapter header background.
**Effort:** S (human: ~1 week / CC: ~30 min)
**Priority:** P3
**Depends on:** Chapter timeline redesign

### Typing indicator / ambient presence — P3
**What:** When partner is creating a memory, show subtle "..." indicator in timeline. Like iMessage typing.
**Why:** Ambient connection. "Someone is thinking about me right now."
**Pros:** Emotional immediacy, differentiation.
**Cons:** Requires real-time infrastructure (WebSocket/ActionCable) that doesn't exist.
**Context:** Backend is API-mode Rails with no real-time layer. Would need ActionCable + Redis (or polling fallback). iOS: subscribe to presence channel per chapter.
**Effort:** L (human: ~1 month / CC: ~2 hr)
**Priority:** P3
**Depends on:** Real-time infrastructure buildout

### Scrapbook export — P2
**What:** Generate a shareable scrapbook-style image from a chapter's memories. Photos at slight random rotations, text as sticky notes, voice clips as waveform tiles. Share via UIActivityViewController.
**Why:** Growth mechanic + gift feature + cold-start invitation vehicle. "You don't ask someone to build a scrapbook together. You send them a beautiful scrapbook and say 'remember this?'"
**Pros:** Off-app sharing, invitation pull (not push), unique to Memory Tunnel.
**Cons:** Image rendering is non-trivial, design decisions about layout.
**Context:** Generate using `UIGraphicsImageRenderer` or SwiftUI snapshot. Layout algorithm: random rotations (2-5 degrees), overlapping tiles. Share via `UIActivityViewController`.
**Effort:** M (human: ~2 weeks / CC: ~1 hr)
**Priority:** P2
**Depends on:** Chapter timeline redesign (memory data access patterns)

---

## ✓ DONE — Shipped 2026-04-05

### ~~Today Tab photo discovery feed~~ — COMPLETE (2026-04-05)
Full-screen swipeable cards from photo library. Two types: "new face" (no chapter) and "unsaved memory" (has chapter). User face pre-scan skips selfies. 21 cards max, 3 per person dedup, 1500 photo scan budget.
**Files:** `TodayFeedService.swift`, `DailyCardContainerView.swift`, `FacePickerSheet.swift`

### ~~Cinematic chapter timeline~~ — COMPLETE (2026-04-05)
Film-strip vertical scroll with distance-based card sizing (1.0x center, 0.3x edges). Photo/text/voice/location card types. Interactive year scrubber with drag + haptics.
**Files:** `CinematicTimelineView.swift`, `CinematicMemoryCard.swift`, `TimelineScrubberView.swift`

### ~~Splash screen animation~~ — COMPLETE (2026-04-06)
Ring draw-on + amber center breathe + floating particles + "tunneling in..." typewriter text. Respects Reduce Motion.
**File:** `ios/MemoryTunnel/Views/Launch/SplashView.swift`

### ~~Scan progress ring~~ — COMPLETE (2026-04-06)
Activity ring with monospace counter, orbiting dot, rotating phrases ("tunneling through memories...", "the algorithm is vibing"). Deep scan mode turns amber with treasure-hunt phrases.
**File:** `ios/MemoryTunnel/Views/Components/ScanProgressRing.swift`

### ~~Daily Dig (suggested photos)~~ — COMPLETE (2026-04-06)
Scans 1000 fresh photos per session instead of 5000 at once. Persists scanned/found IDs. Previous finds load instantly. Today's new finds get sparkle badge. Coverage % pill. "come back tomorrow" retention loop.
**File:** `ios/MemoryTunnel/Views/Chapter/SuggestedPhotosView.swift`

### ~~Replace Vision landmarks with Core ML face embeddings~~ — COMPLETE (2026-04-04)
Integrated MobileFaceNet (w600k_mbf, 6.6MB, 512-dim embeddings) via CoreML. Deleted FaceIndexService entirely.
FaceEmbeddingService is now the single face service with alignment, centroid clustering, and post-merge pass.
PhotoLibraryScanner upgraded: .highQualityFormat at 1024px, random sampling, adaptive scan (500 min, extend to 20+ clusters).
Result: 311/315 faces aligned (98.7%), 9 correct clusters from 2000 photos (vs. 5 broken clusters before).
**Files:** `ios/MemoryTunnel/Services/FaceEmbeddingService.swift`, `ios/MemoryTunnel/Services/PhotoLibraryScanner.swift`
