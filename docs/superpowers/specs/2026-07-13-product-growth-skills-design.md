# Product Growth Skills — Design

## Objective

Create an MIT-licensed public repository named `product-growth-skills` containing six independently installable Codex-compatible skills for app-store assets, web search visibility, Flutter and Expo Android performance, and interactive 2D/3D design.

The collection intentionally spans two product surfaces: web growth through SEO/GEO and mobile product growth through store conversion, performance, and experience design. Neither surface is treated as a subset of the other.

The repository is documentation-first: each skill teaches an agent how to inspect a real project, choose an appropriate workflow, make scoped changes when authorized, and verify the result. It does not bundle a runtime application or require a shared package manager.

## Audience and language

- Primary audience: web and mobile developers, designers, product marketers, and growth teams using Codex or another agent that understands `SKILL.md`.
- Repository documentation: Korean first, with concise English summaries so the project remains approachable internationally.
- Skill instructions: English, because tool and framework terminology is most stable in English. Output language follows the user's language.

## Repository architecture

```text
product-growth-skills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── app-store-listing-creator/
├── seo-geo-optimizer/
├── flutter-android-performance/
├── flutter-interactive-design/
├── expo-android-performance/
├── expo-interactive-design/
└── shared-references/
```

Each skill folder contains:

- `SKILL.md`: trigger metadata, workflow, safety boundaries, outputs, and verification.
- `agents/openai.yaml`: human-facing display name, short description, and starter prompt.
- `references/`: only domain material that would make `SKILL.md` too large or applies conditionally.
- `assets/`: reusable output templates only when a skill needs them.

`shared-references/` contains repository-level source material reused by multiple skills. Each relevant `SKILL.md` links to the exact shared file to load; references are never implicitly required.

## Skills

### 1. `app-store-listing-creator`

Creates or improves Google Play and Apple App Store listing packages:

- app icon creative direction and generation-ready prompts;
- screenshot narrative, per-frame copy, layouts, and generation-ready prompts;
- short description/subtitle, promotional text, full description, and keyword field where supported;
- localization-ready copy tables and an asset manifest;
- preflight checks for current platform constraints.

The workflow starts with product evidence: target audience, core jobs, differentiators, brand assets, supported locales, and screenshots or builds. It must not invent awards, rankings, testimonials, privacy claims, or unsupported capabilities. If image-generation tools are available and the user requests image production, the skill generates assets; otherwise it produces precise creative briefs and prompts.

Platform dimensions, character limits, and policies change. The skill must verify current official Apple and Google documentation before presenting exact submission constraints.

### 2. `seo-geo-optimizer`

Audits and improves conventional SEO, generative-engine optimization (GEO), `llms.txt`, and keyword targeting:

- technical crawlability, metadata, canonicals, structured data, internal links, and indexation signals;
- search intent and keyword clustering mapped to existing or proposed pages;
- entity clarity, answer-first content, citations, provenance, and extractable passages for AI search systems;
- standards-aware `llms.txt` generation without claiming it controls model training or guarantees inclusion;
- before/after validation and a prioritized backlog.

The skill separates facts from recommendations, preserves user-authored claims, and avoids keyword stuffing, doorway pages, cloaking, fabricated expertise, and mass-generated low-value content. It checks current search-engine guidance when policy or syntax is material.

### 3. `flutter-android-performance`

Diagnoses and improves Android performance in Flutter projects. The workflow is measurement-led:

1. establish device, build mode, Flutter version, and reproducible scenario;
2. capture baseline startup, frame timing/jank, CPU, memory, network, package size, and energy signals relevant to the issue;
3. inspect Dart/UI, assets, platform channels, Gradle/R8, rendering, and lifecycle behavior;
4. apply the smallest high-confidence changes authorized by the user;
5. rerun the same scenario and report comparable measurements.

It distinguishes debug/profile/release behavior, protects correctness, and never reports an optimization without before/after evidence. It covers low-end Android devices and current rendering architecture without hard-coding unstable version-specific advice.

### 4. `flutter-interactive-design`

Designs and implements polished Flutter UI with interactive 2D and 3D motion. It covers:

