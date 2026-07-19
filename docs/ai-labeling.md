# AI Labeling

WITT treats photo understanding as a provider-neutral suggestion service. AI output never bypasses user review, and no long-lived provider secret belongs in the iOS app.

## Current Contract

`ThingPhotoLabelingService` accepts normalized photo input and returns a `ThingLabelSuggestion` containing:

- proposed name,
- normalized keywords,
- optional detail,
- optional confidence.

Both known-QR and manual Thing-creation flows receive the service through app-level dependency injection. Provider response shapes do not leak into persistence or feature code.

Relevant implementation:

- `witt/AI/ThingPhotoLabelingService.swift`
- `witt/AI/ThingPhotoLabelingServices.swift`
- `witt/AI/OpenAICompatibleThingPhotoLabelingService.swift`
- `witt/App/ThingPhotoLabelingEnvironment.swift`

## Runtime Configuration

The current Responses-compatible adapter reads environment-only configuration:

- `WITT_AI_RESPONSES_URL`
- `WITT_AI_MODEL`
- optional `WITT_AI_BEARER_TOKEN`

Endpoints must use HTTPS. Loopback HTTP is allowed only for local development.

A complete endpoint/model configuration selects the remote service. Debug builds use the deterministic mock only when no remote configuration exists. Invalid partial configuration and unconfigured release builds select an unavailable service and fall back honestly to manual entry.

## Request And Privacy Behavior

- Camera and Photos input is orientation-normalized, metadata-stripped, JPEG encoded, and size-limited before labeling.
- The request asks for strict structured output.
- Provider-side response storage is disabled with `store: false`.
- Raw provider responses and bearer tokens are not persisted or logged.
- Only user-approved Thing fields are stored by default.
- Cancellation, network failure, timeout, authentication, rate limiting, server errors, incomplete output, refusal, and malformed output map to provider-neutral errors.
- AI suggestions remain editable before save.

## Security Invariants

1. Never embed a provider API key in the app bundle.
2. Keep credentials out of Core Data, logs, analytics, crash metadata, and repo files.
3. Keep transport/provider details behind `ThingPhotoLabelingService`.
4. Preserve manual Thing entry when the service is unavailable.
5. Treat user-facing photo-processing and retention disclosure as a release requirement.

## Production Boundary

The direct adapter and tests are integrated. The provider-neutral WITT relay contract, short-lived credential model, privacy controls, evaluation gates, and rollout plan are documented in [ai-production.md](ai-production.md), but speculative relay and evaluation implementations are intentionally not compiled into the app before the backend, authentication strategy, and real evaluation corpus are chosen.

Live AI remains disabled in release until WITT implements and operates the relay/auth service, chooses a production model, approves provider retention terms and user disclosure, configures spend/rate/monitoring controls, builds the real evaluation corpus, and passes the release gates in [ai-production.md](ai-production.md).

Active production work is tracked only in [todo.md](todo.md) under `AI-001` and `AI-002`.

The full verification baseline is recorded in [status.md](status.md).
