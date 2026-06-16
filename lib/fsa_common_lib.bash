# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.

# re-source guard
[[ ${_fsa_common_lib_included:-} ]] && return 0

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

readonly _fsa_lib_deps=(fsarchiver)
verify_script_dependencies "${_fsa_lib_deps[@]}" || return 1
readonly _fsa_common_lib_included=1

readonly _fsa_archive_sentinel='fsa-archive'

#
# _make_fsa_file_name <file-system>
#
_make_fsa_file_name() {
    local file_system="$1"
    printf '%s_%s_%s.fsa\n' \
        "$file_system" \
        "$(date +%F)" \
        "$(date +%H-%M-%S)"
}

#
# _fsa_pattern_from_prefix <prefix>
#
_fsa_pattern_from_prefix() {
    local prefix="$1"
    printf '%s\n' "${prefix}"'*.fsa'
}
