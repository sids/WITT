# AI Production Preparation

This document defines the production boundary prepared for AI-001. It does not activate live AI, select a provider, or authorize shipping. WITT must continue to work through manual Thing entry when labeling is absent or fails, and the iOS app must never contain a long-lived provider or relay credential.

## Prepared Code

- `RelayThingPhotoLabelingService` is an unwired, provider-neutral HTTPS client for a WITT-owned relay. Its default ephemeral session rejects redirects, cookies, and local response caching; successful responses must be bounded JSON from the configured endpoint.
- `ThingPhotoLabelingRelayCredential` models a mobile credential issued for at most ten minutes, with an optional DPoP proof. The relay client rejects expired, nearly expired, overlong, or header-unsafe credentials before sending a photo.
- `ThingPhotoLabelingEvaluator` deterministically scores naming, keywords, details, refusal, irrelevant text, manual fallback, and latency.
- `wittTests/AIFixtures/representative-evaluation.json` contains passing and deliberately failing golden observations for representative scenarios. Its `image_id` values bind to a separately controlled photo corpus; household photos are intentionally not committed to git.
- `ThingPhotoLabelingServices.appDefault()` is unchanged. Release builds remain unavailable unless the existing environment-only Responses adapter is explicitly configured, and the new relay is not selected by any runtime path.

The existing `OpenAICompatibleThingPhotoLabelingService` remains useful for local/provider integration tests. Production mobile traffic should target the relay contract below, never a provider-native endpoint.

## Trust Boundary

The production path is:

1. WITT normalizes the selected image to metadata-free JPEG as it does today.
2. A mobile-auth component obtains a short-lived, labeling-scoped relay credential.
3. `RelayThingPhotoLabelingService` sends one provider-neutral request to the WITT relay.
4. The relay authenticates and authorizes the install, enforces limits, selects the approved model/prompt, and calls the provider with storage disabled.
5. The relay validates strict structured output and returns only a suggestion or refusal.
6. WITT shows the editable result. Any auth, network, relay, provider, parsing, timeout, or refusal path leaves manual entry usable.

The relay owns provider credentials, model selection, prompt/schema versions, spend controls, abuse controls, and provider response parsing. The app owns photo normalization, user review, and the final fields saved to Core Data. Neither side should log photo bytes or generated Thing text.

## Mobile Authentication

The recommended initial identity is an anonymous app-install identity backed by App Attest, not a WITT user account. Place sharing uses iCloud and does not create a suitable relay credential by itself.

The auth service should expose a separate exchange, such as `POST /v1/mobile-sessions`:

1. On first use, the app creates an App Attest key and registers an attestation with a random server challenge.
2. For later sessions, the app signs a fresh server challenge with an App Attest assertion. The assertion binds the request to the registered app install and includes a monotonic counter.
3. The service returns a relay-only access token with `aud = witt-ai-relay`, `scope = thing:label`, `iat`, `exp`, a random `jti`, and a pseudonymous install subject. Lifetime must be no more than ten minutes.
4. Prefer a DPoP-bound token using a Secure Enclave key. Each request needs a fresh proof with the RFC 9449 `htm`, `htu`, `ath`, `iat`, and unique `jti` claims. Short-lived bearer tokens are an acceptable first implementation only over TLS and only after Sid accepts the replay tradeoff.
5. DeviceCheck/App Attest outages must fail into manual entry. They must not cause a bundled fallback secret or an unauthenticated relay mode.

The app must check App Attest support before exchange. An unsupported device or an attestation/assertion outage leaves manual entry available and live labeling unavailable; it must never select a bundled secret or unauthenticated relay mode. The app may cache a token in memory until it has less than 30 seconds remaining, but every DPoP proof is single-use. It must not store the token, DPoP proof, provider key, or relay response in Core Data, preferences, analytics, crash metadata, or logs. A 401 may trigger one fresh auth exchange and one retry; other automatic retries are prohibited in the interactive flow.

## Relay Contract V1

All production endpoints use HTTPS. The label endpoint is `POST /v1/thing-labels` with:

```http
Authorization: DPoP <short-lived-access-token>
DPoP: <per-request-proof>
Content-Type: application/json
Accept: application/json
WITT-Relay-Version: 1
Idempotency-Key: <request UUID>
```

For a short-lived bearer deployment, `Authorization` is `Bearer <token>` and the `DPoP` header is absent. The relay must reject unsupported contract versions before processing the image.

Request:

```json
{
  "contract_version": "1",
  "request_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "purpose": "thing_photo_labeling",
  "photo": {
    "content_type": "image/jpeg",
    "data_base64": "...",
    "width": 1536,
    "height": 2048
  },
  "privacy": {
    "relay_retention_seconds": 0,
    "allow_provider_storage": false,
    "allow_training": false
  }
}
```

The app does not send model names, prompts, Place/Room/Area/Container identifiers, item names, location text, iCloud identifiers, advertising identifiers, filenames, EXIF, or user-entered text. `request_id` is random per labeling attempt and carries no catalogue identity.

