# Product Growth Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, validate, document, and publicly publish six independently installable product-growth skills covering web SEO/GEO and mobile store, performance, and interactive-design workflows.

**Architecture:** The repository contains six self-contained skill directories with focused `SKILL.md` workflows and UI metadata. Conditional domain detail lives one level below each skill in `references/`; only genuinely cross-skill guidance lives in `shared-references/`. A repository validator checks structure and delegates content validation to the official `skill-creator` validator.

**Tech Stack:** Markdown, YAML, Python 3 standard library, Git, GitHub CLI, Codex skill conventions

## Global Constraints

- Repository name is exactly `product-growth-skills` and the GitHub repository is public.
- The license is MIT.
- Exactly six top-level skill directories are shipped.
- Root documentation is Korean-first with concise English summaries; skill instructions are English and direct output in the user's language.
- Platform dimensions, policies, framework APIs, and performance guidance that may change must be checked against current official sources at task time.
- Skills must distinguish read-only review from authorized implementation and preserve unrelated changes.
- Skills must never promise rankings, store approval, performance gains, or AI-search inclusion.
- Every skill contains valid `SKILL.md` frontmatter and matching `agents/openai.yaml`.
- No machine-specific absolute path, secret, cache, or unfinished placeholder marker may ship.

---

## File map

- `README.md`: Korean-first overview, skill catalog, installation, examples, limitations, contribution link.
- `LICENSE`: MIT license text.
- `CONTRIBUTING.md`: contribution and validation workflow.
- `.gitignore`: local/editor/cache exclusions.
- `scripts/validate_skills.py`: repository structure, link, placeholder, and metadata checks.
- `shared-references/evidence-and-verification.md`: shared evidence, claim, official-source, and validation rules.
- `app-store-listing-creator/`: store listing asset and copy workflow.
- `seo-geo-optimizer/`: web SEO/GEO, keyword, and `llms.txt` workflow.
- `flutter-android-performance/`: Flutter Android measurement and optimization workflow.
- `flutter-interactive-design/`: Flutter visual design and interactive 2D/3D motion workflow.
- `expo-android-performance/`: Expo Android measurement and optimization workflow.
- `expo-interactive-design/`: Expo visual design and interactive 2D/3D motion workflow.

### Task 1: Repository foundation and deterministic validator

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `shared-references/evidence-and-verification.md`
- Create: `scripts/validate_skills.py`

**Interfaces:**
- Consumes: six expected folder names from the approved design.
- Produces: `python3 scripts/validate_skills.py` with exit code `0` on a complete valid repository and nonzero with readable errors otherwise.

- [ ] **Step 1: Write the validator before the skills exist**

Implement these exact checks in `scripts/validate_skills.py` using only the Python standard library:

```python
EXPECTED = {
    "app-store-listing-creator",
    "seo-geo-optimizer",
    "flutter-android-performance",
    "flutter-interactive-design",
    "expo-android-performance",
    "expo-interactive-design",
}
```

Check that each expected directory has `SKILL.md` and `agents/openai.yaml`; parse the simple frontmatter to confirm `name` equals its directory; require `description`; require quoted `display_name`, `short_description`, and `default_prompt`; confirm the default prompt contains `$<skill-name>`; scan Markdown links to local relative paths; and reject unfinished markers and machine-specific user-home paths. Ignore `.git` and the design/plan documents when scanning unfinished-marker language because those documents describe the validation rule itself.

- [ ] **Step 2: Run the validator and verify the expected failure**

Run: `python3 scripts/validate_skills.py`

Expected: nonzero exit and six missing-skill errors.

- [ ] **Step 3: Add repository policy files and shared evidence guidance**

Write the standard MIT text with copyright year `2026` and holder `Product Growth Skills contributors`. Document contribution steps as: keep one responsibility per skill, use official sources for unstable facts, run both repository and official validators, and avoid secrets/generated output. The shared evidence reference must define evidence tiers, prohibited unsupported claims, before/after comparison rules, and how to label unverified assumptions.

- [ ] **Step 4: Verify foundation files**

Run: `git diff --check && python3 -m py_compile scripts/validate_skills.py`

Expected: both commands exit `0`.

