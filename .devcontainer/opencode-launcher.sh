#!/bin/bash
# Launcher installed as /usr/local/bin/opencode. It wraps the real binary.
#
# The image symlinks OpenCode's four XDG directories into /workspace/.opencode
# (see the Dockerfile). Those link targets cannot be created at build time
# (/workspace is a mount point), and the entrypoint that creates them is skipped
# whenever the container is started some other way: dev containers replace the
# entrypoint with their own keep-alive command, and so does `docker run
# --entrypoint ...`. A link whose target does not exist makes OpenCode crash on
# its first write:
#
#   ENOENT: no such file or directory, mkdir '~/.local/share/opencode/log'
#
# So the targets are created here, on every launch, whatever started the
# container. If a target cannot be created (read-only or missing workspace), the
# link is replaced with a plain directory inside the container so OpenCode still
# starts; that state is then lost when the container is removed.

OPENCODE_BIN=/home/node/.opencode/bin/opencode

for link in \
    "${HOME}/.config/opencode" \
    "${HOME}/.local/share/opencode" \
    "${HOME}/.local/state/opencode" \
    "${HOME}/.cache/opencode"; do
    # Only dangling symlinks need attention; real directories and working links
    # are left alone.
    if [[ -L "${link}" && ! -e "${link}" ]]; then
        target="$(readlink "${link}")"
        if ! mkdir -p "${target}" 2> /dev/null; then
            echo "WARNING: cannot create ${target}; keeping OpenCode state in ${link} instead." >&2
            echo "         It will not survive a container rebuild." >&2
            rm -f "${link}" && mkdir -p "${link}"
        fi
    fi
done

exec "${OPENCODE_BIN}" "$@"
