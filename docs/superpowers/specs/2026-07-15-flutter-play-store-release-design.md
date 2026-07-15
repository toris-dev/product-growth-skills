# Flutter Play Store Release Skill — Design

## Objective

Add `flutter-play-store-release` as the seventh skill in `product-growth-skills`, use that repository folder as the canonical source, and install verified copies into both global skill locations:

```text
~/.claude/skills/flutter-play-store-release/
~/.agents/skills/flutter-play-store-release/
```

The skill configures and validates reusable Flutter Android delivery through Fastlane and GitHub Actions. It covers Google Play, optional Firebase App Distribution, and optional Slack notifications. It excludes every iOS/App Store workflow.

The current repository is not a Flutter application. Implementation therefore builds and tests the skill package itself, installs it globally, and does not modify or upload an app.

## Audience and compatibility

- Claude Code and Codex agents reading a generic `SKILL.md` workflow.
- Developers using the bundled shell scripts directly in a local terminal.
- GitHub Actions and other CI environments using the generated files.
- macOS and Linux for the automation scripts; Windows users receive PowerShell secret-encoding instructions.

Repository and skill documentation remain English. Agents return task results in the user's language.

## Canonical package

```text
flutter-play-store-release/
├── .skill-package-id
├── SKILL.md
├── README.md
├── install-manifest.txt
├── agents/
│   └── openai.yaml
├── install.sh
├── update.sh
├── uninstall.sh
├── scripts/
│   ├── inspect_flutter_project.sh
│   ├── bootstrap_android_fastlane.sh
│   ├── validate_release_setup.sh
│   ├── encode_secret.sh
│   └── decode_secret.sh
├── templates/
│   ├── Gemfile
│   ├── Gemfile.lock
│   ├── Appfile
│   ├── Fastfile
│   ├── Pluginfile
│   ├── env.example
│   ├── key.properties.example
│   ├── release-android.yml
│   └── PLAY_STORE_RELEASE.md
├── references/
│   ├── environment-variables.md
│   ├── execution-defaults.md
│   ├── troubleshooting.md
│   └── first-release-checklist.md
└── tests/
    ├── run_tests.sh
    └── fixtures/ generated at test runtime
```

The internal README is included because the user explicitly requires a standalone package usable outside an agent runtime. `SKILL.md` remains concise and routes detailed guidance to references and templates. Its YAML frontmatter must contain `name: flutter-play-store-release` and an English description equivalent to the deployment-focused description in the request. It includes English equivalents of the supplied natural-language use cases, all eight modes, and both Claude Code and Codex invocation forms.

The scripts target macOS and Linux, remain compatible with the system Bash available on supported macOS versions, and do not assume GNU-only flags. Optional helpers such as Ruby, Python, `jq`, or a YAML parser improve validation but are never silently treated as mandatory unless the generated project workflow itself requires them.

## Installation model

Use copies rather than symlinks for maximum compatibility. `.skill-package-id` contains the fixed package ID and schema version. `install-manifest.txt` lists every runtime file that must be copied; canonical-only fixture tests and generated artifacts are outside that manifest. Both installed destinations must be byte-for-byte identical, and every installed manifest entry must match its canonical source.

- `install.sh` uses its own containing directory as the canonical source, copies the manifest into both global destinations, and refuses unsafe source/destination relationships or invalid required files.
- `update.sh` requires an explicit canonical source or a non-installed script location, performs the same validated synchronization, and refuses to treat either global destination as canonical.
- `uninstall.sh` removes only destinations that identify themselves as this package; support `--dry-run` and require an explicit confirmation flag for non-interactive removal.
- Exclude canonical-only tests, test artifacts, VCS metadata, caches, and local secrets from the install manifest.
- Resolve and validate paths; mutate only the two exact global destinations; refuse destination symlinks, source/destination overlap, and unrelated existing directories.
- Stage and validate both copies before replacing either. Retain rollback copies until both atomic swaps succeed; if either swap fails, restore both previous installations.
- Never uninstall the canonical source. Tests inject a failure during the second swap and prove both prior copies remain unchanged.

## Agent workflow and modes

Recognize these modes:

1. `setup`
2. `doctor`
3. `build`
4. `deploy`
5. `ci`
6. `firebase-distribution`
7. `slack`
8. `repair`

Inspect before selecting a mode when the user does not name one. Read the repository-wide [execution defaults](../../../shared-references/execution-defaults.md) in the canonical checkout. Include a self-contained copy at `references/execution-defaults.md` so installed copies preserve the same authorization boundaries without depending on the repository layout.

External safety rules override convenience:

- An explicit deploy request may upload only to the named track after all preflight checks pass.
- Production promotion, rollout changes, GitHub secret mutation, key replacement/deletion, first-release console setup, and any unrequested external change require explicit authorization.
- A setup, doctor, build, CI, Slack, or Firebase configuration request never implies a Play upload.
- Never create a populated `.env`, `key.properties`, keystore, or service-account JSON without the user's explicit request. Never generate a new upload key merely because one is absent, and never generate or replace one when an existing key is detected.
- Never enable `set -x` in code that could handle credentials, and redact secret-bearing command arguments and errors.

## Project inspection

`inspect_flutter_project.sh` must fail clearly unless the selected root contains:

```text
pubspec.yaml
android/
android/app/
```

Support `--project`, human-readable output, and machine-readable JSON. Detect without printing secret values:

- Flutter and Dart constraints;
- Flutter version when the command is available;
- Android Gradle Plugin, Gradle wrapper, and Java compatibility;
- Groovy versus Kotlin DSL;
- release variant `applicationId` and `namespace` separately;
- current Gradle `versionName` and `versionCode`, the `pubspec.yaml` version name/build number, and relevant Gradle overrides;
- build_runner presence;
- Fastlane, GitHub Actions, release signing, Firebase, Firebase App Distribution, flavors, entrypoints, and monorepo indicators;
- dirty Git state and files that the bootstrap may change.

Do not select a flavor silently. Rank a suggested default only when evidence such as an existing release flavor, entrypoint, CI workflow, or documented convention supports it, and label that suggestion as unconfirmed. When the release application ID cannot be resolved statically, return candidates, place `CHANGE_ME_APPLICATION_ID` only in example configuration, block active build/deploy configuration from using it, and request only the missing flavor/package selection. Always compare `APP_PACKAGE_NAME` with the resolved release `applicationId` before upload.

## Idempotent bootstrap

`bootstrap_android_fastlane.sh` supports `--project`, `--dry-run`, optional `--flavor`, and explicit conflict behavior.

It may create or update:

```text
android/Gemfile
android/Gemfile.lock
android/fastlane/Appfile
android/fastlane/Fastfile
android/fastlane/Pluginfile
android/fastlane/.env.example
android/key.properties.example
.github/workflows/release-android.yml
docs/PLAY_STORE_RELEASE.md
.gitignore
android/app/build.gradle or android/app/build.gradle.kts
```

Safety requirements:

- Read existing files before changing them.
- Never replace a customized Fastfile, workflow, or Gradle file wholesale.
- Create new files from templates only when absent.
- Merge missing `.gitignore` lines without duplicates.
- Use deterministic begin/end markers for generated Gradle and Fastlane blocks.
- Refuse ambiguous or malformed existing marker regions.
- Preserve existing lanes and plugins, or stop with a conflict report when safe merging is not possible. Append a marked platform block only when required lane names do not already exist.
- Treat an absent file, a recognized package-owned file, a safely mergeable file, and an unowned non-mergeable file as four distinct cases. Update package-owned content, merge only supported structures, and stop before overwriting unowned workflows or customized configuration.
- Show a diff or dry-run summary before broad changes.
- Compute and stage every proposed edit before touching the project, validate staged output, then apply as one transaction. Preserve byte-for-byte recovery copies, permissions, and line endings until post-write validation succeeds; restore every changed, removed, dirty, or untracked file if any write fails. A conflict exits nonzero with zero project changes.
- `--dry-run` performs zero writes and prints a deterministic plan. Whole generated files carry package identity, schema version, and generated-content hash; user-edited package-owned content causes a conflict instead of being overwritten.
- Running bootstrap twice must produce no second-run diff.

## Android signing

Support Groovy and Kotlin DSL with a generated, marked signing block that reads `android/key.properties` and connects `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` to the release build.

