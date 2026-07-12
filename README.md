# Product Growth Skills

> Open-source agent skills for app-store growth, web SEO/GEO, Flutter and Expo Android performance, and interactive 2D/3D product design.

This repository packages six reusable agent skills for product-growth work across the web and mobile apps. They cover search visibility, app-store conversion, Android performance, and interactive Flutter and Expo design.

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
| [`flutter-interactive-design`](flutter-interactive-design/) | Designs responsive Flutter UI, gesture-driven 2D motion, shaders, bounded 3D, and accessible performance fallbacks | Building screens, onboarding, visualizations, games, or immersive interactions |
| [`expo-android-performance`](expo-android-performance/) | Optimizes Expo across JavaScript, UI, and native boundaries while respecting prebuild ownership | Investigating Expo Android startup, rendering, lists, memory, bundle, or package size |
| [`expo-interactive-design`](expo-interactive-design/) | Builds native Expo UI, routing and gestures, 2D canvas or motion, bounded 3D, and Android fallbacks | Designing screens, transitions, visualizations, or immersive Expo experiences |

## Installation

Every skill folder is independently invocable. Copy or symlink the repository, or only the skills you need, into the skills directory used by Codex. With the default `CODEX_HOME`, the usual location is `~/.codex/skills`.

### Link the whole collection

```bash
git clone https://github.com/toris-dev/product-growth-skills.git
mkdir -p ~/.codex/skills
for skill in app-store-listing-creator seo-geo-optimizer flutter-android-performance flutter-interactive-design expo-android-performance expo-interactive-design; do
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

The skills refer to `shared-references/` through a relative path. When copying a single skill, place the shared folder under the same parent directory as shown above. Cloning the repository and linking selected skill folders is the safest way to preserve this structure.

Start a new Codex task and invoke a skill explicitly with `$skill-name`. Other agents may understand `SKILL.md`, but installation locations and implicit invocation behavior differ by product.

## Usage examples

```text
Use $app-store-listing-creator to inspect my app and create Korean and English
Play Store/App Store icon directions, screenshot storyboards, and final copy.

Use $seo-geo-optimizer to audit this website, map search intent and keywords,
improve GEO-ready content, and create an evidence-based llms.txt if appropriate.

Use $flutter-android-performance to reproduce this Android scroll jank,
measure a profile/release baseline, implement the proven fix, and compare results.

Use $flutter-interactive-design to redesign this Flutter onboarding with a
distinct visual direction, gesture-driven 2D motion, and an accessible 3D moment.

Use $expo-android-performance to diagnose slow Android startup in this Expo app
without editing native files that prebuild owns, then verify a production build.

Use $expo-interactive-design to create an Expo product viewer with intentional
native UI, interactive motion, a bounded 3D scene, and low-end/reduced-motion fallbacks.
```

Skill instructions are written in English, but each skill tells the agent to return deliverables in the user's language unless the target market or locale requires another language.

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
```

If the official `skill-creator` tools are installed, validate each skill separately:

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py app-store-listing-creator
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution steps and quality requirements. Prefer instructions that verify changing platform facts at task time instead of hard-coding them into reusable skills.

## License

[MIT License](LICENSE)
