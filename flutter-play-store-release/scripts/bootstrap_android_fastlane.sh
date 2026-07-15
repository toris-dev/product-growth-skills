#!/usr/bin/env bash
# Bootstrap package-owned Android Fastlane and GitHub Actions configuration safely.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit 1
PACKAGE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 1
COMMON="$SCRIPT_DIR/lib/common.sh"
TRANSACTION_LIBRARY="$SCRIPT_DIR/lib/project_transaction.sh"
GRADLE_LIBRARY="$SCRIPT_DIR/lib/gradle_signing.sh"
INSPECTOR="$SCRIPT_DIR/inspect_flutter_project.sh"
for bootstrap_library in "$COMMON" "$TRANSACTION_LIBRARY" "$GRADLE_LIBRARY"
do
  [ -r "$bootstrap_library" ] || {
    printf 'ERROR: bootstrap helper is unavailable: %s\n' "${bootstrap_library##*/}" >&2
    exit 1
  }
done
. "$COMMON"
. "$TRANSACTION_LIBRARY"
. "$GRADLE_LIBRARY"

fprs_bootstrap_usage() {
  printf 'Usage: %s --project PATH [--flavor NAME] [--dry-run] [--conflict fail|skip]\n' \
    "${0##*/}" >&2
}

fprs_bootstrap_bad_argument() {
  printf 'ERROR: %s\n' "$1" >&2
  fprs_bootstrap_usage
  exit 2
}

fprs_bootstrap_cleanup() {
  case "${bootstrap_stage-}" in
    */.fprs-bootstrap.*)
      [ ! -L "$bootstrap_stage" ] || return 0
      rm -rf -- "$bootstrap_stage" 2>/dev/null || true
      ;;
  esac
}

fprs_bootstrap_copy() {
  local bootstrap_copy_mode
  cp "$1" "$2" 2>/dev/null || return 1
  bootstrap_copy_mode=$(fprs_file_mode "$1") || return 1
  chmod "$bootstrap_copy_mode" "$2" 2>/dev/null
}

fprs_bootstrap_source_for() {
  case "$1" in
    android/Gemfile) printf '%s/templates/Gemfile\n' "$PACKAGE_ROOT" ;;
    android/Gemfile.lock) printf '%s/templates/Gemfile.lock\n' "$PACKAGE_ROOT" ;;
    android/fastlane/Appfile) printf '%s/templates/Appfile\n' "$PACKAGE_ROOT" ;;
    android/fastlane/Fastfile) printf '%s/templates/Fastfile\n' "$PACKAGE_ROOT" ;;
    android/fastlane/Pluginfile) printf '%s/templates/Pluginfile\n' "$PACKAGE_ROOT" ;;
    android/fastlane/lib/flutter_play_store_release.rb)
      printf '%s/templates/FlutterPlayStoreRelease.rb\n' "$PACKAGE_ROOT" ;;
    android/fastlane/.env.example) printf '%s/templates/env.example\n' "$PACKAGE_ROOT" ;;
    android/key.properties.example) printf '%s/templates/key.properties.example\n' "$PACKAGE_ROOT" ;;
    .github/workflows/release-android.yml)
      printf '%s/templates/release-android.yml\n' "$PACKAGE_ROOT" ;;
    docs/PLAY_STORE_RELEASE.md)
      printf '%s/templates/PLAY_STORE_RELEASE.md\n' "$PACKAGE_ROOT" ;;
    tool/flutter-play-store-release/decode_secret.sh)
      printf '%s/scripts/decode_secret.sh\n' "$PACKAGE_ROOT" ;;
    tool/flutter-play-store-release/install_flutter_sdk.sh)
      printf '%s/scripts/install_flutter_sdk.sh\n' "$PACKAGE_ROOT" ;;
    *) return 1 ;;
  esac
}

