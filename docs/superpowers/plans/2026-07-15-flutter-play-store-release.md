# Flutter Play Store Release Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a production-quality, reusable `flutter-play-store-release` skill as the seventh package in this repository, verify it without contacting external deployment systems, install byte-identical copies for Claude Code and Codex, and publish the completed repository state.

**Architecture:** Keep `/Users/toris/projects/product-growth-skills/flutter-play-store-release/` as the only canonical source. Portable Bash entrypoints inspect and bootstrap Flutter projects transactionally; a generated, pinned Fastlane package owns release orchestration; a SHA-pinned GitHub Actions workflow restores secrets only in runner-temporary storage; fixture tests stub all external commands. Manifest-driven installers stage both global copies and roll both back if either destination swap fails.

**Tech Stack:** Bash 3.2-compatible shell, Flutter/Android Gradle (Groovy and Kotlin DSL), Ruby 3.3, Bundler 4.0.16, Fastlane 2.237.0, `fastlane-plugin-firebase_app_distribution` 1.0.0, GitHub Actions, Google Play Developer API, optional Firebase App Distribution and Slack webhook notifications, and Python 3 for repository validation and safe CI archive extraction.

**Global Constraints:** Implement only Android/Google Play behavior. Never create real secrets, upload an artifact, mutate GitHub secrets, call Play/Firebase/Slack, promote a release, or generate/replace an upload key during package development and tests. Keep all package prose and identifiers in English. Preserve unrelated user changes. Use `apply_patch` for hand-authored edits, immutable action SHAs, exact dependency pins, portable shell constructs, explicit `PASS`/`WARN`/`FAIL` reporting, and test-first implementation. Re-check version-sensitive official sources immediately before final verification.

---

## Approved source of truth

Implement against `docs/superpowers/specs/2026-07-15-flutter-play-store-release-design.md`.

Primary implementation sources:

- Flutter Android release and flavors: <https://docs.flutter.dev/deployment/android> and <https://docs.flutter.dev/deployment/flavors>
- Android versioning and signing: <https://developer.android.com/studio/publish/versioning> and <https://developer.android.com/studio/publish/app-signing>
- Google Play API onboarding and edits: <https://developers.google.com/android-publisher/getting_started> and <https://developers.google.com/android-publisher/edits>
- Fastlane Play upload and version lookup: <https://docs.fastlane.tools/actions/upload_to_play_store/> and <https://docs.fastlane.tools/actions/google_play_track_version_codes/>
- Fastlane hooks and Firebase plugin: <https://docs.fastlane.tools/advanced/Fastfile/> and <https://firebase.google.com/docs/app-distribution/android/distribute-fastlane>
- GitHub workflow syntax and action pinning: <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax> and <https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions>
- Firebase/Google Play linking: <https://support.google.com/firebase/answer/6392038>

Version-sensitive baseline verified on 2026-07-15:

| Component | Baseline |
|---|---|
| Fastlane | `2.237.0` |
| Firebase App Distribution plugin | `1.0.0` |
| Ruby | `3.3` default; plugin-compatible minimum `3.2` |
| Bundler | `4.0.16`; recorded by generated `Gemfile.lock` |
| Flutter stable observed during research | `3.44.6`; generated projects honor a project pin instead |
| `actions/checkout` | `9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0` (`v7.0.0`) |
| `actions/setup-java` | `0f481fcb613427c0f801b606911222b5b6f3083a` (`v5.5.0`) |
| `ruby/setup-ruby` | `8e41b362d2589a22a44c1cfa214b3c83052c195b` (`v1.318.0`) |
| Play `versionCode` | positive integer no greater than `2100000000` |
| Current documented Flutter non-flavor AAB | `build/app/outputs/bundle/release/app.aab`; discover and validate the actual new artifact |

If a current primary source disagrees with this plan, update the design and plan with evidence and obtain approval for a material behavior change.

## File and ownership map

Create this canonical package. `tests/` is canonical-only and is excluded from `install-manifest.txt`.

```text
flutter-play-store-release/
├── .skill-package-id
├── SKILL.md
├── README.md
├── install-manifest.txt
├── agents/openai.yaml
├── install.sh
├── update.sh
├── uninstall.sh
├── scripts/
│   ├── lib/common.sh
│   ├── lib/package_sync.sh
│   ├── lib/project_transaction.sh
│   ├── lib/gradle_signing.sh
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
    └── fixtures/              # generated and removed by tests
```

Bootstrap may create or modify only:

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
android/app/build.gradle OR android/app/build.gradle.kts
```

The two runtime scripts under `tool/flutter-play-store-release/` are package-owned CI helpers and contain no project values. `managed-files.sha256` is the authoritative sidecar for package-owned whole-file hashes, including tool-owned formats such as `Gemfile.lock` that cannot safely embed a comment header. Comment-capable generated files also carry package ID/schema/body hash in-file. The sidecar excludes its own hash. Mergeable content uses one file-appropriate marker pair:

```text
BEGIN flutter-play-store-release schema=1
END flutter-play-store-release
```

Reject missing, nested, reversed, or repeated pairs. Never infer ownership from a matching filename alone.

## Stable command interfaces

Keep these signatures synchronized across code, templates, tests, and docs:

```text
scripts/inspect_flutter_project.sh --project PATH [--format human|json] [--flavor NAME]
scripts/bootstrap_android_fastlane.sh --project PATH [--flavor NAME] [--dry-run] [--conflict fail|skip]
scripts/validate_release_setup.sh --project PATH [--context doctor|setup|build|deploy] [--format human|json] [--run-project-commands]
scripts/encode_secret.sh [--input FILE|-] [--output FILE|-]
scripts/decode_secret.sh [--input FILE|-] [--output FILE|-]
scripts/install_flutter_sdk.sh --version VERSION --channel CHANNEL --architecture x64|arm64 --destination PATH [--manifest-url URL]
install.sh [--source PATH] [--dry-run]
update.sh --source PATH [--dry-run]
uninstall.sh [--dry-run] --yes
```

Exit statuses:

- `0`: work completed; validation may contain warnings only.
- `1`: hard validation or operational failure.
- `2`: arguments, ambiguous state, ownership conflict, or refused path.
- `3`: transaction/swap failed and rollback was attempted.

Human diagnostics go to stderr when stdout is JSON or Base64. Codecs emit payload only.

### Inspection JSON schema

JSON mode emits one object with at least these stable keys and types:

```json
{
  "schema_version": 1,
  "project_root": "absolute-path",
  "flutter_constraint": null,
  "dart_constraint": null,
  "flutter_version": null,
  "android_dsl": "groovy|kotlin|ambiguous|missing",
  "gradle_file": null,
  "android_gradle_plugin_version": null,
  "gradle_wrapper_version": null,
  "java_compatibility": null,
  "application_id": null,
  "namespace": null,
  "application_id_candidates": [],
  "version_name": null,
  "version_code": null,
  "pubspec_version_name": null,
  "pubspec_build_number": null,
  "flavors": [],
  "selected_flavor": null,
  "suggested_flavor": null,
  "suggestion_confirmed": false,
  "entrypoints": [],
  "build_runner": false,
  "fastlane": false,
  "github_actions": false,
  "release_signing": false,
  "release_uses_debug_signing": false,
  "firebase": false,
  "firebase_package_names": [],
  "firebase_apps": [],
  "firebase_app_distribution": false,
  "monorepo": false,
  "git_dirty": null,
  "files_bootstrap_may_change": [],
  "warnings": [],
  "failures": []
}
```

Use JSON `null` for unknown scalar values. `CHANGE_ME_APPLICATION_ID` is allowed only in inactive examples.

### Generated Fastlane module

`templates/FlutterPlayStoreRelease.rb` defines these stable, pure/testable entrypoints before action adapters:

```ruby
module FlutterPlayStoreRelease
  def self.normalize_version_name(raw); end
  def self.resolve_version_name(option:, env:, exact_head_tags:, pubspec:); end
  def self.validate_version_code(raw, source:); end
  def self.next_active_track_code(track_names:, fetch_track_codes:); end
  def self.distribution_steps(target:, firebase_enabled:); end
  def self.locate_fresh_artifact(project_root:, build_started_at:, prior_outputs:, flavor:, artifact_type:); end
  def self.resolve_secret(path_value:, base64_value:, default_path:, label:, temp_root:); end
  def self.java_properties_escape(value, label:); end
  def self.write_key_properties(path:, keystore_path:, store_password:, key_alias:, key_password:); end
  def self.cleanup_owned_secrets(secret_records); end
  def self.slack_payload(repository:, version:, track:, result:, run_url:, source_url:); end