- [ ] **Step 5: Commit the foundation**

```bash
git add .gitignore LICENSE CONTRIBUTING.md shared-references scripts/validate_skills.py
git commit -m "build repository validation foundation"
```

### Task 2: App store listing creator skill

**Files:**
- Create: `app-store-listing-creator/SKILL.md`
- Create: `app-store-listing-creator/agents/openai.yaml`
- Create: `app-store-listing-creator/references/deliverables.md`

**Interfaces:**
- Consumes: product evidence, existing store listing/assets, target stores/locales, and `../shared-references/evidence-and-verification.md`.
- Produces: evidence inventory, positioning, icon brief/prompts, screenshot storyboard/prompts, store copy matrix, localization notes, and submission preflight.

- [ ] **Step 1: Initialize the skill with deterministic metadata**

Run `init_skill.py` with name `app-store-listing-creator`, resources `references`, display name `App Store Listing Creator`, short description `Create store icons, screenshots, and conversion copy`, and default prompt `Use $app-store-listing-creator to create a complete Play Store and App Store listing package for my app.`

Expected: skill directory, `SKILL.md`, `agents/openai.yaml`, and `references/` exist.

- [ ] **Step 2: Replace the template with the complete workflow**

`SKILL.md` must include: trigger conditions; evidence intake; current official constraint verification; platform and locale matrix; positioning; icon direction; screenshot narrative; short/full copy; optional image generation with a prompt-only fallback; claim safety; deliverable assembly; and final checks. Exact volatile sizes and character limits belong in the task output after official verification, not hard-coded in the skill.

- [ ] **Step 3: Add the deliverable contract**

`references/deliverables.md` must specify tables for asset manifest, screenshot frames, copy fields, keyword rationale, localization notes, experiment hypotheses, and a preflight checklist. It must say that generated assets never imply store acceptance.

- [ ] **Step 4: Validate the skill**

Run: `python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" app-store-listing-creator`

Expected: `Skill is valid!`

- [ ] **Step 5: Commit**

```bash
git add app-store-listing-creator
git commit -m "add app store listing creator skill"
```

### Task 3: SEO and GEO optimizer skill

**Files:**
- Create: `seo-geo-optimizer/SKILL.md`
- Create: `seo-geo-optimizer/agents/openai.yaml`
- Create: `seo-geo-optimizer/references/audit-and-deliverables.md`
- Create: `seo-geo-optimizer/references/llms-txt.md`

**Interfaces:**
- Consumes: site/repository access, business goals, audience, markets, analytics/search data when available, and shared evidence rules.
- Produces: prioritized audit, intent/keyword map, implemented or proposed changes, GEO content guidance, standards-aware `llms.txt`, and validation report.

- [ ] **Step 1: Initialize deterministic metadata**

Use display name `SEO & GEO Optimizer`, short description `Optimize SEO, GEO, llms.txt, and keyword strategy`, and a default prompt that explicitly invokes `$seo-geo-optimizer` to audit and improve a website.

- [ ] **Step 2: Implement the inspect-to-verify workflow**

Cover technical discovery, indexability, canonical/metadata/structured data, internal links, performance signals, search intent clustering, page mapping, entity clarity, answer-first passages, citation/provenance, `llms.txt`, scoped implementation, and before/after checks. Explicitly prohibit keyword stuffing, doorway pages, cloaking, fabricated authority, and guaranteed rankings or AI citations.

- [ ] **Step 3: Add conditional references**

The audit reference defines severity/evidence/effort tables and exact deliverables. The `llms.txt` reference defines a conservative file structure, distinguishes it from `robots.txt`, states that adoption and behavior vary, and requires current primary-source verification before claiming support.

- [ ] **Step 4: Validate and commit**

Run the official validator, then stage the skill and commit with `add SEO and GEO optimizer skill`.

### Task 4: Flutter Android performance skill

**Files:**
- Create: `flutter-android-performance/SKILL.md`
- Create: `flutter-android-performance/agents/openai.yaml`
- Create: `flutter-android-performance/references/measurement-playbook.md`

**Interfaces:**
- Consumes: Flutter project, reproducible Android scenario, device/build metadata, and authorization scope.
- Produces: baseline, bottleneck evidence, scoped changes or recommendations, comparable rerun, and regression notes.