fprs_bootstrap_gitignore() {
  local bootstrap_ignore_mode bootstrap_ignore_line
  if [ -f "$1" ] && [ ! -L "$1" ]; then
    cp "$1" "$2" 2>/dev/null || return 1
    bootstrap_ignore_mode=$(fprs_file_mode "$1") || return 1
  else
    : > "$2" || return 1
    bootstrap_ignore_mode=644
  fi
  for bootstrap_ignore_line in \
    'android/fastlane/.env' 'android/key.properties' 'android/*.jks' \
    'android/*.keystore' 'google-play-service-account.json' \
    '**/google-play-service-account.json' 'fastlane/report.xml' \
    'fastlane/Preview.html' 'fastlane/screenshots/' 'fastlane/test_output/'
  do
    grep -F -x -- "$bootstrap_ignore_line" "$2" >/dev/null 2>&1 ||
      printf '%s\n' "$bootstrap_ignore_line" >> "$2" || return 1
  done
  chmod "$bootstrap_ignore_mode" "$2" 2>/dev/null
}

fprs_bootstrap_mergeable() {
  local bootstrap_merge_target bootstrap_merge_template bootstrap_merge_output
  local bootstrap_merge_report bootstrap_merge_status bootstrap_merge_begin
  local bootstrap_merge_end bootstrap_merge_mode bootstrap_merge_crlf
  bootstrap_merge_target=$1
  bootstrap_merge_template=$2
  bootstrap_merge_output=$3
  bootstrap_merge_report="$bootstrap_stage/merge-markers.$bootstrap_index"
  awk -v report="$bootstrap_merge_report" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /BEGIN flutter-play-store-release/) any_begin++
      if (line ~ /END flutter-play-store-release/) any_end++
      if (line == "# BEGIN flutter-play-store-release schema=1") {
        exact_begin++
        begin_line = NR
      }
      if (line == "# END flutter-play-store-release") {
        exact_end++
        end_line = NR
      }
    }
    END {
      print begin_line > report
      print end_line >> report
      if (any_begin == 0 && any_end == 0) exit 0
      if (any_begin == 1 && any_end == 1 && exact_begin == 1 && exact_end == 1 && begin_line < end_line) exit 10
      exit 2
    }
  ' "$bootstrap_merge_target"
  bootstrap_merge_status=$?
  case "$bootstrap_merge_status" in
    0) ;;
    10)
      bootstrap_merge_begin=$(sed -n '1p' "$bootstrap_merge_report")
      bootstrap_merge_end=$(sed -n '2p' "$bootstrap_merge_report")
      ;;
    *) return 2 ;;
  esac
  if awk '
    NR == 1 { seen = 1 }
    substr($0, length($0), 1) != "\r" { non_crlf = 1 }
    END { exit(seen && !non_crlf ? 0 : 1) }
  ' "$bootstrap_merge_target"
  then
    bootstrap_merge_crlf=1
  else
    bootstrap_merge_crlf=0
  fi
  if [ "$bootstrap_merge_status" -eq 0 ]; then
    cp "$bootstrap_merge_target" "$bootstrap_merge_output" 2>/dev/null || return 1
    if [ "$bootstrap_merge_crlf" -eq 1 ]; then
      printf '\r\n' >> "$bootstrap_merge_output" || return 1
      printf '# BEGIN flutter-play-store-release schema=1\r\n' >> "$bootstrap_merge_output"
      awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$bootstrap_merge_template" \
        >> "$bootstrap_merge_output" || return 1
      printf '# END flutter-play-store-release\r\n' >> "$bootstrap_merge_output"
    else
      printf '\n' >> "$bootstrap_merge_output" || return 1
      printf '# BEGIN flutter-play-store-release schema=1\n' >> "$bootstrap_merge_output"
      cat "$bootstrap_merge_template" >> "$bootstrap_merge_output" || return 1
      printf '# END flutter-play-store-release\n' >> "$bootstrap_merge_output"
    fi
  else
    awk -v begin="$bootstrap_merge_begin" -v end="$bootstrap_merge_end" \
      -v template="$bootstrap_merge_template" -v crlf="$bootstrap_merge_crlf" '
      NR == begin {
        if (crlf) printf "# BEGIN flutter-play-store-release schema=1\r\n"
        else print "# BEGIN flutter-play-store-release schema=1"
        while ((getline replacement < template) > 0) {
          sub(/\r$/, "", replacement)
          if (crlf) printf "%s\r\n", replacement
          else print replacement
        }
        close(template)
        if (crlf) printf "# END flutter-play-store-release\r\n"
        else print "# END flutter-play-store-release"
        next
      }
      NR > begin && NR <= end { next }
      { print }
    ' "$bootstrap_merge_target" > "$bootstrap_merge_output" || return 1
  fi
  bootstrap_merge_mode=$(fprs_file_mode "$bootstrap_merge_target") || return 1
  chmod "$bootstrap_merge_mode" "$bootstrap_merge_output" 2>/dev/null
}

