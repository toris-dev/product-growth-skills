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

inspection_assert_status() {
  inspection_description=$1
  inspection_expected_status=$2
  shift 2
  inspection_case_index=$((inspection_case_index + 1))
  INSPECTION_LAST_STDOUT="$INSPECTION_LOGS/$inspection_case_index.stdout"
  INSPECTION_LAST_STDERR="$INSPECTION_LOGS/$inspection_case_index.stderr"

  if "$@" > "$INSPECTION_LAST_STDOUT" 2> "$INSPECTION_LAST_STDERR"; then
    inspection_actual_status=0
  else
    inspection_actual_status=$?
  fi
  [ "$inspection_actual_status" -eq "$inspection_expected_status" ] ||
    fail "$inspection_description (expected exit $inspection_expected_status, got $inspection_actual_status)"
}

inspection_assert_json_fragment() {
  inspection_json_file=$1
  inspection_expected_fragment=$2
  inspection_description=$3
  grep -F -- "$inspection_expected_fragment" "$inspection_json_file" >/dev/null 2>&1 ||
    fail "$inspection_description"
}

inspection_assert_schema() {
  inspection_json_file=$1
  inspection_keys='schema_version project_root flutter_constraint dart_constraint flutter_version android_dsl gradle_file android_gradle_plugin_version gradle_wrapper_version java_compatibility application_id namespace application_id_candidates version_name version_code pubspec_version_name pubspec_build_number flavors selected_flavor suggested_flavor suggestion_confirmed entrypoints build_runner fastlane github_actions release_signing release_uses_debug_signing firebase firebase_package_names firebase_apps firebase_app_distribution monorepo git_dirty files_bootstrap_may_change warnings failures'

  [ "$(sed -n '1p' "$inspection_json_file" | cut -c1)" = '{' ] ||
    fail 'inspection JSON did not start with an object'
  [ "$(tail -n 1 "$inspection_json_file" | sed 's/.*\(.\)$/\1/')" = '}' ] ||
    fail 'inspection JSON did not end with an object'
  for inspection_key in $inspection_keys
  do
    inspection_key_count=$(grep -o "\"$inspection_key\":" "$inspection_json_file" | wc -l | tr -d '[:space:]')
    [ "$inspection_key_count" = 1 ] ||
      fail "inspection JSON key count changed for $inspection_key"
  done

  # Keep structural checks even when a richer parser is available.
  grep -E '"schema_version":[0-9]+' "$inspection_json_file" >/dev/null 2>&1 ||
    fail 'inspection schema_version is not numeric'
  grep -E '"suggestion_confirmed":(true|false)' "$inspection_json_file" >/dev/null 2>&1 ||
    fail 'inspection suggestion_confirmed is not boolean'
  grep -E '"git_dirty":(true|false|null)' "$inspection_json_file" >/dev/null 2>&1 ||
    fail 'inspection git_dirty has the wrong structural type'
  for inspection_array_key in application_id_candidates flavors entrypoints firebase_package_names firebase_apps files_bootstrap_may_change warnings failures
  do
    grep -E "\"$inspection_array_key\":\[" "$inspection_json_file" >/dev/null 2>&1 ||
      fail "inspection $inspection_array_key is not structurally an array"
  done

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$inspection_json_file" <<'PY' || fail 'Python rejected the inspection JSON schema'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

nullable_strings = {
    "flutter_constraint", "dart_constraint", "flutter_version", "gradle_file",
    "android_gradle_plugin_version", "gradle_wrapper_version", "java_compatibility",
    "application_id", "namespace", "version_name", "version_code",
    "pubspec_version_name", "pubspec_build_number", "selected_flavor", "suggested_flavor",
}
strings = {"project_root", "android_dsl"}
booleans = {
    "suggestion_confirmed", "build_runner", "fastlane", "github_actions",
    "release_signing", "release_uses_debug_signing", "firebase",
    "firebase_app_distribution", "monorepo",
}
arrays = {
    "application_id_candidates", "flavors", "entrypoints", "firebase_package_names",
    "firebase_apps", "files_bootstrap_may_change", "warnings", "failures",
}
required = {"schema_version", "git_dirty"} | nullable_strings | strings | booleans | arrays
assert required <= set(data)
assert type(data["schema_version"]) is int
assert data["schema_version"] == 1
for key in strings:
    assert type(data[key]) is str
for key in nullable_strings:
    assert data[key] is None or type(data[key]) is str
for key in booleans:
    assert type(data[key]) is bool
for key in arrays:
    assert type(data[key]) is list
assert data["git_dirty"] is None or type(data["git_dirty"]) is bool
PY
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rjson - "$inspection_json_file" <<'RUBY' || fail 'Ruby rejected the inspection JSON schema'
data = JSON.parse(File.read(ARGV.fetch(0)))
nullable_strings = %w[flutter_constraint dart_constraint flutter_version gradle_file android_gradle_plugin_version gradle_wrapper_version java_compatibility application_id namespace version_name version_code pubspec_version_name pubspec_build_number selected_flavor suggested_flavor]
strings = %w[project_root android_dsl]
booleans = %w[suggestion_confirmed build_runner fastlane github_actions release_signing release_uses_debug_signing firebase firebase_app_distribution monorepo]
arrays = %w[application_id_candidates flavors entrypoints firebase_package_names firebase_apps files_bootstrap_may_change warnings failures]
required = (["schema_version", "git_dirty"] + nullable_strings + strings + booleans + arrays).sort
raise unless (required - data.keys).empty?
raise unless data["schema_version"] == 1
strings.each { |key| raise unless data[key].is_a?(String) }
nullable_strings.each { |key| raise unless data[key].nil? || data[key].is_a?(String) }
booleans.each { |key| raise unless data[key] == true || data[key] == false }
arrays.each { |key| raise unless data[key].is_a?(Array) }
raise unless data["git_dirty"].nil? || data["git_dirty"] == true || data["git_dirty"] == false
RUBY
  fi
}

inspection_write_pubspec() {
  inspection_project=$1
  inspection_build_runner_section=$2
  mkdir -p "$inspection_project/android/app/src/main" "$inspection_project/lib"
  case "$inspection_build_runner_section" in
    dev_dependencies)
      cat > "$inspection_project/pubspec.yaml" <<'YAML'
name: inspection_fixture
environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.19.0"
version: 1.2.3+45
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.4.9
YAML
      ;;
    dependencies)
      cat > "$inspection_project/pubspec.yaml" <<'YAML'
name: inspection_fixture
environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: 3.22.0
version: 3.0.0+300
dependencies:
  flutter:
    sdk: flutter
  build_runner: ^2.4.11
dev_dependencies:
  test: any
YAML
      ;;
    *) fail 'unknown build_runner fixture section' ;;
  esac
  printf 'void main() {}\n' > "$inspection_project/lib/main.dart"
}

inspection_write_wrapper() {
  inspection_project=$1
  inspection_gradle_version=$2
  mkdir -p "$inspection_project/android/gradle/wrapper"
  printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-%s-bin.zip\n' \
    "$inspection_gradle_version" > "$inspection_project/android/gradle/wrapper/gradle-wrapper.properties"
}

inspection_append_execution_canary() {
  inspection_gradle_file=$1
  inspection_gradle_dsl=$2
  case "$inspection_gradle_dsl" in
    groovy)
      printf '\nnew File(System.getenv("FPRS_INSPECTION_EXEC_MARKER") ?: "/dev/null").text = "executed"\n' \
        >> "$inspection_gradle_file"
      ;;
    kotlin)
      printf '\njava.io.File(System.getenv("FPRS_INSPECTION_EXEC_MARKER") ?: "/dev/null").writeText("executed")\n' \
        >> "$inspection_gradle_file"
      ;;
    *) fail 'unknown Gradle DSL for execution canary' ;;
  esac
}

inspection_make_groovy() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
pluginManagement {}
plugins {
    // id "com.android.application" version "99.0.0" apply false
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  cat > "$inspection_project/android/app/build.gradle" <<'GRADLE'
plugins {
    id "com.android.application"
}

android {
    namespace "com.example.release"
    /* Inactive documentation example:
    defaultConfig {
        applicationId "CHANGE_ME_APPLICATION_ID"
    }
    */
    compileOptions {
        // sourceCompatibility JavaVersion.VERSION_99
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId "com.example.release"
        versionCode 45
        versionName "1.2.3"
    }
    signingConfigs {
        upload {
            storeFile file(keystoreProperties["storeFile"])
        }
    }
    buildTypes {
        debug {
            signingConfig signingConfigs.debug
        }
        release {
            signingConfig signingConfigs.upload
        }
    }
}

def ignoredSecret = "FPRS_GRADLE_SECRET_CANARY_18d90b"
new File(System.getenv("FPRS_INSPECTION_EXEC_MARKER") ?: "/dev/null").text = "executed"
GRADLE
}

inspection_make_kotlin() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dependencies
  inspection_write_wrapper "$inspection_project" 8.10.2
  printf '{"flutter":"3.22.3"}\n' > "$inspection_project/.fvmrc"
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
pluginManagement {}
plugins {
    id("com.android.application") version "8.7.3" apply false
}
KOTLIN
  cat > "$inspection_project/android/gradle.properties" <<'PROPERTIES'
VERSION_NAME=7.4.0
VERSION_CODE=740
PROPERTIES
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application")
}

android {
    namespace = "com.acme.shell"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            applicationIdSuffix = ".staging"
            versionCode = 999
            versionName = "9.9.9"
        }
        create("release") {
            applicationId = "com.acme.mobile.release"
        }
    }
    defaultConfig {
        applicationId = "com.acme.mobile"
        versionCode = (project.findProperty("VERSION_CODE") ?: "1").toString().toInt()
        versionName = (project.findProperty("VERSION_NAME") ?: "1.0").toString()
    }
    buildTypes {
        getByName("release") { signingConfig = signingConfigs.getByName("debug") }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
  printf 'void main() {}\n' > "$inspection_project/lib/main_release.dart"
  mkdir -p "$inspection_project/android/fastlane" "$inspection_project/.github/workflows"
  printf 'firebase_app_distribution(app: ENV["FIREBASE_APP_ID"])\n' \
    > "$inspection_project/android/fastlane/Fastfile"
  printf 'name: release\n' > "$inspection_project/.github/workflows/release-android.yml"
  mkdir -p "$inspection_project/android/app/src/release"
  printf '%s\n' '{"project_info":{"project_number":"FPRS_FIREBASE_PROJECT_CANARY_7364f1","project_id":"not-for-output","package_name":"com.global.noise"},"client":[{"oauth_client":[{"client_type":1,"android_info":{"package_name":"com.oauth.noise"}}],"client_info":{"mobilesdk_app_id":"1:123456789:android:releaseabc","android_client_info":{"package_name":"com.acme.mobile.release"}},"api_key":[{"current_key":"FPRS_FIREBASE_API_KEY_CANARY_aa90e2"}]},{"client_info":{"mobilesdk_app_id":"1:123456789:android:legacyabc","android_client_info":{"package_name":"com.acme.legacy"}}},{"client_info":{"mobilesdk_app_id":"1:123456789:android:orphanabc"}},{"client_info":{"android_client_info":{"package_name":"com.cross.noise"}}}]}' \
    > "$inspection_project/android/app/src/release/google-services.json"
}

inspection_make_minimal_kotlin() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.9
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.6.1" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
val unrelatedJavaDocumentation = JavaVersion.VERSION_21

android {
    namespace = "com.example.kotlin"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
    }
    defaultConfig {
        applicationId = "com.example.kotlin"
        versionCode = 1_045
        versionName = "1.2.3"
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_unresolved() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.6
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.4.1" apply false
}
GRADLE
  cat > "$inspection_project/android/app/build.gradle" <<'GRADLE'