- [ ] **Step 1: Initialize deterministic metadata**

Use display name `Flutter Android Performance`, short description `Measure and optimize Flutter performance on Android`, and a default prompt invoking `$flutter-android-performance`.

- [ ] **Step 2: Implement measurement-led diagnosis**

Require build-mode/device/version capture; relevant startup, frame, CPU, memory, network, package-size, and energy signals; Dart/widget/rendering/assets/platform-channel/Gradle inspection; hypothesis ranking; minimal authorized edits; identical-scenario rerun; and variance disclosure. Explain that debug results cannot prove release performance.

- [ ] **Step 3: Add measurement reference**

Define a reproducibility sheet, metric table with units, warm/cold run separation, representative low-end Android coverage, median plus range reporting, and correctness/regression gates. Commands must be selected from the detected project and current official Flutter/Android tooling rather than assumed.

- [ ] **Step 4: Validate and commit**

Run the official validator, then commit the skill with `add Flutter Android performance skill`.

### Task 5: Flutter interactive design skill

**Files:**
- Create: `flutter-interactive-design/SKILL.md`
- Create: `flutter-interactive-design/agents/openai.yaml`
- Create: `flutter-interactive-design/references/motion-and-3d.md`

**Interfaces:**
- Consumes: Flutter project or product brief, brand/product context, target devices, desired interaction, and available assets.
- Produces: art direction, component/state plan, implemented UI when authorized, 2D/3D motion, accessible fallback, and profiling evidence.

- [ ] **Step 1: Initialize deterministic metadata**

Use display name `Flutter Interactive Design`, short description `Build polished Flutter UI with interactive 2D and 3D`, and a default prompt invoking `$flutter-interactive-design`.

- [ ] **Step 2: Implement design-to-validation workflow**

Require context inspection, intentional art direction, responsive hierarchy, state matrix, interaction/motion purpose, technology selection after dependency checks, incremental implementation, reduced-motion and assistive-technology behavior, low-end fallback, and frame/rebuild/shader/asset profiling. Avoid generic gradients, excessive cards, decorative motion, or an unbounded 3D scene by default.

- [ ] **Step 3: Add motion and 3D decision reference**

Map interaction needs to Flutter primitives, custom paint/shader, maintained 2D runtimes, and bounded 3D/native/WebView choices. Include gesture ownership, interruption, lifecycle, loading, asset budgets, graceful degradation, and test scenarios without prescribing an unverified package.

- [ ] **Step 4: Validate and commit**

Run the official validator, then commit the skill with `add Flutter interactive design skill`.

### Task 6: Expo Android performance skill

**Files:**
- Create: `expo-android-performance/SKILL.md`
- Create: `expo-android-performance/agents/openai.yaml`
- Create: `expo-android-performance/references/measurement-playbook.md`

**Interfaces:**
- Consumes: Expo project, reproducible Android scenario, detected workflow/architecture/engine/build profile, and authorization scope.
- Produces: baseline, bottleneck evidence across JS/UI/native boundaries, safe Expo-aware changes or recommendations, comparable rerun, and regression notes.

- [ ] **Step 1: Initialize deterministic metadata**

Use display name `Expo Android Performance`, short description `Measure and optimize Expo Android performance`, and a default prompt invoking `$expo-android-performance`.

- [ ] **Step 2: Implement Expo-aware diagnosis**

Detect Expo SDK, React Native version/architecture, JS engine, router/navigation, managed/prebuild/bare workflow, ownership of native directories, and production-like build profile. Measure relevant startup, JS/UI responsiveness, rendering, memory, network, image/font, bundle, and package signals. Preserve config-plugin/prebuild conventions and prohibit edits that will be overwritten.

- [ ] **Step 3: Add measurement reference**

Define controlled runs, JS/UI/native attribution, list and image cases, navigation/startup scenarios, low-end Android coverage, median plus range, build artifact checks, and correctness gates. Require current Expo/React Native/Android official guidance for version-dependent commands.

- [ ] **Step 4: Validate and commit**

Run the official validator, then commit the skill with `add Expo Android performance skill`.