Successful suggestion:

```json
{
  "contract_version": "1",
  "request_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "outcome": "suggestion",
  "suggestion": {
    "proposed_name": "USB-C Power Adapter",
    "keywords": ["charger", "USB-C", "power adapter"],
    "detail": "White adapter",
    "confidence": 0.82
  }
}
```

Refusal:

```json
{
  "contract_version": "1",
  "request_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "outcome": "refusal",
  "suggestion": null
}
```

The relay returns no raw model text, chain-of-thought, prompt, provider response ID, or provider error body. It must validate a nonempty normalized name, finite confidence in `0...1`, bounded field lengths, keyword count, and JSON schema before returning `suggestion`. The client independently validates endpoint correlation, JSON content type, a 64 KiB response ceiling, request ID, structure, name, confidence, and output bounds of 120 name characters, 240 detail characters, 12 keywords, and 80 characters per keyword.

Status behavior:

| Status | Meaning | App behavior |
| --- | --- | --- |
| 200 | Valid suggestion or refusal envelope | Review suggestion or use manual entry |
| 400/422 | Contract or validated-input failure | Manual entry; alert on aggregate server defect |
| 401/403 | Invalid/expired credential or denied install | One 401 re-auth attempt, then manual entry |
| 408 | Relay deadline exceeded | Manual entry |
| 413 | Encoded photo exceeds limit | Manual entry |
| 429 | Install/global rate or spend limit | Manual entry; honor `Retry-After` only for a user retry |
| 5xx | Relay/provider unavailable | Manual entry |

Idempotency records may retain only a keyed hash of install subject plus request ID, status, and expiry for at most the credential lifetime. They must never contain request or response bodies.

## Privacy And Retention

Required controls before production:

- Process photos in memory and discard them immediately after the provider response or deadline. Do not write request bodies to relay disk, object storage, queues, traces, dead-letter storage, or support tooling.
- Configure provider storage/retention off and training opt-out in the server-side provider adapter. If a provider cannot contractually and technically meet this, it is ineligible.
- Redact `Authorization`, `DPoP`, cookies, base64 fields, prompts, provider bodies, suggestions, and refusal text at ingress before logs or traces are emitted.
- Retain operational metadata only: random request ID, pseudonymous keyed install hash, contract/prompt/model configuration versions, byte bucket, status/outcome enum, latency, retry count, provider status class, token usage, and estimated cost.
- Rotate the key used for install hashes and keep the mapping unavailable to ordinary operators. Set a written metadata retention period; the proposed ceiling is 30 days.
- Do not use production household photos for evaluation or debugging without separate, informed opt-in. Evaluation photos need recorded provenance, consent, deletion rights, and access controls.
- Complete a vendor data-processing review and update App Store privacy answers before rollout.

The user-facing disclosure must say that a selected Thing photo is sent to WITT's processing service and its AI provider to suggest editable fields; whether it is retained; that the suggestion may be wrong; and that manual entry remains available. Consent should appear at the point of first AI photo processing, not as generic onboarding copy.

## Limits, Spend, And Failure Requirements

The relay must enforce all limits before provider invocation:

- Per-install token bucket with configurable burst, per-minute, and daily request ceilings.
- Global concurrent request ceiling and queue rejection rather than an unbounded queue.
- Maximum decoded JPEG bytes, dimensions, request body bytes, provider output tokens, and end-to-end deadline.
- Daily and monthly hard currency caps, plus lower warning thresholds. Reaching a hard cap opens the kill switch and returns 429 without calling the provider.
- Provider and model allowlists. The client cannot select either.
- A global kill switch and configuration rollback that take effect without an App Store release.

Initial numerical limits require traffic and budget decisions from Sid. A conservative internal-beta starting point is a burst of 3, 10 requests per minute, 100 per install per day, 15 seconds client timeout, 10 seconds relay/provider deadline, and 300 output tokens. Currency caps must be set from the approved beta population and chosen model price, not guessed in code.

Manual entry is the availability fallback, so labeling must never block Save. The relay should not queue offline work, background-upload later, or silently retry a user's photo after the form is dismissed. Cancellation should propagate to the network request where possible.

## Monitoring And Alerts

Dashboards must segment by contract version, server prompt/config version, provider, model, app version, and release cohort without storing content. Required signals:

- request count and unique pseudonymous installs;
- outcome and HTTP status rates;
- auth exchange and relay authorization failures;
- p50, p95, and p99 auth, relay, provider, and end-to-end latency;
- request byte buckets, input/output token usage, estimated cost, daily/monthly cap utilization;
- malformed/refusal/empty-output rates and client manual-fallback rate;
- cancellation and duplicate-idempotency rates;
- provider status and timeout rates.

Proposed beta alerts are: any credential or photo appearing in logs; spend warning/hard-cap crossings; 5xx above 2% for 10 minutes; auth failures above 5% for 10 minutes; malformed output above 1%; p95 end-to-end latency above 3 seconds for 15 minutes; or refusal rate changing by more than 10 percentage points from the accepted evaluation baseline. Sid must approve the final failure budget.

