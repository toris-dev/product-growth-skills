#!/usr/bin/env bash
# Inspect a Flutter project using static, known configuration files only.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || {
  printf 'ERROR: could not resolve the inspector directory\n' >&2
  exit 1
}
COMMON="$SCRIPT_DIR/lib/common.sh"
[ -r "$COMMON" ] || {
  printf 'ERROR: common helpers are unavailable\n' >&2
  exit 1
}
. "$COMMON"

fprs_inspection_usage() {
  printf 'Usage: %s --project PATH [--format human|json] [--flavor NAME]\n' \
    "${0##*/}" >&2
}

fprs_inspection_argument_error() {
  printf 'ERROR: %s\n' "$1" >&2
  fprs_inspection_usage
  exit 2
}

fprs_inspection_root_error() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

fprs_append_warning() {
  local fprs_message
  fprs_message=$1
  if [ -z "$warnings" ]; then
    warnings=$fprs_message
  else
    warnings="$warnings
$fprs_message"
  fi
}

fprs_append_failure() {
  local fprs_message
  fprs_message=$1
  if [ -z "$failures" ]; then
    failures=$fprs_message
  else
    failures="$failures
$fprs_message"
  fi
}

fprs_line_count() {
  if [ -z "$1" ]; then
    printf '0\n'
  else
    printf '%s\n' "$1" | awk 'NF { count++ } END { print count + 0 }'
  fi
}

