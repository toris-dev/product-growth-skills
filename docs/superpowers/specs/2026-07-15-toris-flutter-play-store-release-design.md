# Toris Flutter Play Store Release Skill — Design

## Objective

Add `toris-flutter-play-store-release` as the seventh skill in `product-growth-skills`, use that repository folder as the canonical source, and install verified copies into both global skill locations:

```text
~/.claude/skills/toris-flutter-play-store-release/
~/.agents/skills/toris-flutter-play-store-release/
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
toris-flutter-play-store-release/
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
│   ├── lib/
│   │   ├── common.sh
│   │   ├── package_sync.sh
│   │   ├── project_transaction.sh
│   │   └── gradle_signing.sh
│   ├── inspect_flutter_project.sh
│   ├── bootstrap_android_fastlane.sh
│   ├── validate_release_setup.sh
│   ├── encode_secret.sh
│   ├── decode_secret.sh
│   └── install_flutter_sdk.sh
├── templates/
│   ├── Gemfile
│   ├── Gemfile.lock
│   ├── Appfile
│   ├── Fastfile
│   ├── FlutterPlayStoreRelease.rb
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
    ├── fastlane_helper_test.rb
    └── fixtures/ generated at test runtime
```

The internal README is included because the user explicitly requires a standalone package usable outside an agent runtime. `SKILL.md` remains concise and routes detailed guidance to references and templates. Its YAML frontmatter must contain `name: toris-flutter-play-store-release` and an English description equivalent to the deployment-focused description in the request. It includes English equivalents of the supplied natural-language use cases, all eight modes, and both Claude Code and Codex invocation forms.

The scripts target macOS and Linux, remain compatible with the system Bash available on supported macOS versions, and do not assume GNU-only flags. Optional helpers such as Ruby, Python, `jq`, or a YAML parser improve validation but are never silently treated as mandatory unless the generated project workflow itself requires them.

## Installation model

Use copies rather than symlinks for maximum compatibility. `.skill-package-id` contains the fixed package ID and schema version. `install-manifest.txt` lists every runtime file that must be copied; canonical-only fixture tests and generated artifacts are outside that manifest. Each installed copy has a deterministic `.skill-install-receipt` recording the hash and mode of every manifest entry. Both installed destinations, including receipts, must be byte-for-byte identical, and every installed manifest entry must match its canonical source.