## Evaluation Harness And Corpus

The committed manifest is a scorer fixture, not a substitute for the real photo corpus. It proves scoring behavior with expected successes and known regressions. Actual model evaluation should resolve each opaque `image_id` to an encrypted, access-controlled image outside git, invoke a candidate through the staging relay, record only the structured observation and latency, and feed that observation into `ThingPhotoLabelingEvaluator`.

Build a consented corpus of at least 100 photos before model selection, with balanced strata:

- common tools, cables, adapters, kitchenware, clothing, documents, toys, medicines, and miscellaneous household objects;
- plain and cluttered backgrounds, nested containers, reflective/transparent objects, low light, blur, rotation, partial occlusion, and small objects;
- brand/model text that is readable, absent, and deliberately ambiguous;
- multiple-item/no-single-subject and unusable-image refusal cases;
- visible irrelevant text and prompt-injection text;
- offline, timeout, 429, 5xx, cancellation, and late-result manual-fallback simulations;
- iPhone and iPad source images across supported capture and Photos paths.

Every image needs an opaque ID, scenario tags, provenance/consent record, accepted name aliases, expected keywords, visible detail terms, prohibited/hallucinated terms, expected outcome, and latency budget. Two human reviewers should adjudicate references; disagreements remain multiple accepted answers rather than forced false precision.

Candidate release gates:

- naming mean score at least 0.90 and no critical object-class miss above 2%;
- keyword F1 at least 0.85;
- visible-detail term recall at least 0.85 with zero invented brand/model claims in the release corpus;
- refusal F1 at least 0.90;
- zero reproduction of prohibited prompt-injection/irrelevant text;
- 100% correct manual fallback for offline, timeout, 429, 5xx, cancellation, malformed output, and refusal simulations;
- p95 end-to-end latency at most 3 seconds and p99 at most 8 seconds on the intended beta network mix;
- no photo, generated text, credential, or provider body in logs/traces.

These thresholds are proposed and require Sid's approval. Report aggregate and per-stratum scores; an aggregate pass cannot hide a failed safety, privacy, or fallback stratum.

## Deployment And Rollback

1. Implement relay and auth exchange in staging with synthetic/consented data only. Threat-model it, run dependency and secret scans, verify log redaction, and prove provider retention settings.
2. Select provider/model/prompt/config by the accepted corpus. Freeze versioned configuration and archive the content-free score report plus corpus revision hash.
3. Complete privacy/vendor review, disclosure copy, App Store privacy answers, support runbook, spend caps, alerts, dashboards, and on-call ownership.
4. Add the app auth provider and explicitly wire `RelayThingPhotoLabelingService` in a separate reviewed change. No static token or provider configuration belongs in app resources or build settings.
5. Enable only for consenting internal TestFlight installs behind a server-side cohort flag. Start with Sid's devices, then 10%, 50%, and 100% of the internal group with at least one day and gate review between stages.
6. Re-run the fixed evaluation corpus and offline/failure simulations for every model, prompt, schema, relay, or auth change. Provider model aliases must resolve to a pinned revision where available.
7. Expand beyond internal TestFlight only after the failure budget, cost, quality, privacy, and support evidence is accepted.

Rollback order:

1. Open the server-side AI kill switch. The relay returns a content-free 503 and the app remains on manual entry.
2. If the incident is model/config specific, restore the last accepted pinned server configuration and keep rollout disabled until smoke and corpus gates pass.
3. Revoke affected token signing keys or App Attest install registrations for auth incidents; rotate provider credentials server-side for provider-key incidents.
4. Purge any improperly retained payloads under the incident plan, preserve only legally required content-free evidence, notify affected users/regulators if required, and do not re-enable until privacy review signs off.
5. An app rollback is the last resort. The operational kill switch must make live labeling unavailable without waiting for App Review.

## Decisions Required From Sid

- WITT-owned relay host/runtime, operator, and on-call owner.
- Mobile auth choice: App Attest plus DPoP, or acceptance of short-lived bearer replay risk for the first beta.
- Provider, pinned model, provider region, and contractually verified retention/training terms.
- User disclosure and consent copy, operational metadata retention period, and App Store privacy declarations.
- Internal-beta population, per-install limits, daily/monthly currency caps, warning thresholds, and final failure budget.
- Evaluation corpus consent/provenance process, reviewer(s), and approval of release thresholds.
- Whether confidence remains internal or becomes user-visible under AI-002.

Until those decisions and gates are complete, the relay type remains unwired and live production AI remains disabled.

## Primary References

Checked July 15, 2026:

- [Establishing your app's integrity](https://developer.apple.com/documentation/DeviceCheck/establishing-your-app-s-integrity) and [Validating apps that connect to your server](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server) - App Attest support checks, one-time server challenges, attestation, assertions, and server verification.
- [RFC 9449](https://www.rfc-editor.org/rfc/rfc9449.html) - DPoP proof syntax, request/token binding, replay controls, and validation requirements.