android {
    namespace namespaceFromEnvironment()
    defaultConfig {
        applicationId applicationIdFromEnvironment()
        versionCode 1 + calculateVersionCode()
        versionName calculateVersionName()
    }
}
GRADLE
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_dynamic_flavor() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
android {
    namespace = "com.example.dynamic"
    defaultConfig {
        applicationId = "com.example.dynamic"
        versionCode = 45
        versionName = "1.2.3"
    }
    productFlavors {
        create("release") {
            applicationIdSuffix = ".release"
        }
    }
    productFlavors {
        create(flavorNameFromEnvironment()) {
            applicationIdSuffix = ".dynamic"
        }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_dynamic_suffix() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  cat > "$inspection_project/android/app/build.gradle" <<'GRADLE'
android {
    namespace "com.example.base"
    defaultConfig {
        applicationId "com.example.base"
        versionCode 45
        versionName "1.2.3"
    }
    productFlavors {
        release {
            applicationIdSuffix ".release" + suffixFromEnvironment()
        }
    }
}
GRADLE
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
  printf 'void main() {}\n' > "$inspection_project/lib/main_release.dart"
}

inspection_make_literal_suffix() {
  inspection_project=$1
  inspection_make_dynamic_suffix "$inspection_project"
  sed 's/applicationIdSuffix .*/applicationIdSuffix ".release"/' \
    "$inspection_project/android/app/build.gradle" \
    > "$inspection_project/android/app/build.gradle.next"
  mv "$inspection_project/android/app/build.gradle.next" \
    "$inspection_project/android/app/build.gradle"
}

inspection_make_release_suffix() {
  inspection_project=$1
  inspection_suffix_expression=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<KOTLIN
android {
    namespace = "com.example.base"
    defaultConfig {
        applicationId = "com.example.base"
        versionCode = 45
        versionName = "1.2.3"
    }
    productFlavors {
        create("release") {
            applicationIdSuffix = ".flavor"
        }
    }
    buildTypes {
        getByName("release") {
            applicationIdSuffix = $inspection_suffix_expression
        }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
  printf 'void main() {}\n' > "$inspection_project/lib/main_release.dart"
}

inspection_make_release_suffix_without_flavors() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
android {
    namespace = "com.example.base"
    defaultConfig {
        applicationId = "com.example.base"
        versionCode = 45
        versionName = "1.2.3"
    }
    buildTypes {
        getByName("release") {
        }
    }
    buildTypes {
        getByName("release") {
            applicationIdSuffix = ".store"
        }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_signing_reference() {
  inspection_project=$1
  inspection_signing_expression=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<KOTLIN
android {
    namespace = "com.example.signing"
    defaultConfig {
        applicationId = "com.example.signing"
        versionCode = 45
        versionName = "1.2.3"
    }
    buildTypes {
        named("release") {
            signingConfig = $inspection_signing_expression
        }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_nested_release_assignments() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
android {
    namespace = "com.example.nested"
    defaultConfig {
        applicationId = "com.example.nested"
        versionCode = 45
        versionName = "1.2.3"
    }
    buildTypes {
        named("release") {
            if (enableConditionalRelease) {
                applicationIdSuffix = ".conditional"
                signingConfig = signingConfigs.named("debug").get()
            }
        }
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_mixed_versions() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  printf 'VERSION_NAME=7.4.0\nVERSION_CODE=740\n' \
    > "$inspection_project/android/gradle.properties"
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
android {
    namespace = "com.example.versions"
    defaultConfig {
        applicationId = "com.example.versions"
        versionCode = (project.findProperty("VERSION_CODE") ?: "1").toString().toInt() + calculateOffset()
        versionName = (project.findProperty("VERSION_NAME") ?: "1.0").toString() + versionSuffix()
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_version_mutations() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  printf 'VERSION_NAME=7.4.0\nVERSION_CODE=740\n' \
    > "$inspection_project/android/gradle.properties"
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  cat > "$inspection_project/android/app/build.gradle.kts" <<'KOTLIN'
android {
    namespace = "com.example.mutations"
    defaultConfig {
        applicationId = "com.example.mutations"
        versionCode = (project.findProperty("VERSION_CODE") ?: "1").toString().toInt()
        versionCode += calculateOffset()
        versionName = (project.findProperty("VERSION_NAME") ?: "1.0").toString()
        versionName += versionSuffix()
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_multidimension() {
  inspection_project=$1
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  cat > "$inspection_project/android/app/build.gradle" <<'GRADLE'
android {
    namespace "com.example.multi"
    defaultConfig {
        applicationId "com.example.multi"
        versionCode 45
        versionName "1.2.3"
    }
    flavorDimensions configuredDimensions
    productFlavors {
        free {
            dimension tierDimension
            applicationIdSuffix ".free"
        }
        production {
            dimension environmentDimension
            applicationIdSuffix ".production"
        }
    }
}
GRADLE
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_flavor_callback() {
  inspection_project=$1
  inspection_callback=$2
  inspection_callback_mode=${3:-mutation}
  case "$inspection_callback_mode" in
    read_only)
      inspection_callback_header="$inspection_callback { flavor ->"
      inspection_callback_statement='println flavor.applicationIdSuffix'
      ;;
    mutation)
      case "$inspection_callback" in
        each|forEach) inspection_callback_header="$inspection_callback { flavor ->" ;;
        *) inspection_callback_header="$inspection_callback {" ;;
      esac
      inspection_callback_statement='applicationIdSuffix ".common"'
      ;;
    *) fail 'unknown flavor callback fixture mode' ;;
  esac
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  cat > "$inspection_project/android/app/build.gradle" <<GRADLE
android {
    namespace "com.example.callback"
    defaultConfig {
        applicationId "com.example.callback"
        versionCode 45
        versionName "1.2.3"
    }
    productFlavors {
        release {
            applicationIdSuffix ".release"
        }
        $inspection_callback_header
            $inspection_callback_statement
        }
    }
}
GRADLE
  printf 'void main() {}\n' > "$inspection_project/lib/main_release.dart"
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_flavor_identity_case() {
  inspection_project=$1
  inspection_identity_case=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  case "$inspection_identity_case" in
    nested)
      inspection_flavor_body='            if (enableIdentity) {
                applicationIdSuffix ".conditional"
            }'
      ;;
    inline)
      inspection_flavor_body='            if (enableIdentity) applicationId "com.example.inline"'
      ;;
    duplicate)
      inspection_flavor_body='            applicationId "com.example.first"
            applicationId "com.example.second"'
      ;;
    mutation)
      inspection_flavor_body='            applicationIdSuffix ".first"
            applicationIdSuffix += ".later"'
      ;;
    *) fail 'unknown flavor identity fixture case' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle" <<GRADLE
android {
    namespace "com.example.identity"
    defaultConfig {
        applicationId "com.example.identity"
        versionCode 45
        versionName "1.2.3"
    }
    productFlavors {
        release {
$inspection_flavor_body
        }
    }
}
GRADLE
  printf 'void main() {}\n' > "$inspection_project/lib/main_release.dart"
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_default_config_case() {
  inspection_project=$1
  inspection_default_case=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  case "$inspection_default_case" in
    compact)
      inspection_default_body='    defaultConfig { applicationId = "com.example.defaults" }
    defaultConfig { versionCode = 77 }
    defaultConfig { versionName = "7.7.0" }'
      ;;
    repeated_dynamic)
      inspection_default_body='    defaultConfig {
        applicationId = "com.example.stale"
        versionCode = 77
        versionName = "7.7.0"
    }
    defaultConfig { applicationId = applicationIdFromEnvironment() }
    defaultConfig { versionCode += calculateOffset() }
    defaultConfig { if (usePreviewVersion) versionName = "8.0.0" }'
      ;;
    nested)
      inspection_default_body='    defaultConfig {
        applicationId = "com.example.stale"
        versionCode = 77
        versionName = "7.7.0"
        if (useNestedDefaults) {
            applicationId = "com.example.nested"
            versionCode = 88
            versionName = "8.8.0"
        }
    }'
      ;;
    *) fail 'unknown defaultConfig fixture case' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle.kts" <<KOTLIN
android {
    namespace = "com.example.defaults"
$inspection_default_body
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_java_case() {
  inspection_project=$1
  inspection_java_case=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  case "$inspection_java_case" in
    compact)
      inspection_java_body='    compileOptions { sourceCompatibility = JavaVersion.VERSION_1_8; targetCompatibility = JavaVersion.VERSION_1_8 }'
      ;;
    later_override)
      inspection_java_body='    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        sourceCompatibility = javaVersionFromEnvironment()
    }'
      ;;
    mixed)
      inspection_java_body='    compileOptions {
        sourceCompatibility = if (useModernJava) JavaVersion.VERSION_21 else JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }'
      ;;
    inconsistent)
      inspection_java_body='    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_21
    }'
      ;;
    *) fail 'unknown Java fixture case' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle.kts" <<KOTLIN
android {
    namespace = "com.example.java"
$inspection_java_body
    defaultConfig {
        applicationId = "com.example.java"
        versionCode = 45
        versionName = "1.2.3"
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_make_compact_release_case() {
  inspection_project=$1
  inspection_release_case=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  case "$inspection_release_case" in
    static)
      inspection_release_line='    buildTypes { release { applicationIdSuffix ".store"; signingConfig signingConfigs.upload } }'
      ;;
    dynamic)
      inspection_release_line='    buildTypes { release { applicationIdSuffix ".store" + suffixFromEnvironment(); signingConfig useDebug ? signingConfigs.debug : signingConfigs.upload } }'
      ;;
    *) fail 'unknown compact release fixture case' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle" <<GRADLE
android {
    namespace "com.example.compactrelease"
    defaultConfig {
        applicationId "com.example.compactrelease"
        versionCode 45
        versionName "1.2.3"
    }
$inspection_release_line
}
GRADLE
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_qualified_write_case() {
  inspection_project=$1
  inspection_qualified_case=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle" <<'GRADLE'
plugins {
    id "com.android.application" version "8.5.2" apply false
}
GRADLE
  case "$inspection_qualified_case" in
    default_version)
      inspection_qualified_body='    defaultConfig.versionCode += calculateOffset()'
      ;;
    flavor_container)
      inspection_qualified_body='    productFlavors.create("release") {
        applicationIdSuffix = ".release"
    }'
      ;;
    release)
      inspection_qualified_body='    buildTypes {
        release {
            applicationIdSuffix ".store"
            signingConfig signingConfigs.upload
        }
    }
    buildTypes.release.applicationIdSuffix = suffixFromEnvironment()
    buildTypes.release.signingConfig = signingConfigs.debug'
      ;;
    read_only_flavor_query)
      inspection_qualified_body='    productFlavors {
        release {
            applicationIdSuffix ".release"
        }
    }
    if (productFlavors.findByName("release") != null) {
        println "release flavor exists"
    }'
      ;;
    flavor_factory_statement)
      inspection_qualified_body='    productFlavors.create("release")'
      ;;
    setter_calls)
      inspection_qualified_body='    buildTypes {
        release {
            applicationIdSuffix ".store"
            signingConfig signingConfigs.upload
        }
    }
    defaultConfig.versionCode calculateOffset()
    buildTypes.release.applicationIdSuffix(suffixFromEnvironment())
    buildTypes.release.signingConfig(signingConfigs.debug)'
      ;;
    *) fail 'unknown qualified Gradle write fixture case' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle" <<GRADLE
android {
    namespace "com.example.qualified"
    defaultConfig {
        applicationId "com.example.qualified"
        versionCode 45
        versionName "1.2.3"
    }
$inspection_qualified_body
}
GRADLE
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle" groovy
}

inspection_make_duplicate_properties() {
  inspection_project=$1
  inspection_property_source=$2
  inspection_write_pubspec "$inspection_project" dev_dependencies
  inspection_write_wrapper "$inspection_project" 8.7
  cat > "$inspection_project/android/settings.gradle.kts" <<'KOTLIN'
plugins {
    id("com.android.application") version "8.5.2" apply false
}
KOTLIN
  case "$inspection_property_source" in
    gradle)
      cat > "$inspection_project/android/gradle.properties" <<'PROPERTIES'
VERSION_NAME=1.0.0
VERSION_CODE=100
VERSION_NAME = 2.0.0
VERSION_CODE = 200
PROPERTIES
      inspection_version_code='(project.findProperty("VERSION_CODE") ?: "1").toString().toInt()'
      inspection_version_name='(project.findProperty("VERSION_NAME") ?: "1.0").toString()'
      ;;
    flutter)
      cat > "$inspection_project/android/local.properties" <<'PROPERTIES'
flutter.versionName=3.0.0
flutter.versionCode=300
flutter.versionName = 4.0.0
flutter.versionCode = 400
PROPERTIES
      inspection_version_code='flutter.versionCode'
      inspection_version_name='flutter.versionName'
      ;;
    continuation)
      cat > "$inspection_project/android/local.properties" <<'PROPERTIES'
flutter.versionName=3.0.0
flutter.versionCode=300
OTHER_NAME=prefix\
flutter.versionName=4.0.0
OTHER_CODE=prefix\
flutter.versionCode=400
PROPERTIES
      inspection_version_code='flutter.versionCode'
      inspection_version_name='flutter.versionName'
      ;;
    *) fail 'unknown duplicate property fixture source' ;;
  esac
  cat > "$inspection_project/android/app/build.gradle.kts" <<KOTLIN
android {
    namespace = "com.example.properties"
    defaultConfig {
        applicationId = "com.example.properties"
        versionCode = $inspection_version_code
        versionName = $inspection_version_name
    }
}
KOTLIN
  inspection_append_execution_canary \
    "$inspection_project/android/app/build.gradle.kts" kotlin
}

inspection_assert_no_canary_logs() {
  for inspection_canary in \
    FPRS_GRADLE_SECRET_CANARY_18d90b \
    FPRS_FIREBASE_PROJECT_CANARY_7364f1 \
    FPRS_FIREBASE_API_KEY_CANARY_aa90e2
  do
    if grep -R -F -- "$inspection_canary" "$INSPECTION_LOGS" >/dev/null 2>&1; then
      fail 'inspection output exposed a secret canary'
    fi
  done
}