### Task 7: Expo interactive design skill

**Files:**
- Create: `expo-interactive-design/SKILL.md`
- Create: `expo-interactive-design/agents/openai.yaml`
- Create: `expo-interactive-design/references/motion-and-3d.md`

**Interfaces:**
- Consumes: Expo project or product brief, brand/product context, target platforms/devices, interaction goal, and installed dependencies.
- Produces: art direction, component/state plan, implemented UI when authorized, interactive 2D/3D motion, accessible fallback, and Android profiling evidence.

- [ ] **Step 1: Initialize deterministic metadata**

Use display name `Expo Interactive Design`, short description `Build polished Expo UI with interactive 2D and 3D`, and a default prompt invoking `$expo-interactive-design`.

- [ ] **Step 2: Implement design-to-validation workflow**

Require project/route/dependency inspection, intentional visual direction, state and gesture plan, selection among core animation, Reanimated/Gesture Handler, SVG/Canvas/Skia-style rendering, authored animation assets, and GL/Three-style 3D based on actual support. Cover reduced motion, screen readers, input methods, low-end fallback, JS/UI thread behavior, navigation lifecycle, Android validation, and web/iOS checks when targeted.

- [ ] **Step 3: Add motion and 3D decision reference**

Define selection criteria, gesture arbitration, worklet/thread boundaries, cleanup, navigation focus, asset loading, bounded scene budgets, graceful degradation, and profiling/test cases. Do not hard-code a dependency version or assume a package is installed.

- [ ] **Step 4: Validate and commit**

Run the official validator, then commit the skill with `add Expo interactive design skill`.

### Task 8: Root README, full validation, and public GitHub publication

**Files:**
- Create: `README.md`
- Modify: any skill file identified by full validation.
- Modify: `scripts/validate_skills.py` only if a real repository rule is uncovered; do not weaken checks to accept invalid content.

**Interfaces:**
- Consumes: all six validated skills and repository policy files.
- Produces: installable public repository URL whose remote `main` commit matches local `HEAD`.

- [ ] **Step 1: Write the Korean-first README**

Include: one-sentence English summary; problem and scope; six-row skill catalog; prerequisites; whole-repository and single-skill installation examples for Codex; explicit `$skill-name` invocation examples; directory tree; behavior and safety limitations; validation commands; contribution link; and MIT license statement. Do not claim compatibility with an agent unless the documented installation model is accurate.

- [ ] **Step 2: Run structural and official validation**

Run:

```bash
python3 scripts/validate_skills.py
for skill in app-store-listing-creator seo-geo-optimizer flutter-android-performance flutter-interactive-design expo-android-performance expo-interactive-design; do
  python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py" "$skill"
done
git diff --check
```

Expected: repository validator reports six valid skills, every official validator prints `Skill is valid!`, and Git whitespace check exits `0`.

- [ ] **Step 3: Forward-test representative prompts**

Read each `SKILL.md` against one matching prompt and confirm that an agent can identify inputs, workflow, deliverables, mutation boundary, and verification without guessing. Record the six prompts in the README invocation examples; fix any ambiguity found.

- [ ] **Step 4: Audit secrets and machine-specific content**

Run searches for credential-shaped terms, machine-specific user-home paths, cache files, and unfinished markers. No secret value or personal absolute path may appear anywhere.

- [ ] **Step 5: Commit implementation documentation**

```bash
git add README.md app-store-listing-creator seo-geo-optimizer flutter-android-performance flutter-interactive-design expo-android-performance expo-interactive-design scripts
git commit -m "document product growth skills collection"
```

- [ ] **Step 6: Verify GitHub prerequisites and create the public repository**

Run `gh --version` and `gh auth status`. Then create `product-growth-skills` as a public source repository from the current directory, adding `origin` and pushing `main`. Do not initialize a remote README or license because local history is authoritative.

Expected: GitHub reports a public repository and `origin/main` exists.

- [ ] **Step 7: Prove remote completion**

Compare local `git rev-parse HEAD` with `git ls-remote origin refs/heads/main`, and query GitHub repository visibility. Both commit hashes must match and visibility must be `PUBLIC` before reporting completion.
