# Changelog

All notable changes to `audit-repo-security`.

The format roughly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are pre-1.0 and not API-stable.

## 0.3.3 — 2026-05-16

Round-six polish.

### Added
- **`LICENSE`** — MIT, copyright "the audit-repo-security authors". Update the holder line when extracting to a personal/org repo.
- **`scripts/validate.sh`** — pre-flight checks: macOS sidecars, JSON block validity, required files present, README output-tree references match the filesystem, no stale `med` confidence values, no pipe-delimited fake-JSON enum strings inside `json` blocks. Exits non-zero on any failure.
- **`scripts/package.sh` now runs `validate.sh` first** and refuses to build a zip if validation fails. The packaging script is now the only sanctioned distribution path.

### Fixed
- README's "License" section no longer says "placeholder" — points at the new `LICENSE` file with a note to update the copyright holder before publishing.
- CHANGELOG 0.3.1 now carries a one-line "Note: corrected in 0.3.2" pointer for the Python lockfile guidance that was wrong in that release.

## 0.3.2 — 2026-05-16

Round-five polish.

### Fixed
- **`pip-audit` instructions corrected.** pip-audit cannot parse `Pipfile.lock` or `poetry.lock` as requirements files — passing them to `--requirement` produces wrong or empty results. Updated both the safety-rules allowed-subcommands list and the §8.2 native-audits checklist:
  - Requirements-style files (`requirements.txt`, `requirements-*.txt`, `constraints.txt`) → use `pip-audit --requirement`.
  - Poetry / pyproject projects → prefer `pip-audit --locked . -f json` when it can run without installing/building/mutating.
  - Pipenv → audit a committed exported requirements file only; do not auto-run `pipenv requirements` / `poetry export` without explicit user permission.
- **"All six" wording in `SKILL.md`** clarified to "all six Phase 3-8 analysis agents" so the orchestrator does not miscount when Phase 2.5's `secrets-triage.md` is also on disk.

## 0.3.1 — 2026-05-16

Round-four polish based on reviewer feedback.

> **Note:** The Python lockfile guidance introduced in this release (`pip-audit --requirement` against `Pipfile.lock` and `poetry.lock`) was incorrect — pip-audit does not parse those formats as requirements files. It was corrected in 0.3.2.

### Fixed
- **Stale "six findings files" wording in `SKILL.md` Step 4.** Now mentions every `findings/*.md` including `secrets-triage.md` plus the two recon files.
- **README output tree** updated to include `findings/secrets-triage.md` (always present) and top-level `HALT.md` (present only when Phase 2.5 halts the audit).
- **`pip-audit --strict` removed from allowed-subcommands.** It audits the currently-installed Python environment, not the repo's declared deps. Replaced with repo-bound forms (see 0.3.2 for the corrected lockfile guidance).
- **`govulncheck` contradiction in supply-chain prompt** resolved: the native-audits checklist no longer says "if Go and tooling available" — it now defers to the safety rules and recommends `osv-scanner --lockfile=go.sum` as the fallback.

### Added
- **`scripts/package.sh`** — clean-zip builder. Strips `._*` and `.DS_Store` from the source tree, sets `COPYFILE_DISABLE=1`, excludes `__MACOSX/`/`._*`/`.DS_Store`/`.git`/`node_modules`, then verifies the archive contains no Finder metadata. Use this instead of hand-rolling `zip`.

## 0.3.0 — 2026-05-16

Round-three hardening based on reviewer feedback.

### Fixed
- **Phase 9 ingestion no longer requires `verdict` globally.** The `verdict` field exists only on Injection and XSS schemas. Auth/authz/SSRF/supply-chain/secret-triage findings were previously being marked malformed for lacking it. Validation is now per-class.
- **Phase 2.5 secret triage now has a formal schema.** `SECRET-TRIAGE-*` records use a new schema in `schemas/findings-queue.md` §7, with `redacted_value`, `secret_shape`, `history_status`, and `classification` fields. Phase 9 ingests them like any other finding.
- **Recent-history scan is now explicit.** Phase 2.5 uses `git log -n 50 -p --all` (instead of an unbounded `git log -p -S '...' --all`) and runs a separate Pass B that pattern-scans the recent patches themselves — catching secrets that were committed and later removed, not just substrings of current HEAD candidates.
- **`govulncheck` is now conditional.** Allowed only if it can run advisory-static without loading or building project binaries on the target environment. Otherwise skipped with a recorded limitation. `osv-scanner` preferred for Go.
- **No repo-state mutation by audit tooling.** New rule 7 in the package-audit safety block: audit tooling must not write to `node_modules/`, `vendor/`, `.venv/`, `target/`, lockfiles, or any tracked file. If a tool would mutate state, skip it and record.