- visual direction, hierarchy, responsive composition, and reusable tokens/components;
- implicit and explicit animation, gesture-driven transitions, physics, custom painting, shaders, and suitable 2D runtimes;
- bounded 3D experiences using the most appropriate maintained library or native/WebView integration after checking project constraints;
- loading, error, empty, reduced-motion, keyboard, screen-reader, and low-performance fallbacks;
- profiling for frame pacing, rebuild scope, shader compilation, asset weight, and thermal impact.

Motion must communicate hierarchy, causality, progress, or delight; it is not added decoratively by default. The skill asks for visual approval before committing to a strong art direction when requirements are ambiguous.

### 5. `expo-android-performance`

Diagnoses and improves Android performance in Expo and React Native projects, including managed and prebuild/native workflows. It measures startup, JavaScript and UI thread responsiveness, rendering, memory, network, image/font cost, bundle size, and package size as applicable.

The skill detects Expo SDK, React Native architecture, router/navigation setup, JavaScript engine, build profile, and whether native directories are generated or user-owned before editing. It preserves Expo config-plugin and prebuild conventions, avoids manual native edits that will be overwritten, and validates changes in a production-like Android build.

### 6. `expo-interactive-design`

Designs and implements distinctive Expo interfaces with interactive 2D and 3D motion. It selects among core React Native animation APIs, Reanimated/Gesture Handler, SVG/Canvas/Skia-style rendering, Lottie/Rive-style assets, and GL/Three-style 3D only after checking installed dependencies and platform support.

The workflow includes design intent, interaction states, gesture arbitration, navigation transitions, accessibility, reduced motion, low-end fallbacks, asset strategy, and Android performance verification. Web and iOS behavior are considered when the project targets them, but Android remains a required validation target.

## Shared behavior

All six skills follow these rules:

1. Inspect before proposing or editing.
2. Clarify only decisions that materially change the outcome; otherwise state a reasonable assumption and proceed.
3. Prefer official, current platform documentation for unstable constraints.
4. Separate diagnosis/recommendation from implementation authorization.
5. Preserve unrelated user changes and existing project conventions.
6. Provide concrete deliverables, not generic advice.
7. Validate in proportion to risk and disclose what could not be verified.
8. Never promise rankings, store approval, performance gains, or AI-search inclusion.

## Data and control flow

Each skill uses the same high-level sequence:

```text
request → detect context → gather evidence → choose workflow
        → produce or implement → validate → hand off artifacts and caveats
```

Skills may invoke other installed capabilities when available (image generation, browser inspection, framework documentation), but remain useful without them by producing briefs, commands, checklists, or implementation guidance.

## Error handling and safety

- Missing project or product evidence: identify the minimum missing input and continue with labeled assumptions when safe.
- Missing tools or dependencies: do not install or mutate outside the user's scope; offer or request the required action.
- Unstable specifications: verify against official documentation and cite the source in the result.
- Conflicting measurements: rerun the controlled scenario and report variance instead of selecting the favorable result.
- Destructive or broad changes: stop and request explicit approval.
- Generated marketing claims: require evidence or rewrite them as neutral, verifiable language.

## Validation strategy

Repository validation must prove:

- exactly six skill directories exist with valid YAML frontmatter;
- names use lowercase hyphen-case and match their folder names;
- descriptions clearly state both capability and trigger conditions;
- every skill has `agents/openai.yaml` consistent with its `SKILL.md`;
- all linked local references exist;
- no unfinished placeholder markers remain;
- the root README documents installation, invocation examples, directory layout, scope, limitations, and contribution steps;
- the license is MIT;
- the repository has no secrets, generated caches, or machine-specific paths.

Use the official `skill-creator` validation script when available, plus repository-specific structural checks. Read each skill once as a forward test against a representative prompt and revise unclear instructions before publishing.

## Publishing

Initialize the current empty Git repository on `main`, commit the approved design separately, then commit the implementation. Create a public GitHub repository named `product-growth-skills`, add it as `origin`, and push `main`. Because this is a new standalone repository rather than a contribution to an existing project, no pull request is required unless GitHub policy forces an alternate branch flow.

Publishing is complete only when the remote is public and the pushed commit matches the verified local `HEAD`.
