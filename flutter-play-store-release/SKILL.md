---
name: flutter-play-store-release
description: Inspect, configure, validate, repair, build, and safely operate Flutter Android delivery through Fastlane and GitHub Actions for Google Play, Firebase App Distribution, and Slack.
---

# Flutter Play Store Release

Operate the Android release path of a Flutter project. Treat this skill as Android only; exclude iOS and App Store work. Write runtime documentation and configuration in English, then report results in the user's language.

## Quick start

1. Invoke `/flutter-play-store-release` in Claude Code or `$flutter-play-store-release` in Codex.
2. Identify the Flutter project root and the user's requested outcome.
3. Inspect before editing. Run `scripts/inspect_flutter_project.sh --project PATH --format human` from this skill's installed directory.
4. Classify the request into one mode and apply the narrowest authorized workflow.
5. Validate locally and report what changed, what passed, what remains unverified, and what only the user can do.

## Triggers

Use this skill for requests equivalent to:

- Set up Android release automation.
- Check whether this Flutter app is ready for Google Play.
- Build an Android App Bundle without uploading it.
- Deploy this build to the named Google Play track.
- Configure the Android release workflow in GitHub Actions.
- Distribute this Android build with Firebase App Distribution.
- Add Slack release notifications.
- Repair the existing Android release setup.

Do not use this skill for iOS delivery, general Flutter feature work, Play listing copy, or unrequested console administration.

## Classification

Select exactly one primary mode. Treat supporting checks as part of that mode.

| Mode | Use it for | External delivery |
| --- | --- | --- |
| `setup` | Install or merge Fastlane, signing hooks, workflow, tools, and project guidance. | None. |
| `doctor` | Read and validate the existing release setup. | None. |
| `build` | Produce and verify a local signed AAB without upload. | None. |
| `deploy` | Upload one verified AAB to the explicitly named Play track. | Google Play only. |
| `ci` | Configure or repair the generated GitHub Actions workflow. | None during configuration. |
| `firebase-distribution` | Configure Firebase delivery or, when explicitly requested, distribute to named testers or groups. | Firebase only. |
| `slack` | Configure notifications or test a webhook when explicitly requested. | Slack only. |
| `repair` | Reconcile owned files while preserving user-owned configuration. | None unless separately requested. |

A `setup`, `doctor`, `build`, `ci`, `firebase-distribution`, `slack`, or `repair` request never authorizes a Play upload. Do not upload from those modes.

## Inspect

Inspect before editing.

```bash
SKILL_ROOT=/path/to/installed/flutter-play-store-release
"$SKILL_ROOT/scripts/inspect_flutter_project.sh" --project PATH --format human
"$SKILL_ROOT/scripts/bootstrap_android_fastlane.sh" --project PATH --dry-run
```

Confirm the project contains `pubspec.yaml`, `android/`, and `android/app/`. Review the Gradle DSL, application ID, namespace, version sources, signing state, flavors, entrypoints, Firebase mapping, Fastlane files, workflow, Git state, and every proposed path. Never infer a release flavor or package name when inspection cannot resolve it.

Classify each proposed target as create, update-owned, merge, preserve, skip-conflict, or fail-conflict. Preserve unrelated changes. Stop on an ambiguous user-owned signing or release configuration and explain the conflict.

Read [execution defaults](references/execution-defaults.md) before acting. The canonical repository also maintains a repository-wide execution-defaults policy; mention it when working from the source checkout, but do not create an installed link back into that repository.

## Authorization gate

Proceed without another prompt for read-only inspection, an authorized local setup or repair, and local validation that stays within the supplied project.

Require an explicit request before any of these actions:

- Upload to Google Play, Firebase, or another external service.
- Promote a release, change a rollout, or target `production`.
- Create or change GitHub secrets, repository variables, Environment rules, accounts, permissions, billing, or legal declarations.
- Create, replace, reset, export, or delete an upload key, app-signing key, service-account key, or webhook.
- Create the first Play Console release or change console-only app content.
- Send a Slack message.

Interpret an explicit internal deploy as authorization for only the named internal track after preflight passes. Do not extend it to another track, promotion, staged rollout, Firebase, Slack, or production. Require `CONFIRM_PRODUCTION_DEPLOY=true` in addition to a separately explicit production request.

Never create a populated `.env`, `android/key.properties`, keystore, service-account JSON, or GitHub secret unless the user explicitly requests that exact mutation. Inspect credential presence without printing values. Never enable shell tracing while secrets may be present.