inspection() {
  INSPECTOR="$PACKAGE_ROOT/scripts/inspect_flutter_project.sh"
  INSPECTION_ROOT="$TMP_ROOT/inspection fixtures"
  INSPECTION_LOGS="$INSPECTION_ROOT/logs"
  inspection_case_index=0
  mkdir -p "$INSPECTION_LOGS"

  groovy_project="$INSPECTION_ROOT/path with spaces/groovy app"
  inspection_make_groovy "$groovy_project"
  groovy_project=$(CDPATH= cd -- "$groovy_project" && pwd -P) ||
    fail 'could not resolve Groovy fixture physically'
  exec_marker="$INSPECTION_ROOT/project-command-executed"
  export FPRS_INSPECTION_EXEC_MARKER="$exec_marker"

  inspection_assert_status 'minimal Groovy JSON inspection failed' 0 \
    "$INSPECTOR" --project "$groovy_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  assert_empty_file "$INSPECTION_LAST_STDERR" 'successful JSON inspection wrote diagnostics to stderr'
  [ ! -e "$exec_marker" ] || fail 'inspection evaluated the Gradle project'
  cat > "$INSPECTION_ROOT/expected-groovy.json" <<EOF
{"schema_version":1,"project_root":"$groovy_project","flutter_constraint":">=3.19.0","dart_constraint":">=3.3.0 <4.0.0","flutter_version":null,"android_dsl":"groovy","gradle_file":"android/app/build.gradle","android_gradle_plugin_version":"8.5.2","gradle_wrapper_version":"8.7","java_compatibility":"17","application_id":"com.example.release","namespace":"com.example.release","application_id_candidates":["com.example.release"],"version_name":"1.2.3","version_code":"45","pubspec_version_name":"1.2.3","pubspec_build_number":"45","flavors":[],"selected_flavor":null,"suggested_flavor":null,"suggestion_confirmed":false,"entrypoints":["lib/main.dart"],"build_runner":true,"fastlane":false,"github_actions":false,"release_signing":true,"release_uses_debug_signing":false,"firebase":false,"firebase_package_names":[],"firebase_apps":[],"firebase_app_distribution":false,"monorepo":false,"git_dirty":null,"files_bootstrap_may_change":["android/Gemfile","android/Gemfile.lock","android/fastlane/Appfile","android/fastlane/Fastfile","android/fastlane/Pluginfile","android/fastlane/lib/flutter_play_store_release.rb","android/fastlane/.env.example","android/key.properties.example",".github/workflows/release-android.yml","docs/PLAY_STORE_RELEASE.md","tool/flutter-play-store-release/decode_secret.sh","tool/flutter-play-store-release/install_flutter_sdk.sh","tool/flutter-play-store-release/managed-files.sha256",".gitignore","android/app/build.gradle"],"warnings":[],"failures":[]}
EOF
  assert_same_file \
    "$INSPECTION_ROOT/expected-groovy.json" \
    "$INSPECTION_LAST_STDOUT" \
    'minimal Groovy JSON changed'

  inspection_assert_status 'minimal Groovy human inspection failed' 0 \
    "$INSPECTOR" --project "$groovy_project" --format human
  assert_empty_file "$INSPECTION_LAST_STDERR" 'successful human inspection wrote diagnostics to stderr'
  cat > "$INSPECTION_ROOT/expected-groovy.human" <<EOF
Flutter project inspection
Schema version: 1
Project root: $groovy_project
Flutter constraint: >=3.19.0
Dart constraint: >=3.3.0 <4.0.0
Flutter version: unknown
Android DSL: groovy
Gradle file: android/app/build.gradle
Android Gradle plugin: 8.5.2
Gradle wrapper: 8.7
Java compatibility: 17
Application ID: com.example.release
Namespace: com.example.release
Application ID candidates: com.example.release
Version name: 1.2.3
Version code: 45
Pubspec version name: 1.2.3
Pubspec build number: 45
Flavors: none
Selected flavor: none
Suggested flavor: none
Suggestion confirmed: no
Entrypoints: lib/main.dart
Build runner: yes
Fastlane: no
GitHub Actions: no
Release signing: yes
Release uses debug signing: no
Firebase: no
Firebase package names: none
Firebase apps: none
Firebase App Distribution: no
Monorepo: no
Git dirty: unknown
Files bootstrap may change: android/Gemfile, android/Gemfile.lock, android/fastlane/Appfile, android/fastlane/Fastfile, android/fastlane/Pluginfile, android/fastlane/lib/flutter_play_store_release.rb, android/fastlane/.env.example, android/key.properties.example, .github/workflows/release-android.yml, docs/PLAY_STORE_RELEASE.md, tool/flutter-play-store-release/decode_secret.sh, tool/flutter-play-store-release/install_flutter_sdk.sh, tool/flutter-play-store-release/managed-files.sha256, .gitignore, android/app/build.gradle
Warnings: none
Failures: none
EOF
  assert_same_file \
    "$INSPECTION_ROOT/expected-groovy.human" \
    "$INSPECTION_LAST_STDOUT" \
    'minimal Groovy human report changed'

  ln -s "$groovy_project" "$INSPECTION_ROOT/groovy alias"
  inspection_assert_status 'physical project-root resolution failed' 0 \
    "$INSPECTOR" --project "$INSPECTION_ROOT/groovy alias" --format json
  inspection_assert_json_fragment \
    "$INSPECTION_LAST_STDOUT" \
    "\"project_root\":\"$groovy_project\"" \
    'inspection did not resolve the project root physically'

  minimal_kotlin_project="$INSPECTION_ROOT/minimal kotlin app"
  inspection_make_minimal_kotlin "$minimal_kotlin_project"
  inspection_assert_status 'minimal Kotlin JSON inspection failed' 0 \
    "$INSPECTOR" --project "$minimal_kotlin_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"android_dsl":"kotlin","gradle_file":"android/app/build.gradle.kts","android_gradle_plugin_version":"8.6.1","gradle_wrapper_version":"8.9","java_compatibility":"8"' \
    'minimal Kotlin Gradle fields changed'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.kotlin","namespace":"com.example.kotlin","application_id_candidates":["com.example.kotlin"]' \
    'minimal Kotlin application identity changed'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":"1.2.3","version_code":"1045"' \
    'minimal Kotlin numeric version literal changed'

  kotlin_project="$INSPECTION_ROOT/kotlin app"
  inspection_make_kotlin "$kotlin_project"
  inspection_assert_status 'ambiguous Kotlin flavor inspection did not use exit 2' 2 \
    "$INSPECTOR" --project "$kotlin_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"android_dsl":"kotlin"' 'Kotlin DSL was not detected'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null' 'ambiguous flavor unexpectedly selected an application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id_candidates":["com.acme.mobile.release","com.acme.mobile.staging"]' \
    'flavor application-ID candidates changed'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"flavors":["release","staging"]' 'Kotlin flavors changed'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"selected_flavor":null,"suggested_flavor":"release","suggestion_confirmed":false' \
    'entrypoint flavor suggestion was not conservative'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"failures":["multiple product flavors require --flavor"]' \
    'ambiguous flavors did not produce a stable failure'
  grep -F 'multiple product flavors require --flavor' "$INSPECTION_LAST_STDERR" >/dev/null 2>&1 ||
    fail 'ambiguous JSON inspection did not diagnose on stderr'

  inspection_assert_status 'explicit Kotlin release flavor inspection failed' 0 \
    "$INSPECTOR" --project "$kotlin_project" --format json --flavor release
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  assert_empty_file "$INSPECTION_LAST_STDERR" 'selected Kotlin flavor emitted diagnostics'
  for inspection_fragment in \
    '"flutter_constraint":"3.22.0","dart_constraint":">=3.4.0 <4.0.0","flutter_version":"3.22.3"' \
    '"android_gradle_plugin_version":"8.7.3","gradle_wrapper_version":"8.10.2","java_compatibility":"21"' \
    '"application_id":"com.acme.mobile.release","namespace":"com.acme.shell"' \
    '"version_name":"7.4.0","version_code":"740","pubspec_version_name":"3.0.0","pubspec_build_number":"300"' \
    '"selected_flavor":"release","suggested_flavor":"release","suggestion_confirmed":false' \
    '"entrypoints":["lib/main.dart","lib/main_release.dart"],"build_runner":true' \
    '"fastlane":true,"github_actions":true,"release_signing":false,"release_uses_debug_signing":true,"firebase":true' \
    '"firebase_package_names":["com.acme.mobile.release","com.acme.legacy"]' \
    '"firebase_apps":[{"package_name":"com.acme.mobile.release","app_id":"1:123456789:android:releaseabc","matches_application_id":true},{"package_name":"com.acme.legacy","app_id":"1:123456789:android:legacyabc","matches_application_id":false}]' \
    '"firebase_app_distribution":true' \
    '"files_bootstrap_may_change":["android/Gemfile","android/Gemfile.lock","android/fastlane/Appfile","android/fastlane/Fastfile","android/fastlane/Pluginfile","android/fastlane/lib/flutter_play_store_release.rb","android/fastlane/.env.example","android/key.properties.example",".github/workflows/release-android.yml","docs/PLAY_STORE_RELEASE.md","tool/flutter-play-store-release/decode_secret.sh","tool/flutter-play-store-release/install_flutter_sdk.sh","tool/flutter-play-store-release/managed-files.sha256",".gitignore","android/app/build.gradle.kts"]' \
    '"warnings":["namespace differs from default application ID","release build type uses debug signing"],"failures":[]'
  do
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" "$inspection_fragment" \
      "selected Kotlin inspection missing: $inspection_fragment"
  done
  if grep -E 'com\.(oauth|global|cross)\.noise' "$INSPECTION_LAST_STDOUT" >/dev/null 2>&1; then
    fail 'Firebase inspection paired an app ID with a package outside client_info.android_client_info'
  fi

  dynamic_flavor_project="$INSPECTION_ROOT/dynamic flavor declaration app"
  inspection_make_dynamic_flavor "$dynamic_flavor_project"
  inspection_assert_status 'dynamic product flavor declaration inspection failed' 0 \
    "$INSPECTOR" --project "$dynamic_flavor_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.dynamic","application_id_candidates":[]' \
    'dynamic product flavor declaration fell back to the base application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["product flavor declarations could not be resolved"]' \
    'dynamic product flavor declaration warning changed'

  dynamic_suffix_project="$INSPECTION_ROOT/dynamic suffix app"
  inspection_make_dynamic_suffix "$dynamic_suffix_project"
  inspection_assert_status 'dynamic application-ID suffix inspection failed' 0 \
    "$INSPECTOR" --project "$dynamic_suffix_project" --format json --flavor release
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.base","application_id_candidates":[]' \
    'dynamic suffix was collapsed into a concrete release application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["application ID suffix expression could not be resolved for flavor release"]' \
    'dynamic suffix warning changed'

  literal_suffix_project="$INSPECTION_ROOT/literal suffix app"
  inspection_make_literal_suffix "$literal_suffix_project"
  inspection_assert_status 'literal application-ID suffix inspection failed' 0 \
    "$INSPECTOR" --project "$literal_suffix_project" --format json --flavor release
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.base.release","namespace":"com.example.base","application_id_candidates":["com.example.base.release"]' \
    'literal suffix release identity changed'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'normal namespace/base identity produced a flavor suffix mismatch warning'

  release_suffix_project="$INSPECTION_ROOT/release build suffix app"
  inspection_make_release_suffix "$release_suffix_project" '".store"'
  inspection_assert_status 'literal release build suffix inspection failed' 0 \
    "$INSPECTOR" --project "$release_suffix_project" --format json --flavor release
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.base.flavor.store","namespace":"com.example.base","application_id_candidates":["com.example.base.flavor.store"]' \
    'release build suffix was not appended after the flavor suffix'

  no_flavor_release_suffix_project="$INSPECTION_ROOT/no-flavor release build suffix app"
  inspection_make_release_suffix_without_flavors "$no_flavor_release_suffix_project"
  inspection_assert_status 'no-flavor release build suffix inspection failed' 0 \
    "$INSPECTOR" --project "$no_flavor_release_suffix_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.base.store","namespace":"com.example.base","application_id_candidates":["com.example.base.store"]' \
    'release build suffix was not applied without product flavors'

  dynamic_release_suffix_project="$INSPECTION_ROOT/dynamic release build suffix app"
  inspection_make_release_suffix "$dynamic_release_suffix_project" \
    '".store" + suffixFromEnvironment()'
  inspection_assert_status 'dynamic release build suffix inspection failed' 0 \
    "$INSPECTOR" --project "$dynamic_release_suffix_project" --format json --flavor release
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.base","application_id_candidates":[]' \
    'dynamic release build suffix produced a concrete application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release application ID suffix expression could not be resolved"]' \
    'dynamic release build suffix warning changed'

  named_debug_signing_project="$INSPECTION_ROOT/named debug signing app"
  inspection_make_signing_reference "$named_debug_signing_project" \
    'signingConfigs.named("debug").get()'
  inspection_assert_status 'Kotlin named debug signing inspection failed' 0 \
    "$INSPECTOR" --project "$named_debug_signing_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":true' \
    'Kotlin named debug signing was not classified as debug signing'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release build type uses debug signing"]' \
    'Kotlin named debug signing warning changed'

  named_upload_signing_project="$INSPECTION_ROOT/named upload signing app"
  inspection_make_signing_reference "$named_upload_signing_project" \
    'signingConfigs.named("upload").get()'
  inspection_assert_status 'Kotlin named upload signing inspection failed' 0 \
    "$INSPECTOR" --project "$named_upload_signing_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":true,"release_uses_debug_signing":false' \
    'Kotlin named upload signing was not classified as non-debug signing'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'Kotlin named upload signing emitted a warning'

  conditional_signing_project="$INSPECTION_ROOT/conditional signing app"
  inspection_make_signing_reference "$conditional_signing_project" \
    'if (useDebugSigning) signingConfigs.debug else signingConfigs.upload'
  inspection_assert_status 'conditional release signing inspection failed' 0 \
    "$INSPECTOR" --project "$conditional_signing_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":false' \
    'conditional release signing expression was classified as a direct reference'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release signing expression could not be resolved"]' \
    'conditional release signing warning changed'

  nested_release_project="$INSPECTION_ROOT/nested conditional release assignments app"
  inspection_make_nested_release_assignments "$nested_release_project"
  inspection_assert_status 'nested conditional release assignment inspection failed' 0 \
    "$INSPECTOR" --project "$nested_release_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.nested","application_id_candidates":[]' \
    'nested release suffix assignment produced a concrete application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":false' \
    'nested release signing assignment was classified as direct'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release application ID suffix expression could not be resolved","release signing expression could not be resolved"]' \
    'nested conditional release warnings changed'

  mixed_versions_project="$INSPECTION_ROOT/mixed version expressions app"
  inspection_make_mixed_versions "$mixed_versions_project"
  inspection_assert_status 'mixed version property expression inspection failed' 0 \
    "$INSPECTOR" --project "$mixed_versions_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":null,"version_code":null' \
    'mixed version expressions were collapsed to property values'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["version code expression could not be resolved","version name expression could not be resolved"]' \
    'mixed version expression warnings changed'

  version_mutations_project="$INSPECTION_ROOT/version property mutations app"
  inspection_make_version_mutations "$version_mutations_project"
  inspection_assert_status 'version property mutation inspection failed' 0 \
    "$INSPECTOR" --project "$version_mutations_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":null,"version_code":null' \
    'later version mutations did not invalidate allowlisted property assignments'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["version code expression could not be resolved","version name expression could not be resolved"]' \
    'version mutation warnings changed'

  for callback_name in all configureEach each forEach
  do
    callback_project="$INSPECTION_ROOT/$callback_name flavor callback app"
    inspection_make_flavor_callback "$callback_project" "$callback_name"
    inspection_assert_status "$callback_name flavor callback inspection failed" 0 \
      "$INSPECTOR" --project "$callback_project" --format json --flavor release
    inspection_assert_schema "$INSPECTION_LAST_STDOUT"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"application_id":null,"namespace":"com.example.callback","application_id_candidates":[]' \
      "$callback_name flavor callback produced a concrete application ID"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"flavors":["release"],"selected_flavor":"release"' \
      "$callback_name callback was reported as a product flavor"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"warnings":["product flavor declarations could not be resolved"]' \
      "$callback_name flavor callback warning changed"
  done

  read_only_callback_project="$INSPECTION_ROOT/read-only flavor callback app"
  inspection_make_flavor_callback "$read_only_callback_project" all read_only
  inspection_assert_status 'read-only flavor callback inspection failed' 0 \
    "$INSPECTOR" --project "$read_only_callback_project" --format json --flavor release
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.callback.release","namespace":"com.example.callback","application_id_candidates":["com.example.callback.release"]' \
    'read-only flavor callback poisoned release identity'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"flavors":["release"],"selected_flavor":"release"' \
    'read-only flavor callback changed flavor discovery'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'read-only flavor callback emitted a warning'

  qualified_default_project="$INSPECTION_ROOT/qualified default version app"
  inspection_make_qualified_write_case "$qualified_default_project" default_version
  inspection_assert_status 'qualified defaultConfig version mutation inspection failed' 0 \
    "$INSPECTOR" --project "$qualified_default_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.qualified","namespace":"com.example.qualified","application_id_candidates":["com.example.qualified"]' \
    'qualified defaultConfig version mutation invalidated the application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":"1.2.3","version_code":null' \
    'qualified defaultConfig version mutation returned the stale version code'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["version code expression could not be resolved"]' \
    'qualified defaultConfig version mutation warning changed'

  qualified_flavor_project="$INSPECTION_ROOT/qualified flavor container app"
  inspection_make_qualified_write_case "$qualified_flavor_project" flavor_container
  inspection_assert_status 'qualified productFlavors container inspection failed' 0 \
    "$INSPECTOR" --project "$qualified_flavor_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.qualified","application_id_candidates":[]' \
    'qualified productFlavors container fell back to the base application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"flavors":[],"selected_flavor":null' \
    'qualified productFlavors container produced a speculative flavor'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["product flavor declarations could not be resolved"]' \
    'qualified productFlavors container warning changed'

  qualified_release_project="$INSPECTION_ROOT/qualified release writes app"
  inspection_make_qualified_write_case "$qualified_release_project" release
  inspection_assert_status 'qualified release write inspection failed' 0 \
    "$INSPECTOR" --project "$qualified_release_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.qualified","application_id_candidates":[]' \
    'qualified release suffix write returned the earlier application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":false' \
    'qualified release signing write returned the earlier signing state'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release application ID suffix expression could not be resolved","release signing expression could not be resolved"]' \
    'qualified release write warnings changed'

  read_only_flavor_project="$INSPECTION_ROOT/read-only qualified flavor query app"
  inspection_make_qualified_write_case "$read_only_flavor_project" read_only_flavor_query
  inspection_assert_status 'read-only qualified productFlavors query inspection failed' 0 \
    "$INSPECTOR" --project "$read_only_flavor_project" --format json --flavor release
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.qualified.release","namespace":"com.example.qualified","application_id_candidates":["com.example.qualified.release"]' \
    'read-only qualified productFlavors query poisoned release identity'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"flavors":["release"],"selected_flavor":"release"' \
    'read-only qualified productFlavors query changed flavor discovery'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'read-only qualified productFlavors query emitted a warning'

  factory_statement_project="$INSPECTION_ROOT/qualified flavor factory statement app"
  inspection_make_qualified_write_case "$factory_statement_project" flavor_factory_statement
  inspection_assert_status 'qualified productFlavors factory statement inspection failed' 0 \
    "$INSPECTOR" --project "$factory_statement_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.qualified","application_id_candidates":[]' \
    'qualified productFlavors factory statement fell back to the base application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["product flavor declarations could not be resolved"]' \
    'qualified productFlavors factory statement warning changed'

  setter_call_project="$INSPECTION_ROOT/qualified setter call app"
  inspection_make_qualified_write_case "$setter_call_project" setter_calls
  inspection_assert_status 'qualified Gradle setter call inspection failed' 0 \
    "$INSPECTOR" --project "$setter_call_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.qualified","application_id_candidates":[]' \
    'qualified Gradle setter call returned the earlier application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":"1.2.3","version_code":null' \
    'qualified Gradle setter call returned the earlier version code'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":false' \
    'qualified Gradle signing call returned the earlier signing state'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["version code expression could not be resolved","release application ID suffix expression could not be resolved","release signing expression could not be resolved"]' \
    'qualified Gradle setter call warnings changed'

  for identity_case in nested inline duplicate mutation
  do
    identity_project="$INSPECTION_ROOT/$identity_case flavor identity app"
    inspection_make_flavor_identity_case "$identity_project" "$identity_case"
    inspection_assert_status "$identity_case flavor identity inspection failed" 0 \
      "$INSPECTOR" --project "$identity_project" --format json --flavor release
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"application_id":null,"namespace":"com.example.identity","application_id_candidates":[]' \
      "$identity_case flavor identity produced a concrete application ID"
    case "$identity_case" in
      nested|mutation) identity_warning='application ID suffix expression could not be resolved for flavor release' ;;
      inline|duplicate) identity_warning='application ID expression could not be resolved for flavor release' ;;
    esac
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      "\"warnings\":[\"$identity_warning\"]" \
      "$identity_case flavor identity warning changed"
  done

  compact_defaults_project="$INSPECTION_ROOT/compact default config app"
  inspection_make_default_config_case "$compact_defaults_project" compact
  inspection_assert_status 'compact defaultConfig inspection failed' 0 \
    "$INSPECTOR" --project "$compact_defaults_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.defaults","namespace":"com.example.defaults","application_id_candidates":["com.example.defaults"]' \
    'compact defaultConfig application ID was not resolved'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"version_name":"7.7.0","version_code":"77"' \
    'compact defaultConfig versions were not resolved'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'compact defaultConfig emitted warnings'

  for default_case in repeated_dynamic nested
  do
    default_project="$INSPECTION_ROOT/$default_case default config app"
    inspection_make_default_config_case "$default_project" "$default_case"
    inspection_assert_status "$default_case defaultConfig inspection failed" 0 \
      "$INSPECTOR" --project "$default_project" --format json
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"application_id":null,"namespace":"com.example.defaults","application_id_candidates":[]' \
      "$default_case defaultConfig returned a stale application ID"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"version_name":null,"version_code":null' \
      "$default_case defaultConfig returned stale versions"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"warnings":["application ID expression could not be resolved","version code expression could not be resolved","version name expression could not be resolved"]' \
      "$default_case defaultConfig warnings changed"
  done

  for property_source in gradle flutter continuation
  do
    duplicate_property_project="$INSPECTION_ROOT/duplicate $property_source properties app"
    inspection_make_duplicate_properties "$duplicate_property_project" "$property_source"
    inspection_assert_status "duplicate $property_source properties inspection failed" 0 \
      "$INSPECTOR" --project "$duplicate_property_project" --format json
    case "$property_source" in
      gradle) expected_duplicate_versions='"version_name":"2.0.0","version_code":"200"' ;;
      flutter) expected_duplicate_versions='"version_name":"4.0.0","version_code":"400"' ;;
      continuation) expected_duplicate_versions='"version_name":null,"version_code":null' ;;
    esac
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      "$expected_duplicate_versions" \
      "duplicate $property_source properties did not use the later entries"
    case "$property_source" in
      continuation)
        inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
          '"warnings":["version code expression could not be resolved","version name expression could not be resolved"],"failures":[]' \
          'continued property lines did not remain conservatively unresolved'
        ;;
      *)
        inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
          '"warnings":[],"failures":[]' \
          "plain duplicate $property_source properties emitted warnings"
        ;;
    esac
  done

  compact_java_project="$INSPECTION_ROOT/compact Java compatibility app"
  inspection_make_java_case "$compact_java_project" compact
  inspection_assert_status 'compact Java compatibility inspection failed' 0 \
    "$INSPECTOR" --project "$compact_java_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"java_compatibility":"8"' \
    'compact Java 8 compatibility was not normalized'

  for java_case in later_override mixed inconsistent
  do
    java_project="$INSPECTION_ROOT/$java_case Java compatibility app"
    inspection_make_java_case "$java_project" "$java_case"
    inspection_assert_status "$java_case Java compatibility inspection failed" 0 \
      "$INSPECTOR" --project "$java_project" --format json
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"java_compatibility":null' \
      "$java_case Java compatibility returned a concrete version"
    inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
      '"warnings":["Java compatibility expression could not be resolved"]' \
      "$java_case Java compatibility warning changed"
  done

  compact_release_project="$INSPECTION_ROOT/compact static release app"
  inspection_make_compact_release_case "$compact_release_project" static
  inspection_assert_status 'compact static release inspection failed' 0 \
    "$INSPECTOR" --project "$compact_release_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":"com.example.compactrelease.store","namespace":"com.example.compactrelease","application_id_candidates":["com.example.compactrelease.store"]' \
    'compact static release suffix was not resolved'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":true,"release_uses_debug_signing":false' \
    'compact static release signing was not resolved'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":[],"failures":[]' \
    'compact static release emitted warnings'

  compact_dynamic_release_project="$INSPECTION_ROOT/compact dynamic release app"
  inspection_make_compact_release_case "$compact_dynamic_release_project" dynamic
  inspection_assert_status 'compact dynamic release inspection failed' 0 \
    "$INSPECTOR" --project "$compact_dynamic_release_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.compactrelease","application_id_candidates":[]' \
    'compact dynamic release produced a concrete application ID'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"release_signing":false,"release_uses_debug_signing":false' \
    'compact conditional release signing produced a false green'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["release application ID suffix expression could not be resolved","release signing expression could not be resolved"]' \
    'compact dynamic release warnings changed'

  multidimension_project="$INSPECTION_ROOT/multiple flavor dimensions app"
  inspection_make_multidimension "$multidimension_project"
  inspection_assert_status 'multiple flavor dimensions did not remain ambiguous' 2 \
    "$INSPECTOR" --project "$multidimension_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":"com.example.multi","application_id_candidates":[]' \
    'multiple flavor dimensions produced nonexistent application-ID candidates'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["flavor dimension expressions prevent deterministic application ID resolution"]' \
    'multiple flavor dimension warning changed'

  override_only_project="$INSPECTION_ROOT/dependency override app"
  inspection_make_groovy "$override_only_project"
  cat > "$override_only_project/pubspec.yaml" <<'YAML'