end
```

`Fastfile` exposes public Android lanes `doctor`, `prepare`, `build`, `release`, `release_play_store`, and `firebase_distribution`. `release` is the CLI-callable router/coordinator; `release_play_store` and `firebase_distribution` delegate to it with fixed targets. Only upload adapters and internal orchestration helpers are private. Map current Fastlane parameters exactly: `json_key`, `aab`, `package_name`, `track`, `release_status`, conditional `rollout`, and `version_name`.

## Test isolation contract

`tests/run_tests.sh` creates a fresh temporary root, fixture HOME, stub command directory, and fixtures per group. Tests fail if stubs for `curl`, `gh`, Play, Firebase, or Slack are contacted. The SDK installer test uses a local injected manifest/archive only.

Fault injection works only with `FPRS_TEST_MODE=1`:

```text
FPRS_TEST_FAIL_PROJECT_WRITE_AFTER=N
FPRS_TEST_FAIL_INSTALL_SWAP=claude|agents
FPRS_TEST_SIGNAL_AT=codec-output|project-write
```

Production scripts ignore those variables otherwise. Failed transaction tests compare exact bytes, existence, modes, and line endings before/after.

The installation lifecycle may additionally use only `$HOME/.flutter-play-store-release-install-state/` for its shared lock and crash journal plus transaction-specific stage/rollback siblings inside the two destination parents. Remove clean state/stages after success; retain and report only evidence needed for recovery after a failure.

---

## Task 1: Initialize the seventh skill and lock the package contract

**Files:**

- Create: all canonical package paths in the file map
- Create: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Initialize with the official skill creator.**

```bash
python3 /Users/toris/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  flutter-play-store-release \
  --path /Users/toris/projects/product-growth-skills \
  --resources scripts,references \
  --interface display_name="Flutter Play Store Release" \
  --interface short_description="Automate safe Flutter releases to Google Play" \
  --interface default_prompt="Use \$flutter-play-store-release to inspect this Flutter app, configure safe Android delivery, and verify the Google Play release setup."
```

Expected: normalized directory with initial `SKILL.md` and `agents/openai.yaml`.

- [ ] **Write the first failing package-contract test.**

Add portable `pass`, `fail`, `assert_file`, `assert_executable`, `assert_contains`, and cleanup helpers. Enumerate every target file, require package ID/schema, require executable entrypoints, require a sorted duplicate-free manifest, and prove `tests/` is excluded.

```bash
bash flutter-play-store-release/tests/run_tests.sh package_contract
```

Expected: nonzero naming the first missing target.

- [ ] **Create the minimal finished skeleton and identity.**

`.skill-package-id`:

```text
package_id=flutter-play-store-release
schema_version=1
```

Populate `agents/openai.yaml` exactly:

```yaml
interface:
  display_name: "Flutter Play Store Release"
  short_description: "Automate safe Flutter releases to Google Play"
  default_prompt: "Use $flutter-play-store-release to inspect this Flutter app, configure safe Android delivery, and verify the Google Play release setup."
```

`SKILL.md` frontmatter contains only `name` and an English description. Include `## Quick start` and `## Definition of done`. Give every target a valid finished header rather than an unfinished marker. Set shell entrypoints executable.

- [ ] **Populate the runtime allowlist.**

List every runtime file in lexical order relative to the package root. Exclude tests, fixtures, VCS data, caches, editor state, generated output, and secret-shaped files.

- [ ] **Run package and official validators.**

```bash
bash flutter-play-store-release/tests/run_tests.sh package_contract
python3 /Users/toris/.codex/skills/.system/skill-creator/scripts/quick_validate.py flutter-play-store-release
```

Expected: both pass.

- [ ] **Commit.**

```bash
git add flutter-play-store-release
git commit -m "build flutter Play release skill package"
```

---

## Task 2: Implement portable helpers and strict secret codecs

**Files:**

- Create: `flutter-play-store-release/scripts/lib/common.sh`
- Modify: `flutter-play-store-release/scripts/encode_secret.sh`
- Modify: `flutter-play-store-release/scripts/decode_secret.sh`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Add failing codec tests.**

Cover text/binary round trips, stdin/stdout, file/stdout, stdin/file, paths with spaces, empty input, wrapped input, invalid alphabet, truncated padding, output replacement safety, decoded mode `0600`, `umask 077`, ambiguous flags, explicit input preservation, success/error/signal cleanup, stderr redaction, and absence of `set -x`. Use `cmp`; detect BSD/GNU `stat` portably; scan logs for unique canaries.

```bash
bash flutter-play-store-release/tests/run_tests.sh secret_codecs
```

Expected: nonzero before implementation.

- [ ] **Implement portable primitives.**

Provide namespaced `fprs_die`, `fprs_warn`, `fprs_info`, `fprs_require_arg`, `fprs_realpath`, `fprs_sha256`, `fprs_mktemp_dir`, `fprs_file_mode`, `fprs_json_escape`, `fprs_is_truthy`, and `fprs_cleanup_dir`. Use Bash 3.2-compatible constructs, `LC_ALL=C`, no `readlink -f`, no GNU-only in-place edit, and no tracing.

- [ ] **Implement strict encoding and decoding.**

Detect macOS/GNU Base64 flags without exposing content. Encoding emits one unwrapped line. Decoding strips ASCII whitespace privately, validates alphabet/length/padding, decodes into a private staged file, sets `0600`, and atomically renames to explicit output. Failed decode preserves prior output. `-` means stdin/stdout. Refuse same input/output. Traps delete only invocation-owned paths.

- [ ] **Run focused verification.**

```bash
bash -n flutter-play-store-release/scripts/lib/common.sh
bash -n flutter-play-store-release/scripts/encode_secret.sh
bash -n flutter-play-store-release/scripts/decode_secret.sh
bash flutter-play-store-release/tests/run_tests.sh secret_codecs
```

Expected: pass; payload-only stdout and mode `0600`.

- [ ] **Commit.**

```bash
git add flutter-play-store-release/scripts flutter-play-store-release/tests/run_tests.sh
git commit -m "implement safe release secret codecs"
```

---

## Task 3: Implement deterministic Flutter project inspection

**Files:**

- Modify: `flutter-play-store-release/scripts/inspect_flutter_project.sh`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Create failing inspection fixtures.**

Generate non-Flutter, minimal Groovy, minimal Kotlin, application-ID/namespace mismatch, suffix, multiple/ambiguous flavors, release flavor with entrypoint evidence, Gradle version overrides, build_runner in both dependency sections, existing Fastlane/workflow/signing/Firebase, Firebase package match/mismatch, release-to-debug signing, nested monorepo, dirty/non-Git, and path-with-spaces fixtures. Assert the full JSON schema and human output. Prove secret canaries never appear.

```bash
bash flutter-play-store-release/tests/run_tests.sh inspection
```

