---
name: audit-repo-security
description: Use this skill when the user asks to audit an entire repository for security issues (not just a branch or PR). Triggers include "security audit of the repo", "find vulnerabilities in this codebase", "scan the whole project for security bugs", "white-box review the codebase", "static pentest of the repo". Faithfully ports Shannon's AI-pentester methodology (pre-recon → recon → critical-secret triage halt gate → 6 parallel analysis agents → consolidated report) for static repo audits. Each phase has a dedicated prompt file under prompts/. The six analysis agents (phases 3-8) run in parallel in a single message, but only after the Phase 2.5 secret-triage gate clears.
license: MIT
compatibility:
  - claude-code
metadata:
  version: 0.3.4
  homepage: https://github.com/nakel-ola/audit-repo-security
---

# Audit Repo Security

White-box, static, repo-wide security audit. No live target, no browser, no exploitation. Each phase is encoded as a dedicated prompt file under `prompts/`. This SKILL.md is the orchestrator: it sequences the phases, copies per-class charters into a scratchpad so each subagent has a clean brief to read, spawns the six analysis agents **in parallel**, then consolidates the report.

## When to use

Invoke this skill when the user wants:
- A full-repo vulnerability assessment, not a diff review.
- A first-pass security baseline for a codebase they are inheriting or shipping.
- A repeatable, methodology-driven audit (not ad-hoc grep).
- Coverage across the six core analysis classes: injection, XSS, auth, authz, SSRF, and supply chain & configuration.

Do not use this skill for:
- Reviewing a single PR or branch diff (use `/security-review` or `/review`).
- Live pentesting against a running target (out of scope).
- Single-file or single-bug analysis (use `/debug` or direct conversation).

## Required runtime tools

This skill is written for Claude Code's tool surface. Required:
- `Agent` (sub-agent invocation; this skill uses `subagent_type: general-purpose`)
- `Read` / `Write` / `Edit`
- `Bash`
- `Glob` (for [GLOB] path filter expansion)
- A task-tracking tool — typically `TaskCreate`/`TaskUpdate` in Claude Code, or `TodoWrite` in some runtimes. If no task tool is available, maintain `.security-audit/scratchpad/tasks.md` manually.
- Optional: `WebFetch` (for OSV / advisory cross-checks during the supply-chain phase)

If you are running this skill in a different runtime, verify these tools exist before proceeding. The skill will degrade gracefully without `WebFetch` (dependency-CVE checks fall back to native package-manager audits) but cannot run without sub-agent invocation.

## Pipeline (9 phases plus a halt gate)

Phases 1, 2, 2.5, and 9 run sequentially. Phases 3-8 (the six analysis agents) run **in parallel** in a single message, but only if the Phase 2.5 halt gate did not fire.

```
Phase 1: Pre-recon  (sequential, orchestrator-driven)
   prompts/01-pre-recon.md
   output: .security-audit/01-pre-recon.md
   purpose: build the architectural baseline, catalog entry points,
            list XSS sinks, list SSRF sinks, map the codebase

Phase 2: Recon  (sequential, orchestrator-driven)
   prompts/02-recon.md
   input:  .security-audit/01-pre-recon.md
   output: .security-audit/02-recon.md
   purpose: attack-surface map, API inventory, role & privilege
            architecture, authorization vuln candidates, injection sources

Phase 2.5: Critical secret triage  (sequential, halt gate)
   prompts/02b-secret-triage.md
   output: .security-audit/findings/secrets-triage.md
   halt marker (only if live secret found): .security-audit/HALT.md
   purpose: fast scan of HEAD + last 50 commits for live secrets.
            If found, halt the pipeline before fan-out so the user
            can rotate first.

Phases 3-8: Parallel analysis  (6 subagents in one message)
   prompts/03-vuln-injection.md   →  .security-audit/findings/injection.md
   prompts/04-vuln-xss.md         →  .security-audit/findings/xss.md
   prompts/05-vuln-auth.md        →  .security-audit/findings/auth.md
   prompts/06-vuln-authz.md       →  .security-audit/findings/authz.md
   prompts/07-vuln-ssrf.md        →  .security-audit/findings/ssrf.md
   prompts/08-supply-chain.md     →  .security-audit/findings/supply-chain.md

Phase 9: Consolidation  (sequential, orchestrator-driven)
   prompts/09-report.md
   inputs:  all of the above
   output:  .security-audit/REPORT.md
```

