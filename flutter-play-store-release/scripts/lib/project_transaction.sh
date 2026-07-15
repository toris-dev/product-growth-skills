#!/usr/bin/env bash
# Provide atomic project-edit staging, application, and rollback primitives.

# This file is sourced by package entrypoints. Keep all public and private names
# under the fprs_project_transaction namespace so it is safe to compose.

FPRS_PROJECT_TRANSACTION_ACTIVE=0
FPRS_PROJECT_TRANSACTION_ROOT=
FPRS_PROJECT_TRANSACTION_STAGE=
FPRS_PROJECT_TRANSACTION_COUNT=0
FPRS_PROJECT_TRANSACTION_APPLIED=0
FPRS_PROJECT_TRANSACTION_VALIDATED=0
FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=0

fprs_project_transaction_error() {
  printf 'ERROR: project transaction: %s\n' "$*" >&2
}

fprs_project_transaction_file_mode() {
  [ "$#" -eq 1 ] && [ -e "$1" ] || return 1
  local fprs_transaction_mode
  if fprs_transaction_mode=$(stat -c '%a' "$1" 2>/dev/null) &&
    case "$fprs_transaction_mode" in ''|*[!0-7]*) false ;; *) true ;; esac
  then
    :
  elif fprs_transaction_mode=$(stat -f '%Lp' "$1" 2>/dev/null) &&
    case "$fprs_transaction_mode" in ''|*[!0-7]*) false ;; *) true ;; esac
  then
    :
  else
    return 1
  fi
  printf '%s\n' "$fprs_transaction_mode"
}

fprs_project_transaction_safe_relative() {
  [ "$#" -eq 1 ] && [ -n "$1" ] || return 1
  case "$1" in
    /*|.|..|*/.|*/..|./*|*//*|*$'\n'*|*$'\t'*) return 1 ;;
  esac
  return 0
}

fprs_project_transaction_target_path() {
  [ "$#" -eq 1 ] || return 1
  fprs_project_transaction_safe_relative "$1" || return 1

  local fprs_transaction_relative fprs_transaction_parent
  local fprs_transaction_parent_physical fprs_transaction_target
  local fprs_transaction_remaining fprs_transaction_component fprs_transaction_next
  fprs_transaction_relative=$1
  fprs_transaction_parent=${fprs_transaction_relative%/*}
  if [ "$fprs_transaction_parent" = "$fprs_transaction_relative" ]; then
    fprs_transaction_parent=.
  fi
  fprs_transaction_parent_physical=$FPRS_PROJECT_TRANSACTION_ROOT
  fprs_transaction_remaining=$fprs_transaction_parent
  while [ "$fprs_transaction_remaining" != . ] &&
    [ -n "$fprs_transaction_remaining" ]
  do
    case "$fprs_transaction_remaining" in
      */*)
        fprs_transaction_component=${fprs_transaction_remaining%%/*}
        fprs_transaction_remaining=${fprs_transaction_remaining#*/}
        ;;
      *)
        fprs_transaction_component=$fprs_transaction_remaining
        fprs_transaction_remaining=
        ;;
    esac
    fprs_transaction_next="$fprs_transaction_parent_physical/$fprs_transaction_component"
    [ ! -L "$fprs_transaction_next" ] || return 1
    if [ -e "$fprs_transaction_next" ]; then
      [ -d "$fprs_transaction_next" ] || return 1
      fprs_transaction_parent_physical=$(
        CDPATH= cd -- "$fprs_transaction_next" 2>/dev/null && pwd -P
      ) || return 1
      case "$fprs_transaction_parent_physical" in
        "$FPRS_PROJECT_TRANSACTION_ROOT"|"$FPRS_PROJECT_TRANSACTION_ROOT"/*) ;;
        *) return 1 ;;
      esac
    else
      fprs_transaction_parent_physical=$fprs_transaction_next
    fi
  done
  fprs_transaction_target="$fprs_transaction_parent_physical/${fprs_transaction_relative##*/}"
  [ ! -L "$fprs_transaction_target" ] || return 1
  printf '%s\n' "$fprs_transaction_target"
}

