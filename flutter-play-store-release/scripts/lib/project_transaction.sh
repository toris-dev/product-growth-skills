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
FPRS_PROJECT_TRANSACTION_PRIOR_HUP=
FPRS_PROJECT_TRANSACTION_PRIOR_INT=
FPRS_PROJECT_TRANSACTION_PRIOR_TERM=
FPRS_PROJECT_TRANSACTION_TRAPS_SAVED=0
FPRS_PROJECT_TRANSACTION_CURRENT_RECORD=
FPRS_PROJECT_TRANSACTION_FD_OPEN=0
FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN=0

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
    /*|*/|*//*|*$'\n'*|*$'\t'*) return 1 ;;
  esac
  local fprs_transaction_remaining fprs_transaction_component
  fprs_transaction_remaining=$1
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
    case "$fprs_transaction_component" in ''|.|..) return 1 ;; esac
  done
  return 0
}

fprs_project_transaction_save_traps() {
  FPRS_PROJECT_TRANSACTION_PRIOR_HUP=$(trap -p HUP)
  FPRS_PROJECT_TRANSACTION_PRIOR_INT=$(trap -p INT)
  FPRS_PROJECT_TRANSACTION_PRIOR_TERM=$(trap -p TERM)
  FPRS_PROJECT_TRANSACTION_TRAPS_SAVED=1
}

fprs_project_transaction_restore_one_trap() {
  local fprs_transaction_signal fprs_transaction_saved
  fprs_transaction_signal=$1
  fprs_transaction_saved=$2
  if [ -n "$fprs_transaction_saved" ]; then
    eval "$fprs_transaction_saved"
  else
    trap - "$fprs_transaction_signal"
  fi
}