## Orchestration

### Step 0: Prepare scratchpad

Create the artifact tree and copy each analysis-class prompt into a per-agent charter under the scratchpad. Each subagent will read its own charter directly — this keeps the agent's context lean and avoids passing huge prompts inline.

Resolve the skill directory first (it may be `.claude/skills/audit-repo-security/` in the audited repo, or `~/.claude/skills/audit-repo-security/`, or under a plugin dir). Set `SKILL_DIR` to whichever exists, then:

```bash
SKILL_DIR="$(dirname "$0")"  # or wherever this SKILL.md lives — set explicitly
mkdir -p .security-audit/findings
mkdir -p .security-audit/scratchpad/charters
cp "$SKILL_DIR/prompts/03-vuln-injection.md" .security-audit/scratchpad/charters/injection.md
cp "$SKILL_DIR/prompts/04-vuln-xss.md"       .security-audit/scratchpad/charters/xss.md
cp "$SKILL_DIR/prompts/05-vuln-auth.md"      .security-audit/scratchpad/charters/auth.md
cp "$SKILL_DIR/prompts/06-vuln-authz.md"     .security-audit/scratchpad/charters/authz.md
cp "$SKILL_DIR/prompts/07-vuln-ssrf.md"      .security-audit/scratchpad/charters/ssrf.md
cp "$SKILL_DIR/prompts/08-supply-chain.md"   .security-audit/scratchpad/charters/supply-chain.md
cp "$SKILL_DIR/schemas/findings-queue.md"    .security-audit/scratchpad/findings-queue.md
```

`.security-audit/` and `.security-audit/scratchpad/` live in the **audited repo's working directory** (cwd), not the skill directory.

### Step 1: Pre-recon (Phase 1)

Read `prompts/01-pre-recon.md` and execute it yourself as the orchestrator. Use the Agent tool with `subagent_type: general-purpose` to delegate the discovery sub-tasks the charter calls for (Architecture Scanner, Entry Point Mapper, Security Pattern Hunter, XSS/Injection Sink Hunter, SSRF/External Request Tracer, Data Security Auditor), then synthesize their output into `.security-audit/01-pre-recon.md` with the Write tool (large reports split across multiple Write/Edit calls).

### Step 2: Recon (Phase 2)

Read `prompts/02-recon.md` and execute it. The recon charter delegates source-code analysis to `general-purpose` Agent subagents (Route Mapper, Authorization Checker, Input Validator, Session Handler, Authorization Architecture, Injection Source Tracer). Synthesize their findings into `.security-audit/02-recon.md`.

### Step 2.5: Critical secret triage (Phase 2.5 — halt gate)

Read `prompts/02b-secret-triage.md` and execute it. This is a fast, sequential pass over HEAD plus the last 50 commits looking for live secrets. The phase writes `.security-audit/findings/secrets-triage.md` always, and `.security-audit/HALT.md` only when a likely-live secret is found.

**Before spawning the parallel agents in Step 3, check for `.security-audit/HALT.md`.** If present, abort immediately, do NOT spawn Phase 3-8, and surface the secret-triage finding to the user with rotation guidance. The deeper full-history sweep for the supply-chain class is intentionally narrower and gated on this triage (see `prompts/08-supply-chain.md` §8.1 "Secret coverage at this phase").

### Step 3: Spawn the 6 analysis agents in parallel (Phases 3-8)

In a single message, issue six `Agent` tool calls. Each call points at one charter under `.security-audit/scratchpad/charters/` and one output path under `.security-audit/findings/`.

Invocation template (one of six; the six calls must all be in the same assistant message):

