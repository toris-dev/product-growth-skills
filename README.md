# Product Growth Skills

> Open-source agent skills for app-store growth, web SEO/GEO, Flutter and Expo Android performance, Flutter Play Store delivery, and interactive 2D/3D product design.

This repository packages seven reusable agent skills for product-growth work across the web and mobile apps. They cover search visibility, app-store conversion, Android performance, Flutter Play Store release automation, and interactive Flutter and Expo design.

Each skill follows an evidence-driven workflow instead of acting as a generic checklist:

```text
inspect context → gather evidence → choose scope → create or implement → verify → report results and limits
```

## Skills

| Skill | What it does | Use it when |
|---|---|---|
| [`app-store-listing-creator`](app-store-listing-creator/) | Creates Play Store and App Store icon directions, image-generation prompts, screenshot storyboards, short and full descriptions, keyword strategy, and localization notes | Launching or relaunching an app, improving store conversion, or preparing listing assets |
| [`seo-geo-optimizer`](seo-geo-optimizer/) | Audits technical SEO, search intent, keyword maps, structured data, internal links, GEO, and `llms.txt` | Launching, migrating, or auditing a website and improving search or AI-answer discoverability |
| [`flutter-android-performance`](flutter-android-performance/) | Measures and optimizes startup, frames and jank, CPU, memory, network, assets, and app size | Investigating Flutter Android regressions or preparing a release performance review |
| [`toris-flutter-play-store-release`](toris-flutter-play-store-release/) | Inspects, configures, validates, repairs, builds, and safely operates Flutter Android delivery with Fastlane and GitHub Actions | Preparing Google Play delivery, Firebase App Distribution, Slack notifications, or Android release automation |
| [`flutter-interactive-design`](flutter-interactive-design/) | Designs responsive Flutter UI, gesture-driven 2D motion, shaders, bounded 3D, and accessible performance fallbacks | Building screens, onboarding, visualizations, games, or immersive interactions |
| [`expo-android-performance`](expo-android-performance/) | Optimizes Expo across JavaScript, UI, and native boundaries while respecting prebuild ownership | Investigating Expo Android startup, rendering, lists, memory, bundle, or package size |
| [`expo-interactive-design`](expo-interactive-design/) | Builds native Expo UI, routing and gestures, 2D canvas or motion, bounded 3D, and Android fallbacks | Designing screens, transitions, visualizations, or immersive Expo experiences |

## Installation

Every skill folder is independently invocable. Copy or symlink the repository, or only the skills you need, into the skills directory used by Codex. With the default `CODEX_HOME`, the usual location is `~/.codex/skills`.

### Link the whole collection

```bash
git clone https://github.com/toris-dev/product-growth-skills.git
mkdir -p ~/.codex/skills
for skill in app-store-listing-creator seo-geo-optimizer flutter-android-performance flutter-interactive-design expo-android-performance expo-interactive-design toris-flutter-play-store-release; do
  ln -s "$(pwd)/product-growth-skills/$skill" "$HOME/.codex/skills/$skill"
done
```

Check for existing folders or symlinks with the same names before running the commands. If you use a custom `CODEX_HOME`, replace the destination with its `skills` directory.

### Copy one skill

```bash
mkdir -p ~/.codex/skills
cp -R product-growth-skills/seo-geo-optimizer ~/.codex/skills/
cp -R product-growth-skills/shared-references ~/.codex/skills/
```

The original six skills refer to `shared-references/` through a relative path. When copying one of them, place the shared folder under the same parent directory as shown above. Cloning the repository and linking selected skill folders is the safest way to preserve this structure.

The standalone `toris-flutter-play-store-release` package carries its own execution policy and lifecycle installer. From a trusted checkout, preview and then copy its verified runtime files into the supported global skill directories:

```bash
./product-growth-skills/toris-flutter-play-store-release/install.sh --dry-run
./product-growth-skills/toris-flutter-play-store-release/install.sh
```

When migrating from the former `flutter-play-store-release` name, install the new package first and rerun its dry-run until it reports `would no change`. Then remove the verified legacy copies through their own uninstaller so both names are not discovered:

```bash
LEGACY_SKILL="$HOME/.agents/skills/flutter-play-store-release"
if [ ! -x "$LEGACY_SKILL/uninstall.sh" ]; then
  LEGACY_SKILL="$HOME/.claude/skills/flutter-play-store-release"
fi
"$LEGACY_SKILL/uninstall.sh" --dry-run
"$LEGACY_SKILL/uninstall.sh" --yes
```