fprs_project_transaction_restore_traps() {
  [ "$FPRS_PROJECT_TRANSACTION_TRAPS_SAVED" -eq 1 ] || return 0
  fprs_project_transaction_restore_one_trap HUP "$FPRS_PROJECT_TRANSACTION_PRIOR_HUP"
  fprs_project_transaction_restore_one_trap INT "$FPRS_PROJECT_TRANSACTION_PRIOR_INT"
  fprs_project_transaction_restore_one_trap TERM "$FPRS_PROJECT_TRANSACTION_PRIOR_TERM"
  FPRS_PROJECT_TRANSACTION_TRAPS_SAVED=0
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
  local fprs_transaction_stage fprs_transaction_cleanup_failed
  fprs_transaction_stage=${FPRS_PROJECT_TRANSACTION_STAGE-}
  fprs_transaction_cleanup_failed=0
  if [ -n "$fprs_transaction_stage" ] &&
    case "${fprs_transaction_stage##*/}" in .fprs-project-transaction.*) true ;; *) false ;; esac &&
    [ -d "$fprs_transaction_stage" ] && [ ! -L "$fprs_transaction_stage" ]
  then
    rm -rf -- "$fprs_transaction_stage" 2>/dev/null ||
      fprs_transaction_cleanup_failed=1
  fi
  FPRS_PROJECT_TRANSACTION_STAGE=
  FPRS_PROJECT_TRANSACTION_ACTIVE=0
  FPRS_PROJECT_TRANSACTION_COUNT=0
  FPRS_PROJECT_TRANSACTION_APPLIED=0
  FPRS_PROJECT_TRANSACTION_VALIDATED=0
  FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=0
  FPRS_PROJECT_TRANSACTION_CURRENT_RECORD=
  if [ "$FPRS_PROJECT_TRANSACTION_FD_OPEN" -eq 1 ]; then
    exec 9<&-
  fi
  FPRS_PROJECT_TRANSACTION_FD_OPEN=0
  if [ "$FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN" -eq 1 ]; then
    exec 8<&-
  fi
  FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN=0
  fprs_project_transaction_restore_traps
  [ "$fprs_transaction_cleanup_failed" -eq 0 ]
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
  fprs_project_transaction_save_traps
  command -v python3 >/dev/null 2>&1 || {
    fprs_project_transaction_error 'Python 3 is required for race-safe publication'
    fprs_project_transaction_restore_traps
    return 1
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
  if ! python3 -c '
import os
import stat
import sys
root, output = sys.argv[1:]
try:
    info = os.stat(root, follow_symlinks=False)
    if not stat.S_ISDIR(info.st_mode):
        raise RuntimeError
    with open(output, "w", encoding="ascii") as target:
        target.write("%d\n%d\n" % (info.st_dev, info.st_ino))
except BaseException:
    raise SystemExit(1)
' "$FPRS_PROJECT_TRANSACTION_ROOT" \
    "$FPRS_PROJECT_TRANSACTION_STAGE/root-identity" >/dev/null 2>&1
  then
    fprs_project_transaction_error 'could not pin the project root identity'
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

fprs_project_transaction_validate_record() {
  local fprs_transaction_index fprs_transaction_record
  local fprs_transaction_relative fprs_transaction_target
  local fprs_transaction_current_target fprs_transaction_existed
  local fprs_transaction_mode fprs_transaction_current_mode
  fprs_transaction_index=$1
  shift
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
  return 0
}

fprs_project_transaction_validate() {
  [ "$FPRS_PROJECT_TRANSACTION_ACTIVE" -eq 1 ] || {
    fprs_project_transaction_error 'validation requires an active transaction'
    return 2
  }
  local fprs_transaction_index fprs_transaction_record
  fprs_transaction_index=1
  while [ "$fprs_transaction_index" -le "$FPRS_PROJECT_TRANSACTION_COUNT" ]
  do
    fprs_project_transaction_validate_record "$fprs_transaction_index" "$@" || return $?
    fprs_transaction_index=$((fprs_transaction_index + 1))
  done
  FPRS_PROJECT_TRANSACTION_VALIDATED=1
  return 0
}

fprs_project_transaction_boundary() {
  [ "${FPRS_TEST_MODE-}" = 1 ] || return 0
  local fprs_transaction_boundary fprs_transaction_relative
  fprs_transaction_boundary=$1
  fprs_transaction_relative=${2-}
  if type fprs_project_transaction_test_hook >/dev/null 2>&1; then
    fprs_project_transaction_test_hook "$fprs_transaction_boundary" \
      "$fprs_transaction_relative" || return 1
  fi
  if [ "${FPRS_TEST_SIGNAL_AT-}" = "$fprs_transaction_boundary" ]; then
    kill -TERM "$$"
  fi
  return 0
}

fprs_project_transaction_pin_root() {
  [ "$#" -eq 0 ] || return 1
  if ! exec 8< "$FPRS_PROJECT_TRANSACTION_ROOT"; then
    return 1
  fi
  FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN=1
  python3 -c '
import os
import stat
import sys
root, identity_path = sys.argv[1:]
try:
    with open(identity_path, encoding="ascii") as source:
        values = source.read().splitlines()
    if len(values) != 2:
        raise RuntimeError
    expected = (int(values[0]), int(values[1]))
    descriptor = os.fstat(8)
    current = os.stat(root, follow_symlinks=False)
    if not stat.S_ISDIR(descriptor.st_mode) or not stat.S_ISDIR(current.st_mode):
        raise RuntimeError
    if (descriptor.st_dev, descriptor.st_ino) != expected:
        raise RuntimeError
    if (current.st_dev, current.st_ino) != expected:
        raise RuntimeError
except BaseException:
    raise SystemExit(1)
' "$FPRS_PROJECT_TRANSACTION_ROOT" \
    "$FPRS_PROJECT_TRANSACTION_STAGE/root-identity" >/dev/null 2>&1
}

fprs_project_transaction_prepare_temp() {
  [ "$#" -eq 7 ] || return 1
  python3 -c '
import os
import signal
import stat
import sys

record, root_path, relative, candidate, mode_text, existed, original = sys.argv[1:]
target_name = relative.split("/")[-1]
temp_name = ".fprs-project-write." + os.path.basename(record)
state_path = os.path.join(record, "temp-state")
created = False

def interrupted(signum, frame):
    raise RuntimeError("interrupted")

for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, interrupted)

def pinned_parent():
    root_path_stat = os.stat(root_path, follow_symlinks=False)
    root_fd_stat = os.fstat(8)
    fd_stat = os.fstat(9)
    if not stat.S_ISDIR(root_path_stat.st_mode) or not stat.S_ISDIR(root_fd_stat.st_mode):
        raise RuntimeError("root is not a directory")
    if (root_path_stat.st_dev, root_path_stat.st_ino) != (root_fd_stat.st_dev, root_fd_stat.st_ino):
        raise RuntimeError("root identity changed")
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    walked_fd = os.dup(8)
    try:
        for component in relative.split("/")[:-1]:
            next_fd = os.open(component, flags, dir_fd=walked_fd)
            os.close(walked_fd)
            walked_fd = next_fd
        walked_stat = os.fstat(walked_fd)
    finally:
        os.close(walked_fd)
    if (walked_stat.st_dev, walked_stat.st_ino) != (fd_stat.st_dev, fd_stat.st_ino):
        raise RuntimeError("parent identity changed")
    return fd_stat

def compare_file(fd, path):
    with os.fdopen(fd, "rb", closefd=True) as left, open(path, "rb") as right:
        while True:
            a = left.read(65536)
            b = right.read(65536)
            if a != b:
                return False
            if not a:
                return True

def validate_target():
    try:
        target_stat = os.stat(target_name, dir_fd=9, follow_symlinks=False)
    except FileNotFoundError:
        target_stat = None
    if existed == "yes":
        if target_stat is None or not stat.S_ISREG(target_stat.st_mode):
            raise RuntimeError("target changed")
        if stat.S_IMODE(target_stat.st_mode) != int(mode_text, 8):
            raise RuntimeError("target mode changed")
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        if not compare_file(os.open(target_name, flags, dir_fd=9), original):
            raise RuntimeError("target bytes changed")
    elif existed == "no":
        if target_stat is not None:
            raise RuntimeError("new target appeared")
    else:
        raise RuntimeError("invalid snapshot")

try:
    parent_stat = pinned_parent()
    validate_target()
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    temp_fd = os.open(temp_name, flags, 0o600, dir_fd=9)
    created = True
    try:
        with os.fdopen(temp_fd, "wb", closefd=True) as output, open(candidate, "rb") as source:
            while True:
                chunk = source.read(65536)
                if not chunk:
                    break
                output.write(chunk)
            output.flush()
            os.fchmod(output.fileno(), int(mode_text, 8))
        temp_stat = os.stat(temp_name, dir_fd=9, follow_symlinks=False)
        if not stat.S_ISREG(temp_stat.st_mode) or temp_stat.st_nlink != 1:
            raise RuntimeError("unsafe temporary file")
        state_tmp = state_path + ".new"
        with open(state_tmp, "w", encoding="ascii") as state:
            state.write("%s\n%d\n%d\n%d\n%d\n" % (
                temp_name, temp_stat.st_dev, temp_stat.st_ino,
                parent_stat.st_dev, parent_stat.st_ino))
            state.flush()
        os.replace(state_tmp, state_path)
    except BaseException:
        try:
            os.unlink(temp_name, dir_fd=9)
        except OSError:
            pass
        raise
except BaseException:
    raise SystemExit(1)
' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >/dev/null 2>&1
}