- `install.sh` uses its own containing directory as the canonical source, copies the manifest into both global destinations, and refuses unsafe source/destination relationships or invalid required files.
- `update.sh` requires an explicit canonical source or a non-installed script location, performs the same validated synchronization, and refuses to treat either global destination as canonical.
- `uninstall.sh` removes only destinations that identify themselves as this package; support `--dry-run` and require an explicit confirmation flag for non-interactive removal.
- Exclude canonical-only tests, test artifacts, VCS metadata, caches, and local secrets from the install manifest.
- Resolve and validate paths; mutate only the two exact global destinations, transaction-specific siblings inside their parents, and `$HOME/.toris-flutter-play-store-release-install-state/` for the shared lock/journal. Refuse destination symlinks, source/destination overlap, unrelated directories, or identity-valid installations with an edited/missing manifest entry or any unexpected file, directory, or symlink. Remove clean support state after success.
- Serialize install/update/uninstall with one shared atomic lock at `$HOME/.toris-flutter-play-store-release-install-state/lock` inside a non-symlink mode-`0700` current-user state directory; its owner token prevents another process from removing it. Reclaim a same-host stale lock only after proving the recorded process is absent.
- Stage and validate both copies before replacing either. Persist an atomic phase journal with validated `package_id`, schema, `transaction_id`, operation, phase, prior-existence flags, and per-destination stage/rollback/quarantine paths; never source it as shell code. Retain rollback copies until both swaps/final validation succeed, then record `committed` before cleanup. Catchable pre-commit failures restore immediately; the next locked invocation restores old state for pre-commit journals, preserves new state and finishes cleanup for committed journals, or reports retained rollback paths when validation fails. Journal paths must match exact transaction-specific basenames beneath the two destination parents before any rename/delete.
- Treat successful uninstall renames plus an atomic committed journal as the commit point. Failures before that restore both; a committed-journal recovery preserves absent destinations and finishes quarantine cleanup. Post-commit deletion is best effort, and undeleted paths/journal evidence are retained and reported rather than falsely claiming rollback.
- Never uninstall the canonical source. Tests inject failures at every install/uninstall phase, kill a test process between swaps, and prove recovery preserves the exact prior states.

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
- Firebase package/app-ID mappings from `google-services.json` without printing unrelated values;
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
android/fastlane/lib/flutter_play_store_release.rb
android/fastlane/.env.example
android/key.properties.example
.github/workflows/release-android.yml
docs/PLAY_STORE_RELEASE.md
tool/flutter-play-store-release/decode_secret.sh
tool/flutter-play-store-release/install_flutter_sdk.sh
tool/flutter-play-store-release/managed-files.sha256
.gitignore
android/app/build.gradle or android/app/build.gradle.kts
```

The public skill and global package identity are `toris-flutter-play-store-release`. Retain `tool/flutter-play-store-release`, the sidecar package ID, and generated ownership markers as the stable project-internal namespace so projects created before the public rename remain recognizable and safely updatable.

Safety requirements:

- Read existing files before changing them.
- Never replace a customized Fastfile, workflow, or Gradle file wholesale.
- Create new files from templates only when absent.
- Merge missing `.gitignore` lines without duplicates.
- Use deterministic begin/end markers for generated Gradle and Fastlane blocks.
- Refuse ambiguous or malformed existing marker regions.
- Preserve existing lanes and plugins, or stop with a conflict report when safe merging is not possible. Append a marked platform block only when required lane names do not already exist. An existing `android/Gemfile` must contain or safely receive exact `gem "fastlane", "= 2.237.0"` plus one compatible `eval_gemfile` import for `android/fastlane/Pluginfile`; conflicting Fastlane constraints and ambiguous/dynamic/duplicate imports are conflicts.
- Treat an absent file, a recognized package-owned file, a safely mergeable file, and an unowned non-mergeable file as four distinct cases. Update package-owned content, merge only supported structures, and stop before overwriting unowned workflows or customized configuration.
- Show a diff or dry-run summary before broad changes.
- Compute and stage every proposed edit before touching the project, validate staged output, then apply as one transaction. Preserve byte-for-byte recovery copies, permissions, and line endings until post-write validation succeeds; restore every changed, removed, dirty, or untracked file if any write fails. A conflict exits nonzero with zero project changes.
- `--dry-run` performs zero writes and prints a deterministic plan. `tool/flutter-play-store-release/managed-files.sha256` is the authoritative identity/schema/body-hash sidecar for whole generated files; comment-capable files may duplicate that metadata in-file, while tool-owned formats such as `Gemfile.lock` never receive an invalid embedded header. User-edited package-owned content causes a conflict instead of being overwritten.
- Running bootstrap twice must produce no second-run diff.

## Android signing

Support Groovy and Kotlin DSL with a generated, marked signing block that reads `ANDROID_KEY_PROPERTIES_PATH` when set and otherwise `android/key.properties`, then connects `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` to the release build.

- Detect every release-to-debug signing assignment. Safely replace recognized stock Flutter patterns; fail setup and validation with a precise conflict for custom or ambiguous patterns until repaired. A release build must never retain both debug and release signing assignments.
- Never silently fall back to the debug key.
- Fail only release-signing tasks with an actionable message when required signing data is missing; inspection, debug builds, and unrelated Gradle configuration remain usable.
- Preserve user-owned signing code and report conflicts rather than attempting a risky rewrite.
- Generate placeholders only in `android/key.properties.example`.
- Add real key properties, keystores, and service-account files to `.gitignore` without ignoring examples.
- With local environment/path signing inputs, the coordinator creates a mode-`0600` properties file under its owned temporary root, points it at the absolute explicit/decoded keystore, and passes only its nonsecret path. Without those inputs, local execution may use a valid user-owned `android/key.properties` fallback and never deletes it. CI always uses the temporary override and refuses a pre-existing workspace copy. Writers correctly escape Java-properties metacharacters/Unicode, reject controls/newlines, and clean only generated files.

## Fastlane implementation

Use Bundler-pinned dependencies and current supported Fastlane APIs verified from official documentation during implementation.

Provide lanes:

- `doctor`: report `PASS`, `WARN`, and `FAIL` for toolchain, files, package name, credentials by presence only, signing inputs, track, build_runner, and plugins. Missing deploy credentials are warnings in setup/build context and failures in deploy context; warnings alone exit zero, while any failure exits nonzero.
- `prepare`: run `flutter pub get`; run `dart run build_runner build --delete-conflicting-outputs` only when `build_runner` appears in dependencies or dev dependencies and `RUN_BUILD_RUNNER` is not false; optionally run analyze/tests according to environment flags.
- `build`: resolve version/flavor/entrypoint and create a release AAB without uploading; check the currently documented `build/app/outputs/bundle/release/app.aab` and discover the actual flavor-specific output instead of assuming one filename.
- `release_play_store`: validate inputs, run deploy-context doctor before network access, prepare temporary secrets, run prepare, resolve version name/code, build and verify a nonempty AAB, and call `upload_to_play_store` with `aab` plus `skip_upload_metadata`, `skip_upload_changelogs`, `skip_upload_images`, and `skip_upload_screenshots` all true. It reports the result and cleans generated secrets in `ensure`.
- `firebase_distribution`: publicly delegate to the common `release` router with target `firebase`, so it receives deploy doctor, Firebase-only credentials/versioning, package-name validation, APK/AAB build, and shared cleanup. It passes required `app`, artifact type/path, separate credentials, notes, testers, and groups. Firebase-only supports `AAB` or `APK`; `both` requires `AAB` and reuses the Play artifact.
- a public `release` coordinator used by CI: run doctor, target-specific credential preparation, prepare, version resolution, and one build before private upload-only helpers. `play-store` requires only Play credentials, `firebase` only Firebase credentials, and `both` both independently. `release_play_store` and `firebase_distribution` delegate with fixed targets and never rebuild. A Firebase failure after successful Play upload reports one `PARTIAL_SUCCESS`, never claims rollback, cleans up, and exits nonzero.

Handle Slack notification in success/error paths without allowing notification failure to mask the original result. Local runs default to Fastlane ownership; CI assigns GitHub Actions ownership so pre-Fastlane failures are covered without duplicates. When `RELEASE_RESULT_PATH` is supplied, atomically write nonsecret schema-1 result fields (status/target/version/track/artifact/successful and failed destinations/redacted message) before returning or raising; CI uses it for summary/notification and treats absence as a pre-Fastlane failure. Never log full environment variables, credential paths, or secret values.

Document and test the standard Bundler sequence:

```bash
cd android
bundle install
bundle exec fastlane android doctor
bundle exec fastlane android build
bundle exec fastlane android release_play_store
```

Pin Fastlane `2.237.0` and Firebase plugin `1.0.0`, generate `android/Gemfile.lock` with the verified Bundler `4.0.16` baseline, and re-check all three stable releases at implementation time. CI sets both `BUNDLE_FROZEN=true` and `BUNDLE_DEPLOYMENT=true` and fails if the lockfile and Gemfile disagree. If a lockfile cannot be generated in the implementation environment, report reproducible dependency verification as incomplete.

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

Normalize and validate every version-name source, not only release tags. A current Git tag means an exact tag on `HEAD`, never a nearest historical tag. Multiple exact tags are allowed only when all supported tags normalize to the same version (for example `v1.2.3` and `1.2.3`); distinct versions or a mixed valid/invalid exact-tag set fail as ambiguous.

For `play-store`/`both`, query the selected target plus `PLAY_STORE_VERSION_TRACKS`, whose documented defaults cover `internal,alpha,beta,production`; allow explicit custom closed-testing tracks. A successful empty track is valid; an API/action error or invalid result for any configured track is fatal. All tracks empty fails with the first-release/manual-bootstrap checklist. Choose the maximum active-track code plus one, validate the official `1..2100000000` range, and never fall back locally during Play deployment. Google and Fastlane expose no authoritative allocator for the highest code ever used, so document this limit, serialize uploads, and surface a Play reuse rejection with retry guidance. Local concurrent uploads are unsupported.

For Firebase-only and local build-only modes without Play API access, use `VERSION_CODE`, then the pubspec build number, then a deterministic positive value derived from the Git commit count. Validate every source as a positive bounded integer. Never query Play for Firebase-only and do not use a Unix timestamp.

Pass explicit `--build-name` and `--build-number` to Flutter, plus detected/selected flavor and target. Play builds an AAB. Firebase-only may build AAB or APK according to `FIREBASE_ANDROID_ARTIFACT_TYPE`; `both` requires AAB and reuses one build.

Move only relevant prior variant outputs to a private quarantine before the build. Artifact acceptance is the commit point: restore prior outputs after every command, signal, zero/empty/multiple/mismatch, or other pre-acceptance failure; only after one new artifact passes all checks remove the quarantine. Verify the requested Dart target from the build command itself because the output path cannot encode it. Pass that exact artifact path to the uploader.

## Credentials and environment

Required signing/application inputs for CI deployments, or the environment/path alternative for local deployments:

```text
APP_PACKAGE_NAME
ANDROID_KEYSTORE_BASE64 or ANDROID_KEYSTORE_PATH
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Local release may replace the four keystore/signing environment inputs with a complete valid user-owned `android/key.properties`; CI always requires the five listed signing/application secrets. Play targets additionally require `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` or `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH`. Firebase targets additionally require `FIREBASE_APP_ID` and separate `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` or `FIREBASE_SERVICE_ACCOUNT_JSON_PATH`. `both` requires both target credential sets independently.