fprs_bootstrap_candidate() {
  local bootstrap_relative bootstrap_target bootstrap_output bootstrap_source
  local bootstrap_candidate_mode
  bootstrap_relative=$1
  bootstrap_target=$2
  bootstrap_output=$3
  case "$bootstrap_relative" in
    .gitignore)
      fprs_bootstrap_gitignore "$bootstrap_target" "$bootstrap_output"
      return
      ;;
    tool/flutter-play-store-release/managed-files.sha256)
      printf '%s\n' 'package_id=flutter-play-store-release' 'schema_version=1' \
        > "$bootstrap_output" || return 1
      chmod 644 "$bootstrap_output" 2>/dev/null
      return
      ;;
  esac
  bootstrap_source=$(fprs_bootstrap_source_for "$bootstrap_relative") || return 2
  [ -f "$bootstrap_source" ] && [ ! -L "$bootstrap_source" ] || return 1
  if [ -f "$bootstrap_target" ] && [ ! -L "$bootstrap_target" ] &&
    case "$bootstrap_relative" in
      android/Gemfile|android/fastlane/Fastfile|android/fastlane/Pluginfile) true ;;
      *) false ;;
    esac && ! cmp -s "$bootstrap_source" "$bootstrap_target"
  then
    fprs_bootstrap_mergeable "$bootstrap_target" "$bootstrap_source" \
      "$bootstrap_output"
  else
    fprs_bootstrap_copy "$bootstrap_source" "$bootstrap_output"
  fi
}

fprs_bootstrap_validate_candidate() {
  [ "$#" -eq 2 ] && [ -n "$1" ] && [ -f "$2" ] && [ ! -L "$2" ] && [ -s "$2" ]
}

project_argument=
flavor_argument=
conflict_mode=fail
dry_run=0
seen_project=0
seen_flavor=0
seen_conflict=0
seen_dry_run=0
if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
  fprs_bootstrap_usage
  exit 0
fi
while [ "$#" -gt 0 ]
do
  case "$1" in
    --project)
      [ "$seen_project" -eq 0 ] || fprs_bootstrap_bad_argument 'duplicate --project'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_bootstrap_bad_argument 'missing value for --project'
      project_argument=$2; seen_project=1; shift 2
      ;;
    --flavor)
      [ "$seen_flavor" -eq 0 ] || fprs_bootstrap_bad_argument 'duplicate --flavor'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_bootstrap_bad_argument 'missing value for --flavor'
      flavor_argument=$2; seen_flavor=1; shift 2
      ;;
    --conflict)
      [ "$seen_conflict" -eq 0 ] || fprs_bootstrap_bad_argument 'duplicate --conflict'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_bootstrap_bad_argument 'missing value for --conflict'
      conflict_mode=$2; seen_conflict=1; shift 2
      ;;
    --dry-run)
      [ "$seen_dry_run" -eq 0 ] || fprs_bootstrap_bad_argument 'duplicate --dry-run'
      dry_run=1; seen_dry_run=1; shift
      ;;
    *) fprs_bootstrap_bad_argument "unknown argument: $1" ;;
  esac