fprs_pubspec_environment_value() {
  local fprs_file fprs_target
  fprs_file=$1
  fprs_target=$2
  awk -v target="$fprs_target" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^[^[:space:]#][^:]*:/ {
      section = $0
      sub(/:.*/, "", section)
      section = trim(section)
      in_environment = (section == "environment")
    }
    in_environment && $0 ~ "^[[:space:]]+" target "[[:space:]]*:" {
      value = $0
      sub("^[[:space:]]+" target "[[:space:]]*:[[:space:]]*", "", value)
      sub(/[[:space:]]+#.*/, "", value)
      value = trim(value)
      first = substr(value, 1, 1)
      last = substr(value, length(value), 1)
      if ((first == "\"" && last == "\"") || (first == "\047" && last == "\047")) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$fprs_file"
}

fprs_pubspec_top_value() {
  local fprs_file fprs_target
  fprs_file=$1
  fprs_target=$2
  awk -v target="$fprs_target" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    $0 ~ "^" target "[[:space:]]*:" {
      value = $0
      sub("^" target "[[:space:]]*:[[:space:]]*", "", value)
      sub(/[[:space:]]+#.*/, "", value)
      value = trim(value)
      first = substr(value, 1, 1)
      last = substr(value, length(value), 1)
      if ((first == "\"" && last == "\"") || (first == "\047" && last == "\047")) {
        value = substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$fprs_file"
}

fprs_pubspec_has_dependency() {
  local fprs_file fprs_target
  fprs_file=$1
  fprs_target=$2
  awk -v target="$fprs_target" '
    /^[^[:space:]#][^:]*:/ {
      section = $0
      sub(/:.*/, "", section)
      in_dependencies = (section == "dependencies" || section == "dev_dependencies")
      next
    }
    in_dependencies && $0 ~ "^[[:space:]]+" target "[[:space:]]*:" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$fprs_file"
}

fprs_extract_json_string_field() {
  local fprs_file fprs_field
  fprs_file=$1
  fprs_field=$2
  awk -v field="$fprs_field" '
    {
      line = $0
      pattern = "\"" field "\"[[:space:]]*:[[:space:]]*\""
      if (line !~ pattern) next
      sub("^.*\"" field "\"[[:space:]]*:[[:space:]]*\"", "", line)
      sub(/\".*/, "", line)
      print line
      exit
    }
  ' "$fprs_file"
}

fprs_gradle_without_comments() {
  local fprs_file
  fprs_file=$1
  awk '
    {
      line = $0
      while (1) {
        if (in_block_comment) {
          if (match(line, /\*\//)) {
            line = substr(line, RSTART + RLENGTH)
            in_block_comment = 0
            continue
          }
          line = ""
          break
        }
        if (match(line, /\/\*/)) {
          before = substr(line, 1, RSTART - 1)
          rest = substr(line, RSTART + RLENGTH)
          if (match(rest, /\*\//)) {
            line = before substr(rest, RSTART + RLENGTH)
            continue
          }
          line = before
          in_block_comment = 1
        }
        break
      }
      sub(/[[:space:]]*\/\/.*/, "", line)
      print line
    }
  ' "$fprs_file"
}

fprs_extract_default_config_text() {
  fprs_gradle_without_comments "$gradle_path" | awk '
    function brace_delta(value, opens, closes, copy) {
      copy = value
      opens = gsub(/\{/, "{", copy)
      copy = value
      closes = gsub(/\}/, "}", copy)
      return opens - closes
    }
    !inside && /defaultConfig[[:space:]]*\{/ {
      inside = 1
      depth = brace_delta($0)
      print
      if (depth <= 0) exit
      next
    }
    inside {
      print
      depth += brace_delta($0)
      if (depth <= 0) exit
    }
  '
}

fprs_text_key_present() {
  local fprs_text fprs_key
  fprs_text=$1
  fprs_key=$2
  printf '%s\n' "$fprs_text" | awk -v key="$fprs_key" '
    $0 ~ "(^|[;{[:space:]])" key "([[:space:]]|=)" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  '
}

fprs_extract_text_literal() {
  local fprs_text fprs_key
  fprs_text=$1
  fprs_key=$2
  printf '%s\n' "$fprs_text" | awk -v key="$fprs_key" '
    $0 ~ "(^|[;{[:space:]])" key "([[:space:]]|=)" {
      line = $0
      sub("^.*" key "[[:space:]]*", "", line)
      sub(/^=[[:space:]]*/, "", line)
      quote = substr(line, 1, 1)
      if (quote != "\"" && quote != "\047") next
      line = substr(line, 2)
      end = index(line, quote)
      if (end < 1) next
      remainder = substr(line, end + 1)
      gsub(/[[:space:];}]/, "", remainder)
      if (remainder == "") {
        print substr(line, 1, end - 1)
        exit
      }
    }
  '
}

fprs_extract_text_integer() {
  local fprs_text fprs_key
  fprs_text=$1
  fprs_key=$2
  printf '%s\n' "$fprs_text" | awk -v key="$fprs_key" '
    $0 ~ "(^|[;{[:space:]])" key "([[:space:]]|=)" {
      line = $0
      sub("^.*" key "[[:space:]]*", "", line)
      sub(/^=[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/[;}][[:space:]]*$/, "", line)
      if (line ~ /^[0-9][0-9_]*$/) {
        gsub(/_/, "", line)
        print line
        exit
      }
    }
  '
}

fprs_gradle_key_present() {
  local fprs_file fprs_key
  fprs_file=$1
  fprs_key=$2
  fprs_gradle_without_comments "$fprs_file" |
    grep -E "^[[:space:]]*$fprs_key([[:space:]]|=)" >/dev/null 2>&1
}

fprs_extract_gradle_literal() {
  local fprs_file fprs_key
  fprs_file=$1
  fprs_key=$2
  fprs_gradle_without_comments "$fprs_file" | awk -v key="$fprs_key" '
    $0 ~ "^[[:space:]]*" key "([[:space:]]|=)" {
      line = $0
      sub("^[[:space:]]*" key "[[:space:]]*", "", line)
      sub(/^=[[:space:]]*/, "", line)
      quote = substr(line, 1, 1)
      if (quote != "\"" && quote != "\047") next
      line = substr(line, 2)
      end = index(line, quote)
      if (end > 0) {
        remainder = substr(line, end + 1)
        gsub(/[[:space:]]/, "", remainder)
        if (remainder == "" || remainder == ";") {
          print substr(line, 1, end - 1)
          exit
        }
      }
    }
  '
}

fprs_extract_gradle_integer() {
  local fprs_file fprs_key
  fprs_file=$1
  fprs_key=$2
  fprs_gradle_without_comments "$fprs_file" | awk -v key="$fprs_key" '
    $0 ~ "^[[:space:]]*" key "([[:space:]]|=)" {
      line = $0
      sub("^[[:space:]]*" key "[[:space:]]*", "", line)
      sub(/^=[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      sub(/;[[:space:]]*$/, "", line)
      if (line ~ /^[0-9][0-9_]*$/) {
        gsub(/_/, "", line)
        print line
        exit
      }
    }
  '
}

fprs_read_property() {
  local fprs_file fprs_key
  fprs_file=$1
  fprs_key=$2
  [ -f "$fprs_file" ] || return 0
  awk -F= -v target="$fprs_key" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    /^[[:space:]]*[#!]/ { next }
    {
      key = trim($1)
      if (key != target) next
      value = substr($0, index($0, "=") + 1)
      print trim(value)
      exit
    }
  ' "$fprs_file"
}

fprs_extract_agp_version() {
  local fprs_file fprs_value
  for fprs_file in \
    "$project_root/android/settings.gradle" \
    "$project_root/android/settings.gradle.kts" \
    "$project_root/android/build.gradle" \
    "$project_root/android/build.gradle.kts"
  do
    [ -f "$fprs_file" ] || continue
    fprs_value=$(fprs_gradle_without_comments "$fprs_file" | awk '
      /com\.android\.application/ && /version[[:space:]]*[=]?[[:space:]]*["\047]/ {
        line = $0
        sub(/^.*version[[:space:]]*[=]?[[:space:]]*/, "", line)
        quote = substr(line, 1, 1)
        if (quote == "\"" || quote == "\047") {
          line = substr(line, 2)
          end = index(line, quote)
          if (end > 0) {
            print substr(line, 1, end - 1)
            exit
          }
        }
      }
      /com\.android\.tools\.build:gradle:/ {
        line = $0
        sub(/^.*com\.android\.tools\.build:gradle:/, "", line)
        sub(/[^0-9A-Za-z_.+-].*/, "", line)
        if (line != "") {
          print line
          exit
        }
      }
    ')
    if printf '%s\n' "$fprs_value" | grep -E '^[0-9][0-9A-Za-z_.+-]*$' >/dev/null 2>&1; then
      printf '%s\n' "$fprs_value"
      return 0
    fi
  done
}

fprs_extract_gradle_wrapper_version() {
  local fprs_file
  fprs_file="$project_root/android/gradle/wrapper/gradle-wrapper.properties"
  [ -f "$fprs_file" ] || return 0
  awk '
    /^distributionUrl[[:space:]]*=/ && /gradle-[0-9][0-9.]*-(all|bin)\.zip/ {
      line = $0
      sub(/^.*gradle-/, "", line)
      sub(/-(all|bin)\.zip.*$/, "", line)
      if (line ~ /^[0-9][0-9.]*$/) print line
      exit
    }
  ' "$fprs_file"
}

fprs_extract_java_compatibility() {
  fprs_gradle_without_comments "$gradle_path" | awk '
    /JavaVersion\.VERSION_[0-9]+/ {
      line = $0
      sub(/^.*JavaVersion\.VERSION_/, "", line)
      sub(/[^0-9].*/, "", line)
      if (line != "") {
        print line
        exit
      }
    }
  '
}

fprs_extract_release_signing_reference() {
  fprs_gradle_without_comments "$gradle_path" | awk '
    function brace_delta(value, opens, closes, copy) {
      copy = value
      opens = gsub(/\{/, "{", copy)
      copy = value
      closes = gsub(/\}/, "}", copy)
      return opens - closes
    }
    !inside && /buildTypes[[:space:]]*\{/ {
      inside = 1
      depth = brace_delta($0)
      next
    }
    inside {
      line = $0
      if (depth == 1 &&
          (line ~ /^[[:space:]]*release[[:space:]]*\{/ ||
           line ~ /^[[:space:]]*(getByName|named)[[:space:]]*\([[:space:]]*"release"[[:space:]]*\)[[:space:]]*\{/ ||
           line ~ /^[[:space:]]*(getByName|named)[[:space:]]*\([[:space:]]*\047release\047[[:space:]]*\)[[:space:]]*\{/)) {
        in_release = 1
        reference = ""
      }
      if (in_release && line ~ /signingConfig([[:space:]]|=)/) {
        reference = "unknown"
        if (line ~ /signingConfigs\.getByName[[:space:]]*\(/) {
          if (line ~ /signingConfigs\.getByName[[:space:]]*\([[:space:]]*["\047]debug["\047]/) reference = "debug"
          else if (line ~ /signingConfigs\.getByName[[:space:]]*\([[:space:]]*["\047][A-Za-z][A-Za-z0-9_]*["\047]/) reference = "release"
        } else if (line ~ /signingConfigs[[:space:]]*\[/) {
          if (line ~ /signingConfigs[[:space:]]*\[[[:space:]]*["\047]debug["\047]/) reference = "debug"
          else if (line ~ /signingConfigs[[:space:]]*\[[[:space:]]*["\047][A-Za-z][A-Za-z0-9_]*["\047]/) reference = "release"
        } else if (line ~ /signingConfigs\.debug([^A-Za-z0-9_]|$)/) reference = "debug"
        else if (line ~ /signingConfigs\.[A-Za-z][A-Za-z0-9_]*/) reference = "release"
      }
      depth += brace_delta(line)
      if (in_release && depth <= 1) {
        if (reference != "") print reference
        exit
      }
      if (depth <= 0) exit
    }
  '
}

fprs_extract_flavor_records() {
  fprs_gradle_without_comments "$gradle_path" | awk '
    function brace_delta(value, opens, closes, copy) {
      copy = value
      opens = gsub(/\{/, "{", copy)
      copy = value
      closes = gsub(/\}/, "}", copy)
      return opens - closes
    }
    function literal_value(value, key, quote, end) {
      literal_ok = 0
      sub("^.*" key "[[:space:]]*", "", value)
      sub(/^=[[:space:]]*/, "", value)
      quote = substr(value, 1, 1)
      if (quote != "\"" && quote != "\047") return ""
      value = substr(value, 2)
      end = index(value, quote)
      if (end < 1) return ""
      remainder = substr(value, end + 1)
      gsub(/[[:space:];}]/, "", remainder)
      if (remainder != "") return ""
      literal_ok = 1
      return substr(value, 1, end - 1)
    }
    !inside && /productFlavors[[:space:]]*\{/ {
      inside = 1
      depth = brace_delta($0)
      next
    }
    inside {
      line = $0
      if (depth == 1) {
        name = ""
        if (line ~ /^[[:space:]]*(create|maybeCreate)[[:space:]]*\([[:space:]]*"[A-Za-z][A-Za-z0-9_-]*"/) {
          name = line
          sub(/^[[:space:]]*(create|maybeCreate)[[:space:]]*\([[:space:]]*"/, "", name)
          sub(/".*/, "", name)
        } else if (line ~ /^[[:space:]]*(create|maybeCreate)[[:space:]]*\([[:space:]]*\047[A-Za-z][A-Za-z0-9_-]*\047/) {
          name = line
          sub(/^[[:space:]]*(create|maybeCreate)[[:space:]]*\([[:space:]]*\047/, "", name)
          sub(/\047.*/, "", name)
        } else if (line ~ /^[[:space:]]*[A-Za-z][A-Za-z0-9_-]*[[:space:]]*\{/) {
          name = line
          sub(/^[[:space:]]*/, "", name)
          sub(/[[:space:]]*\{.*/, "", name)
        }
        if (name != "") {
          current = name
          suffix = ""
          suffix_status = "absent"
          override = ""
          override_status = "absent"
        }
      }
      if (current != "" && line ~ /applicationIdSuffix([[:space:]]|=)/) {
        suffix = literal_value(line, "applicationIdSuffix")
        if (literal_ok && suffix ~ /^\.?[A-Za-z0-9_.-]*$/) suffix_status = "resolved"
        else {
          suffix = ""
          suffix_status = "unresolved"
        }
      }
      if (current != "" && line ~ /applicationId([[:space:]]|=)/ &&
          line !~ /applicationIdSuffix/) {
        override = literal_value(line, "applicationId")
        if (literal_ok && override ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/) override_status = "resolved"
        else {
          override = ""
          override_status = "unresolved"
        }
      }
      depth += brace_delta(line)
      if (current != "" && depth <= 1) {
        if (current ~ /^[A-Za-z][A-Za-z0-9_-]*$/) {
          print current "|" suffix_status "|" suffix "|" override_status "|" override
        }
        current = ""
        suffix = ""
        suffix_status = ""
        override = ""
        override_status = ""
      }
      if (depth <= 0) exit
    }
  ' | LC_ALL=C sort -t '|' -k1,1 -u
}

fprs_extract_flavor_dimensions() {
  fprs_gradle_without_comments "$gradle_path" | awk '
    function emit_quoted(value, index_value, quote, rest, end, item, outside, emitted) {
      index_value = 1
      while (index_value <= length(value)) {
        quote = substr(value, index_value, 1)
        if (quote != "\"" && quote != "\047") {
          outside = outside quote
          index_value++
          continue
        }
        rest = substr(value, index_value + 1)
        end = index(rest, quote)
        if (end < 1) {
          outside = outside quote rest
          break
        }
        item = substr(rest, 1, end - 1)
        if (item ~ /^[A-Za-z][A-Za-z0-9_-]*$/) {
          print item
          emitted++
        } else outside = outside item
        index_value += end + 1
      }
      gsub(/listOf/, "", outside)
      gsub(/[[:space:],+=[\]()]/, "", outside)
      if (!emitted || outside != "") print "?"
    }
    /flavorDimensions/ {
      line = $0
      sub(/^.*flavorDimensions[[:space:]]*/, "", line)
      emit_quoted(line)
      next
    }
    /^[[:space:]]*dimension([[:space:]]|=)/ {
      line = $0
      sub(/^[[:space:]]*dimension[[:space:]]*/, "", line)
      emit_quoted(line)
    }
  ' | LC_ALL=C sort -u
}

fprs_flavor_record() {
  local fprs_name
  fprs_name=$1
  printf '%s\n' "$flavor_records" | awk -F '|' -v target="$fprs_name" '
    $1 == target { print; found = 1; exit }
    END { if (!found) exit 1 }
  '
}

fprs_extract_firebase_records() {
  local fprs_file
  fprs_file=$1
  [ -f "$fprs_file" ] || return 0
  awk '
    function json_value(source, key, value) {
      value = source
      sub("^.*\"" key "\"[[:space:]]*:[[:space:]]*\"", "", value)
      sub(/\".*/, "", value)
      return value
    }
    { document = document $0 "\n" }
    END {
      while (match(document, /"(mobilesdk_app_id|package_name)"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        token = substr(document, RSTART, RLENGTH)
        document = substr(document, RSTART + RLENGTH)
        if (token ~ /^"mobilesdk_app_id"/) {
          app_id = json_value(token, "mobilesdk_app_id")
        } else {
          package_name = json_value(token, "package_name")
        }
        if (app_id != "" && package_name != "") {
          if (app_id ~ /^[A-Za-z0-9:._-]+$/ && package_name ~ /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/) {
            print package_name "|" app_id
          }
          app_id = ""
          package_name = ""
        }
      }
    }
  ' "$fprs_file"
}

fprs_json_string() {
  local fprs_escaped
  fprs_escaped=$(fprs_json_escape "$1") || return 1
  printf '"%s"' "$fprs_escaped"
}

fprs_json_nullable_string() {
  if [ -z "$1" ]; then
    printf 'null'
  else
    fprs_json_string "$1"
  fi
}

fprs_json_string_array() {
  local fprs_lines fprs_first fprs_line
  fprs_lines=$1
  fprs_first=true
  printf '['
  if [ -n "$fprs_lines" ]; then
    while IFS= read -r fprs_line
    do
      [ -n "$fprs_line" ] || continue
      if [ "$fprs_first" = true ]; then
        fprs_first=false
      else
        printf ','
      fi
      fprs_json_string "$fprs_line" || return 1
    done <<EOF
$fprs_lines
EOF
  fi
  printf ']'
}

fprs_json_firebase_apps() {
  local fprs_first fprs_record fprs_package fprs_app_id fprs_matches
  fprs_first=true
  printf '['
  if [ -n "$firebase_records" ]; then
    while IFS= read -r fprs_record
    do
      [ -n "$fprs_record" ] || continue
      fprs_package=${fprs_record%%|*}
      fprs_app_id=${fprs_record#*|}
      if [ "$fprs_first" = true ]; then
        fprs_first=false
      else
        printf ','
      fi
      if [ -z "$application_id" ]; then
        fprs_matches=null
      elif [ "$fprs_package" = "$application_id" ]; then
        fprs_matches=true
      else
        fprs_matches=false
      fi
      printf '{"package_name":'
      fprs_json_string "$fprs_package" || return 1
      printf ',"app_id":'
      fprs_json_string "$fprs_app_id" || return 1
      printf ',"matches_application_id":%s}' "$fprs_matches"
    done <<EOF
$firebase_records
EOF
  fi
  printf ']'
}

fprs_boolean_human() {
  if [ "$1" = true ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

fprs_human_unknown() {
  if [ -n "$1" ]; then
    printf '%s' "$1"
  else
    printf 'unknown'
  fi
}

fprs_human_lines() {
  local fprs_lines fprs_empty fprs_result fprs_line
  fprs_lines=$1
  fprs_empty=$2
  fprs_result=
  if [ -n "$fprs_lines" ]; then
    while IFS= read -r fprs_line
    do
      [ -n "$fprs_line" ] || continue
      if [ -z "$fprs_result" ]; then
        fprs_result=$fprs_line
      else
        fprs_result="$fprs_result, $fprs_line"
      fi
    done <<EOF
$fprs_lines
EOF
  fi
  if [ -n "$fprs_result" ]; then
    printf '%s' "$fprs_result"
  else
    printf '%s' "$fprs_empty"
  fi
}

fprs_human_firebase_apps() {
  local fprs_result fprs_record fprs_package fprs_app_id fprs_match
  fprs_result=
  if [ -n "$firebase_records" ]; then
    while IFS= read -r fprs_record
    do
      [ -n "$fprs_record" ] || continue
      fprs_package=${fprs_record%%|*}
      fprs_app_id=${fprs_record#*|}
      if [ -z "$application_id" ]; then
        fprs_match=unknown
      elif [ "$fprs_package" = "$application_id" ]; then
        fprs_match=yes
      else
        fprs_match=no
      fi
      if [ -z "$fprs_result" ]; then
        fprs_result="$fprs_package -> $fprs_app_id (match: $fprs_match)"
      else
        fprs_result="$fprs_result, $fprs_package -> $fprs_app_id (match: $fprs_match)"
      fi
    done <<EOF
$firebase_records
EOF
  fi
  if [ -n "$fprs_result" ]; then
    printf '%s' "$fprs_result"
  else
    printf 'none'
  fi
}

fprs_emit_json() {
  printf '{"schema_version":1,"project_root":'
  fprs_json_string "$project_root" || return 1
  printf ',"flutter_constraint":'
  fprs_json_nullable_string "$flutter_constraint" || return 1
  printf ',"dart_constraint":'
  fprs_json_nullable_string "$dart_constraint" || return 1
  printf ',"flutter_version":'
  fprs_json_nullable_string "$flutter_version" || return 1
  printf ',"android_dsl":'
  fprs_json_string "$android_dsl" || return 1
  printf ',"gradle_file":'
  fprs_json_nullable_string "$gradle_file" || return 1
  printf ',"android_gradle_plugin_version":'
  fprs_json_nullable_string "$android_gradle_plugin_version" || return 1
  printf ',"gradle_wrapper_version":'
  fprs_json_nullable_string "$gradle_wrapper_version" || return 1
  printf ',"java_compatibility":'
  fprs_json_nullable_string "$java_compatibility" || return 1
  printf ',"application_id":'
  fprs_json_nullable_string "$application_id" || return 1
  printf ',"namespace":'
  fprs_json_nullable_string "$namespace" || return 1
  printf ',"application_id_candidates":'
  fprs_json_string_array "$application_id_candidates" || return 1
  printf ',"version_name":'
  fprs_json_nullable_string "$version_name" || return 1
  printf ',"version_code":'
  fprs_json_nullable_string "$version_code" || return 1
  printf ',"pubspec_version_name":'
  fprs_json_nullable_string "$pubspec_version_name" || return 1
  printf ',"pubspec_build_number":'
  fprs_json_nullable_string "$pubspec_build_number" || return 1
  printf ',"flavors":'
  fprs_json_string_array "$flavors" || return 1
  printf ',"selected_flavor":'
  fprs_json_nullable_string "$selected_flavor" || return 1
  printf ',"suggested_flavor":'
  fprs_json_nullable_string "$suggested_flavor" || return 1
  printf ',"suggestion_confirmed":%s,"entrypoints":' "$suggestion_confirmed"
  fprs_json_string_array "$entrypoints" || return 1
  printf ',"build_runner":%s,"fastlane":%s,"github_actions":%s' \
    "$build_runner" "$fastlane" "$github_actions"
  printf ',"release_signing":%s,"release_uses_debug_signing":%s,"firebase":%s' \
    "$release_signing" "$release_uses_debug_signing" "$firebase"
  printf ',"firebase_package_names":'
  fprs_json_string_array "$firebase_package_names" || return 1
  printf ',"firebase_apps":'
  fprs_json_firebase_apps || return 1
  printf ',"firebase_app_distribution":%s,"monorepo":%s,"git_dirty":%s' \
    "$firebase_app_distribution" "$monorepo" "$git_dirty"
  printf ',"files_bootstrap_may_change":'
  fprs_json_string_array "$files_bootstrap_may_change" || return 1
  printf ',"warnings":'
  fprs_json_string_array "$warnings" || return 1
  printf ',"failures":'
  fprs_json_string_array "$failures" || return 1
  printf '}\n'
}

fprs_emit_human() {
  printf 'Flutter project inspection\n'
  printf 'Schema version: 1\n'
  printf 'Project root: %s\n' "$project_root"
  printf 'Flutter constraint: %s\n' "$(fprs_human_unknown "$flutter_constraint")"
  printf 'Dart constraint: %s\n' "$(fprs_human_unknown "$dart_constraint")"
  printf 'Flutter version: %s\n' "$(fprs_human_unknown "$flutter_version")"
  printf 'Android DSL: %s\n' "$android_dsl"
  printf 'Gradle file: %s\n' "$(fprs_human_unknown "$gradle_file")"
  printf 'Android Gradle plugin: %s\n' "$(fprs_human_unknown "$android_gradle_plugin_version")"
  printf 'Gradle wrapper: %s\n' "$(fprs_human_unknown "$gradle_wrapper_version")"
  printf 'Java compatibility: %s\n' "$(fprs_human_unknown "$java_compatibility")"
  printf 'Application ID: %s\n' "$(fprs_human_unknown "$application_id")"
  printf 'Namespace: %s\n' "$(fprs_human_unknown "$namespace")"
  printf 'Application ID candidates: %s\n' "$(fprs_human_lines "$application_id_candidates" none)"
  printf 'Version name: %s\n' "$(fprs_human_unknown "$version_name")"
  printf 'Version code: %s\n' "$(fprs_human_unknown "$version_code")"
  printf 'Pubspec version name: %s\n' "$(fprs_human_unknown "$pubspec_version_name")"
  printf 'Pubspec build number: %s\n' "$(fprs_human_unknown "$pubspec_build_number")"
  printf 'Flavors: %s\n' "$(fprs_human_lines "$flavors" none)"
  printf 'Selected flavor: %s\n' "$(fprs_human_lines "$selected_flavor" none)"
  printf 'Suggested flavor: %s\n' "$(fprs_human_lines "$suggested_flavor" none)"
  printf 'Suggestion confirmed: %s\n' "$(fprs_boolean_human "$suggestion_confirmed")"
  printf 'Entrypoints: %s\n' "$(fprs_human_lines "$entrypoints" none)"
  printf 'Build runner: %s\n' "$(fprs_boolean_human "$build_runner")"
  printf 'Fastlane: %s\n' "$(fprs_boolean_human "$fastlane")"
  printf 'GitHub Actions: %s\n' "$(fprs_boolean_human "$github_actions")"
  printf 'Release signing: %s\n' "$(fprs_boolean_human "$release_signing")"
  printf 'Release uses debug signing: %s\n' "$(fprs_boolean_human "$release_uses_debug_signing")"
  printf 'Firebase: %s\n' "$(fprs_boolean_human "$firebase")"
  printf 'Firebase package names: %s\n' "$(fprs_human_lines "$firebase_package_names" none)"
  printf 'Firebase apps: %s\n' "$(fprs_human_firebase_apps)"
  printf 'Firebase App Distribution: %s\n' "$(fprs_boolean_human "$firebase_app_distribution")"
  printf 'Monorepo: %s\n' "$(fprs_boolean_human "$monorepo")"
  if [ "$git_dirty" = null ]; then
    printf 'Git dirty: unknown\n'
  else
    printf 'Git dirty: %s\n' "$(fprs_boolean_human "$git_dirty")"
  fi
  printf 'Files bootstrap may change: %s\n' "$(fprs_human_lines "$files_bootstrap_may_change" none)"
  printf 'Warnings: %s\n' "$(fprs_human_lines "$warnings" none)"
  printf 'Failures: %s\n' "$(fprs_human_lines "$failures" none)"
}

project_argument=
output_format=human
requested_flavor=
project_seen=false
format_seen=false
flavor_seen=false

while [ "$#" -gt 0 ]
do
  case "$1" in
    --project)
      [ "$project_seen" = false ] || fprs_inspection_argument_error 'duplicate --project option'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_inspection_argument_error 'missing value for --project'
      project_argument=$2
      project_seen=true
      shift 2
      ;;
    --format)
      [ "$format_seen" = false ] || fprs_inspection_argument_error 'duplicate --format option'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_inspection_argument_error 'missing value for --format'
      output_format=$2
      format_seen=true
      shift 2
      ;;
    --flavor)
      [ "$flavor_seen" = false ] || fprs_inspection_argument_error 'duplicate --flavor option'
      [ "$#" -ge 2 ] && [ -n "$2" ] || fprs_inspection_argument_error 'missing value for --flavor'
      requested_flavor=$2
      flavor_seen=true
      shift 2
      ;;
    -h|--help)
      if [ "$#" -ne 1 ] || [ "$project_seen" != false ] ||
        [ "$format_seen" != false ] || [ "$flavor_seen" != false ]
      then
        fprs_inspection_argument_error '--help cannot be combined with other arguments'
      fi
      fprs_inspection_usage
      exit 0
      ;;
    --*) fprs_inspection_argument_error "unknown option: $1" ;;
    *) fprs_inspection_argument_error 'positional arguments are not supported' ;;
  esac
done

[ "$project_seen" = true ] || fprs_inspection_argument_error '--project is required'
case "$output_format" in
  human|json) ;;
  *) fprs_inspection_argument_error '--format must be human or json' ;;
esac
if [ -n "$requested_flavor" ] && ! printf '%s\n' "$requested_flavor" |
  grep -E '^[A-Za-z][A-Za-z0-9_-]*$' >/dev/null 2>&1
then
  fprs_inspection_argument_error '--flavor must be a static Gradle flavor name'
fi

project_root=$(fprs_realpath "$project_argument") ||
  fprs_inspection_root_error 'project path could not be resolved'
[ -d "$project_root" ] || fprs_inspection_root_error 'project path is not a directory'
[ -f "$project_root/pubspec.yaml" ] ||
  fprs_inspection_root_error 'project root must contain pubspec.yaml'
[ -r "$project_root/pubspec.yaml" ] || fprs_die 'project pubspec.yaml is not readable'
[ -d "$project_root/android" ] ||
  fprs_inspection_root_error 'project root must contain android/'
[ -d "$project_root/android/app" ] ||
  fprs_inspection_root_error 'project root must contain android/app/'

groovy_gradle="$project_root/android/app/build.gradle"
kotlin_gradle="$project_root/android/app/build.gradle.kts"
dsl_failure=
if [ -f "$groovy_gradle" ] && [ -f "$kotlin_gradle" ]; then
  android_dsl=ambiguous
  gradle_file=
  gradle_path=
  dsl_failure='android/app contains both build.gradle and build.gradle.kts'
elif [ -f "$groovy_gradle" ]; then
  android_dsl=groovy
  gradle_file=android/app/build.gradle
  gradle_path=$groovy_gradle
elif [ -f "$kotlin_gradle" ]; then
  android_dsl=kotlin
  gradle_file=android/app/build.gradle.kts
  gradle_path=$kotlin_gradle
else
  android_dsl=missing
  gradle_file=
  gradle_path=
  dsl_failure='android/app contains neither build.gradle nor build.gradle.kts'
fi
if [ -n "$gradle_path" ] && [ ! -r "$gradle_path" ]; then
  fprs_die 'selected Android Gradle file is not readable'
fi

warnings=
failures=
inspection_status=0
if [ -n "$dsl_failure" ]; then
  fprs_append_failure "$dsl_failure"
  inspection_status=2
fi

flutter_constraint=$(fprs_pubspec_environment_value "$project_root/pubspec.yaml" flutter)
dart_constraint=$(fprs_pubspec_environment_value "$project_root/pubspec.yaml" sdk)
pubspec_version=$(fprs_pubspec_top_value "$project_root/pubspec.yaml" version)
pubspec_version_name=
pubspec_build_number=
if [ -n "$pubspec_version" ]; then
  case "$pubspec_version" in
    *+*)
      pubspec_version_name=${pubspec_version%%+*}
      pubspec_build_number=${pubspec_version#*+}
      ;;
    *) pubspec_version_name=$pubspec_version ;;
  esac
fi
if [ -n "$flutter_constraint" ] && ! printf '%s\n' "$flutter_constraint" |
  grep -E '^[-0-9A-Za-z<>=~^.*+[:space:]]+$' >/dev/null 2>&1
then
  flutter_constraint=
fi
if [ -n "$dart_constraint" ] && ! printf '%s\n' "$dart_constraint" |
  grep -E '^[-0-9A-Za-z<>=~^.*+[:space:]]+$' >/dev/null 2>&1
then
  dart_constraint=
fi
if [ -n "$pubspec_version_name" ] && ! printf '%s\n' "$pubspec_version_name" |
  grep -E '^[0-9A-Za-z][0-9A-Za-z._+-]*$' >/dev/null 2>&1
then
  pubspec_version_name=
fi
if [ -n "$pubspec_build_number" ] && ! printf '%s\n' "$pubspec_build_number" |
  grep -E '^[0-9]+$' >/dev/null 2>&1
then
  pubspec_build_number=
fi

if fprs_pubspec_has_dependency "$project_root/pubspec.yaml" build_runner
then
  build_runner=true
else
  build_runner=false
fi

flutter_version=
if [ -f "$project_root/.fvmrc" ]; then
  flutter_version=$(fprs_extract_json_string_field "$project_root/.fvmrc" flutter)
elif [ -f "$project_root/.fvm/fvm_config.json" ]; then
  flutter_version=$(fprs_extract_json_string_field \
    "$project_root/.fvm/fvm_config.json" flutterSdkVersion)
fi
if [ -n "$flutter_version" ] && ! printf '%s\n' "$flutter_version" |
  grep -E '^[0-9][0-9A-Za-z._+-]*$' >/dev/null 2>&1
then
  flutter_version=
fi

android_gradle_plugin_version=$(fprs_extract_agp_version)
gradle_wrapper_version=$(fprs_extract_gradle_wrapper_version)
java_compatibility=
[ -z "$gradle_path" ] || java_compatibility=$(fprs_extract_java_compatibility)

application_id_present=false
namespace_present=false
version_code_present=false
version_name_present=false
base_application_id=
namespace=
version_code=
version_name=
default_config_text=
if [ -n "$gradle_path" ]; then
  default_config_text=$(fprs_extract_default_config_text)
  fprs_text_key_present "$default_config_text" applicationId && application_id_present=true
  fprs_gradle_key_present "$gradle_path" namespace && namespace_present=true
  fprs_text_key_present "$default_config_text" versionCode && version_code_present=true
  fprs_text_key_present "$default_config_text" versionName && version_name_present=true

  base_application_id=$(fprs_extract_text_literal "$default_config_text" applicationId)
  namespace=$(fprs_extract_gradle_literal "$gradle_path" namespace)
  version_code=$(fprs_extract_text_integer "$default_config_text" versionCode)
  version_name=$(fprs_extract_text_literal "$default_config_text" versionName)
fi

if [ -n "$base_application_id" ] && ! printf '%s\n' "$base_application_id" |
  grep -E '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' >/dev/null 2>&1
then
  base_application_id=
fi
if [ -n "$namespace" ] && ! printf '%s\n' "$namespace" |
  grep -E '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' >/dev/null 2>&1
then
  namespace=
fi

if [ -n "$gradle_path" ] && [ -z "$version_name" ]; then
  if printf '%s\n' "$default_config_text" | grep -F 'VERSION_NAME' >/dev/null 2>&1; then
    version_name=$(fprs_read_property "$project_root/android/gradle.properties" VERSION_NAME)
  elif printf '%s\n' "$default_config_text" |
    grep -E 'flutterVersionName|flutter\.versionName' >/dev/null 2>&1
  then
    version_name=$(fprs_read_property "$project_root/android/local.properties" flutter.versionName)
    [ -n "$version_name" ] || version_name=$pubspec_version_name
  fi
fi
if [ -n "$gradle_path" ] && [ -z "$version_code" ]; then
  if printf '%s\n' "$default_config_text" | grep -F 'VERSION_CODE' >/dev/null 2>&1; then
    version_code=$(fprs_read_property "$project_root/android/gradle.properties" VERSION_CODE)
  elif printf '%s\n' "$default_config_text" |
    grep -E 'flutterVersionCode|flutter\.versionCode' >/dev/null 2>&1
  then
    version_code=$(fprs_read_property "$project_root/android/local.properties" flutter.versionCode)
    [ -n "$version_code" ] || version_code=$pubspec_build_number
  fi
fi
if [ -n "$version_name" ] && ! printf '%s\n' "$version_name" |
  grep -E '^[0-9A-Za-z][0-9A-Za-z._+-]*$' >/dev/null 2>&1
then
  version_name=
fi
if [ -n "$version_code" ] && ! printf '%s\n' "$version_code" |
  grep -E '^[0-9]+$' >/dev/null 2>&1
then
  version_code=
fi

[ "$application_id_present" = false ] || [ -n "$base_application_id" ] ||
  fprs_append_warning 'application ID expression could not be resolved'
[ "$namespace_present" = false ] || [ -n "$namespace" ] ||
  fprs_append_warning 'namespace expression could not be resolved'
[ "$version_code_present" = false ] || [ -n "$version_code" ] ||
  fprs_append_warning 'version code expression could not be resolved'
[ "$version_name_present" = false ] || [ -n "$version_name" ] ||
  fprs_append_warning 'version name expression could not be resolved'

flavor_records=
[ -z "$gradle_path" ] || flavor_records=$(fprs_extract_flavor_records)
flavors=$(printf '%s\n' "$flavor_records" | awk -F '|' 'NF && $1 != "" { print $1 }')
flavor_count=$(fprs_line_count "$flavors")
flavor_dimension_records=
[ -z "$gradle_path" ] || flavor_dimension_records=$(fprs_extract_flavor_dimensions)
flavor_dimensions=$(printf '%s\n' "$flavor_dimension_records" |
  awk '$0 != "?" && NF { print }')
flavor_dimension_count=$(fprs_line_count "$flavor_dimensions")
ambiguous_flavor_dimensions=false
if printf '%s\n' "$flavor_dimension_records" | grep -F -x '?' >/dev/null 2>&1; then
  ambiguous_flavor_dimensions=true
  fprs_append_warning 'flavor dimension expressions prevent deterministic application ID resolution'
elif [ "$flavor_dimension_count" -gt 1 ]; then
  ambiguous_flavor_dimensions=true
  fprs_append_warning 'multiple flavor dimensions prevent deterministic application ID resolution'
fi

entrypoints=$(
  for entrypoint_path in "$project_root"/lib/main*.dart
  do
    [ -f "$entrypoint_path" ] || continue
    printf 'lib/%s\n' "${entrypoint_path##*/}"
  done | LC_ALL=C sort -u
)

suggested_flavor=
suggested_matches=
if [ -n "$flavors" ]; then
  while IFS= read -r flavor_name
  do
    [ -n "$flavor_name" ] || continue
    if [ -f "$project_root/lib/main_$flavor_name.dart" ]; then
      if [ -z "$suggested_matches" ]; then
        suggested_matches=$flavor_name
      else
        suggested_matches="$suggested_matches
$flavor_name"
      fi
    fi
  done <<EOF
$flavors
EOF
fi
if [ "$(fprs_line_count "$suggested_matches")" -eq 1 ]; then
  suggested_flavor=$suggested_matches
fi

application_id_candidates=
flavor_candidate_records=
if [ "$flavor_count" -eq 0 ]; then
  application_id_candidates=$base_application_id
else
  candidate_lines=
  while IFS= read -r flavor_record
  do
    [ -n "$flavor_record" ] || continue
    flavor_name=${flavor_record%%|*}
    flavor_rest=${flavor_record#*|}
    flavor_suffix_status=${flavor_rest%%|*}
    flavor_rest=${flavor_rest#*|}
    flavor_suffix=${flavor_rest%%|*}
    flavor_rest=${flavor_rest#*|}
    flavor_override_status=${flavor_rest%%|*}
    flavor_override=${flavor_rest#*|}
    flavor_candidate_status=resolved

    case "$flavor_override_status" in
      resolved) flavor_candidate_base=$flavor_override ;;
      absent) flavor_candidate_base=$base_application_id ;;
      *)
        flavor_candidate_base=
        flavor_candidate_status=unresolved
        fprs_append_warning "application ID expression could not be resolved for flavor $flavor_name"
        ;;
    esac
    if [ "$flavor_suffix_status" = unresolved ]; then
      flavor_candidate_status=unresolved
      fprs_append_warning "application ID suffix expression could not be resolved for flavor $flavor_name"
    fi
    if [ -z "$flavor_candidate_base" ]; then
      flavor_candidate_status=unresolved
    fi
    if [ "$ambiguous_flavor_dimensions" = true ]; then
      flavor_candidate_status=unresolved
    fi

    flavor_candidate=
    if [ "$flavor_candidate_status" = resolved ]; then
      flavor_candidate="$flavor_candidate_base$flavor_suffix"
      if [ -z "$candidate_lines" ]; then
        candidate_lines=$flavor_candidate
      else
        candidate_lines="$candidate_lines
$flavor_candidate"
      fi
    fi
    flavor_candidate_record="$flavor_name|$flavor_candidate|$flavor_candidate_status"
    if [ -z "$flavor_candidate_records" ]; then
      flavor_candidate_records=$flavor_candidate_record
    else
      flavor_candidate_records="$flavor_candidate_records
$flavor_candidate_record"
    fi
  done <<EOF
$flavor_records
EOF
  application_id_candidates=$(printf '%s\n' "$candidate_lines" |
    awk 'NF && !seen[$0]++ { print }' | LC_ALL=C sort)
fi

selected_flavor=
suggestion_confirmed=false
application_id=
if [ -n "$requested_flavor" ]; then
  if selected_record=$(fprs_flavor_record "$requested_flavor"); then
    selected_flavor=$requested_flavor
    [ "$selected_flavor" != "$suggested_flavor" ] || suggestion_confirmed=true
    selected_candidate_record=$(printf '%s\n' "$flavor_candidate_records" |
      awk -F '|' -v target="$requested_flavor" '$1 == target { print; exit }')
    selected_candidate_rest=${selected_candidate_record#*|}
    selected_candidate=${selected_candidate_rest%%|*}
    selected_candidate_status=${selected_candidate_rest##*|}
    if [ "$selected_candidate_status" = resolved ]; then
      application_id=$selected_candidate
    fi
    if [ "$ambiguous_flavor_dimensions" = true ]; then
      fprs_append_failure 'multiple flavor dimensions require manual variant confirmation'
      inspection_status=2
    fi
  else
    fprs_append_failure 'requested flavor is not defined'
    inspection_status=2
  fi
elif [ "$flavor_count" -gt 1 ]; then
  fprs_append_failure 'multiple product flavors require --flavor'
  inspection_status=2
elif [ -n "$application_id_candidates" ]; then
  application_id=$(printf '%s\n' "$application_id_candidates" | sed -n '1p')
fi

if [ -n "$base_application_id" ] && [ -n "$namespace" ] &&
  [ "$base_application_id" != "$namespace" ]
then
  fprs_append_warning 'namespace differs from default application ID'
fi

release_signing_reference=
[ -z "$gradle_path" ] || release_signing_reference=$(fprs_extract_release_signing_reference)
case "$release_signing_reference" in
  release)
    release_signing=true
    release_uses_debug_signing=false
    ;;
  debug)
    release_signing=false
    release_uses_debug_signing=true
    fprs_append_warning 'release build type uses debug signing'
    ;;
  unknown)
    release_signing=false
    release_uses_debug_signing=false
    fprs_append_warning 'release signing expression could not be resolved'
    ;;
  *)
    release_signing=false
    release_uses_debug_signing=false
    ;;
esac

if [ -d "$project_root/android/fastlane" ]; then
  fastlane=true
else
  fastlane=false
fi

github_actions=false
for workflow_path in \
  "$project_root/.github/workflows/"*.yml \
  "$project_root/.github/workflows/"*.yaml
do
  if [ -f "$workflow_path" ]; then
    github_actions=true
    break
  fi
done

firebase=false
firebase_records=
for firebase_file in \
  "$project_root/android/app/google-services.json" \
  "$project_root/android/app/src/"*/google-services.json
do
  [ -f "$firebase_file" ] || continue
  firebase=true
  firebase_file_records=$(fprs_extract_firebase_records "$firebase_file")
  [ -n "$firebase_file_records" ] || continue
  if [ -z "$firebase_records" ]; then
    firebase_records=$firebase_file_records
  else
    firebase_records="$firebase_records
$firebase_file_records"
  fi
done
firebase_records=$(printf '%s\n' "$firebase_records" | awk 'NF && !seen[$0]++ { print }')
firebase_package_names=$(printf '%s\n' "$firebase_records" | awk -F '|' '
  NF && $1 != "" && !seen[$1]++ { print $1 }
')
if [ "$firebase" = true ] && [ -z "$firebase_records" ]; then
  fprs_append_warning 'Firebase client mappings could not be resolved'
fi
if [ "$firebase" = true ] && [ -n "$application_id" ] &&
  ! printf '%s\n' "$firebase_package_names" | grep -F -x "$application_id" >/dev/null 2>&1
then
  fprs_append_warning 'Firebase has no client for selected application ID'
fi

firebase_app_distribution=false
for firebase_distribution_file in \
  "$project_root/android/fastlane/Fastfile" \
  "$project_root/android/fastlane/Pluginfile" \
  "$project_root/android/Gemfile"
do
  [ -f "$firebase_distribution_file" ] || continue
  if grep -F 'firebase_app_distribution' "$firebase_distribution_file" >/dev/null 2>&1; then
    firebase_app_distribution=true
    break
  fi
done

monorepo=false
monorepo_cursor=$project_root
while :
do
  if [ -f "$monorepo_cursor/melos.yaml" ] || [ -f "$monorepo_cursor/melos.yml" ]; then
    monorepo=true
    break
  fi
  if [ -f "$monorepo_cursor/pubspec.yaml" ] &&
    grep -E '^workspace[[:space:]]*:' "$monorepo_cursor/pubspec.yaml" >/dev/null 2>&1
  then
    monorepo=true
    break
  fi
  [ "$monorepo_cursor" != / ] || break
  monorepo_parent=${monorepo_cursor%/*}
  [ -n "$monorepo_parent" ] || monorepo_parent=/
  [ "$monorepo_parent" != "$monorepo_cursor" ] || break
  monorepo_cursor=$monorepo_parent
done

git_dirty=null
if command -v git >/dev/null 2>&1 &&
  GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$project_root" \
    rev-parse --is-inside-work-tree \
    >/dev/null 2>&1
then
  if git_status_output=$(GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false \
    -C "$project_root" status --porcelain --untracked-files=normal -- . 2>/dev/null)
  then
    if [ -n "$git_status_output" ]; then
      git_dirty=true
    else
      git_dirty=false
    fi
  else
    git_dirty=null
  fi
fi

files_bootstrap_may_change='android/Gemfile
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
.gitignore'
if [ -n "$gradle_file" ]; then
  files_bootstrap_may_change="$files_bootstrap_may_change
$gradle_file"
fi

case "$output_format" in
  json) fprs_emit_json || fprs_die 'could not emit inspection JSON' ;;
  human) fprs_emit_human || fprs_die 'could not emit inspection report' ;;
esac

if [ "$inspection_status" -eq 2 ]; then
  printf 'ERROR: %s\n' "$(printf '%s\n' "$failures" | sed -n '1p')" >&2
fi
exit "$inspection_status"