Start a new Codex task and invoke a skill explicitly with `$skill-name`. Other agents may understand `SKILL.md`, but installation locations and implicit invocation behavior differ by product.

## Recommended daily workflow

The default mode is **execute**. For a request to create, improve, optimize, design, implement, or fix something in a supplied project, the selected skill should inspect the current state, make safe in-scope local changes, run relevant verification, and hand off the result.

Override the default explicitly when you want a different outcome:

| Mode | How to request it | Result |
|---|---|---|
| `execute` | "Implement this" or no mode on a create/improve/fix request | Inspect, change, verify, and hand off |
| `review` | "Review only; do not change files" | Inspect and report without local or external changes |
| `plan` | "Plan this; do not implement yet" | Inspect and produce an implementation-ready plan |

### Copy-ready personal prompts

```text
Use $app-store-listing-creator to inspect my app evidence, create the complete
Play Store and App Store package in Korean and English, verify current constraints,
and report only the upload steps I must perform.

Use $seo-geo-optimizer to inspect this live site and repository, implement the
highest-confidence SEO, GEO, keyword, structured-data, and llms.txt improvements,
verify the rendered result, and report remaining external-console actions.

Use $flutter-android-performance to reproduce this Android performance issue,
capture a profile/release baseline, implement the evidenced fix, rerun the same
scenario, and report comparable measurements.

Use $toris-flutter-play-store-release to inspect this Flutter app, configure the
smallest safe Android release path, validate it without uploading, and report
the exact Google Play, Firebase, GitHub, or Slack actions that still require me.

Use $flutter-interactive-design to inspect this app and implement a complete
vertical slice with a distinctive visual direction, purposeful 2D/3D interaction,
reduced-motion fallback, and verified frame performance.

Use $expo-android-performance to reproduce this Android performance issue,
detect Expo and native ownership, implement the fix in the durable source of truth,
and verify the same scenario in a production-like build.

Use $expo-interactive-design to inspect this app and implement a complete route
with intentional native UI, interactive 2D/3D motion, low-end and reduced-motion
fallbacks, and production-like Android verification.
```

Skill instructions are written in English, but each skill tells the agent to return deliverables in the user's language unless the target market or locale requires another language.

### Actions that still require confirmation

The skills can edit and test local project files as part of the requested outcome. They still require explicit authorization before deployment, public upload, store submission, live CMS or external-console changes, paid services, account or permission changes, destructive operations, or contacting other people.

### Expected handoff

```text
Changed: files, assets, copy, or configuration
Verified: commands, measurements, rendered evidence, or review checks
Not verified: missing access, hardware, platforms, or inconclusive evidence
Your action: only the remaining steps that require you
```

## Repository structure

```text
product-growth-skills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── scripts/validate_skills.py
├── shared-references/evidence-and-verification.md
├── app-store-listing-creator/
├── seo-geo-optimizer/
├── flutter-android-performance/
├── toris-flutter-play-store-release/
├── flutter-interactive-design/
├── expo-android-performance/
└── expo-interactive-design/
```

Each skill contains:

- `SKILL.md`: invocation conditions, workflow, mutation boundaries, and verification requirements
- `agents/openai.yaml`: display metadata and an example starter prompt
- `references/`: detailed deliverable contracts and decision guidance loaded only when needed

## Design principles and limits

- Store specifications, search-engine policies, framework APIs, and other unstable facts must be verified against current official documentation during the task.
- An audit or diagnosis request does not authorize publishing externally or changing code.
- The skills never guarantee store approval, search ranking, AI-answer citations, or performance gains.
- When image generation is available and authorized, the store skill can create visual concepts. Otherwise, it produces implementation-ready briefs and prompts.
- Performance skills do not declare success without comparable before-and-after measurements.
- Design skills treat reduced motion, assistive technologies, constrained devices, loading states, and failure states as core deliverables.
- Missing access to external services, store consoles, analytics, or physical devices is reported as an explicit verification limit.

## Validation

Validate the repository structure and metadata:

```bash
python3 scripts/validate_skills.py
bash toris-flutter-play-store-release/tests/run_tests.sh
```

If the official `skill-creator` tools are installed, validate each skill separately:

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py app-store-listing-creator
python3 /path/to/skill-creator/scripts/quick_validate.py toris-flutter-play-store-release
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution steps and quality requirements. Prefer instructions that verify changing platform facts at task time instead of hard-coding them into reusable skills.

## License

[MIT License](LICENSE)