fprs_project_transaction_record_dir() {
  printf '%s/records/%08d\n' "$FPRS_PROJECT_TRANSACTION_STAGE" "$1"
}

fprs_project_transaction_cleanup() {
  local fprs_transaction_stage
  fprs_transaction_stage=${FPRS_PROJECT_TRANSACTION_STAGE-}
  if [ -n "$fprs_transaction_stage" ] &&
    case "${fprs_transaction_stage##*/}" in .fprs-project-transaction.*) true ;; *) false ;; esac &&
    [ -d "$fprs_transaction_stage" ] && [ ! -L "$fprs_transaction_stage" ]
  then
    rm -rf -- "$fprs_transaction_stage" 2>/dev/null || return 1
  fi
  FPRS_PROJECT_TRANSACTION_STAGE=
  FPRS_PROJECT_TRANSACTION_ACTIVE=0
  FPRS_PROJECT_TRANSACTION_COUNT=0
  FPRS_PROJECT_TRANSACTION_APPLIED=0
  FPRS_PROJECT_TRANSACTION_VALIDATED=0
  FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=0
  trap - HUP INT TERM
  return 0
}

fprs_project_transaction_begin() {
  [ "$#" -eq 1 ] || {
    fprs_project_transaction_error 'begin requires one project root'
    return 2
  }
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 0 ] || {
    fprs_project_transaction_error 'another project transaction is active'
    return 2
  }
  [ -d "$1" ] || {
    fprs_project_transaction_error 'project root is not a directory'
    return 2
  }

  FPRS_PROJECT_TRANSACTION_ROOT=$(CDPATH= cd -- "$1" 2>/dev/null && pwd -P) || {
    fprs_project_transaction_error 'could not resolve the project root physically'
    return 2
  }
  FPRS_PROJECT_TRANSACTION_STAGE=$(mktemp -d \
    "${TMPDIR:-/tmp}/.fprs-project-transaction.XXXXXX" 2>/dev/null) || {
    fprs_project_transaction_error 'could not create a private stage'
    return 1
  }
  if ! chmod 700 "$FPRS_PROJECT_TRANSACTION_STAGE" 2>/dev/null ||
    ! mkdir "$FPRS_PROJECT_TRANSACTION_STAGE/records" 2>/dev/null ||
    ! mkdir "$FPRS_PROJECT_TRANSACTION_STAGE/created-dirs" 2>/dev/null
  then
    fprs_project_transaction_error 'could not secure the private stage'
    fprs_project_transaction_cleanup >/dev/null 2>&1 || true
    return 1
  fi
  FPRS_PROJECT_TRANSACTION_ACTIVE=1
  FPRS_PROJECT_TRANSACTION_COUNT=0
  FPRS_PROJECT_TRANSACTION_APPLIED=0
  FPRS_PROJECT_TRANSACTION_VALIDATED=0
  FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=0
  trap 'fprs_project_transaction_signal HUP' HUP
  trap 'fprs_project_transaction_signal INT' INT
  trap 'fprs_project_transaction_signal TERM' TERM
  return 0
}

