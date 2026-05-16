# Findings-Queue Schemas

This document consolidates the per-vulnerability-class record schemas used by Phase 2.5 (secret triage) and the six Phase 3-8 subagents. Each schema is preserved from the Shannon source prompts, with two field renames applied uniformly:

- `exploitation_hypothesis` -> `remediation_hypothesis` (expected impact if not fixed).
- `suggested_exploit_technique` -> `verification_steps` (how a tester would confirm in a controlled environment).

All agents write their findings as records following these schemas in the "Findings Queue" section of their per-class deliverable. The Phase 9 consolidation agent reads these records (including Phase 2.5's `SECRET-TRIAGE-*` records), renumbers them globally (`SEC-001`, `SEC-002`, ...) sorted by severity then confidence, and emits the final `.security-audit/REPORT.md`.

The `witness_payload` field, where present, is recorded only — never executed. This is static analysis.

**Output format:** Each record MUST be a strict JSON object emitted inside a ```json fenced code block. One block per record. Use a descriptive markdown heading immediately above each block (e.g., `### INJ-VULN-001: <short title>`). Do not narrate the schema in prose. Records must parse cleanly with `JSON.parse` — no comments, no trailing commas, no unquoted keys, no pipe-delimited strings, no schema notation inside the block. Pick exactly one allowed value per field.

**Severity rubric** (applies to every record's `severity` field):

- critical: Unauthenticated RCE, auth bypass, mass data exposure, credential leak in HEAD
- high: Authenticated RCE, SQLi with real data, stored XSS, IDOR on sensitive resources, hardcoded prod secret in git history
- medium: Reflected XSS with realistic delivery, missing rate limit on auth, SSRF to non-metadata, weak crypto without immediate break
- low: Missing security headers, verbose errors, dependency CVE with no reachable path, defensive-depth gaps
- info: Hardening opportunities, observability gaps, documentation issues

---

## 1. Injection (SQLi, Command Injection, LFI/RFI, SSTI, Path Traversal, Deserialization)

### Purpose
Defines the format of each per-vulnerability injection record. Trace untrusted input from a source (request parameter, header, cookie, file, queue message, etc.) through any transformations to a sensitive sink (DB query, shell command, file op, template render, deserialize call) and capture whether the sanitization defenses on the path match the sink's slot type.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `INJ-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| source | string | yes | Parameter name and `file:line`. |
| combined_sources | array of strings | yes | Empty array if no merge; otherwise list merge order. |
| path | string | yes | Brief hop list (controller -> fn -> sink). |
| sink_call | string | yes | `file:line` and function/method. |
| slot_type | enum | yes | See allowed values below. |
| sanitization_observed | string | yes | All sanitizers in order, with `file:line`. Use `"None"` if absent. |
| concat_occurrences | string | yes | Each concat/format/join with `file:line`; flag post-sanitization. |
| verdict | enum | yes | See allowed values below. |
| mismatch_reason | string | yes | If vulnerable, 1-2 lines in plain language; else empty string. |
| witness_payload | string | yes | Minimal static example; recorded only, never executed. |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | How a tester would confirm in a controlled environment. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Assumptions, untraversed branches, anything unusual. |

### Allowed values
- `vulnerability_type`: SQLi, CommandInjection, LFI, RFI, SSTI, PathTraversal, InsecureDeserialization.
- `slot_type`: SQL-val, SQL-like, SQL-num, SQL-enum, SQL-ident, CMD-argument, CMD-part-of-string, FILE-path, FILE-include, TEMPLATE-expression, DESERIALIZE-object, PATH-component.
- `verdict`: vulnerable, safe.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false (boolean, not string).

### Valid example record

```json
{
  "ID": "INJ-VULN-001",
  "vulnerability_type": "SQLi",
  "externally_exploitable": true,
  "source": "req.query.q at src/routes/search.ts:18",
  "combined_sources": [],
  "path": "searchRoute -> searchService -> db.query",
  "sink_call": "src/services/search.ts:44 db.query",
  "slot_type": "SQL-val",
  "sanitization_observed": "None",
  "concat_occurrences": "src/services/search.ts:43 string interpolation after input read",
  "verdict": "vulnerable",
  "mismatch_reason": "User-controlled query text reaches SQL string construction without parameter binding.",
  "witness_payload": "single quote character; recorded only, never executed",
  "remediation_hypothesis": "An attacker may manipulate the query condition and read unintended rows.",
  "verification_steps": "In a controlled test environment, submit a crafted search string and verify query behavior changes.",
  "severity": "high",
  "severity_rationale": "Externally reachable SQL injection path affecting application data.",
  "confidence": "high",
  "notes": "No sanitizer or parameter binding observed on this path."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`). Records appear in `.security-audit/REPORT.md` under the global SEC-NNN numbering, sorted by severity then confidence.

---

## 2. XSS (Reflected, Stored, DOM-based)

### Purpose
Captures each context mismatch where data is rendered into a DOM sink without the correct encoder for that render context.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `XSS-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| source | string | yes | The parameter, header, or storage mechanism. |
| source_detail | string | yes | Specific DB read/input that reaches the sink, with `file:line`. |
| path | string | yes | Complete data flow from source to sink. |
| sink_function | string | yes | Function or template construct that renders the data. |
| render_context | enum | yes | See allowed values below. |
| encoding_observed | string | yes | Name and `file:line` of encoders, or `"None"`. |
| verdict | enum | yes | See allowed values below. |
| mismatch_reason | string | yes | If vulnerable, why the encoder is wrong for the context. |
| witness_payload | string | yes | Minimal static example; recorded only, never executed. |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | How a tester would confirm in a controlled environment. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | CSP, HttpOnly flags, WAF behavior, environmental factors. |

### Allowed values
- `vulnerability_type`: Reflected, Stored, DOM-based.
- `render_context`: HTML_BODY, HTML_ATTRIBUTE, JAVASCRIPT_STRING, URL_PARAM, CSS_VALUE.
- `verdict`: vulnerable, safe.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false.

### Valid example record

```json
{
  "ID": "XSS-VULN-001",
  "vulnerability_type": "Reflected",
  "externally_exploitable": true,
  "source": "URL parameter: ?q",
  "source_detail": "req.query.q at src/routes/search.ts:12",
  "path": "req.query.q -> searchController.render() -> innerHTML at views/results.ejs:23",
  "sink_function": "innerHTML",
  "render_context": "HTML_BODY",
  "encoding_observed": "None",
  "verdict": "vulnerable",
  "mismatch_reason": "User input is inserted into HTML_BODY context without HTML entity encoding.",
  "witness_payload": "angle-bracket-prefixed tag-shaped string; recorded only, never executed",
  "remediation_hypothesis": "An attacker could cause arbitrary markup to render in a victim's browser.",
  "verification_steps": "Submit a tag-shaped string through the search field and inspect the rendered DOM in a controlled browser session.",
  "severity": "medium",
  "severity_rationale": "Reflected XSS with realistic delivery via shared search URL.",
  "confidence": "high",
  "notes": "No CSP observed; cookies lack HttpOnly flag at src/middleware/session.ts:18."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`).

---

## 3. Authentication (Broken AuthN)

### Purpose
Captures logical flaws in the application's identity-verification model: weak transport, missing rate limits, session cookie misconfiguration, weak token entropy/lifecycle, session fixation, weak credential policy, user enumeration, recovery flaws, OAuth/OIDC misuse.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `AUTH-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| source_endpoint | string | yes | `{HTTP_METHOD} {endpoint_path}`. |
| vulnerable_code_location | string | yes | Exact `file:line` of the flawed logic. |
| missing_defense | string | yes | Concise description of the core problem. |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | Specific attack pattern a tester would attempt. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Session state, roles, headers, related findings. |

### Allowed values
- `vulnerability_type`: Authentication_Bypass, Session_Management_Flaw, Login_Flow_Logic, Token_Management_Issue, Reset_Recovery_Flaw, Transport_Exposure, Abuse_Defenses_Missing, OAuth_Flow_Issue.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false.

### Valid example record

```json
{
  "ID": "AUTH-VULN-001",
  "vulnerability_type": "Abuse_Defenses_Missing",
  "externally_exploitable": true,
  "source_endpoint": "POST /api/login",
  "vulnerable_code_location": "src/routes/auth.ts:34",
  "missing_defense": "No per-IP or per-account rate limit on POST /api/login.",
  "remediation_hypothesis": "An attacker can attempt credential stuffing or brute-force unconstrained.",
  "verification_steps": "In a controlled test environment, issue rapid sequential login attempts and confirm none are throttled.",
  "severity": "medium",
  "severity_rationale": "Missing rate limit on auth endpoint per the rubric.",
  "confidence": "high",
  "notes": "No middleware applies a limiter; no edge WAF rule observed in repo."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`).

---

## 4. Authorization (Broken Access Control)

### Purpose
Captures logical flaws in the application's access-control model: horizontal escalation (IDOR / cross-tenant), vertical escalation (role bypass), and context/workflow bypass.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `AUTHZ-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| endpoint | string | yes | `HTTP_METHOD /path/to/endpoint`. |
| vulnerable_code_location | string | yes | `file:line` where guard is missing/misplaced. |
| role_context | string | yes | Role(s) that can trigger this vulnerability. |
| guard_evidence | string | yes | Description of missing/misplaced guard. |
| side_effect | string | yes | Specific unauthorized action possible. |
| reason | string | yes | 1-2 lines explaining why this is vulnerable. |
| minimal_witness | string | yes | Brief description of how to trigger. |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | How a tester would confirm in a controlled environment. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Assumptions, related findings, special conditions. |

### Allowed values
- `vulnerability_type`: Horizontal, Vertical, Context_Workflow.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false.

### Valid example record

```json
{
  "ID": "AUTHZ-VULN-001",
  "vulnerability_type": "Horizontal",
  "externally_exploitable": true,
  "endpoint": "GET /api/orders/:orderId",
  "vulnerable_code_location": "src/controllers/orders.ts:52",
  "role_context": "any authenticated user",
  "guard_evidence": "No ownership check; query reads order by id without filtering by current user id.",
  "side_effect": "Read another user's order details, including shipping address and totals.",
  "reason": "The route validates session presence but never binds orderId to the session user.",
  "minimal_witness": "Authenticate as user A and request an orderId known to belong to user B.",
  "remediation_hypothesis": "An attacker can enumerate orders across all users by incrementing orderId.",
  "verification_steps": "In a controlled test environment, sign in as user A, request user B's known orderId, observe the response body contains user B's order.",
  "severity": "high",
  "severity_rationale": "IDOR on sensitive resource per the rubric.",
  "confidence": "high",
  "notes": "orderId is a sequential integer, easing enumeration."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`).

