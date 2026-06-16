# shellcheck shell=bash
# shellcheck disable=SC2155 # Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2181 # Check exit code directly with e.g. `if mycmd;`, not indirectly with `$?`.

# re-source guard
[[ ${_fsa_revive_lib_included:-} ]] && return 0
readonly _fsa_revive_lib_included=1

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
# _fsarchiver_restfs <error-trace out> <fsa-file> <loop-device>
#
_fsarchiver_restfs() {
    local fsa_file="$2"
    local loopdev="$3"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        fsarchiver restfs "$fsa_file" id=0,dest="$loopdev"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" "${!tmpvar}"
    }

    return "$rc"
}

# shellcheck source=./loop_device_lib.bash
source "$BASH_LIBS_DIR/loop_device_lib.bash"
(($? == 0)) || return 1

# create_fsa_file_image <image-file | error-trace-out> \
#   <fsa-file> \
#   <image-size> \
#   <destination-directory>
#
create_fsa_file_image() {
    local fsa_file="$2"
    local image_directory="$3"
    local image_size="$4"

    local basename=${fsa_file##*/}
    basename=${basename%.*}
    local image_file="$image_directory/${basename}.img"

    local tmpvar="$(make_tmpvar)"

    create_loop_image_file "$tmpvar" "$image_file" "$image_size" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local loopdev="${!tmpvar}"

    _fsarchiver_restfs "$tmpvar" "$fsa_file" "$loopdev" || {
        forward_error "$1" "${!tmpvar}"
        sudo_detach_loop_device "$loopdev"
        return 1
    }

    sudo_detach_loop_device "$loopdev"

    copy_out_result "$1" "$image_file"
    return 0
}

# shellcheck source=./rspec_lib.bash
source "$BASH_LIBS_DIR/rspec_lib.bash" || return 1

# shellcheck source=./mspec_lib.bash
source "$BASH_LIBS_DIR/mspec_lib.bash" || return 1

# shellcheck source=./picker_lib.bash
source "$BASH_LIBS_DIR/picker_lib.bash" || return 1

#
# revive_fsa_directory <fsa-file-spec | error-trace out> \
#   <fsa-directory-rspec> \
#   <prefix> \
#   <image-directory> \
#   <image-size>
#
revive_fsa_directory() {
    local fsa_directory_rspec="$2"
    local prefix="$3"
    local image_directory="$4"
    local image_size="$5"

    local tmpvar="$(make_tmpvar)"

    mspec_temp_mount_rspec "$tmpvar" "$fsa_directory_rspec" 'require-exisiting' || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    local mspec="${!tmpvar}"
    local fsa_directory="$(mspec_path "$mspec")"
    local pattern="$(_fsa_pattern_from_prefix "$prefix")"

    pick_and_process_entry_from_directory "$tmpvar" \
        'index of file to revive? ' \
        "$fsa_directory" \
        "$pattern" \
        create_fsa_file_image "$image_directory" "$image_size" || {

        defer_forward_error "$1" \
            "${!tmpvar}" \
            mspec_release "$mspec"

        return 1
    }

    mspec_release "$tmpvar" "$mspec" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

# shellcheck source=./fsa_common_lib.bash
source "$BASH_LIBS_DIR/fsa_common_lib.bash" || return 1

#
# revive_fsa_archive <error-trace out> \
#   <top-level-rspec> \
#   <prefix> \
#   <image_directory> \
#   <image-size>
#
revive_fsa_archive() {
    local top_level_rspec="$2"
    local prefix="$3"
    local image_directory="$4"
    local image_size="$5"

    local rspec="$(rspec_extend_path "$top_level_rspec" "$_fsa_archive_sentinel")"
    local tmpvar="$(make_tmpvar)"

    revive_fsa_directory "$tmpvar" \
        "$rspec" "$prefix" "$image_directory" "$image_size" || {

        forward_error "$1" "${!tmpvar}"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}
