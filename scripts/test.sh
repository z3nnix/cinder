#!/usr/bin/env bash
# Run the Cinder test suite.
# Usage:
#   scripts/test.sh                run every suite
#   scripts/test.sh <file>...      run the given suite files (e.g. test/std_test.rb)
#   scripts/test.sh -n /pattern/   run matching tests across all suites
#   scripts/test.sh --fuzz [n]     exercise the fuzzer (default 500 sources)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--fuzz" ]]; then
  shift
  exec ruby tools/fuzz.rb "${@:-500}"
fi

suites=()
opts=()
next_is_value=false
for arg in "$@"; do
  if [ "$next_is_value" = true ]; then
    opts+=("$arg")
    next_is_value=false
    continue
  fi
  case "$arg" in
    -n) opts+=("$arg"); next_is_value=true ;;
    -*) opts+=("$arg") ;;
    *) suites+=("$arg") ;;
  esac
done

if [ "${#suites[@]}" -eq 0 ]; then
  suites=(test/*_test.rb)
fi

exit_code=0
for suite in "${suites[@]}"; do
  echo "== $suite"
  ruby -I test "$suite" "${opts[@]}" || exit_code=$?
done
exit "$exit_code"