---

## 5. SSRF (Server-Side Request Forgery)

### Purpose
Captures data flows where user-controlled input influences an outbound server-side request and the application fails to validate the destination (scheme, host, port, redirect, sensitive headers, response handling).

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `SSRF-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| source_endpoint | string | yes | `{HTTP_METHOD} {endpoint_path}`. |
| vulnerable_parameter | string | yes | Name of the parameter accepting user input. |
| vulnerable_code_location | string | yes | Exact `file:line` of the HTTP client call. |
| missing_defense | string | yes | Concise description of the core problem. |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | Specific attack pattern a tester would attempt. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Request format, auth requirements, timeouts, related findings. |

### Allowed values
- `vulnerability_type`: URL_Manipulation, Redirect_Abuse, Webhook_Injection, API_Proxy_Bypass, File_Fetch_Abuse, Service_Discovery.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false.

### Valid example record

```json
{
  "ID": "SSRF-VULN-001",
  "vulnerability_type": "URL_Manipulation",
  "externally_exploitable": true,
  "source_endpoint": "POST /api/fetch",
  "vulnerable_parameter": "url",
  "vulnerable_code_location": "src/services/fetcher.ts:21",
  "missing_defense": "No scheme, host, or IP allowlist before invoking the HTTP client.",
  "remediation_hypothesis": "An attacker can cause the server to issue requests to internal services or cloud metadata endpoints.",
  "verification_steps": "In a controlled test environment, submit an internal-only URL and observe whether the response is fetched.",
  "severity": "high",
  "severity_rationale": "SSRF reaching internal network without allowlisting.",
  "confidence": "medium",
  "notes": "HTTP client follows redirects; no host validation observed."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`).

---

## 6. Supply Chain & Configuration (Secrets, Crypto, Dependencies, Config, Infra, CI/CD)

### Purpose
Captures findings outside the source-to-sink runtime flow: hardcoded or historical secrets, cryptographic misuse, vulnerable or unpinned dependencies, missing security headers, CORS/cookie misconfiguration, debug-mode leakage, Dockerfile/Kubernetes/IaC misconfiguration, CI/CD workflow risks, and `.gitignore` gaps. Some of these (e.g., live secret in HEAD) demand immediate disclosure regardless of analysis state.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | Unique within class (e.g., `SUP-VULN-001`). |
| vulnerability_type | enum | yes | See allowed values below. |
| severity | enum | yes | See allowed values below. |
| severity_rationale | string | yes | 1-2 lines referencing the rubric. |
| externally_exploitable | boolean | yes | `true` or `false`, unquoted. |
| location | string | yes | `file:line` or git-history reference (commit SHA + path). |
| evidence | string | yes | Specific snippet/value/CVE reference (redacted for live secrets). |
| remediation_hypothesis | string | yes | Expected impact if not fixed. |
| verification_steps | string | yes | How a tester would confirm. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Anything unusual. |

### Allowed values
- `vulnerability_type`: HardcodedSecret, HistoricalSecret, WeakCrypto, TLSMisuse, VulnerableDependency, UnpinnedDependency, Typosquat, PostinstallRisk, MissingSecurityHeader, CORSMisconfig, DebugModeInProd, DockerfileMisconfig, KubernetesMisconfig, IaCMisconfig, CICDMisconfig, GitignoreGap.
- `severity`: critical, high, medium, low, info.
- `confidence`: high, medium, low.
- `externally_exploitable`: true, false.

### Valid example record

```json
{
  "ID": "SUP-VULN-001",
  "vulnerability_type": "MissingSecurityHeader",
  "severity": "low",
  "severity_rationale": "Missing security header per the rubric.",
  "externally_exploitable": true,
  "location": "src/middleware/headers.ts:14",
  "evidence": "No Strict-Transport-Security header set on responses.",
  "remediation_hypothesis": "Browsers may downgrade connections to HTTP on initial visit, exposing session cookies on hostile networks.",
  "verification_steps": "Inspect response headers from any application endpoint; confirm Strict-Transport-Security is absent.",
  "confidence": "high",
  "notes": "Edge proxy (nginx.conf) also lacks the header."
}
```

### Consumed by
Phase 9 (`prompts/09-report.md`).

---

## Slot taxonomy reference

For convenience, the slot/context labels used by the injection and XSS schemas are reproduced here in one place.

### Injection slot types
- SQL-val: value slot (right-hand side of =, value in IN (...), value in VALUES (...)). Defense: parameter binding.
- SQL-like: value inside a LIKE pattern. Defense: parameter binding + caller-controlled % / _ escaping.
- SQL-num: numeric slot. Defense: cast to numeric type before interpolation; never string-concat.
- SQL-enum: short fixed set of allowed strings (e.g., ASC / DESC). Defense: strict whitelist.
- SQL-ident: identifier slot (table, column, schema, sort key). Defense: strict whitelist of allowed identifiers. Parameter binding does NOT protect identifiers.
- CMD-argument: passed as a discrete argv element to the kernel (shell=False). Defense: array-form exec.
- CMD-part-of-string: interpolated into a shell command string (shell=True, backticks, os.system). Defense: shlex.quote() or move to array form.
- FILE-path: used as a path in open / fopen / readFile / sendFile. Defense: resolve to absolute then verify under an allowed root.
- FILE-include: used by an include/require with execution semantics. Defense: allowlist; ideally remove dynamic include entirely.
- TEMPLATE-expression: interpolated into a template engine's expression context. Defense: autoescape on; never put user data into the template *source*.
- DESERIALIZE-object: passed to a deserializer (pickle.loads, unserialize, readObject, yaml.load). Defense: only trusted sources, or safe formats with integrity (HMAC).
- PATH-component: partial path component used in URL/HTTP routing where path traversal could lead to side effects.

### XSS render contexts
- HTML_BODY: text node or inside a <div> / <p> / <span>. Defense: HTML entity encoding.
- HTML_ATTRIBUTE: inside an HTML attribute value. Defense: attribute encoding, plus URL-scheme check for href/src/formaction/etc.
- JAVASCRIPT_STRING: inside a quoted JS string literal. Defense: JS string escaping.
- URL_PARAM: inside a URL component (path/query/hash). Defense: URL encoding.
- CSS_VALUE: inside a CSS property value. Defense: CSS hex encoding; restrict to known-good values.

### SSRF vulnerability types
- URL_Manipulation: user controls the URL/scheme/host directly.
- Redirect_Abuse: server follows attacker-controlled redirects after passing initial validation.
- Webhook_Injection: user-controllable webhook destination without per-tenant allowlist.
- API_Proxy_Bypass: server forwards a request and either fails to strip sensitive headers or allows header injection.
- File_Fetch_Abuse: user influences a file-fetching URL (importer, "fetch from URL" feature) without protocol/host restrictions.
- Service_Discovery: user influences host/port allowing internal service enumeration.

### Authentication vulnerability types
- Authentication_Bypass: a path that lets a request reach a protected handler without authentication.
- Session_Management_Flaw: session cookies missing flags, session ID not rotated on login, no server-side invalidation on logout.
- Login_Flow_Logic: user enumeration, session fixation, missing OAuth state/nonce, etc.
- Token_Management_Issue: weak entropy, no TTL, no revocation, logged tokens.
- Reset_Recovery_Flaw: reset tokens not single-use, no rate limit, enumerable, long-TTL.
- Transport_Exposure: HTTP fallbacks, missing HSTS, missing Cache-Control: no-store on auth responses.
- Abuse_Defenses_Missing: no rate limiting, no lockout, no CAPTCHA, no anomaly alerting on auth endpoints.
- OAuth_Flow_Issue: wildcard redirect URIs, unverified IdP signatures, accepted alg=none, nOAuth attribute confusion.

### Authorization vulnerability types
- Horizontal: same role, different victim (cross-user / cross-tenant IDOR).
- Vertical: lower role reaches higher-role functionality (admin escalation).
- Context_Workflow: multi-step flow allows skipping prior states (e.g., /checkout/confirm without a populated cart).

---

## 7. Secret Triage (Phase 2.5)

### Purpose
Captures live-secret discoveries from the pre-flight halt gate. One record per detected credential. The Phase 2.5 agent emits these in `.security-audit/findings/secrets-triage.md` and, on `likely-live` classification, writes `.security-audit/HALT.md` to stop the pipeline. Phase 9 ingests these records like any other finding.

### Field reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ID | string | yes | `SECRET-TRIAGE-NNN`. |
| vulnerability_type | enum | yes | See allowed values below. |
| externally_exploitable | boolean | yes | Usually `false` (the secret itself is not the entry point), but `true` if the secret is a public-facing token. |
| location | string | yes | `file:line` for HEAD findings, or `commit SHA + file:line` for history findings. |
| secret_shape | string | yes | Human label for the matched pattern (e.g., "AWS access key", "Stripe live secret", "PEM private key"). |
| redacted_value | string | yes | First 4 + last 4 chars only (e.g., `AKIA...XYZA`). Never include the full value. |
| history_status | enum | yes | See allowed values below. |
| classification | enum | yes | See allowed values below. |
| remediation_hypothesis | string | yes | What an attacker could do if the credential is live. |
| verification_steps | string | yes | Out-of-band confirmation (do NOT test the credential against the live service). |
| severity | enum | yes | Default `critical` for likely-live; lower allowed only after human review. |
| severity_rationale | string | yes | One line. |
| confidence | enum | yes | See allowed values below. |
| notes | string | yes | Any unusual context (e.g., "value matches AWS public example key, likely fake"). |

### Allowed values

- `vulnerability_type`: `LiveSecret`, `HistoricalSecret`, `AmbiguousCandidate`
- `history_status`: `present_in_HEAD`, `removed_in_recent_history`, `present_in_HEAD_and_history`
- `classification`: `likely-live`, `placeholder-or-fixture`, `needs-human-review`
- `severity`: `critical`, `high`, `medium`, `low`, `info`
- `confidence`: `high`, `medium`, `low`
- `externally_exploitable`: `true`, `false`

### Valid example record

```json
{
  "ID": "SECRET-TRIAGE-001",
  "vulnerability_type": "LiveSecret",
  "externally_exploitable": false,
  "location": "src/config/prod.env:3",
  "secret_shape": "AWS access key",
  "redacted_value": "AKIA...XYZA",
  "history_status": "present_in_HEAD",
  "classification": "likely-live",
  "remediation_hypothesis": "A leaked credential may allow unauthorized access to cloud resources until rotated.",
  "verification_steps": "Do not test the credential. Confirm ownership internally, revoke or rotate it, and audit usage logs for unauthorized use.",
  "severity": "critical",
  "severity_rationale": "Credential-like value appears in tracked source and matches a high-confidence live-secret pattern.",
  "confidence": "high",
  "notes": "Secret value intentionally redacted. Pipeline halted via .security-audit/HALT.md."
}
```

### Halt behavior

If any record in this file has `classification: "likely-live"`, the orchestrator MUST NOT spawn Phases 3-8. Phase 9 still runs, but the report leads with the secret-triage finding (see `prompts/09-report.md` honesty rules).