Expected: nonzero on the first missing field.

- [ ] **Implement root/option validation.**

Resolve `--project` physically; require `pubspec.yaml`, `android/`, and `android/app/`; reject both/neither DSL files; never search upward silently. Usage and ambiguity exit `2`.

- [ ] **Implement conservative static extraction.**

Read known non-secret configuration only. Extract pubspec constraints/version/build_runner, wrapper, plugin/AGP, Java, IDs, versions, flavor/suffix candidates, entrypoints, existing systems, signing references, Firebase package/app-ID mappings from `google-services.json` without printing unrelated fields, and Git status. Do not evaluate arbitrary Gradle. Warn on expressions that cannot be resolved.

Honor explicit valid flavor. Suggest one only with evidence; leave it unconfirmed. If release ID remains ambiguous, return candidates and `application_id=null`.

- [ ] **Emit dependency-free JSON.**

Use `fprs_json_escape`; do not require `jq`, Ruby, or Python to run. Tests parse with Python then Ruby when available and retain structural fallback assertions.

- [ ] **Verify and commit.**

```bash
bash -n flutter-play-store-release/scripts/inspect_flutter_project.sh
bash flutter-play-store-release/tests/run_tests.sh inspection
git add flutter-play-store-release/scripts/inspect_flutter_project.sh flutter-play-store-release/tests/run_tests.sh
git commit -m "add Flutter Android project inspection"
```

Expected: fixtures pass; ambiguous/non-Flutter failures are clear and leak no secrets.

---

## Task 4: Build the transactional project editor and Gradle signing planner

**Files:**

- Create: `flutter-play-store-release/scripts/lib/project_transaction.sh`
- Create: `flutter-play-store-release/scripts/lib/gradle_signing.sh`
- Modify: `flutter-play-store-release/scripts/bootstrap_android_fastlane.sh`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing transaction and signing tests.**

Cover new Groovy/Kotlin blocks, recognized stock Flutter debug-signing replacement, custom signing preservation/conflict, simultaneous debug+release rejection, missing key properties failing release tasks only, valid user-owned signing preservation, malformed/multiple markers, CRLF and file-mode preservation, spaces, dry-run zero writes, second-run no diff, and failure after each write restoring tracked/untracked bytes.

Assert `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` are connected once. The guard must inspect requested release-signing tasks so sync, inspection, and debug builds work without credentials.

```bash
bash flutter-play-store-release/tests/run_tests.sh project_transaction gradle_signing
```

Expected: nonzero before implementation.

- [ ] **Implement staged project transactions.**

Expose namespaced functions to register writes, preserve original existence/bytes/mode/line endings, create candidates in a private stage, validate before mutation, use same-directory atomic renames, and restore paths in reverse on failure/signal. Refuse physical paths outside the selected root. Do not use Git to restore, and never remove a pre-existing untracked file.

- [ ] **Implement conservative Gradle edits.**

Accept DSL, source, and optional flavor; output a candidate only. Recognize explicitly tested stock Flutter Groovy/Kotlin debug patterns. Insert one marked block only at a structurally verified `android` scope; otherwise conflict.

The block reads the nonsecret `ANDROID_KEY_PROPERTIES_PATH` when set, otherwise `android/key.properties`; validates the selected properties path, all four values, and keystore existence only for release bundle/assemble/publish task requests; creates `signingConfigs.release`; and assigns release only to it. Never retain or add a debug fallback. Test both override and fallback without printing property values.

- [ ] **Implement bootstrap planning and dry run.**

Inspect first. Classify every target as `create`, `update-owned`, `merge`, `preserve`, `skip-conflict`, or `fail-conflict`; print a deterministic sorted plan. `--conflict=fail` is default. `skip` preserves conflict paths but returns nonzero because setup is incomplete. Plan all conflicts before any write.

- [ ] **Verify and commit.**

```bash
bash -n flutter-play-store-release/scripts/lib/project_transaction.sh
bash -n flutter-play-store-release/scripts/lib/gradle_signing.sh
bash -n flutter-play-store-release/scripts/bootstrap_android_fastlane.sh
bash flutter-play-store-release/tests/run_tests.sh project_transaction gradle_signing bootstrap_core
git add flutter-play-store-release/scripts flutter-play-store-release/tests/run_tests.sh
git commit -m "add transactional Android release bootstrap"
```

Expected: injected failures report rollback and leave byte-identical fixtures.

---

## Task 5: Implement pinned Fastlane templates and release logic

**Files:**

- Modify: `flutter-play-store-release/templates/Gemfile`
- Modify: `flutter-play-store-release/templates/Gemfile.lock`
- Modify: `flutter-play-store-release/templates/Appfile`
- Modify: `flutter-play-store-release/templates/Fastfile`
- Create: `flutter-play-store-release/templates/FlutterPlayStoreRelease.rb`
- Modify: `flutter-play-store-release/templates/Pluginfile`
- Modify: `flutter-play-store-release/templates/env.example`
- Modify: `flutter-play-store-release/templates/key.properties.example`
- Create: `flutter-play-store-release/tests/fastlane_helper_test.rb`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing pure Ruby tests first.**

Use standard-library Minitest. Cover approved version shapes, normalization and precedence, one exact-HEAD tag, equivalent `v1.2.3`/`1.2.3` tags, conflicting exact tags, valid plus invalid exact tags, bounded positive codes, remote maximum across every track, successful empty tracks, failed track queries, all-tracks-empty first-release failure, upper bound, build-only fallbacks, target routing, Firebase disabled behavior, `AAB` and `APK` artifact discovery, secret precedence, invalid explicit-path hard failure, owned cleanup, explicit-path preservation, fresh/zero/multiple/stale/flavor-mismatch artifacts, JSON-safe Slack payload, and nonzero `PARTIAL_SUCCESS`.

```bash
ruby flutter-play-store-release/tests/fastlane_helper_test.rb
```

Expected: load failure before module implementation.

- [ ] **Pin dependencies and generate the lockfile.**

`Gemfile` intent:

```ruby
source "https://rubygems.org"
ruby ">= 3.2", "< 4.0"
gem "fastlane", "= 2.237.0"
plugins_path = File.join(__dir__, "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
```

`Pluginfile` intent:

```ruby
gem "fastlane-plugin-firebase_app_distribution", "= 1.0.0"
```

Generate `Gemfile.lock` in an isolated Android-shaped directory with the templates, add supported Linux/macOS platforms, and run `bundle check`. Commit the resolved lock; if dependency download is unavailable, stop instead of inventing it.

- [ ] **Implement version and artifact helpers.**

Accept only `v?MAJOR.MINOR.PATCH` plus approved dot-separated prerelease and return no leading `v`. Resolve option, environment, exact tags on HEAD, then pubspec. Normalize every supported exact tag; permit multiple tags only when they normalize to one version (for example `v1.2.3` and `1.2.3`), and fail on distinct valid versions or a mixed valid/invalid exact-tag set rather than choosing lexically. `play-store` and `both` query the selected track plus ordered unique `PLAY_STORE_VERSION_TRACKS`; a successful empty track contributes no codes, while any transport/auth/API failure is fatal. If all configured tracks are empty, fail with the first-release checklist rather than inventing a remote value. Call the result “next active-track code,” not “next unused code.” Firebase-only and build-only never query Play; they resolve `VERSION_CODE`, pubspec build number, then positive Git commit count. Enforce `1..2100000000` for every path and never use a timestamp.