- Detect every release-to-debug signing assignment. Safely replace recognized stock Flutter patterns; fail setup and validation with a precise conflict for custom or ambiguous patterns until repaired. A release build must never retain both debug and release signing assignments.
- Never silently fall back to the debug key.
- Fail only release-signing tasks with an actionable message when required signing data is missing; inspection, debug builds, and unrelated Gradle configuration remain usable.
- Preserve user-owned signing code and report conflicts rather than attempting a risky rewrite.
- Generate placeholders only in `android/key.properties.example`.
- Add real key properties, keystores, and service-account files to `.gitignore` without ignoring examples.

## Fastlane implementation

Use Bundler-pinned dependencies and current supported Fastlane APIs verified from official documentation during implementation.

Provide lanes:

- `doctor`: report `PASS`, `WARN`, and `FAIL` for toolchain, files, package name, credentials by presence only, signing inputs, track, build_runner, and plugins. Missing deploy credentials are warnings in setup/build context and failures in deploy context; warnings alone exit zero, while any failure exits nonzero.
- `prepare`: run `flutter pub get`; run `dart run build_runner build --delete-conflicting-outputs` only when `build_runner` appears in dependencies or dev dependencies and `RUN_BUILD_RUNNER` is not false; optionally run analyze/tests according to environment flags.
- `build`: resolve version/flavor/entrypoint and create a release AAB without uploading; check the standard `build/app/outputs/bundle/release/app-release.aab` and discover the actual flavor-specific output.
- `release_play_store`: validate inputs, run deploy-context doctor before network access, prepare temporary secrets, run prepare, resolve version name/code, build and verify a nonempty AAB, upload through Fastlane's official Google Play action, report the result, and clean generated secrets in `ensure`.
- `firebase_distribution`: run only when enabled and selected by `DISTRIBUTION_TARGET`; keep it off by default and add the official plugin only to a package-owned or safely mergeable `Pluginfile`, otherwise provide the exact install step.
- an internal coordinator used by CI: `play-store` uploads only to Play, `firebase` uploads only to Firebase, and `both` builds once then performs the two explicit uploads in documented order. A second-destination failure after the first succeeds reports `PARTIAL_SUCCESS` and never claims rollback.

Handle Slack notification in success/error paths without allowing notification failure to mask the original result. Assign one notification owner per execution so GitHub Actions and Fastlane do not send duplicates. Never log full environment variables or secret values.

Document and test the standard Bundler sequence:

```bash
cd android
bundle install
bundle exec fastlane android doctor
bundle exec fastlane android build
bundle exec fastlane android release_play_store
```

Pin Fastlane and plugin dependencies exactly and generate `android/Gemfile.lock`. CI uses frozen/deployment Bundler mode and fails if the lockfile and Gemfile disagree. If a lockfile cannot be generated in the implementation environment, report reproducible dependency verification as incomplete.

## Versioning

Normalize and validate tags matching these shapes:

```text
1.2.3
v1.2.3
1.2.3-beta.1
v1.2.3-beta.1
```

Resolve local version name in this order:

1. Fastlane `version_name` option;
2. `VERSION_NAME`;
3. current Git tag;
4. `pubspec.yaml` version name.

Normalize and validate every version-name source, not only release tags. A current Git tag means an exact tag on `HEAD`, never a nearest historical tag.

For Play deployment, query the selected target plus `PLAY_STORE_VERSION_TRACKS`, whose documented defaults cover `internal,alpha,beta,production`; allow explicit custom closed-testing tracks. Failure to query any configured track is fatal. Choose the maximum remote code plus one, validate the official numeric range, and never reuse a remote code or fall back locally during deployment. Because Play version codes are app-global, CI serializes all Play uploads for a repository regardless of version, ref, or track, and local concurrent uploads are unsupported.

For local build-only mode without API access, use `VERSION_CODE`, then the pubspec build number, then a deterministic positive value derived from the Git commit count. Validate every source as a positive bounded integer. Do not use a Unix timestamp.

Pass explicit `--build-name` and `--build-number` to `flutter build appbundle`, plus detected/selected flavor and target.

