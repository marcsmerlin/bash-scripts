# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_fsa_inspect_lib_included:-} ]] && return 0
readonly _fsa_inspect_lib_included=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./sudo_lib.bash
source "$BASH_LIBS_DIR/sudo_lib.bash"
(($? == 0)) || return 1

#
# _fsarchiver_archinfo <error-trace out> <fsa-file>
#
_fsarchiver_archinfo() {
    local fsa_file="$2"
    local rc

    [[ -n "$fsa_file" ]] || {
        printf_stderr 'No fsa file selected.\n'
        return 0
    }

    fsarchiver archinfo "$fsa_file"
    rc="$?"

    if ((rc != 0)); then
        originate_error "$1" \
            'fsarchiver archinfo has failed with error code %d.\n' \
            "$rc"
        return 1
    fi

    return 0
}

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash" || return 1

# shellcheck source=./mspec_lib.bash
source "$BASH_LIBS_DIR/mspec_lib.bash" || return 1

# shellcheck source=./picker_lib.bash
source "$BASH_LIBS_DIR/picker_lib.bash" || return 1

#
# inspect_fsa_directory <error-trace out> <resource-spec> <prefix>
#
inspect_fsa_directory() {
    local rspec="$2"
    local prefix="$3"

    local tmpvar="$(make_tmpvar)"

    mspec_temp_mount_rspec "$tmpvar" "$rspec" 'require-exisiting' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local directory="$(mspec_path "$mspec")"
    local pattern="$(_fsa_pattern_from_prefix "$prefix")"

    pick_and_process_entry_from_directory "$tmpvar" \
        'index of file to inspect? ' \
        "$directory" "$pattern" \
        _fsarchiver_archinfo || {

        defer_forward_error "$1" \
            "${!tmpvar}" \
            mspec_release "$mspec"

        return 1
    }

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

# shellcheck source=./fsa_common_lib.bash
source "$BASH_LIBS_DIR/fsa_common_lib.bash" || return 1

#
# inspect_fsa_archive <error-trace out> <top-level-rspec> <prefix>
#
inspect_fsa_archive() {
    local top_level_rspec="$2"
    local prefix="$3"

    local rspec="$(rspec_extend_path "$top_level_rspec" "$_fsa_archive_sentinel")"
    local tmpvar="$(make_tmpvar)"

    inspect_fsa_directory "$tmpvar" "$rspec" "$prefix" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}