Before invoking Flutter, move only relevant prior variant outputs into a private quarantine and record their paths. Artifact acceptance is the commit point: on command error, signal, zero/empty/multiple/mismatched post-build output, or any other pre-acceptance failure, remove only new candidates and restore every prior output. After exactly one candidate passes all checks, commit it and delete quarantined predecessors. The entrypoint is not encoded in an artifact path: assert separately that the build command received the selected `--target`, but never claim to infer it from the filesystem. Play always builds an AAB. Firebase-only accepts `FIREBASE_ANDROID_ARTIFACT_TYPE=AAB|APK` (default `AAB`) and runs the corresponding Flutter build. Firebase AAB requires `CONFIRM_FIREBASE_AAB_PLAY_LINKED=true` after the operator verifies the reviewed/published Play link and test-app signing certificate implications; APK does not. `both` requires `AAB`, reuses the Play artifact, and rejects `APK` because producing both formats would violate the build-once contract.

- [ ] **Implement secret and Slack helpers.**

Resolve explicit path, Base64, then default; invalid higher-precedence input fails. Generated files live under a `0700` per-run root with mode `0600` and ownership records. Validate service-account JSON structure without logging. Keep Play and Firebase accounts separate. A target matrix requires/resolves only Play credentials for `play-store`, only Firebase credentials for `firebase`, and both independently for `both`. CI requires its five signing/application secret values for every target; local release may instead use a complete valid user-owned `android/key.properties`. Play-only code never inspects Firebase credentials, and Firebase-only code never requires or queries a Play service account.

When local environment/path credential inputs are selected, generate a private mode-`0600` properties file under the owned temp root, set `ANDROID_KEY_PROPERTIES_PATH` only for the Gradle/Fastlane process, and point `storeFile` at the absolute explicit/decoded keystore. If no environment/path signing inputs are provided, local execution may use a valid pre-existing user-owned `android/key.properties` through the Gradle fallback and never delete it. CI always uses the temporary override and fails if a workspace `android/key.properties` already exists. Escape Java-properties metacharacters, backslashes, leading spaces, and Unicode correctly; reject NUL, newline, and other control characters with a redacted label. Test Base64 and explicit keystore sources, local fallback preservation, CI pre-existing-file refusal, special-character passwords/alias, and cleanup on every failure.

Generate Slack JSON with Ruby JSON and submit via `curl --data-binary @-`; webhook/payload never enters command arguments. Notification failure warns without replacing the lane result.

- [ ] **Implement Fastlane lanes.**

`doctor` emits `PASS`/`WARN`/`FAIL`; credentials warn for setup/build and fail before network for deploy. `prepare` runs pub get, conditional build_runner, analyze/tests flags. `build` always passes explicit name/code plus optional flavor/target and validates the newly produced requested artifact.

`release_play_store` runs deploy doctor, creates temporary secrets, prepares, resolves version, builds once, checks `APP_PACKAGE_NAME` against resolved release ID, and calls `upload_to_play_store` with `json_key`, `aab`, `package_name`, `track`, `release_status`, conditional `rollout`, `version_name`, `skip_upload_metadata: true`, `skip_upload_changelogs: true`, `skip_upload_images: true`, and `skip_upload_screenshots: true`. Use Ruby `begin ... ensure` for cleanup and a Fastlane `error` hook only for failure classification/notification. This skill uploads the binary/release only and never mutates the Play listing.

`firebase_distribution` delegates to the common router with target `firebase`; it therefore receives deploy doctor, Firebase-only credential resolution, Firebase-only local version code, APK/AAB build, selected release-package validation, and coordinator-wide cleanup. Require the selected release `applicationId` and `FIREBASE_APP_ID` to match one Firebase client mapping in `google-services.json`; when that file/evidence is absent, require explicit `CONFIRM_FIREBASE_PACKAGE_MATCH=true`, but never allow confirmation to override a detected package or app-ID mismatch. The upload adapter passes required `app`, `android_artifact_type`, absolute `android_artifact_path`, `service_credentials_file`, and exactly one release-notes source plus testers/groups to the current plugin action. `FIREBASE_RELEASE_NOTES` takes precedence over a documented generated default; never pass both `release_notes` and `release_notes_file`.

The public `release` router performs doctor → target-specific credential resolution → prepare → version resolution → one artifact build, then calls private upload-only helpers `upload_play_store` and/or `upload_firebase`. Delegate lanes must not duplicate prepare/build. Validated `DISTRIBUTION_TARGET=firebase|both` derives effective `ENABLE_FIREBASE_APP_DISTRIBUTION=true`; `play-store` derives false. When no target is explicit, the enable flag remains a configuration default. One coordinator-wide `begin ... ensure` owns all generated credentials through Play failure, Firebase failure, notification failure, and unexpected exceptions. For `both`, Play succeeds before Firebase is attempted; Firebase failure yields one `PARTIAL_SUCCESS` notification, never retries or rolls back Play, cleans all owned files, and terminates nonzero so CI cannot report full success.

When nonsecret `RELEASE_RESULT_PATH` is supplied, atomically write a schema-1 JSON result containing only status (`SUCCESS|FAILURE|PARTIAL_SUCCESS`), target, normalized version, track, artifact type/path, successful destinations, failed destination, and a redacted message. Write/update it before returning or raising, never include environment dumps/credential paths, and preserve the original exception if result writing fails. Local output prints the same fields; CI uses the file for summary/one Slack notification, while a missing file means failure before Fastlane started.

Support binary-upload statuses `completed`, `draft`, and `inProgress`. Reject `halted` with guidance because halting an existing release is an external rollout mutation outside this new-binary lane. Build upload options conditionally: `inProgress` requires a fraction strictly greater than `0` and less than `1`; `completed` and `draft` omit rollout. Require `CONFIRM_PRODUCTION_DEPLOY=true` for production.

Mock the Fastlane action adapters, not only pure helpers. Record that `google_play_track_version_codes` receives the same `json_key`/`package_name` and every unique track for Play/both but is never called for Firebase-only; `upload_to_play_store` receives `aab` rather than `aab_path` plus all four listing-skip flags as true; Firebase receives `app`, artifact type/path, credentials, notes, testers, and groups; detected package mismatch fails even with confirmation while absent evidence requires confirmation; every distribution target derives the correct Firebase enablement; direct `release`, `release_play_store`, and `firebase_distribution` lanes are discoverable/executable; delegates do not rebuild; `both` builds once; result JSON distinguishes success/failure/partial success without secret paths; failed preflight calls no network adapter; cleanup and notification ownership remain singular.

- [ ] **Verify Ruby, Bundler, lanes, and doctor.**

```bash
ruby -c flutter-play-store-release/templates/FlutterPlayStoreRelease.rb
ruby -c flutter-play-store-release/templates/Fastfile
ruby flutter-play-store-release/tests/fastlane_helper_test.rb
bash flutter-play-store-release/tests/run_tests.sh fastlane_templates
```

In an isolated generated fixture with dependencies:

```bash
cd fixture/android
BUNDLE_FROZEN=true bundle check
bundle exec fastlane lanes
bundle exec fastlane android doctor
```

Expected: syntax/tests pass; intentionally absent credentials produce structured warnings, not a stack trace; no external stub is called.

- [ ] **Commit.**

```bash
git add flutter-play-store-release/templates flutter-play-store-release/tests
git commit -m "implement pinned Fastlane Play release lanes"
```

---

## Task 6: Generate hardened GitHub Actions and verified Flutter installation

**Files:**

- Modify: `flutter-play-store-release/scripts/install_flutter_sdk.sh`
- Modify: `flutter-play-store-release/templates/release-android.yml`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing installer and workflow tests.**

Use a local manifest/archive/checksum. Cover exact version/channel/architecture, duplicate manifest matches, missing version, wrong architecture, hostile `base_url`, relative archive traversal, SHA mismatch, partial download, absolute/member-parent traversal, duplicate normalized member paths, escaping symlink/hardlink targets, devices/FIFOs/sockets, unsafe ownership/setuid/setgid metadata, signal cleanup, existing-destination preservation, extracted-version mismatch, and no extraction before verification.

