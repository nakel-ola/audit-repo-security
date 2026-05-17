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

## Security & threat model

This skill grants the agent capabilities you should think about before pointing it at a repo you don't trust.

### What it does at runtime

- Reads files across the entire repository (Read, Glob).
- Runs shell commands via Bash, including `git log -p` over the last 50 commits during Phase 2.5 secret triage.
- Spawns up to six parallel sub-agents (Phase 3-8) with the same toolset.
- Writes findings under `.security-audit/` in the working directory.
- In Phase 8, invokes package-advisory tools (`npm audit`, `pnpm audit`, `pip-audit --requirement`, `cargo audit`, `bundler-audit`, optionally `osv-scanner`) and may call `https://api.osv.dev/v1/query` via WebFetch.

### What it explicitly does NOT do

- It does not execute the audited application's code. No `node`, `python`, `ruby`, `go run`, `npm install`, `pnpm install`, `pip install`, build scripts, test runners, or package lifecycle scripts (see the package-audit safety rules in `prompts/08-supply-chain.md`).
- It does not modify the audited repo. `.security-audit/` is the only write target. `node_modules/`, lockfiles, and tracked source are untouched.
- It does not exfiltrate findings. All output is local under `.security-audit/`.
- It does not execute witness payloads recorded in findings — they are static examples for the consumer of the report to verify.

### Recommended posture

| Repo trust level | Recommendation |
|---|---|
| Your own code | Run normally. |
| Trusted third party (vendor you have a relationship with) | Run normally; review the report before sharing. |
| Untrusted / actively hostile | Run inside a container with no network and no host mounts beyond a read-only repo bind. Disable Phase 8's WebFetch step. The package-audit tools are advisory-only, but lockfile contents are still attacker-controlled input. |

## Install

Two install paths. Pick whichever fits your workflow.

### `npx skills add` (managed updates)

Use this if you want the Skills CLI to track the install and handle updates for you.

```bash
# Global (available across all projects):
npx skills add nakel-ola/audit-repo-security -g

# Project (committed with your repo, shared with your team):
npx skills add nakel-ola/audit-repo-security

# Update later:
npx skills update
```

### `git clone` (full control, no Node required)

Use this if you don't have Node, prefer not to add a CLI dependency, or want to vendor the skill at a pinned commit.

```bash
# Project scope:
git clone https://github.com/nakel-ola/audit-repo-security \
  .claude/skills/audit-repo-security

# Global scope:
git clone https://github.com/nakel-ola/audit-repo-security \
  ~/.claude/skills/audit-repo-security
```

Update with `git pull` from inside the install directory.

---

Once installed, restart Claude Code. Invoke with any phrasing the skill description matches: "audit this repo for security issues", "find vulnerabilities in this codebase", "white-box review the codebase", "static pentest of the repo", etc.

You can also optionally pass path filters when invoking — focus on specific subtrees or skip vendored code.

## Layout

```
audit-repo-security/
  SKILL.md                                # orchestrator entry point (with skill frontmatter)
  README.md                               # this file
  prompts/
    01-pre-recon.md
    02-recon.md
    02b-secret-triage.md
    03-vuln-injection.md
    04-vuln-xss.md
    05-vuln-auth.md
    06-vuln-authz.md
    07-vuln-ssrf.md
    08-supply-chain.md
    09-report.md
  schemas/
    findings-queue.md                     # per-class record schemas + slot taxonomy
  scripts/
    validate.sh                           # repo-level regression check (not run at install time)
  CHANGELOG.md
  LICENSE
```

## Maintainer workflow

`scripts/validate.sh` is a repo-level regression check for people editing the skill, not something end users run. It verifies:

- No macOS sidecars committed (`._*`, `.DS_Store`, `__MACOSX/`).
- Every fenced `` ```json `` block in the prompts and schemas parses cleanly.
- All required prompt/schema files exist.
- The Layout block above references real files.
- No stale `med` confidence values, no pipe-delimited fake-JSON enum strings.

Run before opening a PR:

```bash
./scripts/validate.sh
```

If you wire it into CI as a GitHub Action on `push` and `pull_request`, regressions get caught automatically.

## Methodology and attribution

The methodology — slot-typed injection analysis, sink-to-source backward taint for XSS, the AuthN/AuthZ checklists, the SSRF defense taxonomy, the recon entity/flow/guard model — is ported from Shannon's AI-pentester prompts. The original prompts target a live application (running URL, Playwright, exploitation phase); this skill adapts them for static code-only analysis:

- All live-target machinery removed (Playwright, curl-based testing, TOTP, login instructions, attacker-perspective URL framing).
- "Exploitation hypothesis" / "suggested exploit technique" renamed to `remediation_hypothesis` / `verification_steps` — they capture the same information, framed for the remediation phase instead of the exploitation phase.
- "External-only" scope dropped in favor of full white-box coverage. Findings are labeled `externally_exploitable: true|false` so consumers can still filter, but the audit covers internal-only code paths too.
- `witness_payload` examples are kept in every schema. They are recorded only and never executed.

All slot taxonomies, render contexts, confidence rubrics, and false-positive guidance are preserved verbatim.

## License

MIT. See `LICENSE`. If you fork or extract this skill into your own repo, update the copyright holder line in `LICENSE` to your name or organization.
