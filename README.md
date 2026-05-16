# audit-repo-security

A self-contained Claude Code skill that performs a static, white-box, repo-wide security audit. Modeled on the AI-pentester methodology from [Shannon](https://github.com/keygraph/shannon), adapted to operate on source code alone — no live target, no browser, no exploitation.

## What it does

The skill runs a 9-phase pipeline (plus a halt gate) against the whole repository checked out in the working directory:

1. **Pre-recon** — architectural baseline, attack-surface catalog, sink/source inventories.
2. **Recon** — API endpoint inventory, role and privilege architecture, authorization vuln candidates, injection sources.
2.5. **Critical secret triage (halt gate)** — fast scan of HEAD + last 50 commits for live secrets. If any are found, the pipeline halts before the parallel fan-out so the user can rotate first.
3. **Injection analysis** — SQLi, command injection, LFI/RFI, SSTI, path traversal, insecure deserialization.
4. **XSS analysis** — reflected, stored, DOM-based; render-context-correct encoder checking.
5. **Auth analysis** — broken AuthN (sessions, tokens, password policy, MFA, OAuth/OIDC).
6. **Authz analysis** — horizontal IDOR, vertical privilege escalation, workflow/context bypass.
7. **SSRF analysis** — URL/scheme/host/port/metadata-endpoint protections.
8. **Supply chain & configuration analysis** — secrets, crypto, dependencies, HTTP/CORS headers, Docker/Kubernetes/IaC, CI/CD workflows.
9. **Consolidation** — globally renumbered, severity-ranked report at `.security-audit/REPORT.md`.

Phases 3-8 run in parallel as six general-purpose subagents spawned in a single message, but only after the Phase 2.5 secret-triage gate clears. The other phases run sequentially.

## What it produces

```
.security-audit/
  01-pre-recon.md           # Phase 1 architectural baseline
  02-recon.md               # Phase 2 attack-surface map
  HALT.md                   # Present ONLY when Phase 2.5 halts the audit on a live secret
  findings/
    secrets-triage.md       # Phase 2.5 halt-gate findings (always present)
    injection.md            # Phase 3
    xss.md                  # Phase 4
    auth.md                 # Phase 5
    authz.md                # Phase 6
    ssrf.md                 # Phase 7
    supply-chain.md         # Phase 8
  scratchpad/
    charters/               # per-agent charter copies (input to subagents)
  REPORT.md                 # Phase 9 consolidated, severity-ranked report
```

Each finding is recorded against a per-class strict-JSON schema (see `schemas/findings-queue.md`). The consolidation phase renumbers findings globally as `SEC-001`, `SEC-002`, ... sorted by severity then confidence, and de-duplicates root causes flagged by multiple classes.

Add `.security-audit/` to `.gitignore` — these reports document vulnerabilities by file:line and should not be committed before fixes ship.

## Install

Drop the directory into your project (or your global skills dir):

```
.claude/skills/audit-repo-security/
```

Or symlink/copy from a clone of this repo.

Once installed, invoke from Claude Code with any phrasing the skill description matches: "audit this repo for security issues", "find vulnerabilities in this codebase", "white-box review the codebase", "static pentest of the repo", etc.

You can also optionally pass path filters when invoking — focus on specific subtrees or skip vendored code.

## Layout

```
audit-repo-security/
  SKILL.md                                # orchestrator entry point (with skill frontmatter)
  README.md                               # this file
  prompts/
    01-pre-recon.md
    02-recon.md
    03-vuln-injection.md
    04-vuln-xss.md
    05-vuln-auth.md
    06-vuln-authz.md
    07-vuln-ssrf.md
    08-supply-chain.md
    09-report.md
    02b-secret-triage.md
  schemas/
    findings-queue.md                     # per-class record schemas + slot taxonomy
  scripts/
    package.sh                            # clean-zip builder (runs validate.sh first)
    validate.sh                           # pre-flight checks: JSON, files, sidecars, schema notation
  CHANGELOG.md
  LICENSE
```

## Methodology and attribution

The methodology — slot-typed injection analysis, sink-to-source backward taint for XSS, the AuthN/AuthZ checklists, the SSRF defense taxonomy, the recon entity/flow/guard model — is ported from Shannon's AI-pentester prompts. The original prompts target a live application (running URL, Playwright, exploitation phase); this skill adapts them for static code-only analysis:

- All live-target machinery removed (Playwright, curl-based testing, TOTP, login instructions, attacker-perspective URL framing).
- "Exploitation hypothesis" / "suggested exploit technique" renamed to `remediation_hypothesis` / `verification_steps` — they capture the same information, framed for the remediation phase instead of the exploitation phase.
- "External-only" scope dropped in favor of full white-box coverage. Findings are labeled `externally_exploitable: true|false` so consumers can still filter, but the audit covers internal-only code paths too.
- `witness_payload` examples are kept in every schema. They are recorded only and never executed.

All slot taxonomies, render contexts, confidence rubrics, and false-positive guidance are preserved verbatim.

## License

MIT. See `LICENSE`. If you fork or extract this skill into your own repo, update the copyright holder line in `LICENSE` to your name or organization.
