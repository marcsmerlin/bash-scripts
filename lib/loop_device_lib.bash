# shellcheck shell=bash
# shellcheck disable=SC2155

# execution guard
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    echo "$(basename "${BASH_SOURCE[0]}") must be sourced." >&2
    exit 1
}

# re-source guard
[[ ${_loop_device_lib_included:-} ]] && return
readonly _loop_device_lib_included=1

if [[ -z ${BASH_LIBS_DIR:-} ]]; then
    readonly BASH_LIBS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# shellcheck source=./result_type_lib.bash
source "$BASH_LIBS_DIR/result_type_lib.bash"

# shellcheck source=./sudo_lib.bash
source "$BASH_LIBS_DIR/sudo_lib.bash"

#
# sudo_attach_loop_device <loop-device | error-trace out> <file_name>
#
sudo_attach_loop_device() {
    local file_name="$2"

    local tmpvar="$(make_tmpvar)"

    sudo_context_capture "$tmpvar" \
        losetup --find --show "$file_name"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Unable to attach loop device to "%s".\n' \
            "$file_name"
        return 1
    }

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# create_loop_image_file <loop-device | error-trace out-device> \
#   <file-name> \
#   <file-size>
#
create_loop_image_file() {
    local file_name="$2"
    local file_size="$3"

    rm -f "$file_name"
    truncate -s "$file_size" "$file_name" || {
        originate_error "$1" \
            'Unable to create image file "%s".\n' \
            "$file_name" \
            "$file_size"
        return 1
    }

    local tmpvar="$(make_tmpvar)"

    sudo_attach_loop_device "$tmpvar" "$file_name" || {
        forward_error "$1" "${!tmpvar}"
        rm -f "$file_name"
        return 1
    } 

    copy_out_result "$1" "${!tmpvar}"
    return 0
}

#
# sudo_detach_loop_device <loop-device>
#
sudo_detach_loop_device() {
    sudo losetup --detach "$1"
}

#
# sudo_mount <error-trace out> <device> <mount-point>
#
sudo_mount_loop_device() {
    local device="$2"
    local mount_point="$3"

    local tmpvar="$(make_tmpvar)"
    local rc

    sudo_context_capture "$tmpvar" \
        mount "$device" "$mount_point"

    rc="$?"

    ((rc == 0)) || {
        originate_error "$1" \
            'Failed to mount device "%s" on mount point "%s": %s' \
            "$device" \
            "$mount_point" \
            "${!tmpvar}"
        return 1
    }

    return 0
}

#
# mount_loop_image_file <loop-device | error-trace out > \
#   <image-file> \
#   <mount-point>
mount_loop_image_file() {
    local image_file="$2"
    local mount_point="$3"

    local tmpvar="$(make_tmpvar)"

    sudo_attach_loop_device "$tmpvar" "$image_file" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    } 

    local loop_device="${!tmpvar}"

    sudo_mount_loop_device "$tmpvar" "$loop_device" "$mount_point" || {
        forward_error "$1" "${!tmpvar}"
        sudo_detach_loop_device "$loop_device"
        return 1
    }

    copy_out_result "$1" "$loop_device"
    return 0
}

#
# unmount_loop_device <error-trace out> <loop-device>
#
unmount_loop_device() {
    local loop_device="$2"

    local tmpvar="$(make_tmpvar)"

    sudo_unmount "$tmpvar" "$loop_device" || {
        forward_error "$1" "${!tmpvar}"
        return 1
    }

    sudo_detach_loop_device "$loop_device"
    return 0
}
