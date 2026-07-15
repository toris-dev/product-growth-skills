# Flutter Play Store Release

This directory is the canonical standalone package for inspecting, configuring, and validating Flutter Android delivery through Fastlane and GitHub Actions.

## Package scope

The package targets Google Play releases, with optional Firebase App Distribution and Slack notifications. It excludes iOS and App Store workflows. Runtime files are explicitly allowlisted in install-manifest.txt; canonical tests and generated fixtures stay outside installed copies.

## Safety boundary

Local inspection and validation are the default. Play uploads, Firebase distribution, Slack notifications, GitHub secret changes, and other external writes require explicit user authorization.