done
[ "$seen_project" -eq 1 ] || fprs_bootstrap_bad_argument '--project is required'
case "$conflict_mode" in fail|skip) ;; *)
  fprs_bootstrap_bad_argument '--conflict must be fail or skip' ;;
esac

bootstrap_stage=$(mktemp -d "${TMPDIR:-/tmp}/.fprs-bootstrap.XXXXXX" 2>/dev/null) || exit 1
chmod 700 "$bootstrap_stage" 2>/dev/null || exit 1
trap fprs_bootstrap_cleanup EXIT
inspection_json="$bootstrap_stage/inspection.json"
if [ -n "$flavor_argument" ]; then
  "$INSPECTOR" --project "$project_argument" --format json --flavor "$flavor_argument" \
    > "$inspection_json"
  inspection_status=$?
else
  "$INSPECTOR" --project "$project_argument" --format json > "$inspection_json"
  inspection_status=$?
fi
case "$inspection_status" in 0) ;; 2) exit 2 ;; *) exit 1 ;; esac

project_root=$(CDPATH= cd -- "$project_argument" 2>/dev/null && pwd -P) || exit 2
android_dsl=$(sed -n 's/^.*"android_dsl":"\([^"]*\)".*$/\1/p' "$inspection_json")
gradle_relative=$(sed -n 's/^.*"gradle_file":"\([^"]*\)".*$/\1/p' "$inspection_json")
case "$android_dsl:$gradle_relative" in
  groovy:android/app/build.gradle|kotlin:android/app/build.gradle.kts) ;;
  *) printf 'ERROR: inspector did not select one supported Gradle file\n' >&2; exit 2 ;;
esac
sed -n 's/^.*"files_bootstrap_may_change":\[\([^]]*\)\],"warnings":.*$/\1/p' \
  "$inspection_json" | tr ',' '\n' | sed 's/^"//; s/"$//' | LC_ALL=C sort \
  > "$bootstrap_stage/targets"
target_count=$(wc -l < "$bootstrap_stage/targets" | tr -d '[:space:]')
[ "$target_count" -eq 15 ] || {
  printf 'ERROR: inspector returned an incomplete bootstrap target set\n' >&2
  exit 1
}

