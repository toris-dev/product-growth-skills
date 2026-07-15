#!/usr/bin/env bash
# Run the canonical package contract and skill-specific test groups.

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
  [ ! -L "$PACKAGE_ROOT/$relative_path" ] || fail "target must not be a symlink: $relative_path"
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

assert_empty_file() {
  actual=$1
  description=$2

  [ ! -s "$actual" ] || fail "$description"
}

assert_mode() {
  expected=$1
  actual_path=$2
  description=$3
  actual_mode=

  if actual_mode=$(stat -c '%a' "$actual_path" 2>/dev/null) &&
    case "$actual_mode" in *[!0-7]*|'') false ;; *) true ;; esac
  then
    :
  elif actual_mode=$(stat -f '%Lp' "$actual_path" 2>/dev/null) &&
    case "$actual_mode" in *[!0-7]*|'') false ;; *) true ;; esac
  then
    :
  else
    fail "could not determine file mode for $description"
  fi

  [ "$actual_mode" = "$expected" ] ||
    fail "$description (expected $expected, got $actual_mode)"
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

inventory_package_files() {
  if ! (
    CDPATH= cd -- "$PACKAGE_ROOT" &&
      find . \( -type f -o -type l \) -print
  ) > "$TMP_ROOT/package-files-with-prefix.txt"; then
    fail 'could not inventory canonical package files'
  fi

  sed 's#^\./##' "$TMP_ROOT/package-files-with-prefix.txt" |
    LC_ALL=C sort > "$TMP_ROOT/actual-package-files.txt"

  # Runtime-generated fixtures are canonical-only test data, not package targets.
  grep -v '^tests/fixtures/' "$TMP_ROOT/actual-package-files.txt" \
    > "$TMP_ROOT/actual-declared-files.txt"
  LC_ALL=C sort -u "$TMP_ROOT/target-files.txt" \
    > "$TMP_ROOT/expected-declared-files.txt"

  missing_path=$(LC_ALL=C comm -23 \
    "$TMP_ROOT/expected-declared-files.txt" \
    "$TMP_ROOT/actual-declared-files.txt" | sed -n '1p')
  [ -z "$missing_path" ] || fail "missing target: $missing_path"

  unexpected_path=$(LC_ALL=C comm -13 \
    "$TMP_ROOT/expected-declared-files.txt" \
    "$TMP_ROOT/actual-declared-files.txt" | sed -n '1p')
  [ -z "$unexpected_path" ] || fail "unexpected package file: $unexpected_path"

  grep -v '^tests/' "$TMP_ROOT/actual-package-files.txt" \
    > "$TMP_ROOT/actual-runtime-files.txt"
}

package_contract() {
  write_target_files

  while IFS= read -r relative_path; do
    assert_file "$relative_path"
  done < "$TMP_ROOT/target-files.txt"
  inventory_package_files

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

  assert_same_file \
    "$TMP_ROOT/actual-runtime-files.txt" \
    "$PACKAGE_ROOT/install-manifest.txt" \
    'install-manifest.txt must exactly match the actual runtime file inventory'

  while IFS= read -r relative_path; do
    case "$relative_path" in
      *.sh) bash -n "$PACKAGE_ROOT/$relative_path" || fail "invalid shell syntax: $relative_path" ;;
    esac
  done < "$TMP_ROOT/target-files.txt"

  pass 'package_contract'
}