name: dependency_override_fixture
environment:
  sdk: ">=3.3.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
dependency_overrides:
  build_runner: ^2.4.9
YAML
  inspection_assert_status 'dependency override inspection failed' 0 \
    "$INSPECTOR" --project "$override_only_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"build_runner":false' 'dependency_overrides was treated as a declared build_runner dependency'

  mkdir -p "$INSPECTION_ROOT/no dependency tools"
  for inspection_tool in jq python python3 ruby
  do
    cat > "$INSPECTION_ROOT/no dependency tools/$inspection_tool" <<'SH'
#!/bin/sh
exit 97
SH
    chmod +x "$INSPECTION_ROOT/no dependency tools/$inspection_tool"
  done
  inspection_assert_status 'inspection required a forbidden JSON dependency' 0 \
    env PATH="$INSPECTION_ROOT/no dependency tools:$PATH" \
    "$INSPECTOR" --project "$groovy_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_status 'Firebase inspection required a forbidden JSON dependency' 0 \
    env PATH="$INSPECTION_ROOT/no dependency tools:$PATH" \
    "$INSPECTOR" --project "$kotlin_project" --format json --flavor release
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"firebase_package_names":["com.acme.mobile.release","com.acme.legacy"]' \
    'dependency-free Firebase inspection changed scoped client mappings'

  unresolved_project="$INSPECTION_ROOT/unresolved expressions"
  inspection_make_unresolved "$unresolved_project"
  inspection_assert_status 'unresolved static expressions were treated as executable' 0 \
    "$INSPECTOR" --project "$unresolved_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"application_id":null,"namespace":null,"application_id_candidates":[]' \
    'unresolved identifiers were reported as concrete values'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"warnings":["application ID expression could not be resolved","namespace expression could not be resolved","version code expression could not be resolved","version name expression could not be resolved"]' \
    'unresolved expression warnings changed'

  monorepo_project="$INSPECTION_ROOT/monorepo workspace/apps/mobile"
  mkdir -p "$INSPECTION_ROOT/monorepo workspace"
  printf 'name: fixture_workspace\nworkspace:\n  - apps/mobile\n' \
    > "$INSPECTION_ROOT/monorepo workspace/pubspec.yaml"
  inspection_make_groovy "$monorepo_project"
  inspection_assert_status 'nested monorepo inspection failed' 0 \
    "$INSPECTOR" --project "$monorepo_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"monorepo":true' 'nested monorepo was not detected'

  dirty_project="$INSPECTION_ROOT/dirty git app"
  inspection_make_groovy "$dirty_project"
  git -C "$dirty_project" init -q || fail 'could not initialize Git fixture'
  git -C "$dirty_project" add . || fail 'could not stage Git fixture'
  git -C "$dirty_project" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgSign=false \
    commit -qm initial || fail 'could not commit Git fixture'
  printf '# dirty\n' >> "$dirty_project/pubspec.yaml"
  inspection_assert_status 'dirty Git inspection failed' 0 \
    "$INSPECTOR" --project "$dirty_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"git_dirty":true' 'dirty Git state was not detected'
  mkdir "$dirty_project/broken git index"
  inspection_assert_status 'Git status failure inspection failed' 0 \
    env GIT_INDEX_FILE="$dirty_project/broken git index" \
    "$INSPECTOR" --project "$dirty_project" --format json
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"git_dirty":null' 'Git status failure was misreported as a clean worktree'
  inspection_assert_json_fragment "$INSPECTION_ROOT/expected-groovy.json" \
    '"git_dirty":null' 'non-Git baseline fixture changed'

  non_flutter_parent="$INSPECTION_ROOT/non Flutter parent"
  inspection_make_groovy "$non_flutter_parent"
  mkdir -p "$non_flutter_parent/nested child"
  inspection_assert_status 'nested non-Flutter path was silently promoted upward' 2 \
    "$INSPECTOR" --project "$non_flutter_parent/nested child" --format json
  assert_empty_file "$INSPECTION_LAST_STDOUT" 'invalid project root emitted partial JSON'
  grep -F 'pubspec.yaml' "$INSPECTION_LAST_STDERR" >/dev/null 2>&1 ||
    fail 'invalid project root did not name the missing Flutter marker'

  both_dsl_project="$INSPECTION_ROOT/both DSL app"
  inspection_make_groovy "$both_dsl_project"
  printf 'android {}\n' > "$both_dsl_project/android/app/build.gradle.kts"
  inspection_assert_status 'both Android DSL files were accepted' 2 \
    "$INSPECTOR" --project "$both_dsl_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"android_dsl":"ambiguous","gradle_file":null' \
    'ambiguous DSL did not emit a complete typed state'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"failures":["android/app contains both build.gradle and build.gradle.kts"]' \
    'ambiguous DSL failure changed'
  grep -F 'both build.gradle and build.gradle.kts' "$INSPECTION_LAST_STDERR" >/dev/null 2>&1 ||
    fail 'ambiguous DSL diagnostic changed'

  missing_dsl_project="$INSPECTION_ROOT/missing DSL app"
  inspection_write_pubspec "$missing_dsl_project" dev_dependencies
  inspection_assert_status 'missing Android DSL file was accepted' 2 \
    "$INSPECTOR" --project "$missing_dsl_project" --format json
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"android_dsl":"missing","gradle_file":null' \
    'missing DSL did not emit a complete typed state'
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"failures":["android/app contains neither build.gradle nor build.gradle.kts"]' \
    'missing DSL failure changed'
  grep -F 'neither build.gradle nor build.gradle.kts' "$INSPECTION_LAST_STDERR" >/dev/null 2>&1 ||
    fail 'missing DSL diagnostic changed'
  inspection_assert_status 'missing Android DSL human report was not clear' 2 \
    "$INSPECTOR" --project "$missing_dsl_project" --format human
  grep -F 'Android DSL: missing' "$INSPECTION_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'missing DSL human report omitted the DSL state'
  grep -F 'Failures: android/app contains neither build.gradle nor build.gradle.kts' \
    "$INSPECTION_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'missing DSL human report omitted the failure'

  inspection_assert_status 'missing inspector arguments were accepted' 2 "$INSPECTOR"
  assert_empty_file "$INSPECTION_LAST_STDOUT" 'usage error wrote to stdout'
  grep -F 'Usage:' "$INSPECTION_LAST_STDERR" >/dev/null 2>&1 || fail 'usage diagnostic changed'
  inspection_assert_status 'invalid output format was accepted' 2 \
    "$INSPECTOR" --project "$groovy_project" --format yaml
  assert_empty_file "$INSPECTION_LAST_STDOUT" 'invalid format wrote to stdout'
  inspection_assert_status '--help was accepted after another option' 2 \
    "$INSPECTOR" --project "$groovy_project" --help
  assert_empty_file "$INSPECTION_LAST_STDOUT" 'ambiguous help arguments wrote to stdout'
  inspection_assert_status 'unknown flavor was accepted' 2 \
    "$INSPECTOR" --project "$kotlin_project" --format json --flavor missing
  inspection_assert_schema "$INSPECTION_LAST_STDOUT"
  inspection_assert_json_fragment "$INSPECTION_LAST_STDOUT" \
    '"failures":["requested flavor is not defined"]' \
    'unknown flavor failure changed'

  [ ! -e "$exec_marker" ] || fail 'an inspection mode evaluated the Gradle project'
  inspection_assert_no_canary_logs
  pass 'inspection'
}