: > "$bootstrap_stage/plan.unsorted"
bootstrap_index=0
bootstrap_conflicts=0
while IFS= read -r bootstrap_relative
do
  bootstrap_index=$((bootstrap_index + 1))
  bootstrap_candidate="$bootstrap_stage/candidate.$(printf '%08d' "$bootstrap_index")"
  bootstrap_target="$project_root/$bootstrap_relative"
  if [ "$bootstrap_relative" = "$gradle_relative" ]; then
    if [ -n "$flavor_argument" ]; then
      fprs_gradle_signing_candidate "$android_dsl" "$bootstrap_target" \
        "$bootstrap_candidate" "$flavor_argument"
      candidate_status=$?
    else
      fprs_gradle_signing_candidate "$android_dsl" "$bootstrap_target" "$bootstrap_candidate"
      candidate_status=$?
    fi
    case "$candidate_status" in
      0)
        bootstrap_classification=$FPRS_GRADLE_SIGNING_CLASSIFICATION
        cmp -s "$bootstrap_candidate" "$bootstrap_target" && bootstrap_classification=preserve
        ;;
      2)
        bootstrap_candidate=
        bootstrap_conflicts=$((bootstrap_conflicts + 1))
        [ "$conflict_mode" = skip ] && bootstrap_classification=skip-conflict ||
          bootstrap_classification=fail-conflict
        ;;
      *)
        printf 'ERROR: Gradle candidate generation failed operationally\n' >&2
        exit 1
        ;;
    esac
  elif [ -e "$bootstrap_target" ] || [ -L "$bootstrap_target" ]; then
    if [ ! -f "$bootstrap_target" ] || [ -L "$bootstrap_target" ]; then
      bootstrap_candidate=
      bootstrap_conflicts=$((bootstrap_conflicts + 1))
      [ "$conflict_mode" = skip ] && bootstrap_classification=skip-conflict ||
        bootstrap_classification=fail-conflict
    else
      fprs_bootstrap_candidate "$bootstrap_relative" "$bootstrap_target" \
        "$bootstrap_candidate"
      candidate_status=$?
      case "$candidate_status" in
        0)
          if cmp -s "$bootstrap_candidate" "$bootstrap_target"; then
            bootstrap_classification=preserve
          else
            case "$bootstrap_relative" in
              .gitignore|android/Gemfile|android/fastlane/Fastfile|android/fastlane/Pluginfile)
                bootstrap_classification=merge ;;
              *)
                bootstrap_candidate=
                bootstrap_conflicts=$((bootstrap_conflicts + 1))
                [ "$conflict_mode" = skip ] && bootstrap_classification=skip-conflict ||
                  bootstrap_classification=fail-conflict
                ;;
            esac
          fi
          ;;
        2)
          bootstrap_candidate=
          bootstrap_conflicts=$((bootstrap_conflicts + 1))
          [ "$conflict_mode" = skip ] && bootstrap_classification=skip-conflict ||
            bootstrap_classification=fail-conflict
          ;;
        *)
          printf 'ERROR: bootstrap candidate generation failed operationally\n' >&2
          exit 1
          ;;
      esac
    fi
  else
    fprs_bootstrap_candidate "$bootstrap_relative" "$bootstrap_target" \
      "$bootstrap_candidate" || exit 1
    bootstrap_classification=create
  fi
  printf '%s|%s|%s\n' "$bootstrap_relative" "$bootstrap_classification" \
    "$bootstrap_candidate" >> "$bootstrap_stage/plan.unsorted" || exit 1
done < "$bootstrap_stage/targets"
LC_ALL=C sort -t '|' -k1,1 "$bootstrap_stage/plan.unsorted" > "$bootstrap_stage/plan"
while IFS='|' read -r bootstrap_relative bootstrap_classification bootstrap_candidate
do
  printf 'PLAN %s %s\n' "$bootstrap_classification" "$bootstrap_relative"
done < "$bootstrap_stage/plan"

if [ "$bootstrap_conflicts" -gt 0 ]; then
  if [ "$conflict_mode" = fail ]; then
    printf 'ERROR: bootstrap refused conflicting paths\n' >&2
    exit 2
  fi
  if [ "$dry_run" -eq 1 ]; then
    printf 'ERROR: bootstrap incomplete; conflicts were skipped\n' >&2
    exit 1
  fi
fi
[ "$dry_run" -eq 0 ] || exit 0

fprs_project_transaction_begin "$project_root" || exit $?
while IFS='|' read -r bootstrap_relative bootstrap_classification bootstrap_candidate
do
  case "$bootstrap_classification" in
    preserve) ;;
    create|update-owned|merge)
      fprs_project_transaction_register "$bootstrap_relative" "$bootstrap_candidate" || {
        bootstrap_status=$?
        fprs_project_transaction_abort >/dev/null 2>&1 || true
        exit "$bootstrap_status"
      }
      ;;
  esac
done < "$bootstrap_stage/plan"
fprs_project_transaction_validate fprs_bootstrap_validate_candidate || {
  bootstrap_status=$?
  fprs_project_transaction_abort >/dev/null 2>&1 || true
  exit "$bootstrap_status"
}
fprs_project_transaction_commit
bootstrap_status=$?
[ "$bootstrap_status" -eq 0 ] || exit "$bootstrap_status"
if [ "$bootstrap_conflicts" -gt 0 ]; then
  printf 'ERROR: bootstrap incomplete; conflicts were skipped\n' >&2
  exit 1
fi
exit 0