fprs_project_transaction_register() {
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 1 ] || {
    fprs_project_transaction_error 'register requires an active transaction'
    return 2
  }
  [ "$#" -eq 2 ] || {
    fprs_project_transaction_error 'register requires a target and candidate'
    return 2
  }
  [ -f "$2" ] && [ ! -L "$2" ] || {
    fprs_project_transaction_error 'candidate must be a regular file'
    return 2
  }

  local fprs_transaction_target fprs_transaction_index
  local fprs_transaction_record fprs_transaction_existing_record
  local fprs_transaction_existing_target fprs_transaction_mode
  fprs_transaction_target=$(fprs_project_transaction_target_path "$1") || {
    fprs_project_transaction_error "refused target outside the physical root: $1"
    return 2
  }

  fprs_transaction_index=1
  while [ "$fprs_transaction_index" -le "$FPRS_PROJECT_TRANSACTION_COUNT" ]
  do
    fprs_transaction_existing_record=$(
      fprs_project_transaction_record_dir "$fprs_transaction_index"
    )
    fprs_transaction_existing_target=$(cat \
      "$fprs_transaction_existing_record/target" 2>/dev/null) || return 1
    [ "$fprs_transaction_existing_target" != "$fprs_transaction_target" ] || {
      fprs_project_transaction_error "target was registered twice: $1"
      return 2
    }
    fprs_transaction_index=$((fprs_transaction_index + 1))
  done

  fprs_transaction_index=$((FPRS_PROJECT_TRANSACTION_COUNT + 1))
  fprs_transaction_record=$(
    fprs_project_transaction_record_dir "$fprs_transaction_index"
  )
  mkdir "$fprs_transaction_record" 2>/dev/null || return 1
  printf '%s\n' "$fprs_transaction_target" > "$fprs_transaction_record/target" || return 1
  printf '%s\n' "$1" > "$fprs_transaction_record/relative" || return 1
  if ! cp "$2" "$fprs_transaction_record/candidate" 2>/dev/null; then
    fprs_project_transaction_error 'could not stage a candidate'
    return 1
  fi

  if [ -e "$fprs_transaction_target" ]; then
    [ -f "$fprs_transaction_target" ] && [ ! -L "$fprs_transaction_target" ] || {
      fprs_project_transaction_error "target is not a regular file: $1"
      return 2
    }
    fprs_transaction_mode=$(
      fprs_project_transaction_file_mode "$fprs_transaction_target"
    ) || return 1
    printf 'yes\n' > "$fprs_transaction_record/existed" || return 1
    printf '%s\n' "$fprs_transaction_mode" > "$fprs_transaction_record/mode" || return 1
    cp "$fprs_transaction_target" "$fprs_transaction_record/original" 2>/dev/null || {
      fprs_project_transaction_error 'could not preserve original bytes'
      return 1
    }
  else
    fprs_transaction_mode=$(fprs_project_transaction_file_mode "$2") || return 1
    printf 'no\n' > "$fprs_transaction_record/existed" || return 1
    printf '%s\n' "$fprs_transaction_mode" > "$fprs_transaction_record/mode" || return 1
  fi
  chmod "$fprs_transaction_mode" "$fprs_transaction_record/candidate" 2>/dev/null || return 1
  FPRS_PROJECT_TRANSACTION_COUNT=$fprs_transaction_index
  FPRS_PROJECT_TRANSACTION_VALIDATED=0
  return 0
}

fprs_project_transaction_validate() {
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 1 ] || {
    fprs_project_transaction_error 'validation requires an active transaction'
    return 2
  }

  local fprs_transaction_index fprs_transaction_record
  local fprs_transaction_relative fprs_transaction_target
  local fprs_transaction_current_target fprs_transaction_existed
  local fprs_transaction_mode fprs_transaction_current_mode
  fprs_transaction_index=1
  while [ "$fprs_transaction_index" -le "$FPRS_PROJECT_TRANSACTION_COUNT" ]
  do
    fprs_transaction_record=$(
      fprs_project_transaction_record_dir "$fprs_transaction_index"
    )
    fprs_transaction_relative=$(cat "$fprs_transaction_record/relative") || return 1
    fprs_transaction_target=$(cat "$fprs_transaction_record/target") || return 1
    fprs_transaction_current_target=$(
      fprs_project_transaction_target_path "$fprs_transaction_relative"
    ) || {
      fprs_project_transaction_error "target containment changed: $fprs_transaction_relative"
      return 2
    }
    [ "$fprs_transaction_current_target" = "$fprs_transaction_target" ] || {
      fprs_project_transaction_error "target containment changed: $fprs_transaction_relative"
      return 2
    }
    [ -f "$fprs_transaction_record/candidate" ] &&
      [ ! -L "$fprs_transaction_record/candidate" ] || return 1
    fprs_transaction_existed=$(cat "$fprs_transaction_record/existed") || return 1
    fprs_transaction_mode=$(cat "$fprs_transaction_record/mode") || return 1
    case "$fprs_transaction_existed" in
      yes)
        [ -f "$fprs_transaction_target" ] && [ ! -L "$fprs_transaction_target" ] || {
          fprs_project_transaction_error "target changed after planning: $fprs_transaction_relative"
          return 2
        }
        cmp -s "$fprs_transaction_record/original" "$fprs_transaction_target" || {
          fprs_project_transaction_error "target bytes changed after planning: $fprs_transaction_relative"
          return 2
        }
        fprs_transaction_current_mode=$(
          fprs_project_transaction_file_mode "$fprs_transaction_target"
        ) || return 1
        [ "$fprs_transaction_current_mode" = "$fprs_transaction_mode" ] || {
          fprs_project_transaction_error "target mode changed after planning: $fprs_transaction_relative"
          return 2
        }
        ;;
      no)
        [ ! -e "$fprs_transaction_target" ] && [ ! -L "$fprs_transaction_target" ] || {
          fprs_project_transaction_error "new target appeared after planning: $fprs_transaction_relative"
          return 2
        }
        ;;
      *) return 1 ;;
    esac
    if [ "$#" -gt 0 ]; then
      "$@" "$fprs_transaction_relative" \
        "$fprs_transaction_record/candidate" || {
        fprs_project_transaction_error "candidate validation failed: $fprs_transaction_relative"
        return 1
      }
    fi
    fprs_transaction_index=$((fprs_transaction_index + 1))
  done
  FPRS_PROJECT_TRANSACTION_VALIDATED=1
  return 0
}