fprs_project_transaction_publish_temp() {
  [ "$#" -eq 7 ] || return 1
  python3 -c '
import os
import signal
import stat
import sys

record, root_path, relative, candidate, mode_text, existed, original = sys.argv[1:]
target_name = relative.split("/")[-1]
state_path = os.path.join(record, "temp-state")
published_path = os.path.join(record, "published")

def interrupted(signum, frame):
    raise RuntimeError("interrupted")

for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, interrupted)

def read_state():
    with open(state_path, encoding="ascii") as state:
        values = state.read().splitlines()
    if len(values) != 5:
        raise RuntimeError("invalid temp journal")
    return values[0], tuple(int(value) for value in values[1:])

def pinned_parent(expected):
    root_path_stat = os.stat(root_path, follow_symlinks=False)
    root_fd_stat = os.fstat(8)
    fd_stat = os.fstat(9)
    if not stat.S_ISDIR(root_path_stat.st_mode) or not stat.S_ISDIR(root_fd_stat.st_mode):
        raise RuntimeError("root is not a directory")
    if (root_path_stat.st_dev, root_path_stat.st_ino) != (root_fd_stat.st_dev, root_fd_stat.st_ino):
        raise RuntimeError("root identity changed")
    if (fd_stat.st_dev, fd_stat.st_ino) != expected:
        raise RuntimeError("parent descriptor changed")
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    walked_fd = os.dup(8)
    try:
        for component in relative.split("/")[:-1]:
            next_fd = os.open(component, flags, dir_fd=walked_fd)
            os.close(walked_fd)
            walked_fd = next_fd
        walked_stat = os.fstat(walked_fd)
    finally:
        os.close(walked_fd)
    if (walked_stat.st_dev, walked_stat.st_ino) != expected:
        raise RuntimeError("parent path changed")