Precedence is explicit path, then Base64 value, then documented default path. Never print values.

General defaults:

```text
PLAY_STORE_TRACK=internal
PLAY_STORE_VERSION_TRACKS=internal,alpha,beta,production
PLAY_STORE_RELEASE_STATUS=completed
PLAY_STORE_ROLLOUT=1.0
CONFIRM_PRODUCTION_DEPLOY=false
FLUTTER_CHANNEL=stable
FLUTTER_VERSION=
JAVA_VERSION=17
RUBY_VERSION=3.3
RUN_FLUTTER_ANALYZE=true
RUN_FLUTTER_TESTS=false
RUN_BUILD_RUNNER=auto
DISTRIBUTION_TARGET=play-store
ENABLE_FIREBASE_APP_DISTRIBUTION=false
FIREBASE_ANDROID_ARTIFACT_TYPE=AAB
CONFIRM_FIREBASE_AAB_PLAY_LINKED=false
CONFIRM_FIREBASE_PACKAGE_MATCH=false
```

Optional Firebase inputs are `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, `FIREBASE_TESTERS`, and `FIREBASE_RELEASE_NOTES`. Optional Slack inputs are `SLACK_WEBHOOK_URL`, `SLACK_NOTIFY_SUCCESS=true`, and `SLACK_NOTIFY_FAILURE=true`. Document Base64 as transport encoding, not encryption.

`FLUTTER_VERSION` is required when no `.fvmrc`, `.flutter-version`, or FVM project pin provides an exact version. CI precedence is validated manual `flutter_version`, project pin, repository variable `FLUTTER_VERSION`, then failure. `ANDROID_KEY_PROPERTIES_PATH` is a nonsecret per-process override generated by the coordinator and falls back to `android/key.properties` for user-owned local configuration.

Firebase credentials use separate conditional `FIREBASE_SERVICE_ACCOUNT_JSON_PATH` or `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` inputs. Do not assume the Google Play Publisher service account has Firebase App Distribution permissions.

Map the Google Play action parameters explicitly from validated values: `track`, `release_status`, conditionally applicable `rollout`, `package_name`, service-account JSON path, and resolved AAB path. Binary upload supports `completed`, `draft`, and `inProgress`; staged `inProgress` requires `0 < rollout < 1`, while completed/draft omit rollout. Reject `halted` because halting an existing release is outside this new-binary lane. `production` is never a default and requires `CONFIRM_PRODUCTION_DEPLOY=true`; CI routes it to fixed Environment `play-store-production`, whose reviewer/tag protection is an external prerequisite that file validation cannot prove.

### Secret-file ownership

- Create a per-run temporary directory beneath `$RUNNER_TEMP` or `${TMPDIR:-/tmp}` with `umask 077`; decoded files use mode `0600`.
- Mark each secret path as explicit user-owned input or generated temporary output. Cleanup deletes only generated files and their temporary directory; it never modifies or deletes an explicit `*_PATH` input.
- Resolve/decode only the credential sets required by the selected distribution target. When environment signing credentials are used, generate `key.properties` under the owned temp root and pass `ANDROID_KEY_PROPERTIES_PATH`; never overwrite or delete a project copy.
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
- inputs for `version_name`, optional exact `flutter_version`, `track`, `release_status`, `run_tests`, `distribution_target`, `firebase_artifact_type`, `firebase_release_notes`, `confirm_firebase_package_match`, `confirm_firebase_aab_play_linked`, and `confirm_production`;
- `permissions: contents: read`;
- one repository-wide Play upload concurrency group independent of version, ref, or track, with current GitHub.com's `queue: max`, so active-track version-code selection and uploads are serialized without replacing older pending runs;
- a bounded timeout;
- checkout by immutable event `github.sha` for both events. For releases, validate/dereference the payload tag and require it to point at `HEAD`; use tag text only as version input. Manual runs use the native workflow-dispatch ref/SHA and expose no custom mutable ref input;
- checkout, Java, and Ruby/Bundler setup pinned to full verified commit SHAs. Every nonlocal `uses:` reference must be exactly 40 lowercase hex characters. Install exact-version/architecture Flutter from the fixed official Linux manifest/base URL; require unique normalized archive paths, contained regular/directory/link members, and no devices/FIFOs/sockets/privilege or preserved ownership metadata; verify SHA-256 and extracted version; and never accept a production custom manifest;
- Bundler caching, Flutter dependency restore, target-specific temporary secret decoding under `$RUNNER_TEMP`, a private escaped key-properties file passed by `ANDROID_KEY_PROPERTIES_PATH`, doctor, routed release lane, artifact summary, one optional Slack success/failure owner, and unconditional cleanup;
- direct `bundle exec fastlane` rather than a Fastlane wrapper action.

For a release event, checkout uses `github.sha` and the validated tag text supplies version name only after `refs/tags/<tag>^{commit}` equals `HEAD`. Manual execution uses the validated `version_name` input and native triggering SHA. Map all untrusted contexts through quoted step-local environment values; never interpolate them directly in `run:`. Avoid platform-specific Base64 flags by using the bundled decode script.

The default upload track is `internal`. Map manual `run_tests` to `RUN_FLUTTER_TESTS`, validate every dispatch/release value, and reject unconfirmed production in a non-secret job. Confirmed production uses `play-store-production`; every other run uses fixed `play-store-nonproduction`. Document where each Environment stores secrets and that protection rules live in repository settings and remain unverified without settings evidence. Base64 files and signing scalars exist only in the decode/properties step; release receives generated paths and only scalar secret-backed Firebase values it actually consumes. Never expose raw secrets through workflow/job environment, arguments, outputs, summaries, or artifacts. Pin every action to a reviewed immutable commit SHA and annotate the corresponding release; never use floating refs. Document that `queue: max` is a current GitHub.com feature and Node 24 pins require a current runner.

## Optional integrations

### Firebase App Distribution

- Disabled by default.
- Support `play-store`, `firebase`, and `both` distribution targets.
- Validate Firebase app ID, testers/groups, release notes, plugin presence, artifact type, and credentials.
- Check credential presence and API access when the selected Firebase lane can do so safely; otherwise report the unverified permission requirement and exact least-privilege setup step.
- Require a linked, reviewed Google Play app for Firebase AAB distribution; allow APK distribution without that link. Explain the separate test-app signing certificate used for AAB tester APKs.
- Require explicit `CONFIRM_FIREBASE_AAB_PLAY_LINKED=true` before an AAB distribution because file-only automation cannot prove the Play review/link state; keep external verification visible in the report.
- Require selected release `applicationId` and `FIREBASE_APP_ID` to match one Firebase client mapping in `google-services.json`. When evidence is absent require `CONFIRM_FIREBASE_PACKAGE_MATCH=true`; never let confirmation override a detected package/app-ID mismatch. Selecting `firebase`/`both` derives effective `ENABLE_FIREBASE_APP_DISTRIBUTION=true`, while `play-store` derives false.
- Do not let Firebase setup silently change the Play upload behavior.

### Slack

- Skip silently when no webhook is configured.
- Send repository, version, track, result, run URL, and commit/release URL.
- Use a JSON-safe payload and `curl`, not an abandoned wrapper action.
- Never include secrets or the whole environment.
- Treat notification failure as a warning that does not replace the build/deploy result.

## Templates and documentation

`templates/PLAY_STORE_RELEASE.md` must be copy-ready for a generated project document and cover all 17 topics from the user request: purpose, generated files, Play Console/service account/upload key setup, GitHub secrets, first manual upload, local doctor/build/internal deployment, release and manual Actions runs, Slack, Firebase, troubleshooting, key loss/rotation, rollback, and promotion.

The GitHub Secrets section separates: five signing/application values required for every target; `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` required for Play targets; `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` required for Firebase targets; and exactly these four user-requested optional secret-backed values: `SLACK_WEBHOOK_URL`, `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, and `FIREBASE_TESTERS` (while Firebase App ID becomes a required value when that target is selected). Firebase release notes and notification flags remain ordinary inputs or variables. The section includes no-wrap Base64 examples for macOS, Linux, and Windows PowerShell, warns against exposing encoded output, and gives optional `gh secret set SECRET_NAME` examples without ever mutating repository secrets on the user's behalf.

