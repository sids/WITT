# WITT Documentation

This directory is the canonical home for WITT product, technical, planning, and release documentation.

## Current Documents

- [Product](product.md) - product purpose, vocabulary, workflows, scope, and UX direction.
- [Architecture](architecture.md) - current domain, persistence, sharing, photo, QR, and presentation architecture.
- [AI Labeling](ai-labeling.md) - provider-neutral labeling contract, runtime behavior, privacy, and production boundary.
- [Todo](todo.md) - the only live backlog and TestFlight feedback inbox.
- [Status](status.md) - concise implementation snapshot and verification baseline.
- [Release](release.md) - App Store Connect facts and repeatable TestFlight/App Store release process.
- [Place Sharing Spike](sharing-spike.md) - repeatable two-account fixture, measurements, and evidence for the CloudKit sharing release gate.

## Documentation Rules

1. Keep actionable work only in [todo.md](todo.md). Other documents may explain constraints or decisions, but must not maintain competing task lists.
2. Update the relevant document in the same commit as a behavior, architecture, release, or product-decision change.
3. Describe the system as it exists now. Remove superseded proposals, completed implementation plans, and stale mock specifications; Git preserves history.
4. Keep product language explicit: Place, Room, Area, Storage Area, Container, Thing, QR Code, and PhotoAsset.
5. Do not commit credentials, private tester information, or temporary local artifact paths.
6. Use relative links so the documentation works locally and on GitHub.

`AGENTS.md` is the bootstrap for coding agents. It points into this directory for durable context.
