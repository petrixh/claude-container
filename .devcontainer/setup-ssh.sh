#!/bin/bash
# Optional SSH server setup, shared by all container variants.
# Does nothing unless SSH_PUBLIC_KEY is set. When it is, installs the key(s)
# into the node user's authorized_keys and starts sshd on port 2222
# (key-only auth, node user only — see /etc/ssh/sshd_config.d/container.conf).
#
# SSH_PUBLIC_KEY may hold one key, or several separated by newlines.
# Safe to re-run: keys are only appended once and a running sshd is reused.

set -e

[[ -z "${SSH_PUBLIC_KEY:-}" ]] && exit 0

SSH_PORT=2222
SSH_DIR=/home/node/.ssh
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "${SSH_DIR}"
touch "${AUTHORIZED_KEYS}"

# Add each valid key that isn't already present
added=0
while IFS= read -r key || [[ -n "${key}" ]]; do
    # Trim surrounding whitespace (and CR from Windows-edited env files)
    key="${key//$'\r'/}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -z "${key}" ]] && continue
    if ! ssh-keygen -l -f <(echo "${key}") > /dev/null 2>&1; then
        echo "Warning: SSH_PUBLIC_KEY entry is not a valid public key, skipping: ${key:0:40}..."
        continue
    fi
    if ! grep -qxF "${key}" "${AUTHORIZED_KEYS}"; then
        echo "${key}" >> "${AUTHORIZED_KEYS}"
    fi
    added=$((added + 1))
done <<< "${SSH_PUBLIC_KEY}"

# sshd's StrictModes rejects keys if these are group/world writable
chown -R node:node "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTHORIZED_KEYS}"

if [[ ${added} -eq 0 ]]; then
    echo "Warning: SSH_PUBLIC_KEY is set but contains no valid keys. SSH server not started."
    exit 0
fi

# SSH sessions don't inherit the container's environment (GH_TOKEN, JAVA_HOME,
# CLAUDE_CONFIG_DIR, PATH, ...). Snapshot it so ~/.zshenv can load it for
# SSH logins, making them behave like `docker exec` shells.
for var in $(compgen -e); do
    case "${var}" in
        HOME|PWD|OLDPWD|SHLVL|HOSTNAME|TERM|USER|LOGNAME|SHELL|MAIL|SSH_PUBLIC_KEY|_) continue ;;
    esac
    printf 'export %s=%q\n' "${var}" "${!var}"
done > /home/node/.container-env
chmod 600 /home/node/.container-env

# Use zsh for SSH logins, matching the container's default shell
if [[ "$(getent passwd node | cut -d: -f7)" != "/bin/zsh" ]]; then
    sudo usermod -s /bin/zsh node
fi

# Host keys are removed at build time so every container gets its own
sudo ssh-keygen -A > /dev/null
sudo mkdir -p /run/sshd

if pgrep -x sshd > /dev/null; then
    echo "SSH server already running on port ${SSH_PORT} (${added} key(s) authorized)."
else
    sudo /usr/sbin/sshd
    echo "SSH server started on port ${SSH_PORT} (${added} key(s) authorized)."
fi
echo "  Publish the port (e.g. -p 2222:2222), then: ssh -p 2222 node@localhost"
echo ""