def bytes_equal(name, expected_path):
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    with os.fdopen(os.open(name, flags, dir_fd=9), "rb") as left, open(expected_path, "rb") as right:
        while True:
            a = left.read(65536)
            b = right.read(65536)
            if a != b:
                return False
            if not a:
                return True

def validate_target():
    try:
        target_stat = os.stat(target_name, dir_fd=9, follow_symlinks=False)
    except FileNotFoundError:
        target_stat = None
    if existed == "yes":
        if target_stat is None or not stat.S_ISREG(target_stat.st_mode):
            raise RuntimeError("target changed")
        if stat.S_IMODE(target_stat.st_mode) != int(mode_text, 8):
            raise RuntimeError("target mode changed")
        if not bytes_equal(target_name, original):
            raise RuntimeError("target bytes changed")
    elif existed == "no":
        if target_stat is not None:
            raise RuntimeError("new target appeared")
    else:
        raise RuntimeError("invalid snapshot")

def restore_after_failed_journal(installed_identity):
    try:
        current = os.stat(target_name, dir_fd=9, follow_symlinks=False)
        if (current.st_dev, current.st_ino) != installed_identity:
            return
        if existed == "no":
            os.unlink(target_name, dir_fd=9)
            return
        recovery_name = ".fprs-project-recovery." + os.path.basename(record)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        recovery_fd = os.open(recovery_name, flags, 0o600, dir_fd=9)
        try:
            with os.fdopen(recovery_fd, "wb") as output, open(original, "rb") as source:
                while True:
                    chunk = source.read(65536)
                    if not chunk:
                        break
                    output.write(chunk)
                output.flush()
                os.fchmod(output.fileno(), int(mode_text, 8))
            os.replace(recovery_name, target_name, src_dir_fd=9, dst_dir_fd=9)
        except BaseException:
            try:
                os.unlink(recovery_name, dir_fd=9)
            except OSError:
                pass
            raise
    except OSError:
        pass

installed_identity = None
try:
    temp_name, identity = read_state()
    temp_dev, temp_ino, parent_dev, parent_ino = identity
    pinned_parent((parent_dev, parent_ino))
    temp_stat = os.stat(temp_name, dir_fd=9, follow_symlinks=False)
    if (temp_stat.st_dev, temp_stat.st_ino) != (temp_dev, temp_ino):
        raise RuntimeError("temporary identity changed")
    validate_target()
    os.replace(temp_name, target_name, src_dir_fd=9, dst_dir_fd=9)
    installed = os.stat(target_name, dir_fd=9, follow_symlinks=False)
    installed_identity = (installed.st_dev, installed.st_ino)
    journal_tmp = published_path + ".new"
    with open(journal_tmp, "w", encoding="ascii") as journal:
        journal.write("%d\n%d\n" % installed_identity)
        journal.flush()
    os.replace(journal_tmp, published_path)