fprs_project_transaction_atomic_copy() {
  [ "$#" -eq 3 ] || return 1
  local fprs_transaction_source fprs_transaction_target
  local fprs_transaction_mode fprs_transaction_parent fprs_transaction_temp
  local fprs_transaction_parent_physical
  fprs_transaction_source=$1
  fprs_transaction_target=$2
  fprs_transaction_mode=$3
  fprs_transaction_parent=${fprs_transaction_target%/*}
  [ -d "$fprs_transaction_parent" ] && [ ! -L "$fprs_transaction_parent" ] || return 1
  fprs_transaction_parent_physical=$(
    CDPATH= cd -- "$fprs_transaction_parent" 2>/dev/null && pwd -P
  ) || return 1
  case "$fprs_transaction_parent_physical" in
    "$FPRS_PROJECT_TRANSACTION_ROOT"|"$FPRS_PROJECT_TRANSACTION_ROOT"/*) ;;
    *) return 1 ;;
  esac
  [ "$fprs_transaction_parent_physical" = "$fprs_transaction_parent" ] || return 1
  fprs_transaction_temp=$(mktemp \
    "$fprs_transaction_parent/.fprs-project-write.XXXXXX" 2>/dev/null) || return 1
  if ! cp "$fprs_transaction_source" "$fprs_transaction_temp" 2>/dev/null ||
    ! chmod "$fprs_transaction_mode" "$fprs_transaction_temp" 2>/dev/null ||
    ! mv -f -- "$fprs_transaction_temp" "$fprs_transaction_target" 2>/dev/null
  then
    rm -f -- "$fprs_transaction_temp" 2>/dev/null || true
    return 1
  fi
  return 0
}

fprs_project_transaction_ensure_parent() {
  [ "$#" -eq 1 ] || return 1
  local fprs_transaction_relative fprs_transaction_parent
  local fprs_transaction_remaining fprs_transaction_component
  local fprs_transaction_current fprs_transaction_next fprs_transaction_physical
  local fprs_transaction_index
  fprs_transaction_relative=$1
  fprs_transaction_parent=${fprs_transaction_relative%/*}
  [ "$fprs_transaction_parent" != "$fprs_transaction_relative" ] || return 0
  fprs_transaction_remaining=$fprs_transaction_parent
  fprs_transaction_current=$FPRS_PROJECT_TRANSACTION_ROOT
  while [ -n "$fprs_transaction_remaining" ]
  do
    case "$fprs_transaction_remaining" in
      */*)
        fprs_transaction_component=${fprs_transaction_remaining%%/*}
        fprs_transaction_remaining=${fprs_transaction_remaining#*/}
        ;;
      *)
        fprs_transaction_component=$fprs_transaction_remaining
        fprs_transaction_remaining=
        ;;
    esac
    fprs_transaction_next="$fprs_transaction_current/$fprs_transaction_component"
    [ ! -L "$fprs_transaction_next" ] || return 1
    if [ ! -e "$fprs_transaction_next" ]; then
      fprs_transaction_index=$((FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT + 1))
      printf '%s\n' "$fprs_transaction_next" > \
        "$FPRS_PROJECT_TRANSACTION_STAGE/created-dirs/$(printf '%08d' "$fprs_transaction_index")" ||
        return 1
      mkdir "$fprs_transaction_next" 2>/dev/null || return 1
      FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=$fprs_transaction_index
    fi
    [ -d "$fprs_transaction_next" ] && [ ! -L "$fprs_transaction_next" ] || return 1
    fprs_transaction_physical=$(CDPATH= cd -- "$fprs_transaction_next" 2>/dev/null && pwd -P) ||
      return 1
    case "$fprs_transaction_physical" in
      "$FPRS_PROJECT_TRANSACTION_ROOT"|"$FPRS_PROJECT_TRANSACTION_ROOT"/*) ;;
      *) return 1 ;;
    esac
    fprs_transaction_current=$fprs_transaction_physical
  done
  return 0
}

fprs_project_transaction_remove_created_dirs() {
  local fprs_transaction_index fprs_transaction_record fprs_transaction_dir
  local fprs_transaction_failed
  fprs_transaction_failed=0
  fprs_transaction_index=$FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT
  while [ "$fprs_transaction_index" -ge 1 ]
  do
    fprs_transaction_record="$FPRS_PROJECT_TRANSACTION_STAGE/created-dirs/$(printf '%08d' "$fprs_transaction_index")"
    fprs_transaction_dir=$(cat "$fprs_transaction_record" 2>/dev/null) || {
      fprs_transaction_failed=1
      fprs_transaction_index=$((fprs_transaction_index - 1))
      continue
    }
    if [ -d "$fprs_transaction_dir" ] && [ ! -L "$fprs_transaction_dir" ]; then
      rmdir "$fprs_transaction_dir" 2>/dev/null || fprs_transaction_failed=1
    elif [ -e "$fprs_transaction_dir" ] || [ -L "$fprs_transaction_dir" ]; then
      fprs_transaction_failed=1
    fi
    fprs_transaction_index=$((fprs_transaction_index - 1))
  done
  FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=0
  [ "$fprs_transaction_failed" -eq 0 ]
}

fprs_project_transaction_rollback() {
  local fprs_transaction_index fprs_transaction_record
  local fprs_transaction_target fprs_transaction_relative
  local fprs_transaction_existed fprs_transaction_mode fprs_transaction_failed
  fprs_transaction_failed=0
  fprs_transaction_index=$FPRS_PROJECT_TRANSACTION_APPLIED
  while [ "$fprs_transaction_index" -ge 1 ]
  do
    fprs_transaction_record=$(
      fprs_project_transaction_record_dir "$fprs_transaction_index"
    )
    fprs_transaction_target=$(cat "$fprs_transaction_record/target" 2>/dev/null) || {
      fprs_transaction_failed=1
      fprs_transaction_index=$((fprs_transaction_index - 1))
      continue
    }
    fprs_transaction_relative=$(cat "$fprs_transaction_record/relative" 2>/dev/null) ||
      fprs_transaction_relative=$fprs_transaction_target
    fprs_transaction_existed=$(cat "$fprs_transaction_record/existed" 2>/dev/null) ||
      fprs_transaction_existed=invalid
    fprs_transaction_mode=$(cat "$fprs_transaction_record/mode" 2>/dev/null) ||
      fprs_transaction_mode=
    case "$fprs_transaction_existed" in
      yes)
        fprs_project_transaction_atomic_copy \
          "$fprs_transaction_record/original" "$fprs_transaction_target" \
          "$fprs_transaction_mode" || fprs_transaction_failed=1
        ;;
      no)
        if [ -f "$fprs_transaction_target" ] &&
          cmp -s "$fprs_transaction_record/candidate" "$fprs_transaction_target"
        then
          rm -f -- "$fprs_transaction_target" 2>/dev/null || fprs_transaction_failed=1
        elif [ -e "$fprs_transaction_target" ] || [ -L "$fprs_transaction_target" ]; then
          fprs_project_transaction_error \
            "refused to remove changed transaction-created path: $fprs_transaction_relative"
          fprs_transaction_failed=1
        fi
        ;;
      *) fprs_transaction_failed=1 ;;
    esac
    fprs_transaction_index=$((fprs_transaction_index - 1))
  done
  FPRS_PROJECT_TRANSACTION_APPLIED=0
  fprs_project_transaction_remove_created_dirs || fprs_transaction_failed=1
  [ "$fprs_transaction_failed" -eq 0 ]
}

fprs_project_transaction_signal() {
  trap - HUP INT TERM
  fprs_project_transaction_error "caught $1; rollback attempted"
  fprs_project_transaction_rollback >/dev/null 2>&1 || true
  fprs_project_transaction_cleanup >/dev/null 2>&1 || true
  exit 3
}

fprs_project_transaction_commit() {
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 1 ] || {
    fprs_project_transaction_error 'commit requires an active transaction'
    return 2
  }
  if [ "$FPRS_PROJECT_TRANSACTION_VALIDATED" -ne 1 ]; then
    fprs_project_transaction_validate || return $?
  else
    # Revalidate the snapshot immediately before the first project write.
    fprs_project_transaction_validate || return $?
  fi

  local fprs_transaction_index fprs_transaction_record
  local fprs_transaction_target fprs_transaction_mode
  local fprs_transaction_fail_after
  fprs_transaction_fail_after=
  if [ "${FPRS_TEST_MODE-}" = 1 ]; then
    fprs_transaction_fail_after=${FPRS_TEST_FAIL_PROJECT_WRITE_AFTER-}
    case "$fprs_transaction_fail_after" in
      ''|*[!0-9]*) fprs_transaction_fail_after= ;;
    esac
  fi

  fprs_transaction_index=1
  while [ "$fprs_transaction_index" -le "$FPRS_PROJECT_TRANSACTION_COUNT" ]
  do
    fprs_transaction_record=$(
      fprs_project_transaction_record_dir "$fprs_transaction_index"
    )
    fprs_transaction_relative=$(cat "$fprs_transaction_record/relative") || break
    if ! fprs_project_transaction_ensure_parent "$fprs_transaction_relative"; then
      break
    fi
    fprs_transaction_target=$(cat "$fprs_transaction_record/target") || break
    fprs_transaction_target=$(
      fprs_project_transaction_target_path "$fprs_transaction_relative"
    ) || break
    fprs_transaction_mode=$(cat "$fprs_transaction_record/mode") || break
    if ! fprs_project_transaction_atomic_copy \
      "$fprs_transaction_record/candidate" "$fprs_transaction_target" \
      "$fprs_transaction_mode"
    then
      break
    fi
    FPRS_PROJECT_TRANSACTION_APPLIED=$fprs_transaction_index
    if [ "${FPRS_TEST_MODE-}" = 1 ] &&
      [ "${FPRS_TEST_SIGNAL_AT-}" = project-write ]
    then
      kill -TERM "$$"
    fi
    if [ -n "$fprs_transaction_fail_after" ] &&
      [ "$fprs_transaction_index" -eq "$fprs_transaction_fail_after" ]
    then
      fprs_project_transaction_error \
        "injected failure after project write $fprs_transaction_index"
      break
    fi
    fprs_transaction_index=$((fprs_transaction_index + 1))
  done

  if [ "$FPRS_PROJECT_TRANSACTION_APPLIED" -ne "$FPRS_PROJECT_TRANSACTION_COUNT" ] ||
    { [ -n "$fprs_transaction_fail_after" ] &&
      [ "$FPRS_PROJECT_TRANSACTION_APPLIED" -eq "$fprs_transaction_fail_after" ]; }
  then
    fprs_project_transaction_error 'project write failed; rollback attempted'
    fprs_project_transaction_rollback || true
    fprs_project_transaction_cleanup || true
    return 3
  fi

  if ! fprs_project_transaction_cleanup; then
    fprs_project_transaction_error 'project writes completed but private cleanup failed'
    return 1
  fi
  return 0
}

fprs_project_transaction_abort() {
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 1 ] || return 0
  fprs_project_transaction_rollback || true
  fprs_project_transaction_cleanup
}