```
Agent({
  description: "Static injection audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/injection.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md. Output: write your final report to .security-audit/findings/injection.md. Static analysis only — do not execute payloads."
})

Agent({
  description: "Static XSS audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/xss.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md. Output: write your final report to .security-audit/findings/xss.md. Static analysis only — do not execute payloads."
})

Agent({
  description: "Static auth audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/auth.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md. Output: write your final report to .security-audit/findings/auth.md. Static analysis only — do not execute payloads."
})

Agent({
  description: "Static authz audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/authz.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md. Output: write your final report to .security-audit/findings/authz.md. Static analysis only — do not execute payloads."
})

Agent({
  description: "Static SSRF audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/ssrf.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md. Output: write your final report to .security-audit/findings/ssrf.md. Static analysis only — do not execute payloads."
})

Agent({
  description: "Static supply-chain & config audit",
  subagent_type: "general-purpose",
  prompt: "Read .security-audit/scratchpad/charters/supply-chain.md for your full charter. Inputs: .security-audit/01-pre-recon.md, .security-audit/02-recon.md, full working tree, git history. Output: write your final report to .security-audit/findings/supply-chain.md. Static analysis only — do not execute payloads, do not rotate or exfiltrate secrets yourself. Honor the critical secret stop condition documented in the charter."
})
```