Assert release `published` and typed manual triggers; `contents: read`; repository-wide `play-store-release` concurrency with `queue: max`; timeout; checkout by immutable `github.sha`; release-tag-to-HEAD verification including annotated/moved/mismatched tags; native manual dispatch ref without a custom mutable ref input; full action SHAs with release comments; no third-party Flutter action; official manifest installer; test mapping; fixed production/nonproduction environment routing; confirmation rejection before secrets; runner-temp secrets; target-specific credentials; Java-properties escaping; pre-existing project properties preservation; routed target; unconditional cleanup; and one Slack owner.

Add injection canaries for version, track, status, distribution target, release tag, and Firebase notes. No expression from `inputs`, release payload, or other untrusted context may be interpolated directly inside a `run:` block: map it to a step-local environment variable, quote it, and validate it first. Assert no `if: secrets.*`, workflow/job-level raw-secret environment, secret command argument, secret output/summary/artifact, or unowned workspace credential file.

```bash
bash flutter-play-store-release/tests/run_tests.sh flutter_sdk_installer workflow_template
```

Expected: nonzero before implementation.

- [ ] **Implement verified official SDK installation.**

Accept a strict version, channel allowlist, explicit architecture, new/empty destination, and the exact official Linux manifest `https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`. `--manifest-url` accepts `file://` only in test mode; production cannot replace the manifest/checksum trust root. Require the documented official `base_url`, a contained relative archive path, and exactly one version/channel/architecture match. Download with curl constrained to HTTPS for the initial URL and redirects, verify SHA-256, and use Python's archive metadata with a data-filter-equivalent policy before private extraction: unique normalized paths; no absolute/parent traversal; only regular files, directories, and contained symlink/hardlink targets; no devices, FIFOs, sockets, setuid/setgid, preserved uid/gid, or other special metadata. Verify `flutter/bin/flutter` and its reported framework version match the request, then atomically move. Cleanup partial files on error/signal and preserve an existing destination.

Resolve exact Flutter version in this order: validated manual `flutter_version` input, `.fvmrc`, `.flutter-version`, FVM config, then repository variable `FLUTTER_VERSION`. If none exists, preflight fails with the exact configuration command. Release events have no manual input and therefore require a project pin or repository variable. Never silently use the observed current stable. Workflow uses `--architecture x64` on `ubuntu-latest`.

- [ ] **Implement workflow inputs and trust boundaries.**

Manual inputs: `version_name`, `flutter_version`, `track`, `release_status`, `run_tests`, `distribution_target`, `firebase_artifact_type`, `firebase_release_notes`, `confirm_firebase_package_match`, `confirm_firebase_aab_play_linked`, and `confirm_production`. Do not add a custom ref input: the native workflow-dispatch ref supplies immutable event `github.sha`. Both release and manual events checkout `github.sha`. For release events, validate `github.event.release.tag_name` with `git check-ref-format`, dereference `refs/tags/<tag>^{commit}`, require that commit to equal `HEAD`, then use only the tag text as version name. Tests cover lightweight/annotated tags, moved tag, mismatch, invalid tag, and manual SHA.

Use the three baseline action SHAs, `fetch-depth: 0`, `persist-credentials: false`, Java 17, Ruby 3.3, Android-root Bundler caching, `BUNDLE_FROZEN=true`, and `BUNDLE_DEPLOYMENT=true`. Parse every non-local `uses:` and require exactly 40 lowercase hex characters; local actions must begin `./`. Any new cache/artifact action requires an independently reviewed full SHA and test.

Target-specific secret mapping:

```text
APP_PACKAGE_NAME
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

The signing five (`ANDROID_KEYSTORE_BASE64`, its three password/alias values, and `APP_PACKAGE_NAME`) are required for every target. `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` is required only for `play-store`/`both`. Firebase requires separate `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64` and `FIREBASE_APP_ID` only for `firebase`/`both`. Play-only steps never receive Firebase credentials; Firebase-only steps never receive Play JSON. Optional secret-backed values are exactly `SLACK_WEBHOOK_URL`, `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, and `FIREBASE_TESTERS`; Firebase release notes use the dispatch input then documented ordinary variable/default.

Scope Base64 JSON/keystore and signing password/alias secrets only to one narrow decode/properties step. Before decoding, fail if workspace `android/key.properties` exists; never overwrite, back up, or delete it. Decode under `$RUNNER_TEMP`, write the mode-`0600` properties file, then the release step receives only generated credential/keystore/properties paths and validated nonsecret inputs. It must not receive any Base64 value or signing password/alias. Only scalar secret-backed Firebase tester/group values genuinely consumed by the plugin may reach release; Slack webhook reaches only its notification step. Remove every runner-temp credential and any transaction-owned workspace file with `if: always()`. Add exact step-scope assertions for each secret.

Add an unprivileged rejection job that fails an unconfirmed production dispatch before any environment or secret-bearing job. Route confirmed production to fixed `play-store-production`; route every release and nonproduction manual run to fixed `play-store-nonproduction`. Document where each Environment's secrets must be configured. The workflow can assert routing but cannot prove reviewer/tag rules; documentation marks production Environment protection as a required external setup and final validation reports it unverified without repository-settings evidence.

Set `SLACK_NOTIFICATION_OWNER=github-actions` and `RELEASE_RESULT_PATH=$RUNNER_TEMP/release-result.json` in CI so Fastlane never duplicates notification. Local Fastlane defaults to owner `fastlane`. One `always()` workflow notification covers pre-Fastlane and lane failures, reads only validated nonsecret result fields when present, encodes JSON through the Ruby helper, and cannot replace the original job result. The job summary reports the same result/artifact path but no secrets. Invoke `bundle exec fastlane android release distribution_target:...` with validated, quoted, step-local inputs and always clean up.

- [ ] **Verify and commit.**

```bash
bash -n flutter-play-store-release/scripts/install_flutter_sdk.sh
bash flutter-play-store-release/tests/run_tests.sh flutter_sdk_installer workflow_template
git add flutter-play-store-release/scripts/install_flutter_sdk.sh flutter-play-store-release/templates/release-android.yml flutter-play-store-release/tests/run_tests.sh
git commit -m "add hardened Flutter Play release workflow"
```

Expected: all assertions and available YAML parsing pass; checksum/archive failures occur before extraction.

---

## Task 7: Complete transactional bootstrap and generated ownership

**Files:**

- Modify: `flutter-play-store-release/scripts/bootstrap_android_fastlane.sh`
- Modify: `flutter-play-store-release/scripts/lib/project_transaction.sh`
- Modify: all `flutter-play-store-release/templates/` files
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing full-bootstrap tests.**

Cover creation of every generated path, sidecar/body hashes including `Gemfile.lock`, safe update of unchanged owned files, edited-owned rejection, safe Fastfile/Pluginfile/Gemfile merge, duplicate/incompatible lane/plugin/`eval_gemfile` conflict, unowned workflow conflict, exact `.gitignore` patterns once, examples still committable, copied CI helpers, substitutions, active placeholders, deterministic dry run, second-run no diff, and rollback after every write.

Exercise four ownership classes: absent, verified owned, safely mergeable, unowned non-mergeable. Any conflict must cause zero project changes.

```bash
bash flutter-play-store-release/tests/run_tests.sh bootstrap_full
```

Expected: nonzero until template population exists.

- [ ] **Implement whole-file ownership hashing.**