secret_codecs_helpers() {
  for helper in \
    fprs_die \
    fprs_warn \
    fprs_info \
    fprs_require_arg \
    fprs_realpath \
    fprs_sha256 \
    fprs_mktemp_dir \
    fprs_file_mode \
    fprs_json_escape \
    fprs_is_truthy \
    fprs_cleanup_dir
  do
    bash -c '. "$1"; command -v "$2" >/dev/null 2>&1' sh "$COMMON" "$helper" ||
      fail "common helper is unavailable: $helper"
  done

  printf 'abc' > "$CODEC_ROOT/sha input"
  helper_sha=$(bash -c '. "$1"; fprs_sha256 "$2"' sh "$COMMON" "$CODEC_ROOT/sha input") ||
    fail 'fprs_sha256 rejected a readable file'
  [ "$helper_sha" = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ] ||
    fail 'fprs_sha256 did not return the SHA-256 payload only'

  mkdir -p "$CODEC_ROOT/real path/child"
  expected_realpath=$(CDPATH= cd -- "$CODEC_ROOT/real path" && pwd -P)/future.txt
  helper_realpath=$(bash -c '. "$1"; fprs_realpath "$2"' sh "$COMMON" "$CODEC_ROOT/real path/child/../future.txt") ||
    fail 'fprs_realpath rejected a path with spaces and a nonexistent leaf'
  [ "$helper_realpath" = "$expected_realpath" ] ||
    fail 'fprs_realpath did not normalize the parent path physically'

  helper_json=$(bash -c '. "$1"; fprs_json_escape "$2"' sh "$COMMON" 'quote" slash\ line
	tab') || fail 'fprs_json_escape rejected control characters'
  [ "$helper_json" = 'quote\" slash\\ line\n\ttab' ] ||
    fail 'fprs_json_escape did not escape JSON metacharacters and controls'

  bash -c '. "$1"; fprs_is_truthy "YeS"' sh "$COMMON" ||
    fail 'fprs_is_truthy rejected a mixed-case truthy value'
  if bash -c '. "$1"; fprs_is_truthy "no"' sh "$COMMON"; then
    fail 'fprs_is_truthy accepted a false value'
  fi

  helper_temp=$(bash -c '
    . "$1"
    helper_temp=$(fprs_mktemp_dir codec-helper "$2") || exit
    printf private > "$helper_temp/private file" || exit
    printf "%s\n" "$helper_temp"
  ' sh "$COMMON" "$CODEC_ROOT") ||
    fail 'fprs_mktemp_dir could not create a private directory'
  [ -d "$helper_temp" ] || fail 'fprs_mktemp_dir did not return a directory'
  assert_mode '700' "$helper_temp" 'fprs_mktemp_dir mode'
  assert_mode '600' "$helper_temp/private file" 'umask inherited from common helpers'
  bash -c '. "$1"; fprs_cleanup_dir "$2"' sh "$COMMON" "$helper_temp" ||
    fail 'fprs_cleanup_dir rejected an owned temporary directory'
  [ ! -e "$helper_temp" ] || fail 'fprs_cleanup_dir did not remove its target'
  if bash -c '. "$1"; fprs_cleanup_dir /' sh "$COMMON"; then
    fail 'fprs_cleanup_dir accepted the filesystem root'
  fi

  printf 'mode' > "$CODEC_ROOT/mode file"
  chmod 640 "$CODEC_ROOT/mode file"
  helper_mode=$(bash -c '. "$1"; fprs_file_mode "$2"' sh "$COMMON" "$CODEC_ROOT/mode file") ||
    fail 'fprs_file_mode rejected a readable file'
  [ "$helper_mode" = '640' ] || fail 'fprs_file_mode returned the wrong mode'

  bash -c '. "$1"; fprs_require_arg --input "$2"' sh "$COMMON" "$CODEC_ROOT/sha input" ||
    fail 'fprs_require_arg rejected a present argument'
  if bash -c '. "$1"; fprs_require_arg --input ""' sh "$COMMON" \
    > "$CODEC_ROOT/require.stdout" 2> "$CODEC_ROOT/require.stderr"
  then
    fail 'fprs_require_arg accepted an empty argument'
  fi
  assert_empty_file "$CODEC_ROOT/require.stdout" 'fprs_require_arg wrote diagnostics to stdout'

  bash -c '. "$1"; fprs_info ready; fprs_warn careful' sh "$COMMON" \
    > "$CODEC_ROOT/log.stdout" 2> "$CODEC_ROOT/log.stderr" ||
    fail 'common logging helpers failed'
  : > "$CODEC_ROOT/expected-log.stdout"
  printf 'INFO: ready\nWARNING: careful\n' > "$CODEC_ROOT/expected-log.stderr"
  assert_same_file "$CODEC_ROOT/expected-log.stdout" "$CODEC_ROOT/log.stdout" 'logging helpers wrote to stdout'
  assert_same_file "$CODEC_ROOT/expected-log.stderr" "$CODEC_ROOT/log.stderr" 'fprs_warn output changed'
  if bash -c '. "$1"; fprs_die stopped' sh "$COMMON" \
    > "$CODEC_ROOT/die.stdout" 2> "$CODEC_ROOT/die.stderr"
  then
    fail 'fprs_die returned success'
  fi
  assert_empty_file "$CODEC_ROOT/die.stdout" 'fprs_die wrote diagnostics to stdout'
}

secret_codecs_round_trips() {
  printf 'portable release secret\n' > "$CODEC_ROOT/text input"
  "$ENCODER" --input "$CODEC_ROOT/text input" \
    > "$CODEC_ROOT/text encoded" 2> "$CODEC_ROOT/text encode.stderr" ||
    fail 'file-to-stdout encoding failed'
  assert_empty_file "$CODEC_ROOT/text encode.stderr" 'successful encoding wrote to stderr'
  [ "$(wc -l < "$CODEC_ROOT/text encoded" | tr -d '[:space:]')" = '1' ] ||
    fail 'encoded payload was wrapped across multiple lines'
  [ "$(tail -c 1 "$CODEC_ROOT/text encoded" | wc -l | tr -d '[:space:]')" = '1' ] ||
    fail 'encoded payload did not end with exactly one newline'
  "$DECODER" --input "$CODEC_ROOT/text encoded" \
    > "$CODEC_ROOT/text decoded" 2> "$CODEC_ROOT/text decode.stderr" ||
    fail 'file-to-stdout decoding failed'
  assert_same_file "$CODEC_ROOT/text input" "$CODEC_ROOT/text decoded" 'text round trip changed bytes'
  assert_empty_file "$CODEC_ROOT/text decode.stderr" 'successful decoding wrote to stderr'

  printf '\000\001\002\177\200\377binary\nbytes\000' > "$CODEC_ROOT/binary input"
  printf 'stale encoded output' > "$CODEC_ROOT/binary encoded"
  chmod 644 "$CODEC_ROOT/binary encoded"
  printf 'unchanged' > "$CODEC_ROOT/binary output"
  (umask 000; "$ENCODER" --input - --output "$CODEC_ROOT/binary encoded" \
    < "$CODEC_ROOT/binary input") \
    > "$CODEC_ROOT/binary encode.stdout" 2> "$CODEC_ROOT/binary encode.stderr" ||
    fail 'stdin-to-file encoding failed'
  assert_empty_file "$CODEC_ROOT/binary encode.stdout" 'file encoding emitted payload to stdout'
  assert_mode '600' "$CODEC_ROOT/binary encoded" 'replaced encoded output mode'
  (umask 000; "$DECODER" --input "$CODEC_ROOT/binary encoded" --output "$CODEC_ROOT/binary output") \
    > "$CODEC_ROOT/binary decode.stdout" 2> "$CODEC_ROOT/binary decode.stderr" ||
    fail 'file-to-file binary decoding failed'
  assert_empty_file "$CODEC_ROOT/binary decode.stdout" 'file decoding emitted payload to stdout'
  assert_same_file "$CODEC_ROOT/binary input" "$CODEC_ROOT/binary output" 'binary round trip changed bytes'
  assert_mode '600' "$CODEC_ROOT/binary output" 'replaced decoded output mode'

  mkdir -p "$CODEC_ROOT/path with spaces"
  cp "$CODEC_ROOT/binary input" "$CODEC_ROOT/path with spaces/input secret"
  "$ENCODER" --input "$CODEC_ROOT/path with spaces/input secret" \
    --output "$CODEC_ROOT/path with spaces/encoded secret" ||
    fail 'encoding paths with spaces failed'
  "$DECODER" --input - --output "$CODEC_ROOT/path with spaces/decoded secret" \
    < "$CODEC_ROOT/path with spaces/encoded secret" ||
    fail 'decoding paths with spaces failed'
  assert_same_file \
    "$CODEC_ROOT/path with spaces/input secret" \
    "$CODEC_ROOT/path with spaces/decoded secret" \
    'path-with-spaces round trip changed bytes'
  assert_mode '600' "$CODEC_ROOT/path with spaces/decoded secret" 'new decoded output mode'

  printf '' | "$ENCODER" > "$CODEC_ROOT/empty encoded" 2> "$CODEC_ROOT/empty encode.stderr" ||
    fail 'empty stdin encoding failed'
  printf '\n' > "$CODEC_ROOT/expected empty encoding"
  assert_same_file \
    "$CODEC_ROOT/expected empty encoding" \
    "$CODEC_ROOT/empty encoded" \
    'empty input did not encode as one empty line'
  printf '' > "$CODEC_ROOT/empty output"
  "$DECODER" --input - --output "$CODEC_ROOT/empty output" \
    < "$CODEC_ROOT/empty encoded" || fail 'empty input decoding failed'
  assert_empty_file "$CODEC_ROOT/empty output" 'empty decode produced bytes'
  assert_mode '600' "$CODEC_ROOT/empty output" 'empty decoded output mode'

  printf ' aG\tVs\nbG\r8=\v\f' > "$CODEC_ROOT/wrapped input"
  "$DECODER" --input "$CODEC_ROOT/wrapped input" > "$CODEC_ROOT/wrapped output" ||
    fail 'ASCII-whitespace-wrapped input was rejected'
  printf 'hello' > "$CODEC_ROOT/expected hello"
  assert_same_file "$CODEC_ROOT/expected hello" "$CODEC_ROOT/wrapped output" 'wrapped decode changed bytes'

  cp "$CODEC_ROOT/wrapped input" "$CODEC_ROOT/wrapped input.before"
  "$DECODER" --input "$CODEC_ROOT/wrapped input" > /dev/null ||
    fail 'explicit wrapped input could not be decoded twice'
  assert_same_file \
    "$CODEC_ROOT/wrapped input.before" \
    "$CODEC_ROOT/wrapped input" \
    'successful decode modified explicit input'
  cp "$CODEC_ROOT/binary input" "$CODEC_ROOT/binary input.before"
  "$ENCODER" --input "$CODEC_ROOT/binary input" > /dev/null ||
    fail 'explicit binary input could not be encoded twice'
  assert_same_file \
    "$CODEC_ROOT/binary input.before" \
    "$CODEC_ROOT/binary input" \
    'successful encode modified explicit input'
}

secret_codecs_strictness() {
  printf 'keep-this-output' > "$CODEC_ROOT/existing output"
  chmod 644 "$CODEC_ROOT/existing output"
  cp "$CODEC_ROOT/existing output" "$CODEC_ROOT/existing output.before"
  for invalid_case in invalid-alphabet truncated-padding middle-padding excess-padding noncanonical-padding
  do
    case "$invalid_case" in
      invalid-alphabet) invalid_payload='Zm9v_CANARY_CODEC!' ;;
      truncated-padding) invalid_payload='Zg=' ;;
      middle-padding) invalid_payload='Z=g=' ;;
      excess-padding) invalid_payload='Z===' ;;
      noncanonical-padding) invalid_payload='Zh==' ;;
    esac
    printf '%s' "$invalid_payload" > "$CODEC_ROOT/$invalid_case.input"
    cp "$CODEC_ROOT/$invalid_case.input" "$CODEC_ROOT/$invalid_case.before"
    if "$DECODER" --input "$CODEC_ROOT/$invalid_case.input" --output "$CODEC_ROOT/existing output" \
      > "$CODEC_ROOT/$invalid_case.stdout" 2> "$CODEC_ROOT/$invalid_case.stderr"
    then
      fail "invalid Base64 was accepted: $invalid_case"
    else
      invalid_status=$?
    fi
    [ "$invalid_status" -eq 1 ] ||
      fail "invalid Base64 did not use exit 1: $invalid_case"
    assert_empty_file "$CODEC_ROOT/$invalid_case.stdout" "invalid decode emitted payload: $invalid_case"
    assert_same_file \
      "$CODEC_ROOT/$invalid_case.before" \
      "$CODEC_ROOT/$invalid_case.input" \
      "failed decode modified explicit input: $invalid_case"
    assert_same_file \
      "$CODEC_ROOT/existing output.before" \
      "$CODEC_ROOT/existing output" \
      "failed decode replaced prior output: $invalid_case"
    if grep -F 'CANARY_CODEC' "$CODEC_ROOT/$invalid_case.stderr" >/dev/null 2>&1; then
      fail "failed decode exposed secret content on stderr: $invalid_case"
    fi
  done
  assert_mode '644' "$CODEC_ROOT/existing output" 'failed decode changed prior output mode'

  printf 'same-file-secret' > "$CODEC_ROOT/same input"
  cp "$CODEC_ROOT/same input" "$CODEC_ROOT/same input.before"
  if "$ENCODER" --input "$CODEC_ROOT/same input" --output "$CODEC_ROOT/same input" \
    > "$CODEC_ROOT/same.stdout" 2> "$CODEC_ROOT/same.stderr"
  then
    fail 'encoder accepted identical input and output'
  else
    same_status=$?
  fi
  [ "$same_status" -eq 2 ] || fail 'encoder did not use exit 2 for a refused same path'
  assert_same_file "$CODEC_ROOT/same input.before" "$CODEC_ROOT/same input" 'same-path refusal modified input'

  ln "$CODEC_ROOT/same input" "$CODEC_ROOT/same hardlink"
  if "$DECODER" --input "$CODEC_ROOT/same input" --output "$CODEC_ROOT/same hardlink" \
    > /dev/null 2> "$CODEC_ROOT/hardlink.stderr"
  then
    fail 'decoder accepted hard-linked input and output'
  else
    hardlink_status=$?
  fi
  [ "$hardlink_status" -eq 2 ] || fail 'decoder did not use exit 2 for a same-file alias'
  assert_same_file "$CODEC_ROOT/same input.before" "$CODEC_ROOT/same input" 'same-file alias refusal modified input'

  mkdir -p "$CODEC_ROOT/alias child"
  printf 'YWxpYXM=' > "$CODEC_ROOT/alias input"
  alias_spelling="$CODEC_ROOT/alias child/../alias input"
  if "$DECODER" --input "$CODEC_ROOT/alias input" --output "$alias_spelling" \
    > /dev/null 2> "$CODEC_ROOT/alias.stderr"
  then
    fail 'decoder accepted a lexical same-path alias'
  else
    alias_status=$?
  fi
  [ "$alias_status" -eq 2 ] || fail 'lexical same-path alias did not use exit 2'

  printf 'argument-secret' > "$CODEC_ROOT/argument input"
  cp "$CODEC_ROOT/argument input" "$CODEC_ROOT/argument input.before"
  for codec_command in "$ENCODER" "$DECODER"
  do
    codec_name=$(basename "$codec_command")
    for argument_case in duplicate-input duplicate-output missing-value positional unknown
    do
      case "$argument_case" in
        duplicate-input)
          set -- --input "$CODEC_ROOT/argument input" --input - ;;
        duplicate-output)
          set -- --output - --output "$CODEC_ROOT/argument output" ;;
        missing-value)
          set -- --input ;;
        positional)
          set -- "$CODEC_ROOT/argument input" ;;
        unknown)
          set -- --wat ;;
      esac
      if "$codec_command" "$@" > "$CODEC_ROOT/$codec_name-$argument_case.stdout" \
        2> "$CODEC_ROOT/$codec_name-$argument_case.stderr"
      then
        fail "ambiguous or invalid arguments were accepted by $codec_name: $argument_case"
      else
        argument_status=$?
      fi
      [ "$argument_status" -eq 2 ] ||
        fail "argument error did not use exit 2 in $codec_name: $argument_case"
      assert_empty_file \
        "$CODEC_ROOT/$codec_name-$argument_case.stdout" \
        "argument error wrote to stdout in $codec_name: $argument_case"
    done
  done
  assert_same_file \
    "$CODEC_ROOT/argument input.before" \
    "$CODEC_ROOT/argument input" \
    'argument parsing modified explicit input'

  redaction_raw='FPRS_RAW_SECRET_CANARY_7d06d4'
  redaction_encoded='RlBSU19SQVdfU0VDUkVUX0NBTkFSWV83ZDA2ZDQ='
  mkdir -p "$CODEC_ROOT/redaction logs" "$CODEC_ROOT/redaction shim"
  cat > "$CODEC_ROOT/redaction shim/base64" <<'SH'
