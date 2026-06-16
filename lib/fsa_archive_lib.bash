# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_fsa_archive_lib_included:-} ]] && return 0
readonly _fsa_archive_lib_included=1

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
# _fsarchiver_savefs <error-trace out> <fsa-file> <fs-dev>
#
_fsarchiver_savefs() {
    local fsa_file="$2"
    local fs_dev="$3"

    local threads=$(($(nproc) / 2))
    ((threads < 1)) && threads=1

    local compression_level=3

    local fsa_opts=(
        -o
        -j "$threads"
        -Z "$compression_level"
    )

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        fsarchiver savefs "${fsa_opts[@]}" "$fsa_file" "$fs_dev"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" "${!tmpvar}"
        return 1
    }

    return 0
}

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./mspec_lib.bash
source "$BASH_LIBS_DIR/mspec_lib.bash"
(($? == 0)) || return 1

# shellcheck source=./fsa_common_lib.bash
source "$BASH_LIBS_DIR/fsa_common_lib.bash" || return 1

#
# create_fsa_file <error-trace | fsa-file-rspec out> \
#   <file-system> \
#   <resource-spec>
#
create_fsa_file() {
    local file_system="$2"
    local rspec="$3"
    local tmpvar="$(make_tmpvar)"

    get_device_for_label "$tmpvar" "$file_system" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local fs_dev="${!tmpvar}"
    local fsa_file_name="$(_make_fsa_file_name "$file_system")"

    mspec_temp_mount_rspec "$tmpvar" "$rspec" 'create-if-missing' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local fsa_file_path="$(mspec_file_path "$mspec" "$fsa_file_name")"

    _fsarchiver_savefs "$tmpvar" "$fsa_file_path" "$fs_dev" || {
        local trigger_error="${!tmpvar}"

        defer_forward_error "$1" \
            "$trigger_error" \
            mspec_release "$mspec"

        return 1
    }

    sudo_chown "$tmpvar" "$fsa_file_path" || {
        local trigger_error="${!tmpvar}"

        defer_forward_error "$1" \
            "$trigger_error" \
            mspec_release "$mspec"

        return 1
    }

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "$(rspec_extend_path "$rspec" "$fsa_file_name")"
    return 0
}

#
# archive_file_system <fsa-file_rspec | error-trace out> \
#   <file-system> \
#   <top-level-rspec>
#
archive_file_system() {
    local file_system="$2"
    local top_level_rspec="$3"

    local rspec="$(rspec_extend_path "$top_level_rspec" "$_fsa_archive_sentinel")"
    local tmpvar="$(make_tmpvar)"

    create_fsa_file "$tmpvar" "$file_system" "$rspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