Write `tool/flutter-play-store-release/managed-files.sha256` with package ID/schema plus deterministic path/hash records for every whole generated file. Comment-capable files may duplicate identity/hash in-file, but the sidecar is authoritative for `Gemfile.lock` and other tool-owned formats that cannot embed headers. Exclude the sidecar's own hash. Verify prior records before update; user-edited owned content conflicts. Normalize hashing identically on macOS/Linux without changing user line endings.

- [ ] **Implement safe merges.**

Create absent files; replace verified owned files; append one marked Android platform block only when existing Fastfile syntax is valid and required lane names are absent; add the pinned plugin only to safely parseable compatible Pluginfiles. For an existing `android/Gemfile`, require or safely add exact `gem "fastlane", "= 2.237.0"` and exactly one compatible `eval_gemfile` import of `android/fastlane/Pluginfile`; preserve equivalent declarations and stop on conflicting Fastlane constraints or duplicate/incompatible dynamic imports. Regenerate/verify the lock after a safe merge. Never overwrite an unowned workflow.

Merge these exact ignore lines without duplicates and never ignore examples:

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

Substitute validated non-secret package/flavor values only. If the release application ID is unresolved, put `CHANGE_ME_APPLICATION_ID` only in examples/docs, omit active upload configuration, and return actionable incomplete status.

- [ ] **Apply one validated transaction.**

Plan all outputs; stage all candidates; validate marker/hash/Ruby/YAML/shell/placeholder rules against the staged tree; then atomically install. Preserve mode and line endings. Keep recovery copies until post-write validation passes. On failure/signal restore prior files and remove only transaction-created paths.

- [ ] **Verify idempotency and commit.**

```bash
bash flutter-play-store-release/tests/run_tests.sh bootstrap_full
bash flutter-play-store-release/tests/run_tests.sh bootstrap_full
git add flutter-play-store-release/scripts flutter-play-store-release/templates flutter-play-store-release/tests/run_tests.sh
git commit -m "complete idempotent Flutter release bootstrap"
```

Expected: both pass; second invocation has no diff and injected failures restore exact fixtures.

---

## Task 8: Implement non-deploying setup validation and doctor parity

**Files:**

- Modify: `flutter-play-store-release/scripts/validate_release_setup.sh`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing validator tests.**

Cover project shape, inspection, required files, markers/hashes, YAML with/without parser, Ruby with/without Ruby, shell syntax, Groovy/Kotlin signing, release-to-debug, ignore entries/example exceptions, active placeholders, credential-shaped content, tracked secret names, optional tools, package mismatch, all contexts, and deterministic `PASS`/`WARN`/`FAIL`. In `doctor` context, prove `pubspec.lock`, `.dart_tool`, generated plugin files, and the full project tree are unchanged. Stub Flutter/Java/Ruby/Bundler/Git/Fastlane and every network tool. Validation must never invoke upload.

```bash
bash flutter-play-store-release/tests/run_tests.sh release_validator
```

Expected: nonzero before implementation.

- [ ] **Implement deterministic check collection.**

Collect named checks before output, then emit sorted human lines or one JSON object. Warnings alone exit zero; any failure exits one. Missing optional parser/tool is a warning with prerequisite and copy-ready command, never a fabricated pass. Argument/conflict errors remain status two.

- [ ] **Implement layered checks.**

Always run inspection, required path/marker/hash/ignore/placeholder/secret scans, and bundled shell syntax. `doctor` is the default read-only context: it may run read-only version/syntax/listing checks but never `flutter pub get`, analyze, tests, build, or any command that can write project/cache state; report those as not run with copy-ready commands. `--run-project-commands` is an explicit opt-in valid only with setup/build contexts. When authorized prerequisites exist, setup/build may run pub get/analyze and the documented matrix. Never upload. Report the real-project matrix as not run when no project is supplied.

Share check names/severities with Fastlane doctor for package ID, credential presence, signing, track, plugin, and toolchain. Deploy-context failures occur before any stubbed network adapter.

- [ ] **Verify and commit.**

```bash
bash -n flutter-play-store-release/scripts/validate_release_setup.sh
bash flutter-play-store-release/tests/run_tests.sh release_validator
git add flutter-play-store-release/scripts/validate_release_setup.sh flutter-play-store-release/tests/run_tests.sh
git commit -m "add safe Flutter release setup validation"
```

Expected: valid setup exits zero with warnings; hard failures exit one; no external marker exists.

---

## Task 9: Write the skill workflow and standalone operator documentation

**Files:**

- Modify: `flutter-play-store-release/SKILL.md`
- Modify: `flutter-play-store-release/README.md`
- Modify: `flutter-play-store-release/templates/PLAY_STORE_RELEASE.md`
- Modify: all files under `flutter-play-store-release/references/`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing documentation contract tests.**

Assert English-only runtime prose, eight modes, English equivalents of every supplied use case, Android-only scope, Claude slash/Codex dollar invocation, inspect-before-edit, authorization boundaries, generated paths, all 17 requested guide topics, commands, secret groups, macOS/Linux/PowerShell no-wrap Base64, encoding-not-encryption, first manual Play upload, Play App Signing/key backup, least privilege, current personal-account closed-test warning, rollback/promotion, Firebase AAB link/test certificate, Slack nonmasking, troubleshooting categories, and primary links.

Assert `SKILL.md` is under 500 lines, one-level reference routing, imperative voice, only `name`/`description` frontmatter, `## Quick start`, and `## Definition of done`.

```bash
bash flutter-play-store-release/tests/run_tests.sh documentation
```

Expected: nonzero until docs are complete.

- [ ] **Write concise cross-agent `SKILL.md`.**

Describe triggers, classification (`setup`, `doctor`, `build`, `deploy`, `ci`, `firebase-distribution`, `slack`, `repair`), inspection, authorization gate, execution, validation, and required completion headings. Link installed `references/execution-defaults.md`; mention the repository policy source in prose without an installed broken link.

Setup/build/doctor never imply upload. Explicit internal deploy authorizes only the named track after preflight. Production/promotion/key/console/secret mutations remain separately explicit.

- [ ] **Write README and generated project guide.**

README covers purpose, compatibility, install/update/uninstall, direct scripts, prompts, modes, safety, generated files, validation, limitations, and sources. `PLAY_STORE_RELEASE.md` covers the requested 17 topics with no repository-specific identifier.

GitHub configuration documents exact Flutter resolution precedence (`flutter_version` dispatch input → project pin → repository variable `FLUTTER_VERSION` → fail), the nonsecret `ANDROID_KEY_PROPERTIES_PATH`, `FIREBASE_ANDROID_ARTIFACT_TYPE`, and the production/nonproduction Environment names. It labels reviewer/tag protection as an external setting that file validation cannot prove.

GitHub Secrets groups:

- five signing/application values required for every target;
- Play-conditional `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` (making the original six-value set for Play);
- Firebase-conditional credential `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`;
- exactly four user-requested optional secret-backed values: `SLACK_WEBHOOK_URL`, `FIREBASE_APP_ID`, `FIREBASE_TESTER_GROUPS`, `FIREBASE_TESTERS`; `FIREBASE_APP_ID` becomes a required runtime value when a Firebase target is selected and may instead come from a documented nonsecret variable.

Release notes and flags are not secrets. `gh secret set SECRET_NAME` appears only as a user-run option.

- [ ] **Write references.**

The environment catalog records type, context, default, precedence, secrecy, validation, and owner for every variable, including `FLUTTER_VERSION`, `ANDROID_KEY_PROPERTIES_PATH`, `RELEASE_RESULT_PATH`, track lists, production/Firebase-package/Firebase-AAB confirmations, routing, Firebase artifact type/release-note precedence, separate Firebase credentials, and path > Base64 > default.