#!/bin/sh
case "${1-}" in
  -w|-b)
    [ "${2-}" = 0 ] || exit 64
    payload=$(cat)
    if [ -z "$payload" ]; then
      exit 0
    fi
    printf '%s' "$payload"
    printf '%s' "$payload" >&2
    exit 70
    ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$CODEC_ROOT/redaction shim/base64"

  redaction_index=0
  for redaction_payload in "$redaction_raw" "$redaction_encoded"
  do
    redaction_index=$((redaction_index + 1))
    if printf '%s' "$redaction_payload" | PATH="$CODEC_ROOT/redaction shim:$PATH" "$ENCODER" \
      > "$CODEC_ROOT/redaction logs/encode-$redaction_index.stdout" \
      2> "$CODEC_ROOT/redaction logs/encode-$redaction_index.stderr"
    then
      fail 'encoder redaction failure probe unexpectedly succeeded'
    else
      redaction_status=$?
    fi
    [ "$redaction_status" -eq 1 ] || fail 'encoder redaction probe did not use exit 1'
  done

  redaction_index=0
  for redaction_payload in "$redaction_raw" "$redaction_encoded"
  do
    redaction_index=$((redaction_index + 1))
    if printf '%s!' "$redaction_payload" | "$DECODER" \
      > "$CODEC_ROOT/redaction logs/decode-$redaction_index.stdout" \
      2> "$CODEC_ROOT/redaction logs/decode-$redaction_index.stderr"
    then
      fail 'decoder redaction failure probe unexpectedly succeeded'
    else
      redaction_status=$?
    fi
    [ "$redaction_status" -eq 1 ] || fail 'decoder redaction probe did not use exit 1'
  done

  for redaction_log in "$CODEC_ROOT/redaction logs"/*.stdout
  do
    assert_empty_file "$redaction_log" 'secret codec failure emitted a payload'
  done
  for redaction_log in "$CODEC_ROOT/redaction logs"/*.stdout "$CODEC_ROOT/redaction logs"/*.stderr
  do
    if grep -F "$redaction_raw" "$redaction_log" >/dev/null 2>&1 ||
      grep -F "$redaction_encoded" "$redaction_log" >/dev/null 2>&1
    then
      fail 'secret codec failure logs exposed a unique canary'
    fi
  done

  if grep -E '(^|[[:space:]])set[[:space:]]+(-[^[:space:]]*x|-o[[:space:]]+xtrace)|^#!.*[[:space:]]+-[^[:space:]]*x' \
    "$COMMON" "$ENCODER" "$DECODER" >/dev/null 2>&1
  then
    fail 'secret codec scripts enable shell tracing'
  fi
}

secret_codecs_publication_races() {
  race_real_base64=$(command -v base64) || fail 'base64 is required for publication race tests'
  mkdir -p "$CODEC_ROOT/publication race/shim"
  cat > "$CODEC_ROOT/publication race/shim/base64" <<'SH'
#!/bin/sh
if [ ! -e "$FPRS_RACE_OUTPUT" ]; then
  mkdir "$FPRS_RACE_OUTPUT" || exit 70
fi
exec "$FPRS_REAL_BASE64" "$@"
SH
  chmod +x "$CODEC_ROOT/publication race/shim/base64"

  for race_codec in encode decode
  do
    race_output="$CODEC_ROOT/publication race/$race_codec target"
    case "$race_codec" in
      encode)
        race_command=$ENCODER
        race_input="$CODEC_ROOT/text input"
        ;;
      decode)
        race_command=$DECODER
        race_input="$CODEC_ROOT/text encoded"
        ;;
    esac

    if PATH="$CODEC_ROOT/publication race/shim:$PATH" \
      FPRS_REAL_BASE64="$race_real_base64" FPRS_RACE_OUTPUT="$race_output" \
      "$race_command" --input "$race_input" --output "$race_output" \
      > "$CODEC_ROOT/publication race/$race_codec.stdout" \
      2> "$CODEC_ROOT/publication race/$race_codec.stderr"
    then
      fail "$race_codec accepted a publication directory race"
    else
      race_status=$?
    fi
    [ "$race_status" -eq 1 ] || fail "$race_codec publication race did not use exit 1"
    assert_empty_file \
      "$CODEC_ROOT/publication race/$race_codec.stdout" \
      "$race_codec publication race emitted a payload"
    [ -d "$race_output" ] || fail "$race_codec publication race fixture was not injected"
    race_leak=$(find "$race_output" -mindepth 1 -print | sed -n '1p')
    [ -z "$race_leak" ] || fail "$race_codec left secret data under an injected directory"
  done

  race_leftover=$(find "$CODEC_ROOT/publication race" -type d -name '.fprs-secret-codec.*' \
    -print | sed -n '1p')
  [ -z "$race_leftover" ] || fail 'publication race left an invocation-owned directory'
  pass 'publication_race_regression'
}

secret_codec_signal_case() {
  signal_name=$1
  signal_codec_name=$2
  signal_root="$CODEC_ROOT/signal $signal_codec_name $signal_name"
  signal_fifo="$signal_root/input"
  signal_output="$signal_root/output"
  mkdir -p "$signal_root"
  mkdir "$signal_root/.fprs-secret-codec.keep"
  printf 'pre-existing-lookalike' > "$signal_root/.fprs-secret-codec.keep/sentinel"
  mkfifo "$signal_fifo"

  case "$signal_codec_name" in
    encode)
      signal_command=$ENCODER
      signal_prefix='signal-encode-input'
      ;;
    decode)
      signal_command=$DECODER
      signal_prefix='Zm9v'
      printf 'preserve-decoder-output' > "$signal_output"
      chmod 640 "$signal_output"
      cp "$signal_output" "$signal_output.before"
      ;;
    *) fail 'unknown signal codec fixture' ;;
  esac

  (printf '%s' "$signal_prefix"; while :; do :; done) > "$signal_fifo" &
  signal_writer=$!
  python3 -c '
import os
import signal
import sys
for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])
' "$signal_command" --input "$signal_fifo" --output "$signal_output" \
    > "$signal_root/stdout" 2> "$signal_root/stderr" &
  signal_codec=$!

  signal_ready=false
  signal_attempt=0
  while [ "$signal_attempt" -lt 100 ]; do
    if find "$signal_root" -type d -name '.fprs-secret-codec.*' \
      ! -name '.fprs-secret-codec.keep' -print |
      grep . >/dev/null 2>&1
    then
      signal_ready=true
      break
    fi
    signal_attempt=$((signal_attempt + 1))
    sleep 0.02
  done
  if [ "$signal_ready" != true ]; then
    kill -TERM "$signal_codec" "$signal_writer" >/dev/null 2>&1 || true
    wait "$signal_codec" >/dev/null 2>&1 || true
    wait "$signal_writer" >/dev/null 2>&1 || true
    fail "$signal_name signal test could not observe $signal_codec_name staging"
  fi

  kill -"$signal_name" "$signal_codec" >/dev/null 2>&1 || true
  kill -TERM "$signal_writer" >/dev/null 2>&1 || true
  if wait "$signal_codec"; then
    wait "$signal_writer" >/dev/null 2>&1 || true
    fail "$signal_name-interrupted $signal_codec_name returned success"
  else
    signal_status=$?
  fi
  wait "$signal_writer" >/dev/null 2>&1 || true

  [ "$signal_status" -eq 1 ] ||
    fail "$signal_name-interrupted $signal_codec_name did not use exit 1"
  assert_empty_file "$signal_root/stdout" "$signal_name-interrupted $signal_codec_name emitted payload"
  signal_leftover=$(find "$signal_root" -type d -name '.fprs-secret-codec.*' \
    ! -name '.fprs-secret-codec.keep' -print | sed -n '1p')
  [ -z "$signal_leftover" ] ||
    fail "$signal_name-interrupted $signal_codec_name left a temporary directory"
  [ -f "$signal_root/.fprs-secret-codec.keep/sentinel" ] ||
    fail "$signal_name-interrupted $signal_codec_name removed a pre-existing lookalike"

  case "$signal_codec_name" in
    encode)
      [ ! -e "$signal_output" ] ||
        fail "$signal_name-interrupted encoder published an explicit output"
      ;;
    decode)
      assert_same_file \
        "$signal_output.before" \
        "$signal_output" \
        "$signal_name-interrupted decoder changed prior output"
      assert_mode '640' "$signal_output" "$signal_name-interrupted decoder changed prior output mode"
      ;;
  esac
}

secret_codecs_platform_and_cleanup() {
  command -v python3 >/dev/null 2>&1 || fail 'python3 is required for codec publication tests'
  real_base64=$(command -v base64) || fail 'base64 is required for codec tests'
  if printf '' | "$real_base64" --decode >/dev/null 2>&1; then
    real_decode_flag=--decode
  elif printf '' | "$real_base64" -D >/dev/null 2>&1; then
    real_decode_flag=-D
  elif printf '' | "$real_base64" -d >/dev/null 2>&1; then
    real_decode_flag=-d
  else
    fail 'test runner could not identify the platform Base64 decode flag'
  fi

  mkdir -p "$CODEC_ROOT/bsd shim"
  cat > "$CODEC_ROOT/bsd shim/base64" <<'SH'
#!/bin/sh
case "${1-}" in
  -b)
    [ "${2-}" = 0 ] || exit 64
    shift 2
    "$FPRS_REAL_BASE64" | tr -d '\r\n'
    ;;
  -D)
    shift
    "$FPRS_REAL_BASE64" "$FPRS_REAL_DECODE_FLAG" "$@"
    ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$CODEC_ROOT/bsd shim/base64"
  printf 'forced BSD flavor' > "$CODEC_ROOT/bsd input"
  PATH="$CODEC_ROOT/bsd shim:$PATH" \
    FPRS_REAL_BASE64="$real_base64" FPRS_REAL_DECODE_FLAG="$real_decode_flag" \
    "$ENCODER" --input "$CODEC_ROOT/bsd input" > "$CODEC_ROOT/bsd encoded" ||
    fail 'encoder did not detect BSD Base64 flags'
  PATH="$CODEC_ROOT/bsd shim:$PATH" \
    FPRS_REAL_BASE64="$real_base64" FPRS_REAL_DECODE_FLAG="$real_decode_flag" \
    "$DECODER" --input "$CODEC_ROOT/bsd encoded" > "$CODEC_ROOT/bsd output" ||
    fail 'decoder did not detect BSD Base64 flags'
  assert_same_file "$CODEC_ROOT/bsd input" "$CODEC_ROOT/bsd output" 'BSD Base64 round trip changed bytes'

  mkdir -p "$CODEC_ROOT/gnu shim"
  cat > "$CODEC_ROOT/gnu shim/base64" <<'SH'
#!/bin/sh
case "${1-}" in
  -w)
    [ "${2-}" = 0 ] || exit 64
    shift 2
    "$FPRS_REAL_BASE64" | tr -d '\r\n'
    ;;
  --decode)
    shift
    "$FPRS_REAL_BASE64" "$FPRS_REAL_DECODE_FLAG" "$@"
    ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$CODEC_ROOT/gnu shim/base64"
  PATH="$CODEC_ROOT/gnu shim:$PATH" \
    FPRS_REAL_BASE64="$real_base64" FPRS_REAL_DECODE_FLAG="$real_decode_flag" \
    "$ENCODER" --input "$CODEC_ROOT/bsd input" > "$CODEC_ROOT/gnu encoded" ||
    fail 'encoder did not detect GNU Base64 flags'
  PATH="$CODEC_ROOT/gnu shim:$PATH" \
    FPRS_REAL_BASE64="$real_base64" FPRS_REAL_DECODE_FLAG="$real_decode_flag" \
    "$DECODER" --input "$CODEC_ROOT/gnu encoded" > "$CODEC_ROOT/gnu output" ||
    fail 'decoder did not detect GNU Base64 flags'
  assert_same_file "$CODEC_ROOT/bsd input" "$CODEC_ROOT/gnu output" 'GNU Base64 round trip changed bytes'

  mkdir -p "$CODEC_ROOT/failing shim"
  cat > "$CODEC_ROOT/failing shim/base64" <<'SH'
#!/bin/sh
case "${1-}" in
  --decode|-D|-d)
    shift
    payload=$(cat)
    [ -z "$payload" ] && exit 0
    exit 70
    ;;
  -w|-b)
    [ "${2-}" = 0 ] || exit 64
    payload=$(cat)
    [ -z "$payload" ] && exit 0
    exit 70
    ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$CODEC_ROOT/failing shim/base64"
  printf 'decoder-failure-sentinel' > "$CODEC_ROOT/tool failure output"
  chmod 640 "$CODEC_ROOT/tool failure output"
  cp "$CODEC_ROOT/tool failure output" "$CODEC_ROOT/tool failure output.before"
  if PATH="$CODEC_ROOT/failing shim:$PATH" "$DECODER" \
    --input "$CODEC_ROOT/text encoded" --output "$CODEC_ROOT/tool failure output" \
    > "$CODEC_ROOT/tool failure.stdout" 2> "$CODEC_ROOT/tool failure.stderr"
  then
    fail 'decoder accepted a Base64 tool failure'
  else
    tool_failure_status=$?
  fi
  [ "$tool_failure_status" -eq 1 ] || fail 'Base64 tool failure did not use exit 1'
  assert_empty_file "$CODEC_ROOT/tool failure.stdout" 'Base64 tool failure emitted payload'
  assert_same_file \
    "$CODEC_ROOT/tool failure output.before" \
    "$CODEC_ROOT/tool failure output" \
    'Base64 tool failure replaced prior output'
  assert_mode '640' "$CODEC_ROOT/tool failure output" 'Base64 tool failure changed prior output mode'

  printf 'encoder-failure-sentinel' > "$CODEC_ROOT/encode tool failure output"
  chmod 640 "$CODEC_ROOT/encode tool failure output"
  cp "$CODEC_ROOT/encode tool failure output" "$CODEC_ROOT/encode tool failure output.before"
  if PATH="$CODEC_ROOT/failing shim:$PATH" "$ENCODER" \
    --input "$CODEC_ROOT/text input" --output "$CODEC_ROOT/encode tool failure output" \
    > "$CODEC_ROOT/encode tool failure.stdout" 2> "$CODEC_ROOT/encode tool failure.stderr"
  then
    fail 'encoder accepted a Base64 tool failure'
  else
    tool_failure_status=$?
  fi
  [ "$tool_failure_status" -eq 1 ] || fail 'encoder Base64 tool failure did not use exit 1'
  assert_empty_file "$CODEC_ROOT/encode tool failure.stdout" 'encoder Base64 tool failure emitted payload'
  assert_same_file \
    "$CODEC_ROOT/encode tool failure output.before" \
    "$CODEC_ROOT/encode tool failure output" \
    'encoder Base64 tool failure replaced prior output'
  assert_mode '640' "$CODEC_ROOT/encode tool failure output" 'encoder tool failure changed prior output mode'

  mkdir -p "$CODEC_ROOT/cleanup tmp" "$CODEC_ROOT/cleanup output"
  mkdir "$CODEC_ROOT/cleanup tmp/.fprs-secret-codec.keep"
  mkdir "$CODEC_ROOT/cleanup output/.fprs-secret-codec.keep"
  printf 'owned sentinel' > "$CODEC_ROOT/cleanup tmp/.fprs-secret-codec.keep/sentinel"
  printf 'owned sentinel' > "$CODEC_ROOT/cleanup output/.fprs-secret-codec.keep/sentinel"
  TMPDIR="$CODEC_ROOT/cleanup tmp" "$ENCODER" --input "$CODEC_ROOT/text input" \
    --output "$CODEC_ROOT/cleanup output/encoded success" ||
    fail 'encoder cleanup success setup failed'
  TMPDIR="$CODEC_ROOT/cleanup tmp" "$DECODER" --input "$CODEC_ROOT/text encoded" \
    --output "$CODEC_ROOT/cleanup output/decoded success" ||
    fail 'decoder cleanup success setup failed'
  assert_same_file \
    "$CODEC_ROOT/text input" \
    "$CODEC_ROOT/cleanup output/decoded success" \
    'decoder cleanup success changed bytes'

  printf 'preserve-encode-error' > "$CODEC_ROOT/cleanup output/encode error"
  cp "$CODEC_ROOT/cleanup output/encode error" "$CODEC_ROOT/cleanup output/encode error.before"
  if PATH="$CODEC_ROOT/failing shim:$PATH" TMPDIR="$CODEC_ROOT/cleanup tmp" \
    "$ENCODER" --input "$CODEC_ROOT/text input" \
    --output "$CODEC_ROOT/cleanup output/encode error" \
    > "$CODEC_ROOT/cleanup encode error.stdout" 2> "$CODEC_ROOT/cleanup encode error.stderr"
  then
    fail 'encoder cleanup error setup unexpectedly succeeded'
  fi
  assert_same_file \
    "$CODEC_ROOT/cleanup output/encode error.before" \
    "$CODEC_ROOT/cleanup output/encode error" \
    'encoder cleanup error changed explicit output'

  printf 'preserve-decode-error' > "$CODEC_ROOT/cleanup output/decode error"
  cp "$CODEC_ROOT/cleanup output/decode error" "$CODEC_ROOT/cleanup output/decode error.before"
  if TMPDIR="$CODEC_ROOT/cleanup tmp" "$DECODER" --input "$CODEC_ROOT/invalid-alphabet.input" \
    --output "$CODEC_ROOT/cleanup output/decode error" \
    > "$CODEC_ROOT/cleanup decode error.stdout" 2> "$CODEC_ROOT/cleanup decode error.stderr"
  then
    fail 'decoder cleanup error setup unexpectedly succeeded'
  fi
  assert_same_file \
    "$CODEC_ROOT/cleanup output/decode error.before" \
    "$CODEC_ROOT/cleanup output/decode error" \
    'decoder cleanup error changed explicit output'
  [ -f "$CODEC_ROOT/cleanup tmp/.fprs-secret-codec.keep/sentinel" ] ||
    fail 'cleanup removed a pre-existing TMPDIR lookalike'
  [ -f "$CODEC_ROOT/cleanup output/.fprs-secret-codec.keep/sentinel" ] ||
    fail 'cleanup removed a pre-existing output lookalike'
  cleanup_leftover=$(find "$CODEC_ROOT/cleanup tmp" "$CODEC_ROOT/cleanup output" \
    -type d -name '.fprs-secret-codec.*' \
    ! -name '.fprs-secret-codec.keep' -print | sed -n '1p')
  [ -z "$cleanup_leftover" ] || fail 'temporary directory remained after success or error'

  for signal_name in HUP INT TERM
  do
    secret_codec_signal_case "$signal_name" encode
    secret_codec_signal_case "$signal_name" decode
  done
  pass 'signal_status_cleanup_regression'
  [ -f "$CODEC_ROOT/cleanup output/.fprs-secret-codec.keep/sentinel" ] ||
    fail 'signal cleanup removed a pre-existing lookalike'

  mkdir -p "$CODEC_ROOT/umask shim"
  cat > "$CODEC_ROOT/umask shim/base64" <<'SH'
#!/bin/sh
umask > "$FPRS_UMASK_LOG"
exit 70
SH
  chmod +x "$CODEC_ROOT/umask shim/base64"
  if PATH="$CODEC_ROOT/umask shim:$PATH" FPRS_UMASK_LOG="$CODEC_ROOT/encode umask" \
    "$ENCODER" < /dev/null > /dev/null 2> "$CODEC_ROOT/encode umask.stderr"
  then
    fail 'umask probe encoder unexpectedly succeeded'
  fi
  if PATH="$CODEC_ROOT/umask shim:$PATH" FPRS_UMASK_LOG="$CODEC_ROOT/decode umask" \
    "$DECODER" < /dev/null > /dev/null 2> "$CODEC_ROOT/decode umask.stderr"
  then
    fail 'umask probe decoder unexpectedly succeeded'
  fi
  encode_umask=$(tr -d '[:space:]' < "$CODEC_ROOT/encode umask")
  decode_umask=$(tr -d '[:space:]' < "$CODEC_ROOT/decode umask")
  case "$encode_umask" in *077) ;; *) fail 'encoder did not establish umask 077' ;; esac
  case "$decode_umask" in *077) ;; *) fail 'decoder did not establish umask 077' ;; esac
}

secret_codecs() {
  CODEC_ROOT="$TMP_ROOT/secret codecs"
  COMMON="$PACKAGE_ROOT/scripts/lib/common.sh"
  ENCODER="$PACKAGE_ROOT/scripts/encode_secret.sh"
  DECODER="$PACKAGE_ROOT/scripts/decode_secret.sh"
  mkdir -p "$CODEC_ROOT"

  secret_codecs_helpers
  secret_codecs_round_trips
  secret_codecs_strictness
  secret_codecs_publication_races
  secret_codecs_platform_and_cleanup
  pass 'secret_codecs'
}

case "${1:-all}" in
  all)
    package_contract
    secret_codecs
    ;;
  package_contract)
    package_contract
    ;;
  secret_codecs)
    secret_codecs
    ;;
  *)
    fail "unknown test group: $1"
    ;;
esac