project_transaction() {
  TRANSACTION_ROOT="$TMP_ROOT/project transaction/project with spaces"
  TRANSACTION_CANDIDATE="$TMP_ROOT/project transaction/candidate"
  TRANSACTION_LIBRARY="$PACKAGE_ROOT/scripts/lib/project_transaction.sh"
  mkdir -p "$TRANSACTION_ROOT/android/app" "${TRANSACTION_CANDIDATE%/*}"
  printf 'old bytes\r\n' > "$TRANSACTION_ROOT/android/app/build.gradle"
  chmod 640 "$TRANSACTION_ROOT/android/app/build.gradle"
  printf 'new bytes\r\n' > "$TRANSACTION_CANDIDATE"

  # shellcheck source=/dev/null
  . "$TRANSACTION_LIBRARY"
  type fprs_project_transaction_begin >/dev/null 2>&1 ||
    fail 'missing transaction begin function'
  type fprs_project_transaction_register >/dev/null 2>&1 ||
    fail 'missing transaction register function'
  type fprs_project_transaction_validate >/dev/null 2>&1 ||
    fail 'missing transaction validation function'
  type fprs_project_transaction_commit >/dev/null 2>&1 ||
    fail 'missing transaction commit function'

  fprs_project_transaction_begin "$TRANSACTION_ROOT" ||
    fail 'transaction begin failed'
  fprs_project_transaction_register \
    'android/app/build.gradle' "$TRANSACTION_CANDIDATE" ||
    fail 'transaction registration failed'
  fprs_project_transaction_validate ||
    fail 'transaction validation failed'
  fprs_project_transaction_commit ||
    fail 'transaction commit failed'

  assert_same_file "$TRANSACTION_CANDIDATE" \
    "$TRANSACTION_ROOT/android/app/build.gradle" \
    'transaction did not install the registered candidate'
  assert_mode 640 "$TRANSACTION_ROOT/android/app/build.gradle" \
    'transaction did not preserve the existing file mode'

  printf 'created bytes\n' > "$TRANSACTION_CANDIDATE"
  chmod 600 "$TRANSACTION_CANDIDATE"
  fprs_project_transaction_begin "$TRANSACTION_ROOT" ||
    fail 'create transaction begin failed'
  fprs_project_transaction_register \
    'tool/flutter-play-store-release/generated.txt' "$TRANSACTION_CANDIDATE" ||
    fail 'transaction could not register a target with missing parents'
  fprs_project_transaction_validate ||
    fail 'create transaction validation failed'
  fprs_project_transaction_commit ||
    fail 'create transaction commit failed'
  assert_same_file "$TRANSACTION_CANDIDATE" \
    "$TRANSACTION_ROOT/tool/flutter-play-store-release/generated.txt" \
    'transaction did not create a nested target'
  assert_mode 600 \
    "$TRANSACTION_ROOT/tool/flutter-play-store-release/generated.txt" \
    'transaction did not preserve the candidate mode for a created file'

  transaction_outside="$TMP_ROOT/project transaction/outside"
  mkdir -p "$transaction_outside"
  ln -s "$transaction_outside" "$TRANSACTION_ROOT/escape"
  fprs_project_transaction_begin "$TRANSACTION_ROOT" ||
    fail 'containment transaction begin failed'
  if fprs_project_transaction_register 'escape/refused.txt' "$TRANSACTION_CANDIDATE"; then
    fail 'transaction accepted a physical path outside the selected root'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 2 ] ||
    fail 'physical containment refusal did not return status 2'
  fprs_project_transaction_abort || fail 'containment transaction abort failed'

  transaction_lexical_root="$TMP_ROOT/project transaction/lexical aliases"
  mkdir -p "$transaction_lexical_root/a" "$transaction_lexical_root/b"
  printf 'pre-existing victim\r\n' > "$transaction_lexical_root/b/victim.txt"
  cp "$transaction_lexical_root/b/victim.txt" "$TMP_ROOT/lexical-victim.expected"
  fprs_project_transaction_begin "$transaction_lexical_root" ||
    fail 'lexical-alias transaction begin failed'
  if fprs_project_transaction_register 'a/../b/victim.txt' "$TRANSACTION_CANDIDATE"; then
    fail 'transaction accepted an internal parent traversal segment'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 2 ] ||
    fail 'internal parent traversal did not return status 2'
  fprs_project_transaction_abort || fail 'lexical-alias transaction abort failed'
  assert_same_file "$TMP_ROOT/lexical-victim.expected" \
    "$transaction_lexical_root/b/victim.txt" \
    'lexical alias registration changed a pre-existing victim'
  for transaction_bad_relative in 'a/./victim.txt' 'a//victim.txt' './victim.txt' 'a/'
  do
    fprs_project_transaction_begin "$transaction_lexical_root" ||
      fail 'ambiguous-relative transaction begin failed'
    if fprs_project_transaction_register "$transaction_bad_relative" \
      "$TRANSACTION_CANDIDATE"
    then
      fail "transaction accepted ambiguous relative path: $transaction_bad_relative"
    fi
    fprs_project_transaction_abort || fail 'ambiguous-relative transaction abort failed'
  done

  trap 'printf prior-hup >/dev/null' HUP
  trap 'printf prior-int >/dev/null' INT
  trap 'printf prior-term >/dev/null' TERM
  transaction_prior_hup=$(trap -p HUP)
  transaction_prior_int=$(trap -p INT)
  transaction_prior_term=$(trap -p TERM)
  fprs_project_transaction_begin "$transaction_lexical_root" ||
    fail 'trap-preservation transaction begin failed'
  fprs_project_transaction_abort || fail 'trap-preservation abort failed'
  [ "$(trap -p HUP)" = "$transaction_prior_hup" ] &&
    [ "$(trap -p INT)" = "$transaction_prior_int" ] &&
    [ "$(trap -p TERM)" = "$transaction_prior_term" ] ||
    fail 'transaction did not restore prior signal traps exactly'
  trap - HUP INT TERM

  transaction_race_root="$TMP_ROOT/project transaction/race"
  mkdir -p "$transaction_race_root"
  fprs_project_transaction_begin "$transaction_race_root" ||
    fail 'race transaction begin failed'
  fprs_project_transaction_register 'pre-existing-untracked.txt' \
    "$TRANSACTION_CANDIDATE" || fail 'race target registration failed'
  printf 'user-created during planning\n' > \
    "$transaction_race_root/pre-existing-untracked.txt"
  if fprs_project_transaction_validate; then
    fail 'transaction ignored a new pre-existing untracked file'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 2 ] ||
    fail 'new pre-existing path conflict did not return status 2'
  fprs_project_transaction_abort || fail 'race transaction abort failed'
  grep -F 'user-created during planning' \
    "$transaction_race_root/pre-existing-untracked.txt" >/dev/null 2>&1 ||
    fail 'transaction removed a pre-existing untracked file'

  transaction_reject_candidate() { return 1; }
  printf 'validation original\n' > "$transaction_race_root/validation.txt"
  printf 'validation replacement\n' > "$TRANSACTION_CANDIDATE"
  fprs_project_transaction_begin "$transaction_race_root" ||
    fail 'validation transaction begin failed'
  fprs_project_transaction_register validation.txt "$TRANSACTION_CANDIDATE" ||
    fail 'validation target registration failed'
  if fprs_project_transaction_validate transaction_reject_candidate; then
    fail 'transaction accepted a candidate rejected by pre-write validation'
  fi
  fprs_project_transaction_abort || fail 'validation transaction abort failed'
  [ "$(cat "$transaction_race_root/validation.txt")" = 'validation original' ] ||
    fail 'candidate validation failure changed the project'

  transaction_late_root="$TMP_ROOT/project transaction/late target"
  mkdir -p "$transaction_late_root"
  printf 'first original\n' > "$transaction_late_root/first.txt"
  printf 'first replacement\n' > "$TMP_ROOT/late-first.candidate"
  printf 'late replacement\n' > "$TMP_ROOT/late-second.candidate"
  fprs_project_transaction_test_hook() {
    [ "$1" = project-before-target-validation ] || return 0
    [ "$2" = late.txt ] || return 0
    printf 'late user-owned bytes\r\n' > "$transaction_late_root/late.txt"
    chmod 604 "$transaction_late_root/late.txt"
  }
  fprs_project_transaction_begin "$transaction_late_root" ||
    fail 'late-target transaction begin failed'
  fprs_project_transaction_register first.txt "$TMP_ROOT/late-first.candidate" ||
    fail 'late-target first registration failed'
  fprs_project_transaction_register late.txt "$TMP_ROOT/late-second.candidate" ||
    fail 'late-target second registration failed'
  fprs_project_transaction_validate || fail 'late-target global validation failed'
  if FPRS_TEST_MODE=1 fprs_project_transaction_commit; then
    fail 'transaction overwrote a late-created untracked target'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 3 ] ||
    fail 'late-created target refusal did not return transaction status 3'
  [ "$(cat "$transaction_late_root/first.txt")" = 'first original' ] ||
    fail 'late-target refusal did not roll back an earlier write'
  printf 'late user-owned bytes\r\n' > "$TMP_ROOT/late-user.expected"
  assert_same_file "$TMP_ROOT/late-user.expected" \
    "$transaction_late_root/late.txt" \
    'late-created untracked target was not preserved byte-for-byte'
  assert_mode 604 "$transaction_late_root/late.txt" \
    'late-created untracked target mode changed'
  unset -f fprs_project_transaction_test_hook

  transaction_late_change_root="$TMP_ROOT/project transaction/late changed target"
  mkdir -p "$transaction_late_change_root"
  printf 'first original\n' > "$transaction_late_change_root/first.txt"
  printf 'tracked original\r\n' > "$transaction_late_change_root/tracked.txt"
  chmod 640 "$transaction_late_change_root/tracked.txt"
  fprs_project_transaction_test_hook() {
    [ "$1" = project-before-target-validation ] || return 0
    [ "$2" = tracked.txt ] || return 0
    printf 'late user edit\r\n' > "$transaction_late_change_root/tracked.txt"
    chmod 604 "$transaction_late_change_root/tracked.txt"
  }
  fprs_project_transaction_begin "$transaction_late_change_root" ||
    fail 'late-change transaction begin failed'
  fprs_project_transaction_register first.txt "$TMP_ROOT/late-first.candidate" ||
    fail 'late-change first registration failed'
  fprs_project_transaction_register tracked.txt "$TMP_ROOT/late-second.candidate" ||
    fail 'late-change tracked registration failed'
  fprs_project_transaction_validate || fail 'late-change global validation failed'
  if FPRS_TEST_MODE=1 fprs_project_transaction_commit; then
    fail 'transaction overwrote a late modification to a tracked target'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 3 ] ||
    fail 'late-modified target refusal did not return transaction status 3'
  [ "$(cat "$transaction_late_change_root/first.txt")" = 'first original' ] ||
    fail 'late-modified target refusal did not roll back an earlier write'
  printf 'late user edit\r\n' > "$TMP_ROOT/late-user-edit.expected"
  assert_same_file "$TMP_ROOT/late-user-edit.expected" \
    "$transaction_late_change_root/tracked.txt" \
    'late modification was not preserved byte-for-byte'
  assert_mode 604 "$transaction_late_change_root/tracked.txt" \
    'late-modified target mode changed'
  unset -f fprs_project_transaction_test_hook

  transaction_swap_root="$TMP_ROOT/project transaction/parent swap"
  transaction_swap_outside="$TMP_ROOT/project transaction/parent swap outside"
  mkdir -p "$transaction_swap_root/safe" "$transaction_swap_outside"
  printf 'swap candidate\n' > "$TMP_ROOT/swap.candidate"
  fprs_project_transaction_test_hook() {
    [ "$1" = project-before-publish ] || return 0
    [ "$2" = safe/victim.txt ] || return 0
    mv "$transaction_swap_root/safe" "$transaction_swap_root/safe-pinned"
    ln -s "$transaction_swap_outside" "$transaction_swap_root/safe"
  }
  fprs_project_transaction_begin "$transaction_swap_root" ||
    fail 'parent-swap transaction begin failed'
  fprs_project_transaction_register safe/victim.txt "$TMP_ROOT/swap.candidate" ||
    fail 'parent-swap target registration failed'
  fprs_project_transaction_validate || fail 'parent-swap validation failed'
  if FPRS_TEST_MODE=1 fprs_project_transaction_commit; then
    fail 'transaction published through a swapped parent path'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 3 ] ||
    fail 'parent-swap refusal did not return transaction status 3'
  [ ! -e "$transaction_swap_outside/victim.txt" ] ||
    fail 'parent swap escaped the selected physical root'
  [ ! -e "$transaction_swap_root/safe-pinned/victim.txt" ] ||
    fail 'parent-swap refusal left an installed target in the pinned directory'
  if find "$transaction_swap_root/safe-pinned" -name '.fprs-project-write.*' -print |
    grep . >/dev/null 2>&1
  then
    fail 'parent-swap refusal left an invocation-owned temporary file'
  fi
  rm "$transaction_swap_root/safe"
  mv "$transaction_swap_root/safe-pinned" "$transaction_swap_root/safe"
  unset -f fprs_project_transaction_test_hook

  transaction_ancestor_root="$TMP_ROOT/project transaction/ancestor swap"
  transaction_ancestor_outside="$TMP_ROOT/project transaction/ancestor swap outside"
  mkdir -p "$transaction_ancestor_root/outer/safe" \
    "$transaction_ancestor_outside/safe"
  fprs_project_transaction_test_hook() {
    [ "$1" = project-before-publish ] || return 0
    [ "$2" = outer/safe/victim.txt ] || return 0
    mv "$transaction_ancestor_root/outer" \
      "$transaction_ancestor_root/outer-pinned"
    ln -s "$transaction_ancestor_outside" "$transaction_ancestor_root/outer"
  }
  fprs_project_transaction_begin "$transaction_ancestor_root" ||
    fail 'ancestor-swap transaction begin failed'
  fprs_project_transaction_register outer/safe/victim.txt "$TMP_ROOT/swap.candidate" ||
    fail 'ancestor-swap target registration failed'
  fprs_project_transaction_validate || fail 'ancestor-swap validation failed'
  if FPRS_TEST_MODE=1 fprs_project_transaction_commit; then
    fail 'transaction published through a swapped ancestor path'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 3 ] ||
    fail 'ancestor-swap refusal did not return transaction status 3'
  [ ! -e "$transaction_ancestor_outside/safe/victim.txt" ] ||
    fail 'ancestor swap escaped the selected physical root'
  [ ! -e "$transaction_ancestor_root/outer-pinned/safe/victim.txt" ] ||
    fail 'ancestor-swap refusal installed a target in the pinned directory'
  if find "$transaction_ancestor_root/outer-pinned" \
    -name '.fprs-project-write.*' -print | grep . >/dev/null 2>&1
  then
    fail 'ancestor-swap refusal left an invocation-owned temporary file'
  fi
  rm "$transaction_ancestor_root/outer"
  mv "$transaction_ancestor_root/outer-pinned" "$transaction_ancestor_root/outer"
  unset -f fprs_project_transaction_test_hook

  transaction_failure_root="$TMP_ROOT/project transaction/failure rollback"
  mkdir -p "$transaction_failure_root/data"
  printf 'tracked original\r\n' > "$transaction_failure_root/data/tracked.txt"
  printf 'untracked original\n' > "$transaction_failure_root/data/untracked.txt"
  chmod 640 "$transaction_failure_root/data/tracked.txt"
  chmod 604 "$transaction_failure_root/data/untracked.txt"
  cp "$transaction_failure_root/data/tracked.txt" "$TMP_ROOT/tracked.expected"
  cp "$transaction_failure_root/data/untracked.txt" "$TMP_ROOT/untracked.expected"
  printf 'tracked replacement\n' > "$TMP_ROOT/tracked.candidate"
  printf 'untracked replacement\r\n' > "$TMP_ROOT/untracked.candidate"
  printf 'created replacement\n' > "$TMP_ROOT/created.candidate"
  for transaction_fail_after in 1 2 3
  do
    cp "$TMP_ROOT/tracked.expected" "$transaction_failure_root/data/tracked.txt"
    cp "$TMP_ROOT/untracked.expected" "$transaction_failure_root/data/untracked.txt"
    chmod 640 "$transaction_failure_root/data/tracked.txt"
    chmod 604 "$transaction_failure_root/data/untracked.txt"
    rm -f "$transaction_failure_root/data/created.txt"
    fprs_project_transaction_begin "$transaction_failure_root" ||
      fail 'rollback transaction begin failed'
    fprs_project_transaction_register data/tracked.txt "$TMP_ROOT/tracked.candidate" ||
      fail 'tracked rollback registration failed'
    fprs_project_transaction_register data/untracked.txt "$TMP_ROOT/untracked.candidate" ||
      fail 'untracked rollback registration failed'
    fprs_project_transaction_register data/created.txt "$TMP_ROOT/created.candidate" ||
      fail 'created rollback registration failed'
    fprs_project_transaction_validate || fail 'rollback validation failed'
    if FPRS_TEST_MODE=1 \
      FPRS_TEST_FAIL_PROJECT_WRITE_AFTER=$transaction_fail_after \
      fprs_project_transaction_commit
    then
      fail "injected project write $transaction_fail_after unexpectedly succeeded"
    else
      transaction_status=$?
    fi
    [ "$transaction_status" -eq 3 ] ||
      fail "injected project write $transaction_fail_after did not return status 3"
    assert_same_file "$TMP_ROOT/tracked.expected" \
      "$transaction_failure_root/data/tracked.txt" \
      "tracked bytes changed after injected write $transaction_fail_after"
    assert_same_file "$TMP_ROOT/untracked.expected" \
      "$transaction_failure_root/data/untracked.txt" \
      "untracked bytes changed after injected write $transaction_fail_after"
    assert_mode 640 "$transaction_failure_root/data/tracked.txt" \
      "tracked mode changed after injected write $transaction_fail_after"
    assert_mode 604 "$transaction_failure_root/data/untracked.txt" \
      "untracked mode changed after injected write $transaction_fail_after"
    [ ! -e "$transaction_failure_root/data/created.txt" ] ||
      fail "created path remained after injected write $transaction_fail_after"
    if find "$transaction_failure_root" -name '.fprs-project-write.*' -print |
      grep . >/dev/null 2>&1
    then
      fail "same-directory temporary file remained after injected write $transaction_fail_after"
    fi
  done

  transaction_signal_root="$TMP_ROOT/project transaction/signal"
  transaction_signal_helper="$TMP_ROOT/project transaction/signal-helper.sh"
  mkdir -p "$transaction_signal_root"
  printf 'signal original\r\n' > "$transaction_signal_root/existing.txt"
  chmod 640 "$transaction_signal_root/existing.txt"
  cp "$transaction_signal_root/existing.txt" "$TMP_ROOT/signal.expected"
  printf 'signal replacement\n' > "$TMP_ROOT/signal.candidate"
  cat > "$transaction_signal_helper" <<'SH'
