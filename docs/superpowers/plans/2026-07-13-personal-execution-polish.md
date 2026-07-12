# Personal Execution Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all six skills practical for daily personal use by defaulting local create/improve/fix requests to inspect, implement, verify, and hand off while retaining explicit gates for external or risky actions.

**Architecture:** Put shared mode and authorization behavior in `shared-references/execution-defaults.md`. Keep domain-specific startup and completion requirements in each `SKILL.md`, update UI prompts to request execution, and make the repository validator enforce the contract.

**Tech Stack:** Markdown, YAML, Python 3 standard library, Git, Codex skill conventions

## Global Constraints

- Keep exactly six top-level skill directories.
- Keep repository and skill documentation in English; direct task output to the user's language.
- Default to `execute` for create, improve, optimize, design, or fix requests against a supplied project.
- Honor explicit `review` and `plan` modes.
- Proceed with reversible in-scope local work without repeated confirmation.
- Require explicit authorization for deployment, publishing, store submission, live external consoles, paid services, account/credential/billing/legal actions, destructive operations, and external communication.
- Every skill must contain `## Quick start`, `## Definition of done`, and a link to `../shared-references/execution-defaults.md`.
- Every default prompt must explicitly contain its `$skill-name` and request inspect–implement–verify behavior.
- Do not weaken existing evidence, accessibility, platform, or validation requirements.

---

### Task 1: Enforce the personal execution contract

**Files:**
- Modify: `scripts/validate_skills.py`

**Interfaces:**
- Consumes: each expected skill's `SKILL.md` text.
- Produces: validation errors for missing quick start, definition of done, or shared execution-policy link.

- [ ] **Step 1: Add contract checks before changing skill files**

In `validate_skill(name)`, read `SKILL.md` and append these exact errors when content is absent:

```python
required_content = {
    "## Quick start": "missing Quick start section",
    "## Definition of done": "missing Definition of done section",
    "../shared-references/execution-defaults.md": "missing shared execution policy link",
}
```

- [ ] **Step 2: Run the validator and prove RED**

Run: `python3 scripts/validate_skills.py`

Expected: nonzero exit with three contract errors for each of the six existing skills.

- [ ] **Step 3: Verify validator quality**

Run: `python3 -m py_compile scripts/validate_skills.py && git diff --check`

Expected: exit `0`.

### Task 2: Add the shared policy and domain execution paths

**Files:**
- Create: `shared-references/execution-defaults.md`
- Modify: `app-store-listing-creator/SKILL.md`
- Modify: `seo-geo-optimizer/SKILL.md`
- Modify: `flutter-android-performance/SKILL.md`
- Modify: `flutter-interactive-design/SKILL.md`
- Modify: `expo-android-performance/SKILL.md`
- Modify: `expo-interactive-design/SKILL.md`

**Interfaces:**
- Consumes: the approved mode/authorization design and each existing domain workflow.
- Produces: consistent `execute`, `review`, and `plan` behavior plus domain-specific start and completion evidence.

- [ ] **Step 1: Write the shared execution policy**

Create a concise policy with these sections and behavior:

```markdown
# Execution defaults
## Select the mode
## Execute without another confirmation
## Explain impact or ask first
## Require explicit authorization
## Handle uncertainty and failures
## Handoff
```

Define `execute` as the default for creation/improvement/fix requests, `review` as read-only, and `plan` as no implementation. Allow reversible local inspection, edits, and existing validation. Gate external publishing, paid/account/destructive actions, and material scope expansion. Require a handoff of changes, verification evidence, limits, and user actions.

- [ ] **Step 2: Add a domain Quick start to every skill**

Place `## Quick start` after each introduction. Start by reading the shared policy, selecting the mode, inspecting the relevant project evidence, and producing the first domain artifact:

- store: listing matrix and evidence inventory, then full listing package;
- SEO/GEO: site/repository baseline and prioritized change set, then authorized local implementation;
- Flutter performance: reproducible scenario and baseline, then evidenced fix;
- Flutter design: project/brief inspection and intentional direction, then a working vertical slice;
- Expo performance: workflow/native ownership map and production-like baseline, then durable-source fix;
- Expo design: runtime/route/dependency inspection and direction, then an accessible vertical slice.

- [ ] **Step 3: Align conflicting default language**

Remove or qualify statements that default unclear create/improve requests to read-only behavior. Preserve explicit audit/diagnosis requests as `review` and preserve every external mutation gate.

- [ ] **Step 4: Add a Definition of done to every skill**

Add 4–6 domain-specific checkboxes or bullets proving the requested artifact/change exists, relevant validation passed, regressions/accessibility were checked, external actions were not taken without authorization, and the final handoff is complete.

- [ ] **Step 5: Run repository validation and prove GREEN**

Run: `python3 scripts/validate_skills.py`

Expected: `Validated 6 skills successfully.`

### Task 3: Make daily invocation copy-ready

**Files:**
- Modify: `app-store-listing-creator/agents/openai.yaml`
- Modify: `seo-geo-optimizer/agents/openai.yaml`
- Modify: `flutter-android-performance/agents/openai.yaml`
- Modify: `flutter-interactive-design/agents/openai.yaml`
- Modify: `expo-android-performance/agents/openai.yaml`
- Modify: `expo-interactive-design/agents/openai.yaml`
- Modify: `README.md`

**Interfaces:**
- Consumes: the shared execution modes and six domain workflows.
- Produces: one-click default prompts and a personal daily workflow documented in the README.

- [ ] **Step 1: Update six UI default prompts**

Use one sentence per prompt, explicitly naming the skill and asking it to inspect context, implement the requested result, verify it, and report limits. Preserve each domain's distinguishing outcome.

- [ ] **Step 2: Add Recommended daily workflow to README**

Document default `execute`, explicit `review` and `plan`, copy-ready prompts for all six skills, gated external actions, and this final handoff shape:

```text
Changed: files or artifacts
Verified: commands, measurements, or review evidence
Not verified: missing access or platform coverage
Your action: only steps that require the user
```

- [ ] **Step 3: Validate copy and metadata**

Run repository validation and every official `quick_validate.py` command. Search the repository for Korean characters, unfinished markers, machine-specific paths, and credential-shaped values. Run `git diff --check`.

Expected: all validators pass and all prohibited-content searches have no matches.

### Task 4: Forward test, commit, and publish

**Files:**
- Modify: any file with a real ambiguity found during forward testing; do not weaken the contract.

**Interfaces:**
- Consumes: six updated skills and the public Git remote.
- Produces: a verified public `main` whose hash matches local `HEAD`.

- [ ] **Step 1: Forward-test six representative prompts**

For each README prompt, read the selected skill as a fresh task and verify it answers: default mode, first inspection, allowed local change, gated external action, completion evidence, and handoff. Fix any ambiguity.

- [ ] **Step 2: Run the full verification suite fresh**

Run repository validation, all six official validators, Python compilation, English-only/secret/placeholder/path scans, Markdown-link validation through the repository validator, and `git diff --check`.

- [ ] **Step 3: Commit intentional files**

```bash
git add shared-references/execution-defaults.md scripts/validate_skills.py README.md \
  app-store-listing-creator seo-geo-optimizer \
  flutter-android-performance flutter-interactive-design \
  expo-android-performance expo-interactive-design
git commit -m "make skills execution-first for daily use"
```

- [ ] **Step 4: Push and prove remote state**

Push `main` to `origin`, compare `git rev-parse HEAD` with `git ls-remote origin refs/heads/main`, and confirm the worktree is clean.