Record build start and prior output state. Accept exactly one newly produced AAB matching the selected flavor and target, and fail on zero, multiple, unchanged, or stale candidates. Pass that exact artifact path to the uploader.

## Credentials and environment

Required deployment inputs:

```text
APP_PACKAGE_NAME
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 or GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH
ANDROID_KEYSTORE_BASE64 or ANDROID_KEYSTORE_PATH
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Precedence is explicit path, then Base64 value, then documented default path. Never print values.

General defaults:

```text
PLAY_STORE_TRACK=internal
PLAY_STORE_VERSION_TRACKS=internal,alpha,beta,production
PLAY_STORE_RELEASE_STATUS=completed
PLAY_STORE_ROLLOUT=1.0
CONFIRM_PRODUCTION_DEPLOY=false
FLUTTER_CHANNEL=stable
JAVA_VERSION=17
RUBY_VERSION=3.3
RUN_FLUTTER_ANALYZE=true
RUN_FLUTTER_TESTS=false
RUN_BUILD_RUNNER=auto
DISTRIBUTION_TARGET=play-store
ENABLE_FIREBASE_APP_DISTRIBUTION=false
```

Optional Firebase inputs are `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, `FIREBASE_TESTERS`, and `FIREBASE_RELEASE_NOTES`. Optional Slack inputs are `SLACK_WEBHOOK_URL`, `SLACK_NOTIFY_SUCCESS=true`, and `SLACK_NOTIFY_FAILURE=true`. Document Base64 as transport encoding, not encryption.

Map the Google Play action parameters explicitly from validated values: `track`, `release_status`, `rollout`, `package_name`, service-account JSON path, and resolved AAB path. Validate the track/release-status allowlists, rollout bounds, and valid status/rollout combinations. `production` is never a default and requires `CONFIRM_PRODUCTION_DEPLOY=true`; CI additionally requires a protected GitHub Environment.

### Secret-file ownership

- Create a per-run temporary directory beneath `$RUNNER_TEMP` or `${TMPDIR:-/tmp}` with `umask 077`; decoded files use mode `0600`.
- Mark each secret path as explicit user-owned input or generated temporary output. Cleanup deletes only generated files and their temporary directory; it never modifies or deletes an explicit `*_PATH` input.
- If a higher-precedence explicit path is missing, unreadable, or invalid, fail rather than falling through to Base64 or a default.
- Reject malformed/truncated Base64 and validate decoded JSON structure before use. Keep secret content out of arguments, logs, `$GITHUB_ENV`, and `$GITHUB_OUTPUT`.
- Install cleanup handlers for normal completion, errors, `EXIT`, `HUP`, `INT`, and `TERM`; CI cleanup uses `if: always()`.

`encode_secret.sh` and `decode_secret.sh` must:

- support macOS and Linux without line wrapping;
- accept file/stdin and file/stdout options without echoing content unexpectedly;
- use restrictive permissions for decoded files;
- reject ambiguous argument combinations;
- install cleanup traps for temporary files where they create them;
- never enable shell tracing.

## GitHub Actions template

Generate `.github/workflows/release-android.yml` with:

- `release: types: [published]` and `workflow_dispatch`;
- inputs for `version_name`, `track`, `release_status`, and `run_tests`;
- `permissions: contents: read`;
- one repository-wide Play upload concurrency group independent of version, ref, or track, with `cancel-in-progress: false`, so app-global version-code allocation is serialized;
- a bounded timeout;
- exact release-tag checkout for `release.published`, and the trusted triggering SHA or an explicitly validated ref for manual runs;
- checkout, Java, Flutter, Ruby/Bundler setup pinned to stable action versions verified during implementation;
- Bundler caching, Flutter dependency restore, temporary secret decoding under `$RUNNER_TEMP`, `key.properties` creation, doctor, routed release lane, artifact summary, optional Slack success/failure notification, and unconditional cleanup;
- direct `bundle exec fastlane` rather than a Fastlane wrapper action.

For a release event, both checkout and version source use `github.event.release.tag_name`. Manual execution uses the validated `version_name` input and the triggering SHA unless an explicit ref input is provided. Avoid platform-specific Base64 flags by using the bundled decode script.