## Execute

### Setup or repair

Preview the complete plan, then apply it only when conflicts are resolved.

```bash
"$SKILL_ROOT/scripts/bootstrap_android_fastlane.sh" --project PATH --dry-run
"$SKILL_ROOT/scripts/bootstrap_android_fastlane.sh" --project PATH --conflict fail
```

Use `--flavor NAME` only after the release flavor is confirmed. Use `--conflict skip` only when the user accepts an incomplete nonzero result. Review the generated paths:

- `android/Gemfile` and `android/Gemfile.lock`
- `android/fastlane/Appfile`, `Fastfile`, `Pluginfile`, `.env.example`, and `lib/flutter_play_store_release.rb`
- `android/key.properties.example`
- `.github/workflows/release-android.yml`
- `docs/PLAY_STORE_RELEASE.md`
- `tool/flutter-play-store-release/decode_secret.sh`, `install_flutter_sdk.sh`, and `managed-files.sha256`

### Doctor

Run read-only validation by default.

```bash
"$SKILL_ROOT/scripts/validate_release_setup.sh" --project PATH --context doctor --format human
```

Do not add `--run-project-commands` to doctor. Treat `PASS`, `WARN`, and `FAIL` literally. Report absent credentials as readiness findings, not as permission to create them.

### Build

Obtain authorization before running project commands that may write caches or build output.

```bash
"$SKILL_ROOT/scripts/validate_release_setup.sh" --project PATH --context build --run-project-commands
cd PATH/android
bundle install
bundle exec fastlane android doctor
bundle exec fastlane android build
```

Verify exactly one fresh, nonempty artifact and its version, flavor, package, signing, and target. Do not upload.

### Deploy

Confirm the named track and target, then run deploy-context validation before network access.

```bash
"$SKILL_ROOT/scripts/validate_release_setup.sh" --project PATH --context deploy
cd PATH/android
bundle install
bundle exec fastlane android doctor
PLAY_STORE_TRACK=internal bundle exec fastlane android release_play_store
```

Replace `internal` only with the track the user explicitly named. Stop before network access on failed package, signing, credential, track, artifact, or version checks. Never claim deployment from a successful build alone.

### CI, Firebase, and Slack

For `ci`, configure the generated workflow and document the fixed GitHub Environments `play-store-nonproduction` and `play-store-production`. Leave reviewer and tag protection as an external, unverified repository setting.

For `firebase-distribution`, keep Firebase credentials separate from Play credentials. Require a matching Firebase application and, for AAB delivery, a reviewed Play link plus `CONFIRM_FIREBASE_AAB_PLAY_LINKED=true`. An AAB link confirmation does not authorize a Play release.

For `slack`, keep `SLACK_NOTIFICATION_OWNER` single-owner. Make notification failures warnings that never replace the build or delivery result. Do not test a webhook without explicit authorization to send a message.

Use [environment variables](references/environment-variables.md), [first release checklist](references/first-release-checklist.md), and [troubleshooting](references/troubleshooting.md) for detailed operator decisions.

## Validate

Run the narrowest relevant checks, then expand only as needed.

```bash
bash -n "$SKILL_ROOT/scripts/inspect_flutter_project.sh"
bash -n "$SKILL_ROOT/scripts/bootstrap_android_fastlane.sh"
bash -n "$SKILL_ROOT/scripts/validate_release_setup.sh"
"$SKILL_ROOT/scripts/validate_release_setup.sh" --project PATH --context doctor
```

When setup or build execution is authorized, add `--context setup|build --run-project-commands`. When credentials or platform access are absent, record those checks as not verified. Do not convert an unrun check into a pass.

## Completion report

Return these headings:

- **Changed:** List created, merged, modified, and preserved paths.
- **Verified:** List exact commands and observed results.
- **Not verified:** List missing access, credentials, platform state, or project prerequisites.
- **Your action:** List only steps that require the user, such as secret entry, console review, first manual upload, or production approval.

Never report a Play, Firebase, or Slack action as successful unless its adapter returned success and the final result preserved that outcome.

## Definition of done

- Keep work inside the selected Android release mode and authorization boundary.
- Preserve user-owned configuration and unrelated changes.
- Leave no plaintext credential, generated secret file, stale artifact, or temporary signing material behind.
- Validate owned files, application identity, signing, versions, artifacts, and selected integrations to the extent available.
- Report every external action, skipped check, warning, failure, and remaining user step accurately.