#!/usr/bin/env bash
set -u
. "$1"
fprs_project_transaction_begin "$2" || exit $?
fprs_project_transaction_register existing.txt "$3" || exit $?
fprs_project_transaction_validate || exit $?
fprs_project_transaction_commit
SH
  chmod 700 "$transaction_signal_helper"
  if env FPRS_TEST_MODE=1 FPRS_TEST_SIGNAL_AT=project-write \
    /bin/bash "$transaction_signal_helper" "$TRANSACTION_LIBRARY" \
    "$transaction_signal_root" "$TMP_ROOT/signal.candidate" \
    > "$TMP_ROOT/signal.stdout" 2> "$TMP_ROOT/signal.stderr"
  then
    fail 'injected transaction signal unexpectedly succeeded'
  else
    transaction_status=$?
  fi
  [ "$transaction_status" -eq 3 ] ||
    fail 'injected transaction signal did not return status 3'
  grep -F 'rollback attempted' "$TMP_ROOT/signal.stderr" >/dev/null 2>&1 ||
    fail 'injected transaction signal did not report rollback'
  assert_same_file "$TMP_ROOT/signal.expected" \
    "$transaction_signal_root/existing.txt" \
    'signal rollback changed original bytes'
  assert_mode 640 "$transaction_signal_root/existing.txt" \
    'signal rollback changed original mode'

  transaction_boundary_helper="$TMP_ROOT/project transaction/boundary-helper.sh"
  cat > "$transaction_boundary_helper" <<'SH'
#!/usr/bin/env bash
set -u
. "$1"
root=$2
candidate=$3
boundary=$4
case "$boundary" in
  project-dir-created) relative='nested/path/created.txt' ;;
  *) relative='existing.txt' ;;
esac
fprs_project_transaction_begin "$root" || exit $?
fprs_project_transaction_register "$relative" "$candidate" || exit $?
fprs_project_transaction_validate || exit $?
FPRS_TEST_MODE=1 FPRS_TEST_SIGNAL_AT=$boundary fprs_project_transaction_commit
SH
  chmod 700 "$transaction_boundary_helper"
  for transaction_boundary in project-dir-created project-temp-created project-published
  do
    transaction_boundary_root="$TMP_ROOT/project transaction/boundary $transaction_boundary"
    mkdir -p "$transaction_boundary_root"
    printf 'boundary original\r\n' > "$transaction_boundary_root/existing.txt"
    chmod 640 "$transaction_boundary_root/existing.txt"
    cp "$transaction_boundary_root/existing.txt" "$TMP_ROOT/boundary.expected"
    if /bin/bash "$transaction_boundary_helper" "$TRANSACTION_LIBRARY" \
      "$transaction_boundary_root" "$TMP_ROOT/signal.candidate" \
      "$transaction_boundary" > "$TMP_ROOT/boundary.stdout" \
      2> "$TMP_ROOT/boundary.stderr"
    then
      fail "transaction signal boundary unexpectedly succeeded: $transaction_boundary"
    else
      transaction_status=$?
    fi
    [ "$transaction_status" -eq 3 ] ||
      fail "transaction signal boundary did not return 3: $transaction_boundary"
    assert_same_file "$TMP_ROOT/boundary.expected" \
      "$transaction_boundary_root/existing.txt" \
      "signal boundary changed original bytes: $transaction_boundary"
    assert_mode 640 "$transaction_boundary_root/existing.txt" \
      "signal boundary changed original mode: $transaction_boundary"
    [ ! -e "$transaction_boundary_root/nested" ] ||
      fail "signal boundary left a created directory: $transaction_boundary"
    if find "$transaction_boundary_root" -name '.fprs-project-write.*' -print |
      grep . >/dev/null 2>&1
    then
      fail "signal boundary left a same-directory temp: $transaction_boundary"
    fi
  done

  if grep -E 'git[[:space:]]+(checkout|restore|reset)' \
    "$TRANSACTION_LIBRARY" >/dev/null 2>&1
  then
    fail 'project transaction uses Git for restoration'
  fi
  pass 'project_transaction'
}

