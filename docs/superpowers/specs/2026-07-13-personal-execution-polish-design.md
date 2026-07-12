# Personal Execution Polish — Design

## Objective

Turn the six public skills from audit-oriented reference guides into practical daily-use workflows for the repository owner. A normal invocation should inspect the local project, make safe in-scope changes, run relevant verification, and return a concise handoff without repeatedly asking for permission.

The skills remain safe for public use: external publishing, account actions, paid services, destructive changes, and material scope expansion still require explicit authorization.

## Selected approach

Use one shared execution policy plus a short domain-specific quick start and definition of done in every skill.

This keeps execution behavior consistent without copying the same policy into six files. Each skill remains independently selectable; a single-skill installation continues to include `shared-references/` as documented in the README.

Rejected alternatives:

- Duplicating the full policy in each skill would make later updates drift.
- Adding a seventh orchestration skill would weaken triggering and violate the current exactly-six-skill contract.

## Default behavior

The default mode is `execute`.

When invoked against a local project, the agent should:

1. inspect the repository, relevant files, current state, and available evidence;
2. state any important assumption and continue when it is safe;
3. implement the smallest coherent in-scope change;
4. run verification proportional to the risk;
5. iterate on failures caused by the change;
6. return the changed files, evidence, remaining limits, and any user action still required.

Do not stop for routine reversible work inside the user's stated project. Ask one focused question only when a missing decision would materially change the result or make proceeding unsafe.

## Execution modes

Every skill recognizes three modes:

- `execute` (default): inspect, change, verify, and hand off.
- `review`: inspect and report without changing project files or external systems.
- `plan`: inspect and produce an implementation-ready plan without making the implementation changes.

The user's explicit wording always overrides the default. If no mode is stated, use `execute` for a request that asks to create, improve, optimize, design, or fix something in a supplied project. Use `review` for requests explicitly framed as an audit, critique, explanation, or diagnosis only.

## Authorization boundaries

Proceed without an extra confirmation for reversible local work that is a normal part of the request, including:

- reading project files and configuration;
- editing in-scope source, content, metadata, assets, or tests;
- running existing local validation, builds, profilers, and formatters;
- creating local reports, prompts, storyboards, and generated assets requested by the user;
- making small configuration changes needed by the authorized implementation.

Explain the impact before taking a materially broader local action such as installing a dependency, changing framework architecture, regenerating native projects, or restructuring several unrelated areas. Continue only when it is clearly necessary and within the user's requested outcome; otherwise request direction.

Require explicit authorization for:

- deployment, release, store submission, CMS publishing, or public upload;
- changing live external dashboards, analytics, DNS, search consoles, or store consoles;
- paid service use or purchases;
- credentials, account, permission, billing, or legal acceptance actions;
- destructive or difficult-to-reverse operations;
- contacting people or sending external messages.

## Skill changes

Each `SKILL.md` receives:

1. a `Quick start` section directly after the introduction;
2. a link to the shared execution policy;
3. domain-specific first-pass detection and the first artifact or change to produce;
4. a concise `Definition of done` section;
5. wording that removes audit-first defaults where they conflict with `execute` mode.

Domain behavior:

- Store listing: inspect product evidence, create the full listing package, and generate requested visual concepts when a tool is available; never upload without authorization.
- SEO/GEO: inspect live/repository surfaces, implement local changes by default, and validate rendered/technical output; external consoles and production publishing stay gated.
- Flutter performance: reproduce, baseline, fix the evidenced bottleneck, and rerun the same scenario.
- Flutter design: inspect the app, choose or confirm a direction only when materially ambiguous, implement a vertical slice, and validate accessibility/performance.
- Expo performance: detect workflow/native ownership, baseline, change the durable source of truth, and validate a production-like Android path.
- Expo design: detect Expo/runtime constraints, implement a vertical slice with fallbacks, and validate Android plus targeted platforms.

## Default prompts

Update every `agents/openai.yaml` default prompt to request an inspect–implement–verify outcome. Prompts remain one sentence and explicitly contain `$skill-name`.

Examples of the intended shape:

```text
Use $flutter-android-performance to inspect this project, fix the evidenced Android bottleneck, and verify the result with comparable measurements.
```

## README changes

Add a `Recommended daily workflow` section that explains:

- the default `execute` behavior;
- how to request `review` or `plan` explicitly;
- six copy-ready personal prompts;
- which external actions still require confirmation;
- the expected final handoff.

Keep the repository documentation in English.

## Validator changes

The repository validator must require:

- a `## Quick start` heading in every `SKILL.md`;
- a `## Definition of done` heading in every `SKILL.md`;
- a link to `../shared-references/execution-defaults.md` in every skill;
- the literal skill name in each default prompt, as it already does;
- exactly six skill directories, as it already does.

Use a temporary fixture or pre-change run to prove the new checks fail before the skill files are updated, then rerun after implementation to prove they pass.

## Forward tests

Evaluate one representative prompt per skill. For each, verify that a fresh agent can determine:

- the default mode;
- what to inspect first;
- what it may change without another question;
- which action remains gated;
- the concrete completion evidence and handoff.

No live production system, store console, or external dashboard is used during forward testing.

## Completion criteria

The work is complete when:

- all six skills implement the shared execution default and domain quick start;
- all six UI prompts request inspect–implement–verify behavior;
- README documents personal daily use and mode overrides;
- repository validation fails on the old structure and passes on the new structure;
- all six official skill validators pass;
- English-only, link, placeholder, secret, and whitespace scans pass;
- the local `main` commit is pushed to the public GitHub repository and matches `origin/main`.
