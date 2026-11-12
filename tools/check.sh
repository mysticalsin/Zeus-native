#!/bin/sh
# Native Zeus adapter for Software Factory's documented ./tools/check.sh entrypoint.
# The existing closed-loop runner remains the sole pass/fail authority.
set -eu

usage() {
    printf '%s\n' 'Usage: tools/check.sh [development|full|--mode MODE] [--output NEW_DIRECTORY] [--jobs N] [--timeout SECONDS]'
    printf '%s\n' 'Default: development with a fresh external evidence directory whose path is printed and retained.'
    printf '%s\n' 'Development checks are not device acceptance. Full mode fails while any required proof is missing.'
}

reject() {
    printf '%s\n' "$1" >&2
    usage >&2
    exit 2
}

if [ "$#" -eq 1 ] && [ "$1" = '--help' ]; then
    usage
    exit 0
fi
mode=development
if [ "$#" -gt 0 ]; then
    case "$1" in
        development|full) mode=$1; shift ;;
        --mode)
            [ "$#" -ge 2 ] || reject '--mode requires development or full.'
            mode=$2
            shift 2
            ;;
        --output|--jobs|--timeout) ;;
        *) reject 'Unsupported check mode or option.' ;;
    esac
fi
case "$mode" in
    development|full) ;;
    *) reject 'Unsupported check mode.' ;;
esac

# Validate without rewriting arguments or changing the caller's working directory.
# In particular a second --mode must never downgrade an explicitly requested full run.
validate_arguments() {
    seen_output=0
    seen_jobs=0
    seen_timeout=0
    while [ "$#" -gt 0 ]; do
        [ "$#" -ge 2 ] || reject 'Every option requires a value.'
        option=$1
        value=$2
        case "$option" in
            --output)
                [ "$seen_output" -eq 0 ] || reject '--output may only be supplied once.'
                [ -n "$value" ] || reject '--output must name a new directory.'
                seen_output=1
                ;;
            --jobs|--timeout)
                case "$value" in ''|*[!0-9]*) reject 'Job counts and timeouts must be positive integers.' ;; esac
                case "$value" in *[1-9]*) ;; *) reject 'Job counts and timeouts must be positive integers.' ;; esac
                if [ "$option" = '--jobs' ]; then
                    [ "$seen_jobs" -eq 0 ] || reject '--jobs may only be supplied once.'
                    seen_jobs=1
                else
                    [ "$seen_timeout" -eq 0 ] || reject '--timeout may only be supplied once.'
                    seen_timeout=1
                fi
                ;;
            *) reject 'Unsupported check option.' ;;
        esac
        shift 2
    done
}
validate_arguments "$@"

if [ "$seen_output" -eq 0 ]; then
    # mktemp owns a fresh external parent; the runner must create its still-absent result child.
    # Keep the parent on failure too: a failed run's evidence is just as important.
    evidence_parent=$(mktemp -d "/tmp/zeus-${mode}.XXXXXXXX")
    evidence_output=$evidence_parent/result
    printf 'Zeus %s evidence: %s\n' "$mode" "$evidence_output"
    set -- "$@" --output "$evidence_output"
fi

script_directory=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
exec python3 "$script_directory/../qa/closed-loop/run.py" --mode "$mode" "$@"
