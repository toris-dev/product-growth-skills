#!/usr/bin/env bash
# Run the canonical package contract and later skill-specific test groups.

set -u

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_ROOT=$(CDPATH= cd -- "$TESTS_DIR/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flutter-play-store-release-tests.XXXXXX") || {
  printf 'FAIL: could not create a temporary test directory\n' >&2
  exit 1
}

cleanup() {
  rm -rf -- "$TMP_ROOT"
}

trap cleanup EXIT HUP INT TERM

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  relative_path=$1
  [ -f "$PACKAGE_ROOT/$relative_path" ] || fail "missing target: $relative_path"
  [ -s "$PACKAGE_ROOT/$relative_path" ] || fail "empty target: $relative_path"
}

assert_executable() {
  relative_path=$1
  [ -x "$PACKAGE_ROOT/$relative_path" ] || fail "entrypoint is not executable: $relative_path"
}

assert_contains() {
  relative_path=$1
  expected=$2
  grep -F -- "$expected" "$PACKAGE_ROOT/$relative_path" >/dev/null 2>&1 ||
    fail "$relative_path does not contain: $expected"
}

assert_same_file() {
  expected=$1
  actual=$2
  description=$3

  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" >&2 || true
    fail "$description"
  fi
}

write_target_files() {
  cat > "$TMP_ROOT/target-files.txt" <<'FILES'
.skill-package-id
README.md
SKILL.md
agents/openai.yaml
install-manifest.txt
install.sh
references/environment-variables.md
references/execution-defaults.md
references/first-release-checklist.md
references/troubleshooting.md
scripts/bootstrap_android_fastlane.sh
scripts/decode_secret.sh
scripts/encode_secret.sh
scripts/inspect_flutter_project.sh
scripts/install_flutter_sdk.sh
scripts/lib/common.sh
scripts/lib/gradle_signing.sh
scripts/lib/package_sync.sh
scripts/lib/project_transaction.sh
scripts/validate_release_setup.sh
templates/Appfile
templates/Fastfile
templates/FlutterPlayStoreRelease.rb
templates/Gemfile
templates/Gemfile.lock
templates/PLAY_STORE_RELEASE.md
templates/Pluginfile
templates/env.example
templates/key.properties.example
templates/release-android.yml
tests/fastlane_helper_test.rb
tests/run_tests.sh
uninstall.sh
update.sh
FILES
}

write_expected_manifest() {
  cat > "$TMP_ROOT/expected-manifest.txt" <<'FILES'
.skill-package-id
README.md
SKILL.md
agents/openai.yaml
install-manifest.txt
install.sh
references/environment-variables.md
references/execution-defaults.md
references/first-release-checklist.md
references/troubleshooting.md
scripts/bootstrap_android_fastlane.sh
scripts/decode_secret.sh
scripts/encode_secret.sh
scripts/inspect_flutter_project.sh
scripts/install_flutter_sdk.sh
scripts/lib/common.sh
scripts/lib/gradle_signing.sh
scripts/lib/package_sync.sh
scripts/lib/project_transaction.sh
scripts/validate_release_setup.sh
templates/Appfile
templates/Fastfile
templates/FlutterPlayStoreRelease.rb
templates/Gemfile
templates/Gemfile.lock
templates/PLAY_STORE_RELEASE.md
templates/Pluginfile
templates/env.example
templates/key.properties.example
templates/release-android.yml
uninstall.sh
update.sh
FILES
}