except BaseException:
    if installed_identity is not None and not os.path.exists(published_path):
        restore_after_failed_journal(installed_identity)
    raise SystemExit(1)
' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >/dev/null 2>&1
}

fprs_project_transaction_cleanup_current_temp() {
  local fprs_transaction_record
  fprs_transaction_record=$1
  [ -f "$fprs_transaction_record/temp-state" ] || return 0
  python3 -c '
import os
import stat
import sys
record = sys.argv[1]
try:
    with open(os.path.join(record, "temp-state"), encoding="ascii") as state:
        values = state.read().splitlines()
    if len(values) != 5:
        raise RuntimeError
    name = values[0]
    expected = (int(values[1]), int(values[2]))
    current = os.stat(name, dir_fd=9, follow_symlinks=False)
    if (current.st_dev, current.st_ino) != expected or not stat.S_ISREG(current.st_mode):
        raise RuntimeError
    os.unlink(name, dir_fd=9)
except FileNotFoundError:
    pass
except BaseException:
    raise SystemExit(1)
' "$fprs_transaction_record" >/dev/null 2>&1
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
  local fprs_transaction_index fprs_transaction_record
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
      fprs_transaction_record="$FPRS_PROJECT_TRANSACTION_STAGE/created-dirs/$(printf '%08d' "$fprs_transaction_index")"
      printf '%s\n' "$fprs_transaction_next" > \
        "$fprs_transaction_record.path" ||
        return 1
      FPRS_PROJECT_TRANSACTION_CREATED_DIR_COUNT=$fprs_transaction_index
      python3 -c '
import os
import signal
import stat
import sys
path, journal = sys.argv[1:]
created = False
def interrupted(signum, frame):
    raise RuntimeError("interrupted")
for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, interrupted)
try:
    os.mkdir(path, 0o755)
    created = True
    info = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(info.st_mode):
        raise RuntimeError("created path is not a directory")
    temporary = journal + ".new"
    with open(temporary, "w", encoding="ascii") as output:
        output.write("%d\n%d\n" % (info.st_dev, info.st_ino))
        output.flush()
    os.replace(temporary, journal)
except BaseException:
    if created:
        try:
            os.rmdir(path)
        except OSError:
            pass
    raise SystemExit(1)
' "$fprs_transaction_next" "$fprs_transaction_record.created" >/dev/null 2>&1 ||
        return 1
      fprs_project_transaction_boundary project-dir-created \
        "$fprs_transaction_relative" || return 1
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
    fprs_transaction_dir=$(cat "$fprs_transaction_record.path" 2>/dev/null) || {
      fprs_transaction_index=$((fprs_transaction_index - 1))
      continue
    }
    if [ -f "$fprs_transaction_record.created" ]; then
      if ! python3 -c '
import os
import stat
import sys
path, journal = sys.argv[1:]
try:
    with open(journal, encoding="ascii") as source:
        values = source.read().splitlines()
    if len(values) != 2:
        raise RuntimeError
    expected = (int(values[0]), int(values[1]))
    current = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(current.st_mode) or (current.st_dev, current.st_ino) != expected:
        raise RuntimeError
    os.rmdir(path)
except FileNotFoundError:
    pass
except BaseException:
    raise SystemExit(1)