The default upload track is `internal`. Map manual `run_tests` to `RUN_FLUTTER_TESTS`, validate all dispatch inputs, and expose a separate production confirmation input when `track=production`. Pin every action to a reviewed immutable commit SHA and annotate the corresponding human-readable release; never use a floating `latest` reference.

## Optional integrations

### Firebase App Distribution

- Disabled by default.
- Support `play-store`, `firebase`, and `both` distribution targets.
- Validate Firebase app ID, testers/groups, release notes, plugin presence, artifact type, and credentials.
- Check credential presence and API access when the selected Firebase lane can do so safely; otherwise report the unverified permission requirement and exact least-privilege setup step.
- Do not let Firebase setup silently change the Play upload behavior.

### Slack

- Skip silently when no webhook is configured.
- Send repository, version, track, result, run URL, and commit/release URL.
- Use a JSON-safe payload and `curl`, not an abandoned wrapper action.
- Never include secrets or the whole environment.
- Treat notification failure as a warning that does not replace the build/deploy result.

## Templates and documentation

`templates/PLAY_STORE_RELEASE.md` must be copy-ready for a generated project document and cover all 17 topics from the user request: purpose, generated files, Play Console/service account/upload key setup, GitHub secrets, first manual upload, local doctor/build/internal deployment, release and manual Actions runs, Slack, Firebase, troubleshooting, key loss/rotation, rollback, and promotion.

