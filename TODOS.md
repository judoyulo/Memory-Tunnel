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

### Voice playback silent failure — P2
`VoiceClipTileView.downloadAudioIfNeeded()` silently fails on network error or expired signed URL.
**Fix:** Show error state or retry CTA in the sheet.
**File:** `ios/MemoryTunnel/Views/Chapter/ChapterDetailView.swift`

### Signed URL TTL not tracked client-side — P2
Media URLs expire after ~60 min. `refresh_url` endpoint exists but iOS never calls it proactively.
**Fix:** Track `signedAt` timestamp on `Memory`, call `refresh_url` when TTL > 50 min.
**File:** `ios/MemoryTunnel/Models/Models.swift`

### Face index migration on update — P3
Existing `face_index.json` in `Documents/` won't migrate to `Application Support/` automatically. First post-update launch silently starts a fresh index.
**Fix:** On init, check old path and move file if present (one-time migration).
**File:** `ios/MemoryTunnel/Services/FaceIndexService.swift`

### AVAudioSession not deactivated after playback — P3
`VoicePlayerView.stopPlayback()` doesn't call `AVAudioSession.sharedInstance().setActive(false)`.
Low impact (playback category only, not record), but can interfere with other apps.
**File:** `ios/MemoryTunnel/Views/SendFlow/VoiceFlowView.swift`

### Face matching not validated in production — P2
`FaceIndexService` uses Vision landmark vectors with L2 distance (threshold: 0.12) for identity clustering.
Not tested on real-world diversity (lighting variation, glasses, masks, age range, skin tone).
**Risk:** Smart Start suggests wrong people → erodes trust immediately at first-run.
**Fix:** Before v1 launch, run a manual test on a device with real photos across varied conditions. Consider temporarily raising threshold to 0.15 and adding user-facing "wrong person?" correction in Smart Start picker.
**File:** `ios/MemoryTunnel/Services/FaceIndexService.swift`