package_contract() {
  write_target_files

  while IFS= read -r relative_path; do
    assert_file "$relative_path"
  done < "$TMP_ROOT/target-files.txt"

  printf '%s\n' \
    'package_id=flutter-play-store-release' \
    'schema_version=1' > "$TMP_ROOT/expected-package-id"
  assert_same_file \
    "$TMP_ROOT/expected-package-id" \
    "$PACKAGE_ROOT/.skill-package-id" \
    '.skill-package-id must contain the canonical package ID and schema only'

  cat > "$TMP_ROOT/expected-openai.yaml" <<'YAML'
interface:
  display_name: "Flutter Play Store Release"
  short_description: "Automate safe Flutter releases to Google Play"
  default_prompt: "Use $flutter-play-store-release to inspect this Flutter app, configure safe Android delivery, and verify the Google Play release setup."
YAML
  assert_same_file \
    "$TMP_ROOT/expected-openai.yaml" \
    "$PACKAGE_ROOT/agents/openai.yaml" \
    'agents/openai.yaml does not match the canonical interface metadata'

  [ "$(sed -n '1p' "$PACKAGE_ROOT/SKILL.md")" = '---' ] ||
    fail 'SKILL.md must start with YAML frontmatter'
  [ "$(sed -n '2p' "$PACKAGE_ROOT/SKILL.md")" = 'name: flutter-play-store-release' ] ||
    fail 'SKILL.md frontmatter must declare the canonical name first'
  description_line=$(sed -n '3p' "$PACKAGE_ROOT/SKILL.md")
  case "$description_line" in
    'description: '[A-Za-z]*) ;;
    *) fail 'SKILL.md frontmatter must contain an English description second' ;;
  esac
  if LC_ALL=C printf '%s\n' "$description_line" | grep '[^ -~]' >/dev/null 2>&1; then
    fail 'SKILL.md frontmatter description must use English ASCII text'
  fi
  [ "$(sed -n '4p' "$PACKAGE_ROOT/SKILL.md")" = '---' ] ||
    fail 'SKILL.md frontmatter may contain only name and description'
  assert_contains 'SKILL.md' '## Quick start'
  assert_contains 'SKILL.md' '## Definition of done'

  unfinished_pattern='TO''DO|TB''D|FIX''ME|PLACE''HOLDER'
  while IFS= read -r relative_path; do
    if grep -E "$unfinished_pattern" "$PACKAGE_ROOT/$relative_path" >/dev/null 2>&1; then
      fail "unfinished marker found in target: $relative_path"
    fi
  done < "$TMP_ROOT/target-files.txt"

  for relative_path in \
    install.sh \
    update.sh \
    uninstall.sh \
    scripts/inspect_flutter_project.sh \
    scripts/bootstrap_android_fastlane.sh \
    scripts/validate_release_setup.sh \
    scripts/encode_secret.sh \
    scripts/decode_secret.sh \
    scripts/install_flutter_sdk.sh \
    tests/run_tests.sh
  do
    assert_executable "$relative_path"
  done

  write_expected_manifest
  assert_same_file \
    "$TMP_ROOT/expected-manifest.txt" \
    "$PACKAGE_ROOT/install-manifest.txt" \
    'install-manifest.txt must list every runtime file in lexical order'

  LC_ALL=C sort "$PACKAGE_ROOT/install-manifest.txt" > "$TMP_ROOT/sorted-manifest.txt"
  assert_same_file \
    "$TMP_ROOT/sorted-manifest.txt" \
    "$PACKAGE_ROOT/install-manifest.txt" \
    'install-manifest.txt is not sorted lexically'

  LC_ALL=C sort -u "$PACKAGE_ROOT/install-manifest.txt" > "$TMP_ROOT/unique-manifest.txt"
  assert_same_file \
    "$TMP_ROOT/unique-manifest.txt" \
    "$PACKAGE_ROOT/install-manifest.txt" \
    'install-manifest.txt contains duplicate entries'

  if grep -E '(^|/)(tests|fixtures)(/|$)' "$PACKAGE_ROOT/install-manifest.txt" >/dev/null 2>&1; then
    fail 'install-manifest.txt must exclude tests and fixtures'
  fi

  if grep -E '(^|/)(\.git|\.svn|\.hg|\.idea|\.vscode|__pycache__|\.pytest_cache|\.dart_tool|node_modules|build|dist)(/|$)|(^|/)\.env($|\.)|(^|/)[^/]*(\.jks|\.keystore|\.p12|\.pem|\.key)$' "$PACKAGE_ROOT/install-manifest.txt" >/dev/null 2>&1; then
    fail 'install-manifest.txt contains VCS, cache, editor, generated, or secret-shaped paths'
  fi

  while IFS= read -r relative_path; do
    case "$relative_path" in
      *.sh) bash -n "$PACKAGE_ROOT/$relative_path" || fail "invalid shell syntax: $relative_path" ;;
    esac
  done < "$TMP_ROOT/target-files.txt"

  pass 'package_contract'
}

case "${1:-all}" in
  all|package_contract)
    package_contract
    ;;
  *)
    fail "unknown test group: $1"
    ;;
esac