The GitHub Secrets section enumerates the six required values plus exactly these optional secrets: `SLACK_WEBHOOK_URL`, `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, and `FIREBASE_TESTERS`. Firebase release notes and notification flags remain ordinary inputs or variables. The section includes no-wrap Base64 examples for macOS, Linux, and Windows PowerShell, warns against exposing encoded output, and gives optional `gh secret set SECRET_NAME` examples without ever mutating repository secrets on the user's behalf.

References provide:

- a complete environment-variable catalog, defaults, precedence, and secrecy classification;
- troubleshooting organized by doctor/build/signing/Play API/first release/Firebase/Slack/CI;
- a least-privilege first-release checklist covering Play Console app creation, Android Developer API enablement, service-account creation and Play Console linkage, target-app release permissions, JSON issuance, Play App Signing, a possible first manual AAB, internal-track creation, tester registration, and final automation preflight.

The release lane distinguishes authentication/permission errors from first-release or draft-app constraints and points to the corrective checklist instead of retrying blindly.

All commands must be copyable. No real secret or repository-specific identifier appears in a template.

The bootstrap merges these exact ignore patterns without duplication and verifies that examples remain committable:

```gitignore
android/fastlane/.env
android/key.properties
android/*.jks
android/*.keystore
google-play-service-account.json
**/google-play-service-account.json
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/
fastlane/test_output/
```

## Validation script

`validate_release_setup.sh` supports `--project` and returns nonzero on hard failures. Validate:

- project shape and inspection result;
- required generated files;
- YAML parse when a parser is available, with a safe structural fallback;
- Ruby syntax when Ruby is available;
- shell syntax for generated/bundled scripts;
- Groovy/Kotlin marker integrity and release signing structure;
- `.gitignore` required patterns and example-file exceptions;
- unresolved unsafe placeholders in active configuration;
- hardcoded credential patterns and tracked-secret filenames;
- Bundler/Fastlane lanes and Flutter checks when tools and inputs are available.

Report each check as `PASS`, `WARN`, or `FAIL`; missing optional tools are warnings, not fabricated successes. Never upload during validation.

On a supplied real Flutter project, run the following exact validation matrix when its prerequisites are available:

```bash
flutter --version
flutter pub get
flutter analyze
cd android && bundle check
cd android && bundle exec fastlane lanes
cd android && bundle exec fastlane android doctor
```

An AAB verification requires a build-capable environment and user authorization. Missing secrets must produce structured doctor findings rather than a stack trace. Every skipped command records the prerequisite that was absent and a copy-ready command for the user; the package-only fixture environment does not pretend these project checks ran.

## Tests

`tests/run_tests.sh` creates disposable fixtures and covers:

- non-Flutter project rejection;
- Groovy and Kotlin DSL inspection;
- application ID/namespace distinction;
- flavor ambiguity;
- monorepo root selection;
- Base64 encode/decode round trips including binary content, invalid/truncated input rejection, decoded mode `0600`, cleanup after success/error/signal, explicit-path preservation, and secret-log scans;
- bootstrap creation, zero-write dry runs, second-run idempotency, fault injection after each write with exact rollback, malformed/multiple markers, edited owned regions, and file-mode preservation;
- preservation or explicit zero-write conflict for existing Fastlane/workflow/signing content;
- `.gitignore` de-duplication;
- doctor and validator exit behavior with `PASS`, `WARN`, `FAIL`, build context, deploy context, and missing secrets;
- install/update/uninstall in temporary HOME directories, including manifest hashes, unrelated-directory and symlink refusal, installed-copy self-update refusal, and second-destination rollback;
- version-name/code precedence and validation, exact-HEAD tags, multi-track remote maximum, failed track queries, bounds, and prohibition of deploy fallback;
- stale/multiple AAB rejection and release application-ID mismatch rejection;
- workflow assertions for exact tag checkout, non-cancelling repository-wide concurrency, immutable action pins, test-input mapping, protected production gate, and unconditional cleanup;
- stubbed commands proving doctor, build, bootstrap, and validation never contact Play, Firebase, Slack, or GitHub;
- `play-store`, `firebase`, and `both` routing, including partial-success reporting and exactly one Slack notification owner;
- shell, Ruby, and YAML syntax where the relevant parser exists.

Tests never need real Google, Firebase, Slack, or GitHub credentials and never contact external systems.

## Repository integration

- Add `flutter-play-store-release` to the repository validator's expected set and update the exact skill count from six to seven.
- Update the root README introduction, skill table, install loop, personal prompt examples, structure tree, and validation examples.
- Keep the existing six skills unchanged except where a count or installation loop must change.
- Add a new design and implementation plan rather than rewriting historical design records that accurately describe earlier repository states.

## Official-source verification

Before finalizing version-sensitive code, verify current primary documentation for:

- Flutter Android app bundle and version options;
- Fastlane `upload_to_play_store`, version-code lookup, Firebase App Distribution plugin, and lane error/ensure behavior;
- GitHub Actions workflow syntax, permissions, concurrency, release/manual events, secret handling, and stable official action releases;
- Google Play first-release/API/service-account and least-privilege guidance;
- Firebase App Distribution Fastlane setup.

Record durable source links in the package README or references without copying long copyrighted text. Do not rely on old blog snippets.

## Completion report

Report:

- canonical source and both global installation paths;
- all created package files;
- that no Flutter project was provided or modified;
- project changes grouped as created, modified, preserved, and backed up, using `N/A` when no project was supplied;
- detected Flutter version, Android Gradle DSL, release application ID, flavor, build_runner, existing Fastlane, existing GitHub Actions, and current environment/tool availability, again preserving fields as `N/A` rather than omitting them;
- required and optional user values;
- a separate GitHub Secrets section;
- local doctor/build/internal-deploy commands plus GitHub Release and manual workflow commands;
- validation `PASS`, `WARN`, `FAIL`, and unrun items;
- first-upload, keystore backup, and production-promotion cautions;
- Claude Code slash and Codex dollar invocation examples.

Use the requested headings without collapsing fields: `Global skill installation result`, `Created skill files`, `Current Flutter project changes`, `Detected project information`, `Values the user must prepare`, `Local validation commands`, `GitHub Secrets`, `Deployment commands`, `Validation results`, and `Cautions`. Preserve created/modified/preserved/backup and `PASS`/`WARN`/`FAIL`/not-run subgroups even when their value is `N/A`.

## Completion criteria

The work is complete only when:

- every required package file exists and contains finished content;
- all fixture tests pass;
- bundled shell scripts pass syntax checks and executable tests;
- templates pass available Ruby/YAML/static checks;
- repository and official skill validators pass with exactly seven skills;
- secret, placeholder, absolute-path, link, and English-only scans pass;
- both global copies are identical and every installed manifest entry matches the canonical package content;
- no Play, Firebase, Slack, GitHub secret, or production change was attempted;
- the local commit is pushed and matches public `origin/main`.