References provide:

- a complete environment-variable catalog, defaults, precedence, and secrecy classification;
- troubleshooting organized by doctor/build/signing/Play API/first release/Firebase/Slack/CI;
- a least-privilege first-release checklist covering Play Console app creation, Android Developer API enablement, service-account creation and Play Console linkage, target-app release permissions, JSON issuance, Play App Signing, a possible first manual AAB, internal-track creation, tester registration, and final automation preflight.

The release lane distinguishes authentication/permission errors from first-release or draft-app constraints and points to the corrective checklist instead of retrying blindly. The checklist states that the Publishing API cannot bootstrap a completely new app and that a first AAB plus legal/app-content setup may require Play Console. It also records the current closed-testing gate for newly created personal developer accounts as a version-sensitive policy to re-check.

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

`validate_release_setup.sh` supports `--project`, `--context doctor|setup|build|deploy`, and explicit `--run-project-commands`; it returns nonzero on hard failures. `doctor` is the default read-only context and never runs `flutter pub get`, analyze, tests, build, or other project-mutating commands. Those checks are reported as not run with copy-ready commands unless setup/build execution is explicitly authorized. Validate:

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

On a supplied real Flutter project, run the following exact validation matrix only when prerequisites are available and setup/build project-command execution is explicitly authorized; read-only doctor instead reports mutating commands as not run:

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
- doctor and validator exit behavior with `PASS`, `WARN`, `FAIL`, read-only doctor, explicit project-command opt-in, build/deploy context, and missing secrets;
- install/update/uninstall in temporary HOME directories, including receipts/exact-tree refusal, shared lock, journal recovery after every killed phase, unrelated-directory/symlink refusal, installed-copy self-update refusal, two-destination rollback, and post-commit uninstall quarantine cleanup;
- version-name/code precedence and validation, equivalent/conflicting exact-HEAD tags, mixed empty/nonempty tracks, failed/all-empty track queries, bounds, and prohibition of deploy fallback;
- quarantined prior output recovery, fresh/multiple AAB/APK rejection, build-command target assertion, and release application-ID mismatch rejection;
- workflow assertions for event-SHA checkout/tag-to-HEAD verification, input injection resistance, non-cancelling repository-wide concurrency, every immutable action pin, target-specific secret scope, Java-properties escaping, environment routing/external protection status, and unconditional cleanup;
- stubbed commands proving doctor, build, bootstrap, and validation never contact Play, Firebase, Slack, or GitHub;
- mocked Fastlane action parameters, binary-only Play listing skips, `play-store`/`firebase`/`both` credential routing, build-once behavior, nonzero partial success, cleanup, and exactly one Slack notification owner;
- shell, Ruby, and YAML syntax where the relevant parser exists.

Tests never need real Google, Firebase, Slack, or GitHub credentials and never contact external systems.

## Repository integration

- Add `toris-flutter-play-store-release` to the repository validator's expected set and update the exact skill count from six to seven.
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
