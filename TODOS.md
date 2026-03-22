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
