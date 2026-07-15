---
name: flutter-play-store-release
description: Inspect and configure safe Flutter Android delivery through Fastlane and GitHub Actions for Google Play, with optional Firebase App Distribution and Slack notifications. Use when preparing, validating, repairing, or deploying a Flutter app's Android release workflow.
---

# Flutter Play Store Release

Inspect the Flutter project before changing release configuration. Keep external uploads, secret changes, and notifications behind explicit user authorization.

## Quick start

1. Invoke $flutter-play-store-release with the Flutter project and desired release outcome.
2. Inspect the existing Android, Fastlane, workflow, signing, and tool configuration.
3. Select the narrowest safe action, preview proposed changes, and confirm any external write.
4. Use the bundled scripts, templates, and references for deterministic project work.

## Definition of done

- Validate the resulting Android release setup with the available local tools.
- Preserve unrelated project files and existing compatible configuration.
- Report created, modified, and preserved files plus any blocked or unverified checks.
- Perform no Google Play, Firebase, Slack, GitHub secret, or deployment write without explicit authorization.