The first-release checklist separates Cloud API enablement, Play service-account invitation/app permissions, signing, upload-key backup, legal/app-content setup, first manual AAB, testers, internal/closed/production gates, and changing policy checks. Troubleshooting separates auth, permission, draft/new app, reused code, signing, stale artifacts, Firebase link, Slack, and CI runner/actions.

- [ ] **Verify and commit.**

```bash
bash flutter-play-store-release/tests/run_tests.sh documentation
python3 /Users/toris/.codex/skills/.system/skill-creator/scripts/quick_validate.py flutter-play-store-release
git add flutter-play-store-release/SKILL.md flutter-play-store-release/README.md flutter-play-store-release/templates/PLAY_STORE_RELEASE.md flutter-play-store-release/references flutter-play-store-release/tests/run_tests.sh
git commit -m "document Flutter Play release skill workflow"
```

Expected: pass; runtime package has no broken local link or machine-specific path.

---

## Task 10: Implement atomic dual-destination installation lifecycle

**Files:**

- Create: `flutter-play-store-release/scripts/lib/package_sync.sh`
- Modify: `flutter-play-store-release/install.sh`
- Modify: `flutter-play-store-release/update.sh`
- Modify: `flutter-play-store-release/uninstall.sh`
- Modify: `flutter-play-store-release/install-manifest.txt`
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing isolated-HOME tests.**

Cover initial install/update/dry-run/explicit source, both destinations, allowlisted files plus deterministic `.skill-install-receipt`, content/mode hashes, identical copies, unrelated directory and symlink refusal, source symlink, overlap, installed-copy self-update, missing/traversal/duplicate manifest entry, edited/missing installed manifest file, unexpected file/directory/symlink, lifecycle-lock contention/stale-lock ownership, and idempotency.

Cover crash/journal recovery after old-Claude rename, old-Agents rename, new-Claude install, new-Agents install, final validation, committed-before-cleanup, and each uninstall quarantine phase for initially absent, one-sided, identical, and divergent prior installs. Cover tampered transaction IDs/paths/basenames, uninstall first/second rename, and first/second quarantine-cleanup failures. Use catchable signals plus a killed test process followed by next-invocation recovery. Never use actual user global directories.

```bash
bash flutter-play-store-release/tests/run_tests.sh installation
```

Expected: nonzero before implementation.

- [ ] **Validate source, manifest, and destinations.**

Require a regular non-symlink source outside both destinations and valid package identity. Require sorted unique relative manifest entries, regular files, containment, and executable modes. Reject unrelated destinations and all destination symlinks. Copy allowlisted files only.

Each installed copy also gets a deterministic `.skill-install-receipt` containing package/schema and path/hash/mode records for every manifest file. Before update or uninstall, require the identity, receipt, hashes/modes, and exact tree (receipt is the only permitted non-manifest file). Refuse unexpected files, directories, symlinks, edits, or missing entries with zero mutation. The two receipts are byte-identical.

- [ ] **Implement two-phase install/update.**

Acquire one shared atomic lifecycle lock at `$HOME/.flutter-play-store-release-install-state/lock` for install/update/uninstall. Require the state root to be a non-symlink mode-`0700` directory owned by the current user with known entries only. Store an owner token, host, PID, and safe process identity; remove it only when the current token owns it. Refuse a live lock. Reclaim a same-host stale lock only after proving its recorded process is absent; otherwise report the manual verification path. A concurrent-process test must prove operations cannot interleave.

Create private stages and rollback directories inside each destination parent. Copy/hash both stages and generate receipts before mutation. Persist `$HOME/.flutter-play-store-release-install-state/transaction` atomically before the first rename and after every phase. Rename old installs to rollback names, install Claude then Agents copies, validate final manifests/receipts/cross-copy equality, then atomically record `committed` before cleanup. On catchable pre-commit failure restore both and return status three. On startup under the lock, a pre-commit journal restores the exact old state; a committed journal preserves/revalidates the new copies and only finishes rollback/stage cleanup. If either recovery cannot be proved, retain all evidence and stop with a recovery report. Delete journal, rollbacks, and empty state directory only after the corresponding recovery/cleanup completes.

The journal is a strict `key=value` file with only: `schema_version`, `package_id`, `transaction_id`, `operation`, `phase`, `claude_existed`, `claude_destination`, `claude_stage`, `claude_rollback`, `claude_quarantine`, `agents_existed`, `agents_destination`, `agents_stage`, `agents_rollback`, and `agents_quarantine`. Reject unknown/duplicate keys instead of sourcing the file as shell code. Before any recovery rename/delete, validate package/schema/transaction ID and require every nonempty stage/rollback/quarantine path to be under the exact corresponding destination parent with the transaction-specific generated basename. Install/update phases are `staged`, `claude_old_moved`, `agents_old_moved`, `claude_new_installed`, `agents_new_installed`, `validated`, `committed`; uninstall phases are `planned`, `claude_quarantined`, `agents_quarantined`, `committed`, `cleanup_complete`.

`install.sh` defaults to its physical package directory and accepts explicit source. `update.sh` requires `--source` and refuses either installed destination as canonical. Both support dry run.

- [ ] **Implement identity-checked uninstall.**

Require `--yes` for mutation. Both absent is an idempotent success; one present valid copy may be removed, but every present destination must pass exact receipt/tree validation before any change. Rename all present copies to transaction-specific quarantines and atomically record uninstall `committed`; that is the commit point. Failures before it restore all renamed destinations. After commit, quarantine deletion is best-effort cleanup rather than rollback: retain journal/path evidence for any undeleted quarantine, never claim the removed installation was restored, and let a later locked invocation preserve the absent destinations while finishing cleanup. Never remove canonical or unrelated content.

- [ ] **Verify and commit.**

```bash
bash -n flutter-play-store-release/scripts/lib/package_sync.sh
bash -n flutter-play-store-release/install.sh
bash -n flutter-play-store-release/update.sh
bash -n flutter-play-store-release/uninstall.sh
bash flutter-play-store-release/tests/run_tests.sh installation
git add flutter-play-store-release/install.sh flutter-play-store-release/update.sh flutter-play-store-release/uninstall.sh flutter-play-store-release/install-manifest.txt flutter-play-store-release/scripts/lib/package_sync.sh flutter-play-store-release/tests/run_tests.sh
git commit -m "add atomic global skill installation"
```

Expected: lock, receipt, phase-fault, killed-process recovery, and uninstall-quarantine tests all pass without a split installation or silent data loss.

---

## Task 11: Integrate the seventh skill with the repository

**Files:**

- Modify: `scripts/validate_skills.py`
- Modify: `README.md`
- Modify: `CONTRIBUTING.md` only if package-test guidance is needed
- Modify: `flutter-play-store-release/tests/run_tests.sh`

- [ ] **Write failing repository expectations.**

Require the root introduction/count/table/install loop/prompt/tree/validation examples to name `flutter-play-store-release`. Require the validator to expect exactly seven skills and allow this standalone package's local execution policy without weakening policy-link checks for the existing six.

```bash
bash flutter-play-store-release/tests/run_tests.sh repository_integration
python3 scripts/validate_skills.py
```

Expected: failure while repository still expects six.

- [ ] **Update repository validation narrowly.**

Add the skill to `EXPECTED`; retain unexpected top-level rejection. Existing six require `../shared-references/execution-defaults.md`; the standalone skill requires `references/execution-defaults.md`. Extend runtime scans to relevant shell/Ruby/YAML/properties/Gemfile content while excluding Git, generated fixtures, and historical `docs/superpowers` records.

Validate executable scripts, sorted contained manifest, English runtime docs, unfinished markers, machine-home paths, active unsafe placeholders, and obvious private-key/service-account signatures. Avoid false positives for documented variable names and example placeholders.

- [ ] **Update root documentation.**