' "$fprs_transaction_dir" "$fprs_transaction_record.created" >/dev/null 2>&1
      then
        fprs_transaction_failed=1
      fi
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
  fprs_transaction_index=$FPRS_PROJECT_TRANSACTION_COUNT
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
    if [ ! -f "$fprs_transaction_record/published" ]; then
      if [ "$FPRS_PROJECT_TRANSACTION_FD_OPEN" -eq 1 ] &&
        [ "$FPRS_PROJECT_TRANSACTION_CURRENT_RECORD" = "$fprs_transaction_record" ]
      then
        fprs_project_transaction_cleanup_current_temp "$fprs_transaction_record" ||
          fprs_transaction_failed=1
      fi
      fprs_transaction_index=$((fprs_transaction_index - 1))
      continue
    fi
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
  if [ "$FPRS_PROJECT_TRANSACTION_FD_OPEN" -eq 1 ]; then
    exec 9<&-
    FPRS_PROJECT_TRANSACTION_FD_OPEN=0
  fi
  if [ "$FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN" -eq 1 ]; then
    exec 8<&-
    FPRS_PROJECT_TRANSACTION_ROOT_FD_OPEN=0
  fi
  FPRS_PROJECT_TRANSACTION_CURRENT_RECORD=
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
  command -v python3 >/dev/null 2>&1 || {
    fprs_project_transaction_error 'Python 3 is required for race-safe publication'
    return 1
  }

  local fprs_transaction_index fprs_transaction_record
  local fprs_transaction_target fprs_transaction_mode fprs_transaction_relative
  local fprs_transaction_parent fprs_transaction_existed
  local fprs_transaction_fail_after
  fprs_transaction_fail_after=
  if [ "${FPRS_TEST_MODE-}" = 1 ]; then
    fprs_transaction_fail_after=${FPRS_TEST_FAIL_PROJECT_WRITE_AFTER-}
    case "$fprs_transaction_fail_after" in
      ''|*[!0-9]*) fprs_transaction_fail_after= ;;
    esac
  fi

  if ! fprs_project_transaction_pin_root; then
    fprs_project_transaction_error 'project root identity changed before publication'
    fprs_project_transaction_rollback || true
    fprs_project_transaction_cleanup || true
    return 3
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
    fprs_transaction_existed=$(cat "$fprs_transaction_record/existed") || break
    fprs_transaction_parent=${fprs_transaction_target%/*}
    if ! exec 9< "$fprs_transaction_parent"; then
      break
    fi
    FPRS_PROJECT_TRANSACTION_FD_OPEN=1
    FPRS_PROJECT_TRANSACTION_CURRENT_RECORD=$fprs_transaction_record
    fprs_project_transaction_boundary project-before-target-validation \
      "$fprs_transaction_relative" || break
    if ! fprs_project_transaction_validate_record "$fprs_transaction_index"; then
      break
    fi
    if ! fprs_project_transaction_prepare_temp "$fprs_transaction_record" \
      "$FPRS_PROJECT_TRANSACTION_ROOT" "$fprs_transaction_relative" \
      "$fprs_transaction_record/candidate" "$fprs_transaction_mode" \
      "$fprs_transaction_existed" "$fprs_transaction_record/original"
    then
      break
    fi
    fprs_project_transaction_boundary project-temp-created \
      "$fprs_transaction_relative" || break
    fprs_project_transaction_boundary project-before-publish \
      "$fprs_transaction_relative" || break
    if ! fprs_project_transaction_publish_temp "$fprs_transaction_record" \
      "$FPRS_PROJECT_TRANSACTION_ROOT" "$fprs_transaction_relative" \
      "$fprs_transaction_record/candidate" "$fprs_transaction_mode" \
      "$fprs_transaction_existed" "$fprs_transaction_record/original"
    then
      break
    fi
    FPRS_PROJECT_TRANSACTION_APPLIED=$fprs_transaction_index
    fprs_project_transaction_boundary project-published \
      "$fprs_transaction_relative" || break
    fprs_project_transaction_boundary project-write \
      "$fprs_transaction_relative" || break
    if [ -n "$fprs_transaction_fail_after" ] &&
      [ "$fprs_transaction_index" -eq "$fprs_transaction_fail_after" ]
    then
      fprs_project_transaction_error \
        "injected failure after project write $fprs_transaction_index"
      break
    fi
    exec 9<&-
    FPRS_PROJECT_TRANSACTION_FD_OPEN=0
    FPRS_PROJECT_TRANSACTION_CURRENT_RECORD=
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