gradle_signing() {
  GRADLE_ROOT="$TMP_ROOT/gradle signing"
  GRADLE_SOURCE="$GRADLE_ROOT/build.gradle"
  GRADLE_CANDIDATE="$GRADLE_ROOT/build.gradle.candidate"
  GRADLE_LIBRARY="$PACKAGE_ROOT/scripts/lib/gradle_signing.sh"
  mkdir -p "$GRADLE_ROOT"
  cat > "$GRADLE_SOURCE" <<'GRADLE'
android {
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
GRADLE

  # shellcheck source=/dev/null
  . "$GRADLE_LIBRARY"
  type fprs_gradle_signing_candidate >/dev/null 2>&1 ||
    fail 'missing Gradle candidate function'
  cp "$GRADLE_SOURCE" "$GRADLE_ROOT/alias-source.expected"
  ln "$GRADLE_SOURCE" "$GRADLE_ROOT/source-hardlink.gradle"
  if fprs_gradle_signing_candidate groovy "$GRADLE_SOURCE" \
    "$GRADLE_ROOT/source-hardlink.gradle"; then
    fail 'Gradle planner accepted a hardlink output alias to its source'
  else
    gradle_status=$?
  fi
  [ "$gradle_status" -eq 2 ] ||
    fail 'Gradle hardlink output alias did not return status 2'
  assert_same_file "$GRADLE_ROOT/alias-source.expected" "$GRADLE_SOURCE" \
    'Gradle hardlink output alias mutated the source'
  ln -s "$GRADLE_SOURCE" "$GRADLE_ROOT/source-symlink.gradle"
  if fprs_gradle_signing_candidate groovy "$GRADLE_SOURCE" \
    "$GRADLE_ROOT/source-symlink.gradle"; then
    fail 'Gradle planner accepted a symlink output alias to its source'
  fi
  printf 'unrelated candidate owner\n' > "$GRADLE_ROOT/existing-output.gradle"
  if fprs_gradle_signing_candidate groovy "$GRADLE_SOURCE" \
    "$GRADLE_ROOT/existing-output.gradle"; then
    fail 'Gradle planner accepted an unsafe pre-existing output'
  fi
  [ "$(cat "$GRADLE_ROOT/existing-output.gradle")" = 'unrelated candidate owner' ] ||
    fail 'Gradle planner changed an unsafe pre-existing output'
  fprs_gradle_signing_candidate groovy "$GRADLE_SOURCE" \
    "$GRADLE_CANDIDATE" || fail 'Groovy Gradle candidate generation failed'
  grep -F 'BEGIN flutter-play-store-release schema=1' \
    "$GRADLE_CANDIDATE" >/dev/null 2>&1 ||
    fail 'Gradle candidate omitted the owned signing block'
  if LC_ALL=C grep "$(printf '\r')" "$GRADLE_CANDIDATE" >/dev/null 2>&1; then
    fail 'Gradle candidate introduced CRLF into an LF source'
  fi
  if grep -F 'signingConfig signingConfigs.debug' \
    "$GRADLE_CANDIDATE" >/dev/null 2>&1; then
    fail 'Gradle candidate retained stock debug release signing'
  fi
  gradle_store_file_count=$(grep -c 'storeFile' "$GRADLE_CANDIDATE")
  [ "$gradle_store_file_count" -gt 0 ] ||
    fail 'Gradle candidate did not connect storeFile'

  for gradle_property in storeFile storePassword keyAlias keyPassword
  do
    gradle_assignment_count=$(grep -Ec \
      "^[[:space:]]*$gradle_property([[:space:]]+|[[:space:]]*=[[:space:]]*)" \
      "$GRADLE_CANDIDATE")
    [ "$gradle_assignment_count" -eq 1 ] ||
      fail "$gradle_property was not connected exactly once in Groovy"
  done
  grep -F 'providers.environmentVariable("ANDROID_KEY_PROPERTIES_PATH").orNull' \
    "$GRADLE_CANDIDATE" >/dev/null 2>&1 ||
    fail 'Groovy block omitted the key-properties override'
  grep -F 'rootProject.file("key.properties")' "$GRADLE_CANDIDATE" >/dev/null 2>&1 ||
    fail 'Groovy block omitted the android/key.properties fallback'
  grep -F 'gradle.startParameter.taskNames.any' "$GRADLE_CANDIDATE" >/dev/null 2>&1 ||
    fail 'Groovy block does not inspect directly requested tasks'
  gradle_guard_line=$(grep -n 'if (fprsReleaseSigningTaskRequested)' \
    "$GRADLE_CANDIDATE" | sed -n '1s/:.*//p')
  gradle_load_line=$(grep -n 'withInputStream' "$GRADLE_CANDIDATE" |
    sed -n '1s/:.*//p')
  [ -n "$gradle_guard_line" ] && [ -n "$gradle_load_line" ] &&
    [ "$gradle_guard_line" -lt "$gradle_load_line" ] ||
    fail 'Groovy block reads key properties outside the direct release-task guard'
  if grep -E 'taskGraph|println|logger\.' \
    "$GRADLE_CANDIDATE" >/dev/null 2>&1; then
    fail 'Groovy signing guard uses a late task graph or secret-shaped output'
  fi

  cp "$GRADLE_SOURCE" "$GRADLE_ROOT/groovy.source.expected"
  chmod 640 "$GRADLE_SOURCE"
  fprs_gradle_signing_candidate groovy "$GRADLE_CANDIDATE" \
    "$GRADLE_ROOT/groovy.second" || fail 'second Groovy generation failed'
  assert_same_file "$GRADLE_CANDIDATE" "$GRADLE_ROOT/groovy.second" \
    'second Groovy generation changed the candidate'
  assert_same_file "$GRADLE_ROOT/groovy.source.expected" "$GRADLE_SOURCE" \
    'Gradle planner modified its source file'

  gradle_kotlin_source="$GRADLE_ROOT/build.gradle.kts"
  gradle_kotlin_candidate="$GRADLE_ROOT/build.gradle.kts.candidate"
  cat > "$gradle_kotlin_source" <<'KOTLIN'
android {
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
KOTLIN
  chmod 644 "$gradle_kotlin_source"
  fprs_gradle_signing_candidate kotlin "$gradle_kotlin_source" \
    "$gradle_kotlin_candidate" release ||
    fail 'Kotlin Gradle candidate generation failed'
  if grep -F 'signingConfigs.getByName("debug")' \
    "$gradle_kotlin_candidate" >/dev/null 2>&1; then
    fail 'Kotlin Gradle candidate retained stock debug release signing'
  fi
  for gradle_property in storeFile storePassword keyAlias keyPassword
  do
    gradle_assignment_count=$(grep -Ec \
      "^[[:space:]]*$gradle_property[[:space:]]*=" \
      "$gradle_kotlin_candidate")
    [ "$gradle_assignment_count" -eq 1 ] ||
      fail "$gradle_property was not connected exactly once in Kotlin"
  done
  gradle_guard_line=$(grep -n 'if (fprsReleaseSigningTaskRequested)' \
    "$gradle_kotlin_candidate" | sed -n '1s/:.*//p')
  gradle_load_line=$(grep -n 'inputStream().use' "$gradle_kotlin_candidate" |
    sed -n '1s/:.*//p')
  [ -n "$gradle_guard_line" ] && [ -n "$gradle_load_line" ] &&
    [ "$gradle_guard_line" -lt "$gradle_load_line" ] ||
    fail 'Kotlin block reads key properties outside the direct release-task guard'
  assert_mode 644 "$gradle_kotlin_candidate" \
    'Kotlin candidate did not preserve source mode'
  fprs_gradle_signing_candidate kotlin "$gradle_kotlin_candidate" \
    "$GRADLE_ROOT/kotlin.second" release || fail 'second Kotlin generation failed'
  assert_same_file "$gradle_kotlin_candidate" "$GRADLE_ROOT/kotlin.second" \
    'second Kotlin generation changed the candidate'

  gradle_crlf_source="$GRADLE_ROOT/crlf build.gradle"
  gradle_crlf_candidate="$GRADLE_ROOT/crlf candidate.gradle"
  awk '{ printf "%s\r\n", $0 }' "$GRADLE_SOURCE" > "$gradle_crlf_source"
  chmod 604 "$gradle_crlf_source"
  fprs_gradle_signing_candidate groovy "$gradle_crlf_source" \
    "$gradle_crlf_candidate" || fail 'CRLF Gradle generation failed'
  awk 'substr($0, length($0), 1) != "\r" { exit 1 }' \
    "$gradle_crlf_candidate" || fail 'Gradle candidate changed CRLF line endings'
  assert_mode 604 "$gradle_crlf_candidate" \
    'Gradle candidate changed a nondefault file mode'

  gradle_custom_source="$GRADLE_ROOT/custom signing.gradle"
  gradle_custom_candidate="$GRADLE_ROOT/custom candidate.gradle"
  cat > "$gradle_custom_source" <<'GRADLE'
android {
    signingConfigs {
        upload {
            storeFile file("user-owned.jks")
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.upload
        }
    }
}
GRADLE
  fprs_gradle_signing_candidate groovy "$gradle_custom_source" \
    "$gradle_custom_candidate" || fail 'valid user-owned signing was rejected'
  [ "$FPRS_GRADLE_SIGNING_CLASSIFICATION" = preserve ] ||
    fail 'valid user-owned signing was not classified as preserve'
  assert_same_file "$gradle_custom_source" "$gradle_custom_candidate" \
    'valid user-owned signing was modified'

  gradle_conflict_source="$GRADLE_ROOT/conflict.gradle"
  cat > "$gradle_conflict_source" <<'GRADLE'
android {
    buildTypes {
        release {
            signingConfig signingConfigs.debug
            signingConfig signingConfigs.release
        }
    }
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/conflict.candidate"; then
    fail 'simultaneous debug and release signing was accepted'
  else
    gradle_status=$?
  fi
  [ "$gradle_status" -eq 2 ] ||
    fail 'simultaneous signing conflict did not return status 2'

  cat > "$gradle_conflict_source" <<'GRADLE'
android {
    buildTypes {
        release {
            signingConfig signingConfigs.upload
        }
    }
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/missing-config.candidate"; then
    fail 'undeclared custom signing config was accepted'
  fi

  cat > "$gradle_conflict_source" <<'GRADLE'
android {
    // BEGIN flutter-play-store-release schema=1
    // END flutter-play-store-release
    // BEGIN flutter-play-store-release schema=1
    // END flutter-play-store-release
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/multiple-marker.candidate"; then
    fail 'multiple owned marker blocks were accepted'
  fi

  cat > "$gradle_conflict_source" <<'GRADLE'
// BEGIN flutter-play-store-release schema=1
// END flutter-play-store-release
android {
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/outside-marker.candidate"; then
    fail 'owned marker outside the structural android scope was accepted'
  fi

  cat > "$gradle_conflict_source" <<'GRADLE'
/*
// BEGIN flutter-play-store-release schema=1
// END flutter-play-store-release
android {
    buildTypes { release { signingConfig signingConfigs.debug } }
}
*/
def documentation = """
android {
    // BEGIN flutter-play-store-release schema=1
    buildTypes { release { signingConfig signingConfigs.debug } }
    // END flutter-play-store-release
}
"""
android {
}
GRADLE
  fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/comment-string.candidate" ||
    fail 'marker/scope text inside comments or multiline strings caused a conflict'
  grep -F 'def documentation = """' "$GRADLE_ROOT/comment-string.candidate" \
    >/dev/null 2>&1 || fail 'Gradle planner did not preserve multiline user text'

  cat > "$gradle_conflict_source" <<'GRADLE'
android {
    buildTypes {
        release {
        }
    }
    buildTypes {
        release {
        }
    }
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/multiple-release.candidate"; then
    fail 'multiple structural release scopes were accepted'
  else
    gradle_status=$?
  fi
  [ "$gradle_status" -eq 2 ] ||
    fail 'multiple release scopes did not return status 2'

  cat > "$gradle_conflict_source" <<'GRADLE'
// android { }
android {
}
android {
}
GRADLE
  if fprs_gradle_signing_candidate groovy "$gradle_conflict_source" \
    "$GRADLE_ROOT/multiple-android.candidate"; then
    fail 'multiple structural android scopes were accepted'
  fi

  type fprs_gradle_signing_task_requires_credentials >/dev/null 2>&1 ||
    fail 'missing pure Gradle release-task guard helper'
  type fprs_gradle_signing_properties_path >/dev/null 2>&1 ||
    fail 'missing pure key-properties path helper'
  type fprs_gradle_signing_guard_check >/dev/null 2>&1 ||
    fail 'missing pure signing credential guard helper'
  for gradle_nonrelease_task in help tasks properties assembleDebug bundleQaDebug testDebugUnitTest lintRelease
  do
    if fprs_gradle_signing_task_requires_credentials "$gradle_nonrelease_task"; then
      fail "non-signing task required release credentials: $gradle_nonrelease_task"
    fi
  done
  for gradle_release_task in :app:bundleRelease assembleProdRelease publishReleaseBundle
  do
    fprs_gradle_signing_task_requires_credentials "$gradle_release_task" ||
      fail "release signing task bypassed credentials: $gradle_release_task"
  done
  gradle_guard_root="$GRADLE_ROOT/guard project/android"
  mkdir -p "$gradle_guard_root/app"
  gradle_fallback_path=$(unset ANDROID_KEY_PROPERTIES_PATH; \
    fprs_gradle_signing_properties_path "$gradle_guard_root") ||
    fail 'key-properties fallback resolution failed'
  [ "$gradle_fallback_path" = "$gradle_guard_root/key.properties" ] ||
    fail 'key-properties fallback did not resolve under the Android root'
  gradle_override_path=$(ANDROID_KEY_PROPERTIES_PATH="$GRADLE_ROOT/override.properties" \
    fprs_gradle_signing_properties_path "$gradle_guard_root") ||
    fail 'key-properties override resolution failed'
  [ "$gradle_override_path" = "$GRADLE_ROOT/override.properties" ] ||
    fail 'ANDROID_KEY_PROPERTIES_PATH did not take precedence'
  if ! fprs_gradle_signing_guard_check assembleDebug \
    "$GRADLE_ROOT/missing.properties" "$gradle_guard_root/app" \
    > "$GRADLE_ROOT/debug-guard.stdout" 2> "$GRADLE_ROOT/debug-guard.stderr"
  then
    fail 'debug task required missing release credentials'
  fi
  assert_empty_file "$GRADLE_ROOT/debug-guard.stdout" \
    'debug signing guard wrote output'
  assert_empty_file "$GRADLE_ROOT/debug-guard.stderr" \
    'debug signing guard emitted a credential diagnostic'
  if fprs_gradle_signing_guard_check bundleRelease \
    "$GRADLE_ROOT/missing.properties" "$gradle_guard_root/app" \
    > "$GRADLE_ROOT/release-guard.stdout" 2> "$GRADLE_ROOT/release-guard.stderr"
  then
    fail 'release task accepted missing signing properties'
  fi
  grep -F 'release signing properties file is missing' \
    "$GRADLE_ROOT/release-guard.stderr" >/dev/null 2>&1 ||
    fail 'release signing guard omitted a redacted missing-file diagnostic'
  printf 'keystore bytes\n' > "$GRADLE_ROOT/upload.jks"
  cat > "$GRADLE_ROOT/valid.properties" <<PROPERTIES
storeFile=$GRADLE_ROOT/upload.jks
storePassword=FPRS_STORE_PASSWORD_CANARY_ef52
keyAlias=FPRS_ALIAS_CANARY_6b31
keyPassword=FPRS_KEY_PASSWORD_CANARY_91ad
PROPERTIES
  fprs_gradle_signing_guard_check publishReleaseBundle \
    "$GRADLE_ROOT/valid.properties" "$gradle_guard_root/app" \
    > "$GRADLE_ROOT/valid-guard.stdout" 2> "$GRADLE_ROOT/valid-guard.stderr" ||
    fail 'release task rejected complete signing credentials'
  assert_empty_file "$GRADLE_ROOT/valid-guard.stdout" \
    'valid signing guard wrote output'
  assert_empty_file "$GRADLE_ROOT/valid-guard.stderr" \
    'valid signing guard wrote a diagnostic'
  if grep -R -E 'FPRS_(STORE_PASSWORD|ALIAS|KEY_PASSWORD)_CANARY' \
    "$GRADLE_ROOT"/*.stderr "$GRADLE_ROOT"/*.stdout >/dev/null 2>&1; then
    fail 'signing guard leaked a credential value'
  fi
  pass 'gradle_signing'
}

bootstrap_core_run() {
  bootstrap_description=$1
  bootstrap_expected_status=$2
  shift 2
  bootstrap_case_index=$((bootstrap_case_index + 1))
  BOOTSTRAP_LAST_STDOUT="$BOOTSTRAP_LOGS/$bootstrap_case_index.stdout"
  BOOTSTRAP_LAST_STDERR="$BOOTSTRAP_LOGS/$bootstrap_case_index.stderr"
  if "$@" > "$BOOTSTRAP_LAST_STDOUT" 2> "$BOOTSTRAP_LAST_STDERR"; then
    bootstrap_actual_status=0
  else
    bootstrap_actual_status=$?
  fi
  [ "$bootstrap_actual_status" -eq "$bootstrap_expected_status" ] ||
    fail "$bootstrap_description (expected exit $bootstrap_expected_status, got $bootstrap_actual_status)"
}

bootstrap_core() {
  BOOTSTRAP="$PACKAGE_ROOT/scripts/bootstrap_android_fastlane.sh"
  BOOTSTRAP_ROOT="$TMP_ROOT/bootstrap core"
  BOOTSTRAP_LOGS="$BOOTSTRAP_ROOT/logs"
  bootstrap_case_index=0
  mkdir -p "$BOOTSTRAP_LOGS"

  bootstrap_dry_project="$BOOTSTRAP_ROOT/dry run project with spaces"
  bootstrap_dry_baseline="$BOOTSTRAP_ROOT/dry baseline"
  inspection_make_minimal_kotlin "$bootstrap_dry_project"
  cp -R "$bootstrap_dry_project" "$bootstrap_dry_baseline"
  bootstrap_core_run 'fresh bootstrap dry run failed' 0 \
    "$BOOTSTRAP" --project "$bootstrap_dry_project" --dry-run
  diff -r "$bootstrap_dry_baseline" "$bootstrap_dry_project" >/dev/null 2>&1 ||
    fail 'bootstrap dry run changed the project'
  bootstrap_plan_count=$(grep -c '^PLAN ' "$BOOTSTRAP_LAST_STDOUT" || true)
  [ "$bootstrap_plan_count" -eq 15 ] ||
    fail "bootstrap dry run did not plan all 15 targets (got $bootstrap_plan_count)"
  awk '/^PLAN / { print $3 }' "$BOOTSTRAP_LAST_STDOUT" > "$BOOTSTRAP_ROOT/plan.paths"
  LC_ALL=C sort "$BOOTSTRAP_ROOT/plan.paths" > "$BOOTSTRAP_ROOT/plan.sorted"
  assert_same_file "$BOOTSTRAP_ROOT/plan.sorted" "$BOOTSTRAP_ROOT/plan.paths" \
    'bootstrap plan was not sorted by target path'
  grep -F 'PLAN merge android/app/build.gradle.kts' \
    "$BOOTSTRAP_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'bootstrap did not classify the Gradle candidate as a merge'
  grep -F 'PLAN create android/Gemfile' "$BOOTSTRAP_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'bootstrap did not classify an absent generated target as create'

  bootstrap_conflict_project="$BOOTSTRAP_ROOT/conflict project"
  inspection_make_minimal_kotlin "$bootstrap_conflict_project"
  mkdir -p "$bootstrap_conflict_project/.github/workflows"
  printf 'name: user-owned workflow\n' > \
    "$bootstrap_conflict_project/.github/workflows/release-android.yml"
  cp -R "$bootstrap_conflict_project" "$BOOTSTRAP_ROOT/conflict baseline"
  bootstrap_core_run 'default bootstrap conflict did not fail' 2 \
    "$BOOTSTRAP" --project "$bootstrap_conflict_project" --dry-run
  grep -F 'PLAN fail-conflict .github/workflows/release-android.yml' \
    "$BOOTSTRAP_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'default conflict was not classified as fail-conflict'
  diff -r "$BOOTSTRAP_ROOT/conflict baseline" "$bootstrap_conflict_project" \
    >/dev/null 2>&1 || fail 'conflict planning changed the project'

  bootstrap_core_run 'skip conflict did not report incomplete setup' 1 \
    "$BOOTSTRAP" --project "$bootstrap_conflict_project" \
    --dry-run --conflict skip
  grep -F 'PLAN skip-conflict .github/workflows/release-android.yml' \
    "$BOOTSTRAP_LAST_STDOUT" >/dev/null 2>&1 ||
    fail 'skip conflict was not classified as skip-conflict'
  diff -r "$BOOTSTRAP_ROOT/conflict baseline" "$bootstrap_conflict_project" \
    >/dev/null 2>&1 || fail 'skip conflict changed the project'

  bootstrap_skip_apply_project="$BOOTSTRAP_ROOT/skip apply project"
  inspection_make_minimal_kotlin "$bootstrap_skip_apply_project"
  mkdir -p "$bootstrap_skip_apply_project/.github/workflows"
  printf 'name: preserved user workflow\n' > \
    "$bootstrap_skip_apply_project/.github/workflows/release-android.yml"
  cp "$bootstrap_skip_apply_project/.github/workflows/release-android.yml" \
    "$BOOTSTRAP_ROOT/skip-workflow.expected"
  bootstrap_core_run 'non-dry skip did not report incomplete setup' 1 \
    "$BOOTSTRAP" --project "$bootstrap_skip_apply_project" --conflict skip
  assert_same_file "$BOOTSTRAP_ROOT/skip-workflow.expected" \
    "$bootstrap_skip_apply_project/.github/workflows/release-android.yml" \
    'non-dry skip changed the conflicting workflow'
  grep -F 'BEGIN flutter-play-store-release schema=1' \
    "$bootstrap_skip_apply_project/android/app/build.gradle.kts" >/dev/null 2>&1 ||
    fail 'non-dry skip did not apply the safe Gradle candidate'
  [ -f "$bootstrap_skip_apply_project/android/Gemfile" ] ||
    fail 'non-dry skip did not create a safe planned target'

  bootstrap_core_run 'missing bootstrap arguments were accepted' 2 "$BOOTSTRAP"
  bootstrap_core_run 'invalid conflict mode was accepted' 2 \
    "$BOOTSTRAP" --project "$bootstrap_dry_project" --conflict overwrite

  bootstrap_apply_project="$BOOTSTRAP_ROOT/apply project"
  inspection_make_minimal_kotlin "$bootstrap_apply_project"
  bootstrap_core_run 'fresh bootstrap apply failed' 0 \
    "$BOOTSTRAP" --project "$bootstrap_apply_project"
  grep -F 'BEGIN flutter-play-store-release schema=1' \
    "$bootstrap_apply_project/android/app/build.gradle.kts" >/dev/null 2>&1 ||
    fail 'bootstrap apply did not install the Gradle signing candidate'
  for bootstrap_created_path in \
    android/Gemfile \
    android/fastlane/Fastfile \
    .github/workflows/release-android.yml \
    docs/PLAY_STORE_RELEASE.md \
    tool/flutter-play-store-release/decode_secret.sh \
    tool/flutter-play-store-release/managed-files.sha256
  do
    [ -f "$bootstrap_apply_project/$bootstrap_created_path" ] ||
      fail "bootstrap apply omitted $bootstrap_created_path"
  done
  cp -R "$bootstrap_apply_project" "$BOOTSTRAP_ROOT/apply baseline"
  bootstrap_core_run 'second bootstrap apply failed' 0 \
    "$BOOTSTRAP" --project "$bootstrap_apply_project"
  diff -r "$BOOTSTRAP_ROOT/apply baseline" "$bootstrap_apply_project" \
    >/dev/null 2>&1 || fail 'second bootstrap apply changed the project'

  bootstrap_merge_project="$BOOTSTRAP_ROOT/merge ownership project"
  inspection_make_minimal_kotlin "$bootstrap_merge_project"
  mkdir -p "$bootstrap_merge_project/android/fastlane"
  printf 'source "https://example.invalid"\n' > "$bootstrap_merge_project/android/Gemfile"
  printf 'platform :android do\nend\n' > "$bootstrap_merge_project/android/fastlane/Fastfile"
  printf '# user plugin declarations\n' > "$bootstrap_merge_project/android/fastlane/Pluginfile"
  bootstrap_core_run 'first merge bootstrap failed' 0 \
    "$BOOTSTRAP" --project "$bootstrap_merge_project"
  for bootstrap_merge_path in \
    android/Gemfile android/fastlane/Fastfile android/fastlane/Pluginfile
  do
    bootstrap_marker_count=$(grep -c '^# BEGIN flutter-play-store-release schema=1$' \
      "$bootstrap_merge_project/$bootstrap_merge_path")
    [ "$bootstrap_marker_count" -eq 1 ] ||
      fail "first merge did not create one owned block: $bootstrap_merge_path"
  done
  cp -R "$bootstrap_merge_project" "$BOOTSTRAP_ROOT/merge ownership baseline"
  bootstrap_core_run 'second merge bootstrap failed' 0 \
    "$BOOTSTRAP" --project "$bootstrap_merge_project"
  diff -r "$BOOTSTRAP_ROOT/merge ownership baseline" "$bootstrap_merge_project" \
    >/dev/null 2>&1 || fail 'second merge bootstrap appended or changed an owned block'

  bootstrap_bad_marker_project="$BOOTSTRAP_ROOT/malformed merge marker project"
  inspection_make_minimal_kotlin "$bootstrap_bad_marker_project"
  printf '# BEGIN flutter-play-store-release schema=1\n' > \
    "$bootstrap_bad_marker_project/android/Gemfile"
  bootstrap_core_run 'malformed merge marker was accepted' 2 \
    "$BOOTSTRAP" --project "$bootstrap_bad_marker_project" --dry-run
  grep -F 'PLAN fail-conflict android/Gemfile' "$BOOTSTRAP_LAST_STDOUT" \
    >/dev/null 2>&1 || fail 'malformed merge marker was not planned as a conflict'

  for bootstrap_fail_after in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
  do
    bootstrap_failure_project="$BOOTSTRAP_ROOT/failure $bootstrap_fail_after"
    bootstrap_failure_baseline="$BOOTSTRAP_ROOT/failure baseline $bootstrap_fail_after"
    inspection_make_minimal_kotlin "$bootstrap_failure_project"
    cp -R "$bootstrap_failure_project" "$bootstrap_failure_baseline"
    bootstrap_core_run "bootstrap write failure $bootstrap_fail_after did not roll back" 3 \
      env FPRS_TEST_MODE=1 \
      FPRS_TEST_FAIL_PROJECT_WRITE_AFTER="$bootstrap_fail_after" \
      "$BOOTSTRAP" --project "$bootstrap_failure_project"
    grep -F 'rollback attempted' "$BOOTSTRAP_LAST_STDERR" >/dev/null 2>&1 ||
      fail "bootstrap write failure $bootstrap_fail_after did not report rollback"
    diff -r "$bootstrap_failure_baseline" "$bootstrap_failure_project" \
      >/dev/null 2>&1 ||
      fail "bootstrap write failure $bootstrap_fail_after changed project bytes"
  done
  pass 'bootstrap_core'
}

run_test_group() {
  case "$1" in
    package_contract) package_contract ;;
    secret_codecs) secret_codecs ;;
    inspection) inspection ;;
    project_transaction) project_transaction ;;
    gradle_signing) gradle_signing ;;
    bootstrap_core) bootstrap_core ;;
    *) fail "unknown test group: $1" ;;
  esac
}

if [ "$#" -eq 0 ] || [ "${1-}" = all ]; then
  [ "$#" -le 1 ] || fail 'all cannot be combined with named test groups'
  package_contract
  secret_codecs
  inspection
  project_transaction
  gradle_signing
  bootstrap_core
else
  for requested_group in "$@"
  do
    run_test_group "$requested_group"
  done
fi
