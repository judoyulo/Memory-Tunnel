# Memory Tunnel — Project Guide

## Design System
Always read DESIGN.md before making any visual or UI decisions.
All colors, typography, spacing, motion, and aesthetic direction are defined there.
Do not deviate without explicit user approval.
In QA mode, flag any code that doesn't match DESIGN.md.

Key rules from DESIGN.md:
- Background: `#F5EAD8` (warm cream) — never pure white, never dark
- Accent `#C8956C` appears ONLY at emotional peaks (✓ sent, birthday, decay dot) — nowhere else
- No blue or accent-colored buttons — primary CTA is `#1C1C1E` fill
- SF Pro system font only — no custom font imports
- Daily card is edge-to-edge (no margins, no card chrome)
- Chapter view: 2-column square grid, 2pt gap, 24pt avatar pill identity

## Stack (v1)
- **iOS:** Swift / SwiftUI, iOS-first
- **Backend:** Ruby on Rails (API mode)
- **Background jobs:** GoodJob (PostgreSQL-backed, no Redis)
- **Media storage:** S3 (direct upload via presigned URL)
- **Auth:** SMS OTP (Twilio), JWT stored in iOS Keychain
- **Face detection:** Apple Vision + bundled Core ML (~5MB), on-device only — embeddings never leave device
- **Deferred deep links:** Branch.io (invitation token preserved through App Store install)
- **Push notifications:** APNs only

## Design Documents
- CEO Plan: `~/.gstack/projects/gstack-test/ceo-plans/2026-03-21-memory-tunnel.md`
- Office Hours design doc: `~/.gstack/projects/gstack-test/xuanqiyang-unknown-design-20260321-130119.md`

## Key Product Constraints
- One card per day — never more than one proactive notification per day
- Birthday detection is on-device (iOS Contacts) — no birthday data sent to server
- FaceIndex records and embeddings never leave the device
- Photos only in v1 — no video, voice, text-only memories
- 1:1 Chapters only — no group chapters in v1