Wait for all six Phase 3-8 analysis agents to finish before moving on. (Phase 2.5's `secrets-triage.md` was already written before the fan-out, so the consolidator will see seven findings files total — six from this step plus the triage file.) If any one of the six returns an empty file for a class that is clearly in scope, re-spawn that one agent with a more pointed brief.

### Step 4: Consolidate (Phase 9)

Read `prompts/09-report.md` and execute it yourself. Read every `.security-audit/findings/*.md` file — including `secrets-triage.md` from Phase 2.5 — plus `.security-audit/01-pre-recon.md` and `.security-audit/02-recon.md`. Ingest the JSON records strictly (per the Phase 9 charter), renumber findings globally, de-duplicate root causes, and emit `.security-audit/REPORT.md` in the structure defined by the charter. Use Write for the initial sections and Edit to append additional sections so the report does not exceed any single-call output limit.

## Path filters (optional)

If the user supplies path filters (e.g., "only audit `src/api/` and `src/auth/`", or "skip `vendor/` and `migrations/`"), record them at the top of `.security-audit/01-pre-recon.md` and `.security-audit/02-recon.md` so all subagents inherit them. The charters reference these via the `[FILE]` (literal path) and `[GLOB]` (pattern) routing convention. `[FILE]` entries are read directly; `[GLOB]` entries are expanded via the Glob tool then handed to the Agent tool one match at a time. Without explicit filters, audit the entire repository (subject to the default excludes below).

## Default excludes

Before any agent reads the filesystem, the orchestrator (and each sub-agent) should treat the following as out-of-scope by default unless the user explicitly opts them in:

- `node_modules/`, `bower_components/`, `.pnpm-store/`
- `vendor/`, `third_party/`
- `dist/`, `build/`, `out/`, `target/`, `.next/`, `.nuxt/`, `.svelte-kit/`
- `coverage/`, `.nyc_output/`
- `.git/`, `.hg/`, `.svn/`
- Minified assets (`*.min.js`, `*.min.css`, source maps `*.map`)
- Snapshots and fixtures (`__snapshots__/`, `fixtures/`, `cassettes/`)
- Generated protobuf / gRPC stubs (`*.pb.go`, `*_pb2.py`, `*_pb.js`)
- Lockfile-as-data — read but don't grep for sinks (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `go.sum`, `Cargo.lock`)

Do not rely on `.gitignore` — it is honored but not sufficient (vendored deps are often committed despite policy).

## Tasking

Use the available task-tracking tool (typically `TaskCreate`/`TaskUpdate` in Claude Code, or `TodoWrite` in some runtimes). If no task tool is available, maintain `.security-audit/scratchpad/tasks.md` manually. Track per-phase progress (one task per phase, plus one task per vuln source identified during recon). Mark tasks `in_progress` when starting, `completed` when done. Do not start Phase 2 until Phase 1 is complete; do not start the Phase 3-8 fan-out until Phase 2.5 has cleared (no `HALT.md`); do not start Phase 9 until all six Phase 3-8 analysis agents have written their findings files.

## Package-audit safety

Phase 8 (supply chain) runs package-manager audits. Those audits MUST be advisory-only and MUST NOT execute install scripts, lifecycle hooks, or application code. See `prompts/08-supply-chain.md` §8.2 "Package-audit safety rules" for the full allowlist and constraints. The orchestrator does not invoke these directly — but if a sub-agent escalates a Bash request that violates the rules, decline it.

## Severity rubric

| Level    | Use when                                                                          |
|----------|-----------------------------------------------------------------------------------|
| critical | Unauthenticated RCE, auth bypass, mass data exposure, credential leak in HEAD     |
| high     | Authenticated RCE, SQLi with real data, stored XSS, IDOR on sensitive resources, hardcoded prod secret in git history |
| medium   | Reflected XSS with realistic delivery, missing rate limit on auth, SSRF to non-metadata, weak crypto without immediate break |
| low      | Missing security headers, verbose errors, dependency CVE with no reachable path, defensive-depth gaps |
| info     | Hardening opportunities, observability gaps, documentation issues                  |

## Confidence rubric

| Level  | Use when                                                                                |
|--------|-----------------------------------------------------------------------------------------|
| high   | Complete source-to-sink trace; slot/context labeled; mismatch unambiguous; no post-sanitization mutation; reproducible from code alone |
| medium | Flaw strongly indicated but at least one unresolved hop (helper not fully inspected, conditional path) |
| low    | Suspicious pattern with incomplete trace; needs human follow-up                          |

When uncertain, **round down**. False positives erode trust faster than false negatives in a static audit.

## Output artifacts

After running this skill, the repo will contain:

```
.security-audit/
  01-pre-recon.md           # Phase 1 architectural baseline
  02-recon.md               # Phase 2 attack-surface map
  findings/
    injection.md            # Phase 3 — SQLi, cmd-inj, LFI/RFI, SSTI, path-traversal, deserialization
    xss.md                  # Phase 4 — reflected, stored, DOM-based, mXSS
    auth.md                 # Phase 5 — authN: sessions, tokens, password, MFA, OAuth/OIDC
    authz.md                # Phase 6 — horizontal, vertical, context/workflow
    ssrf.md                 # Phase 7 — URL/scheme/host/port/metadata
    supply-chain.md         # Phase 8 — secrets, crypto, deps, headers, CORS, Docker, k8s, IaC, CI/CD
  scratchpad/
    charters/               # per-agent charter copies (input to subagents)
    ...                     # any scratch work, intermediate notes
  REPORT.md                 # Phase 9 consolidated, severity-ranked report
```

## .gitignore

Recommend the user add `.security-audit/` to `.gitignore`. These reports document vulnerabilities by file:line and should not be committed before fixes ship.

## Findings-queue schemas

The per-class strict-JSON schemas (with field renames `exploitation_hypothesis` → `remediation_hypothesis`, `suggested_exploit_technique` → `verification_steps`, and a uniform `severity` / `severity_rationale` pair) live at `schemas/findings-queue.md`. Each analysis prompt references that file for its exact schema. The supply-chain class adds an additional schema (`SUP-VULN-NN`) covering hardcoded/historical secrets, crypto misuse, TLS misuse, vulnerable/unpinned dependencies, missing security headers, CORS, debug-in-prod, Dockerfile/Kubernetes/IaC misconfiguration, CI/CD risks, and `.gitignore` gaps.

## Stopping conditions

Stop and ask the user before proceeding if:
- The repo is enormous (>500k LOC) — propose scoping to specific subtrees first via path filters.
- A subagent's findings file is empty *and* the class is clearly in scope — re-spawn with a more pointed brief.
- You discover a critical issue mid-audit that needs immediate disclosure (e.g., a committed production key) — surface it now, don't wait for Phase 9. This is required by the supply-chain charter's secret-stop condition.