### Added
- Packaging guidance in README — clean-zip command excluding `__MACOSX/`, `._*` sidecars, and `.DS_Store`.
- This CHANGELOG.

## 0.2.0 — 2026-05-15

Round-two overhaul based on reviewer critique.

### Fixed
- **Removed biased report templates.** Replaced "Several high-confidence vulnerabilities were identified" boilerplate with neutral wording: "Report only what was actually found. If no confirmed vulnerabilities exist in this class, write exactly: 'No confirmed vulnerabilities of this class were found.'"
- **Added `severity` and `severity_rationale` to every finding schema.** Previously the report agent was asked to sort by severity against records that had no severity field.
- **Resolved report-structure contradiction.** Phase 9 now produces one global findings list sorted by severity, plus short class-level note sections. Removed the conflicting "preserve per-class section order" instruction.
- **Replaced "JSON-ish" schemas with valid example JSON.** Schemas now use a 3-part layout: field-reference table, allowed-values prose, and a literally-parseable example record. No more pipe-delimited strings inside ```json blocks.
- **Normalized confidence values to `high | medium | low`.** Previously some schemas used `med`, others used `medium`.
- **Softened the "never use Read" rule.** Sub-agents are preferred for breadth and depth; direct Read is now explicitly allowed for verifying file:line evidence, inspecting small files, checking findings before consolidation, and resolving contradictions.

### Added
- **Phase 2.5 — Critical secret triage** as a halt gate between Recon and the parallel fan-out. Writes `.security-audit/HALT.md` on a live-secret hit; orchestrator aborts before Phase 3-8 spawn.
- **Phase 8 — Supply chain & configuration analysis.** Covers secrets/crypto, dependency CVEs, security headers, CORS, Docker, Kubernetes, IaC, CI/CD workflows, `.gitignore` gaps. Includes an operational critical-secret stop trigger inside the prompt itself.
- **Package-audit safety rules.** Audit tooling is restricted to advisory subcommands; install/build/test/lifecycle scripts banned; network-unavailable fallback defined; untrusted-registry rule.
- **Output-contract validation in Phase 9.** Strict JSON parsing; malformed blocks routed to a "Malformed Findings" subsection; honesty rules forbid silently repairing or inventing severity/CWE/remediation.
- **Standard subagent output sections.** Every class deliverable ends with the same five sections (Files inspected / Sinks-sources traced / Confirmed findings / Confirmed safe vectors / Blind spots).
- **"Required runtime tools" section in `SKILL.md`** documenting the assumed tool surface and graceful-degradation behavior.
- **Default-excludes section.** `node_modules`, `vendor`, `dist`, `build`, `coverage`, `.next`, minified assets, snapshots, generated stubs — out of scope unless the user opts them in.

## 0.1.0 — 2026-05-15

Initial faithful port of Shannon's AI-pentester prompts for static repo audits.

### Added
- Pipeline: pre-recon → recon → 5 parallel vuln-class agents (injection, XSS, auth, authz, SSRF) → report.
- All Shannon slot taxonomies preserved (SQL-val/like/num/ident, CMD-argument, FILE-path, TEMPLATE-expression, DESERIALIZE-object, HTML_BODY/HTML_ATTRIBUTE/JAVASCRIPT_STRING/URL_PARAM/CSS_VALUE).
- Findings-queue schemas per class, with field renames `exploitation_hypothesis` → `remediation_hypothesis` and `suggested_exploit_technique` → `verification_steps`.
- Stripped live-target machinery: Playwright, browser automation, TOTP, login instructions, URL framing.
- Severity and confidence rubrics, with "round down when uncertain" rule.
- Output artifacts under `.security-audit/` with a recommendation to add it to `.gitignore`.