Change six to seven; add row, install loop entry, personal prompt, structure tree entry, standalone installer explanation, and package test command. Preserve existing six skill descriptions.

- [ ] **Verify and commit.**

```bash
python3 scripts/validate_skills.py
bash flutter-play-store-release/tests/run_tests.sh repository_integration documentation package_contract
python3 /Users/toris/.codex/skills/.system/skill-creator/scripts/quick_validate.py flutter-play-store-release
git add README.md CONTRIBUTING.md scripts/validate_skills.py flutter-play-store-release/tests/run_tests.sh
git commit -m "integrate Flutter Play release skill"
```

Expected: `Validated 7 skills successfully.` and all package checks pass. Do not add unchanged `CONTRIBUTING.md`.

---

## Task 12: Run full safety, fixture, and forward-use verification

**Files:**

- Modify only the smallest affected implementation/test/doc files when a new failing regression test justifies it
- Do not retain generated fixtures or secret material

- [ ] **Run all package tests in a clean environment.**

```bash
env -i HOME="$HOME" PATH="$PATH" LANG=C LC_ALL=C \
  bash flutter-play-store-release/tests/run_tests.sh
```

Expected: every named group passes with zero external-contact markers.

- [ ] **Run syntax, dependency, and repository checks.**

```bash
find flutter-play-store-release -type f -name '*.sh' -exec bash -n {} \;
ruby -c flutter-play-store-release/templates/Fastfile
ruby -c flutter-play-store-release/templates/FlutterPlayStoreRelease.rb
ruby flutter-play-store-release/tests/fastlane_helper_test.rb
python3 scripts/validate_skills.py
python3 /Users/toris/.codex/skills/.system/skill-creator/scripts/quick_validate.py flutter-play-store-release
```

Expected: all pass. In a disposable generated project, also run `BUNDLE_FROZEN=true bundle check`, `bundle exec fastlane lanes`, and build-context doctor when pinned dependencies are installed. Run `actionlint` when available; otherwise record it as not run with its installation command.

- [ ] **Run hygiene and security scans.**

```bash
git diff --check
git status --short
rg -n 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|"private_key"\s*:\s*"-----BEGIN|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[0-9A-Za-z]{20,}' flutter-play-store-release
python3 -c 'import pathlib,re; p=pathlib.Path("flutter-play-store-release/templates/release-android.yml"); refs=re.findall(r"uses:\s*([^\s#]+)",p.read_text()); bad=[r for r in refs if not (r.startswith("./") or re.fullmatch(r"[^@]+@[0-9a-f]{40}",r))]; raise SystemExit(f"mutable action refs: {bad}" if bad else 0)'
rg -n '/Users/|set -x|GITHUB_ENV|GITHUB_OUTPUT' flutter-play-store-release
```

Expected: no credential/key, floating action, runtime machine path, tracing, or workflow secret-output use. Manually review expected documentation statements about forbidden output files.

- [ ] **Forward-test with fresh agents.**

Use three isolated reviewers:

1. follow only `SKILL.md` against a disposable minimal Groovy project for setup/doctor;
2. follow it against Kotlin flavors and ambiguous application IDs for conflict safety;
3. audit deploy/Firebase/Slack/workflow paths for unrequested mutation or leakage.

Give each reviewer only the skill and fixture request. For every misunderstanding, classify instruction versus implementation defect, add a failing regression test, fix minimally, then rerun focused and full suites.

- [ ] **Re-check primary sources.**

Confirm current Fastlane/plugin releases and parameters, Flutter AAB/version behavior, GitHub workflow/concurrency/action releases, Play onboarding/version/service-account/target-API/personal-account guidance, and Firebase linking. Update pins only with stable primary evidence and rerun affected tests.

- [ ] **Audit design/request coverage and interface consistency.**

Map each approved design heading and each numbered original requirement to at least one runtime/doc file and passing test. Check every stable path, command signature, environment variable, report heading, action parameter, and default across skill, README, references, shell, Ruby, workflow, and tests. Do not retain a temporary mapping unless useful as durable docs.

- [ ] **Commit verification fixes only when present.**

```bash
git add <only-affected-files>
git commit -m "harden Flutter Play release skill verification"
```

Do not create an empty commit.

---

## Task 13: Install verified copies and publish

**Files:**

- Create via the authorized installer:
  - `~/.claude/skills/flutter-play-store-release/`
  - `~/.agents/skills/flutter-play-store-release/`
- Modify repository only if final verification exposes a defect

- [ ] **Confirm repository readiness.**

```bash
git status --short --branch
python3 scripts/validate_skills.py
bash flutter-play-store-release/tests/run_tests.sh
```

Expected: clean tracked state, intended commits only, seven skills, all tests passing.

- [ ] **Preview and perform the approved installation.**

```bash
flutter-play-store-release/install.sh --source "$PWD/flutter-play-store-release" --dry-run
flutter-play-store-release/install.sh --source "$PWD/flutter-play-store-release"
```

Expected: only the two exact global destinations are changed; no symlink.

- [ ] **Verify manifest and copy equality.**

Reuse a read-only `package_sync.sh verify` operation or an equivalent receipt/manifest verifier. For every entry compare canonical/Claude/Agents hashes and modes, accept only the deterministic receipt as installation metadata, reject all other extras, validate identity, and prove installed copies (including receipts) equal each other. Tests must be absent globally and no recovery journal/quarantine may remain.

- [ ] **Smoke-test installed entrypoints read-only.**

Run supported `--help` commands and both installed inspectors against a disposable non-Flutter fixture. Usage/help succeeds; rejection is clear; no actual project or external state changes.

- [ ] **Push and verify public parity.**

```bash
git status --short
git log --oneline --decorate -15
git push origin main
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

Expected: local `HEAD` equals `origin/main`.

- [ ] **Prepare the completion report with exact headings.**

```text
Global skill installation result
Created skill files
Current Flutter project changes
Detected project information
Values the user must prepare
Local validation commands
GitHub Secrets
Deployment commands
Validation results
Cautions
```

Retain `created`, `modified`, `preserved`, and `backup` subgroups for project changes; retain `PASS`, `WARN`, `FAIL`, and `not run` for validation. Use `N/A` rather than omit fields because no Flutter project was supplied. State that no Play, Firebase, Slack, GitHub-secret, or production mutation occurred. Include canonical/global paths, Claude/Codex invocations, required values, local build/internal deploy commands, GitHub Release/manual behavior, first-upload warning, upload-key backup, and production gate.

---

## Final acceptance matrix

Do not complete implementation until every row has evidence:

| Area | Evidence |
|---|---|
| Package completeness | manifest contract and official skill validator |
| Cross-agent usability | `SKILL.md`, OpenAI metadata, three forward-use reviews |
| Inspection | Groovy/Kotlin/flavor/monorepo/redaction fixtures |
| Idempotency | second bootstrap produces no diff |
| Project safety | every injected failure restores bytes, modes, and existence |
| Signing | no debug fallback; missing inputs fail release tasks only |
| Fastlane | Ruby tests, syntax, lock, lanes, and doctor |
| Version/artifact | exact-tag ambiguity, mixed tracks, bounds, quarantine, multiple AAB/APK tests |
| CI | parsed YAML, immutable pins, serialized queue, exact environment routing; repository protection is externally verified or explicitly not run |
| Secrets | binary codecs, `0600`, cleanup, ownership, log scan |
| Integrations | separate Firebase credentials, routing, partial success, one Slack owner |
| Installation | isolated HOME tests, lock/journal crash recovery, receipt checks, and real manifest equality |
| Repository | exactly seven skills and clean scans |
| External safety | stubs prove no Play/Firebase/Slack/GitHub-secret contact |
| Publication | local `HEAD` equals `origin/main` |
