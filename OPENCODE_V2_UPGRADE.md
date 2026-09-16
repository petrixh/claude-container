# OpenCode V2 — Upgrade Requirements for This Container

Investigation for [#30](https://github.com/petrixh/claude-container/issues/30).
Reference: [https://opencode.ai/v2/docs/migrate-v1/](https://opencode.ai/v2/docs/migrate-v1/)

**Status:** investigation only — no container files changed yet.

**Verified against:** OpenCode **v2.0.1** and **v2.0.3**, installed from
`https://opencode.ai/v2/install` on linux/arm64 (glibc) and compared against the
**v1.18.30** binary. Everything marked *(verified)* was observed directly by running the
binary or fetching the endpoint; everything else comes from the official docs.

---

## TL;DR

The container needs **four changes**, one of which moves where OpenCode keeps its state:


| #   | Change                                                                    | Where                                                             | Severity                         |
| --- | ------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------- |
| 1   | Install URL `opencode.ai/install` → `opencode.ai/v2/install`              | `Dockerfile` (opencode stage)                                     | Required                         |
| 2 | Document `models.opencode.ai` as a commented-out opt-in; note that `opencode.ai` is also the Zen inference endpoint | `allowed-domains.conf` | Recommended |
| 3 | Consolidate state into one `./.opencode` folder in the project | `Dockerfile`, `entrypoint-opencode.sh`, `docker-compose.yml`, `devcontainer-opencode*.json` | **Required — data-loss risk** |
| 4   | Document the new background-service model and `/connect` auth             | `README.md`, `entrypoint-opencode.sh`                             | Recommended                      |


Everything else in the image keeps working unchanged: install directory, the
`/usr/local/bin/opencode` symlink, the baked-in Playwright Agent CLI skill, Java,
the firewall's loopback rule, and the CI `opencode --version` smoke test.

The heavy part of the V1→V2 migration is **user config schema**, not container plumbing.
This repo ships no `opencode.json`, so that lands on users — but the README should point
at it.

---

## 1. Distribution and install *(verified)* 


|                           | V1                                                                               | V2                                                                      |
| ------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Install script            | `https://opencode.ai/install`                                                    | `https://opencode.ai/v2/install`                                        |
| Artifact source           | `github.com/anomalyco/opencode/releases` (+ `api.github.com` for the latest tag) | `registry.npmjs.org/@opencode/cli-<os>-<arch>/-/cli-<target>-<ver>.tgz` |
| Version metadata | GitHub releases API | `https://opencode.ai/update/api/beta/cli/npm` — **see the channel trap below** |
| npm package               | `opencode-ai`                                                                    | `@opencode/cli`                                                         |
| Docker image              | —                                                                                | `ghcr.io/anomalyco/opencode:<version>`                                  |
| Binary size (linux/arm64) | 176 MB                                                                           | 193 MB                                                                  |
| `--version` output | `1.18.30` | `opencode v2.0.3` |


**Unchanged and therefore safe:**

- `INSTALL_DIR` is still `$HOME/.opencode/bin` — the Dockerfile's
`ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode` still resolves.
- Flags are identical: `-v/--version <ver>`, `--binary <path>`, `--no-modify-path`.
The existing `bash -s -- --version ${OPENCODE_VERSION}` invocation works as-is.
- Build prerequisites are the same (`curl`, `tar`, `sed`, `mkfifo`) — all present in
`base-common`.

**Note:** V2 also drops a tiny `opencode2` shim next to the binary
(`exec "$(dirname "$0")/opencode" "$@"`). Harmless; no symlink needed for it.

### The channel trap — `latest` is *not* what the script installs

The published v2 installer hardcodes the **`beta`** channel:

```bash
metadata=$(curl -fsSL https://opencode.ai/update/api/beta/cli/npm || true)
```

That endpoint is stale. Checked side by side *(verified)*:

| Source | Version |
|---|---|
| `opencode.ai/update/api/beta/cli/npm` (what the script uses) | **2.0.1** |
| `opencode.ai/update/api/latest/cli/npm` | **2.0.3** |
| npm `@opencode/cli` dist-tag `latest` | **2.0.3** |
| npm dist-tag `beta` | `0.0.0-beta-19507` |
| npm dist-tag `dev` | `0.0.0-dev-19638` |

So `OPENCODE_VERSION=latest` today silently builds **2.0.1**, three patch releases
behind — which is exactly why the first pass of this document was written against 2.0.1.
These are ordinary releases, not prereleases: v2.0.2 and v2.0.3 are published on GitHub
with `prerelease: false`. The `beta` name in the URL looks like a leftover from the v2
prerelease period that was never repointed. (The GitHub *releases* API is no help either
— `releases/latest` still returns **v1.18.31**, since v1 and v2 share a repo.)

`stable`, `v2` and `release` are not valid channels (404). Only `beta` and `latest` exist.

**Recommendation: never rely on the script's default.** Resolve the `latest` channel
explicitly and pass it through — `jq` is already in the image:

```dockerfile
RUN if [ "${OPENCODE_VERSION}" = "latest" ]; then \
      OPENCODE_VERSION=$(curl -fsSL https://opencode.ai/update/api/latest/cli/npm | jq -r .version); \
    fi \
 && su - node -c "curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path --version ${OPENCODE_VERSION}"
```

*(Verified: resolving the endpoint and passing `--version 2.0.3` installs
`opencode v2.0.3`.)* This also makes every build log the exact version it baked in, which
is what the weekly scheduled build needs.

The alternative is `npm install -g @opencode/cli`, which resolves the npm `latest`
dist-tag correctly and would also sidestep §4's install-directory problem — worth
considering, though it adds a postinstall step that picks the native binary.

### Suggested Dockerfile change

Channel as a build arg so a v1 image stays buildable, `latest` resolved explicitly per the
trap above, and the binary relocated per §4:

```dockerfile
# OPENCODE_CHANNEL: "v2" (default) or "v1"
ARG OPENCODE_CHANNEL=v2
ARG OPENCODE_VERSION=latest

RUN set -eu; \
    if [ "${OPENCODE_CHANNEL}" = "v2" ]; then \
      INSTALL_URL=https://opencode.ai/v2/install; \
      CHANNEL_URL=https://opencode.ai/update/api/latest/cli/npm; \
    else \
      INSTALL_URL=https://opencode.ai/install; \
      CHANNEL_URL=; \
    fi; \
    VERSION="${OPENCODE_VERSION}"; \
    if [ "${VERSION}" = "latest" ] && [ -n "${CHANNEL_URL}" ]; then \
      VERSION=$(curl -fsSL "${CHANNEL_URL}" | jq -r .version); \
    fi; \
    echo "Installing opencode ${VERSION} from ${INSTALL_URL}"; \
    if [ "${VERSION}" = "latest" ]; then \
      su - node -c "curl -fsSL ${INSTALL_URL} | bash -s -- --no-modify-path"; \
    else \
      su - node -c "curl -fsSL ${INSTALL_URL} | bash -s -- --no-modify-path --version ${VERSION}"; \
    fi; \
    ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode

ENV OPENCODE_DISABLE_AUTOUPDATE=1
```

`OPENCODE_DISABLE_AUTOUPDATE=1` keeps a pinned image from silently replacing the binary
the build just pinned. `--no-modify-path` suppresses the installer's `.zshrc` PATH edit
(§4).

---

## 2. Firewall / allowed domains

The install path is *better* under V2: it needs only `opencode.ai` and
`registry.npmjs.org`, both already allowlisted. `github.com` / `api.github.com` are no
longer required to install OpenCode (still needed for `gh` and git).

Nothing here is *required*. Blocking model endpoints by default is the point of the
firewall — whether prompts and code leave the container is the user's call, which is why
the provider APIs in `allowed-domains.conf` ship commented out. Both items below follow
that pattern: a comment, not an allow.

### 2a. `models.opencode.ai` — opt-in, and metadata only

`init-firewall.sh` resolves exact hostnames (no wildcards), and this host shares no IPs
with `opencode.ai` *(verified)*, so it is blocked today:

```
opencode.ai        -> 172.65.90.20 .21 .22 .23
models.opencode.ai -> 172.66.173.149 104.20.32.17
```

Worth documenting accurately, because it is **not** an inference endpoint. It serves one
~4.7 MB public catalog, `https://models.opencode.ai/api.json`, listing providers and
their models — id, display name, credential env var names, base URL, context limits,
pricing *(verified by fetching it)*. A one-way GET of a public file; no code or prompts
are sent.

**Blocked, OpenCode still works** *(verified)*: `opencode models` with the fetch disabled
still lists the built-in `opencode/*` models. What is lost is metadata for third-party
providers — names, context limits and pricing in the model picker. The catalog is cached
in `opencode.db` once fetched, so allowing it for a single run and re-blocking also works.

Suggested `allowed-domains.conf` entry — commented, with the tradeoff stated:

```
# OpenCode model catalog (metadata only: provider/model names, limits, pricing).
# ~4.7MB public JSON, one-way GET - no code or prompts are sent.
# Left blocked by default; without it third-party models show no metadata.
# Set OPENCODE_DISABLE_MODELS_FETCH=1 to skip the request entirely.
# models.opencode.ai
```

### 2b. `opencode.ai` is *also* the Zen inference endpoint

This one cuts against the default posture and is worth knowing. `opencode.ai` is
allowlisted (uncommented) today because the installer needs it — but the built-in free
models advertised on first run route inference through **`https://opencode.ai/zen/v1`**
*(verified in the catalog: provider id `opencode`, "OpenCode Zen")*.

So with the stock config the free models work out of the box, and **prompts do leave the
container** — via the same host on which the harmless metadata catalog is blocked.

Removing it is possible, with a real cost:

- **Installing is build-time, not runtime.** The binary is baked into the image, so the
  runtime firewall does not need `opencode.ai` for the container to function.
- **But** `opencode.ai` also serves `/oauth/opencode/client.json`, used by the OAuth
  provider flows behind `/connect`. Block it and provider login is API-key only.
- `opencode upgrade` and the config/theme schema fetches also stop working. Neither
  matters much in a rebuild-the-image workflow.

Suggested treatment — keep it allowed (the least surprising default) and state what it
implies:

```
# OpenCode. Needed at build time to install the CLI, and at runtime for OAuth
# provider login (/connect) and `opencode upgrade`.
# NOTE: this host is ALSO the OpenCode Zen inference endpoint (opencode.ai/zen/v1)
# used by the built-in free models - so leaving it allowed means prompts can leave the
# container. Comment it out for an inference-free sandbox; provider login is then
# API-key only.
opencode.ai
```

Other hosts the V2 binary references (`opencode.ai/config.json`, `/theme.json`,
`/v2/cli.json`, `/update/api/…`) are all on `opencode.ai` and covered by the above.

### 2c. Remote MCP servers

Each remote MCP server needs **its own host** added to `allowed-domains.conf` — see §6c.
This is the most likely "MCP worked on my host but not in the container" failure.

No firewall change is needed for the new background service: it binds
`127.0.0.1:<random>` and `init-firewall.sh` already accepts `-o lo`.

---

## 3. New runtime architecture: the background service *(verified)*

This is the largest behavioural change for a container.

V2 runs a **shared background server** by default; the TUI, `run`, and `api` are clients
of it.

```
$ opencode service status
stopped
$ opencode service start
http://127.0.0.1:49374
```

- Subcommands: `service start | stop | restart | status | get | set | unset`.
- Bypass with `--standalone` (private per-process server) or `--server <url>`.
- The service records `{id, version, url, pid, password}` in
`~/.local/state/opencode/service.json` (removed on stop).
- The shared secret lives in `**~/.config/opencode/service.json**`, is generated on first
start and then **reused** across restarts *(verified)*.

**Container implications:**

- Inside a single container this is fine — loopback only, no port to publish.
- `~/.local/state/opencode` should stay **unmounted** so each container gets its own
service record. The current mounts already do this correctly.
- `~/.config/opencode` *is* bind-mounted from the host, so the host's service password is
shared into the container. Not a functional break (the password is reused, not
regenerated), but it means a host secret now crosses the sandbox boundary — worth a
README note for anyone using this container as a security boundary.
- For CI-style non-interactive use, prefer `opencode run --standalone …` to avoid leaving
a daemon behind.

---

## 4. Filesystem layout and the data-dir hazard

`opencode debug paths` on V2 *(verified)*:


| Selector | Path                                                         |
| -------- | ------------------------------------------------------------ |
| `config` | `~/.config/opencode` (overridable via `OPENCODE_CONFIG_DIR`) |
| `data`   | `~/.local/share/opencode`                                    |
| `state`  | `~/.local/state/opencode`                                    |
| `cache`  | `~/.cache/opencode`                                          |
| `bin`    | `~/.cache/opencode/bin`                                      |
| `log`    | `~/.local/share/opencode/log`                                |
| `repos`  | `~/.local/share/opencode/repos`                              |
| `db`     | `~/.local/share/opencode/opencode.db`                        |
| `tmp`    | `/tmp/opencode`                                              |


The XDG locations are unchanged from v1.18, so the existing mounts still point at the
right places. The problem is *what now lives there*.

### 4a. Credentials are in SQLite, not `auth.json`

The DB contains `credential`, `account`, `account_state` and `control_account` tables
*(verified by inspecting the schema)*. `auth.json` is legacy-import only. So "share my
logins with the container" now means "share the whole session database".

### 4b. V2 migrates the V1 database **in place**

v1.18 and v2 use the *same filename*, `~/.local/share/opencode/opencode.db`. The V2
binary contains a migration that reads the V1 `message` / `part` tables and rewrites them
into V2's `session_message`, logging `Migrating sessions` / `Failed to copy V1 session`
*(verified in the binary)*.

Both `docker-compose.yml` and `devcontainer-opencode*.json` currently bind-mount:

```
source=${localEnv:HOME}/.local/share/opencode,target=/home/node/.local/share/opencode
```

**Starting a V2 container against that mount will migrate the user's host database.**
If the host still runs v1, that is a one-way trip.

### 4c. SQLite WAL over a bind mount

The DB runs in WAL mode — `opencode.db-wal` and `opencode.db-shm` appear alongside it
*(verified)*. Two servers (host v1 + container v2) holding the same bind-mounted DB
concurrently is unsafe, and WAL shared-memory is unreliable over Docker Desktop's
virtiofs/gRPC-FUSE bind mounts on macOS and Windows. V2's always-on background service
makes concurrent access the normal case rather than the exception.

### Recommendation — one `./.opencode` folder in the project

The bind mount stays. The problem is not the mount *type*, it is that OpenCode's state is
scattered across four XDG directories and one of them collides, file-for-file, with a host
v1 install.

Put all four in **one `.opencode` folder inside the devcontainer project**, alongside the
code:

```
myproject/
├── .opencode/          <- everything OpenCode, travels with the project
│   ├── config/
│   ├── data/
│   ├── state/
│   └── cache/
├── src/
└── ...
```

Move or copy the project folder and the sessions, credentials and config go with it. It
survives `docker system prune` and container rebuilds for the same reason the code does —
it is a host directory, not a volume.

**No new mount is needed.** The project is already bind-mounted at `/workspace`, so
`./.opencode` on the host is `/workspace/.opencode` in the container. The two current
OpenCode mounts are simply deleted:

```yaml
# docker-compose.yml — opencode and opencode-dind
volumes:
  - ./:/workspace:delegated          # already there; nothing else needed
# - ${HOME}/.config/opencode:...     <- remove
# - ${HOME}/.local/share/opencode:... <- remove
```

Same for the `mounts` arrays in `devcontainer-opencode.json` and
`devcontainer-opencode-dind.json` — drop both OpenCode entries and keep `workspaceMount`.

Inside the image, the four XDG locations become symlinks into that folder:

```dockerfile
RUN mkdir -p /home/node/.config /home/node/.local/share \
             /home/node/.local/state /home/node/.cache \
 && ln -s /workspace/.opencode/config /home/node/.config/opencode \
 && ln -s /workspace/.opencode/data   /home/node/.local/share/opencode \
 && ln -s /workspace/.opencode/state  /home/node/.local/state/opencode \
 && ln -s /workspace/.opencode/cache  /home/node/.cache/opencode \
 && chown -R node:node /home/node
```

The subdirectories are created by **`entrypoint-opencode.sh`**, not the Dockerfile —
`/workspace` is a mount point, so anything the image writes there is shadowed the moment
the bind mount lands. The symlinks are deliberately left dangling in the image and resolve
on first start:

```bash
mkdir -p /workspace/.opencode/{config,data,state,cache}
```

A project that has never run OpenCode therefore gets a working `.opencode` folder
automatically, with no setup step.

**Verified** *(against `~/.opencode`, but the mechanism is identical — only the symlink
target differs)*: with those symlinks in place, starting the service and running
`auth list` puts everything in the one folder:

```
.opencode/config/service.json
.opencode/data/opencode.db
.opencode/data/log/opencode.log
.opencode/data/repos/
.opencode/data/shell/
.opencode/cache/bin/
```

`opencode debug paths` still reports the standard XDG paths — it resolves them through the
symlinks and neither notices nor cares.

#### ⚠️ This puts credentials in the project folder

`.opencode/data/opencode.db` holds provider credentials (§4a). It **must not** be
committed. The project's `.gitignore` needs:

```gitignore
.opencode/config/
.opencode/data/
.opencode/state/
.opencode/cache/
```

Deliberately not `.opencode/` wholesale: that same folder is where OpenCode looks for
*project* config — `.opencode/opencode.json`, `.opencode/agents/`, `.opencode/commands/`,
`.opencode/skills/` (§6e) — and those are meant to be committed and shared. The four
runtime subdirectories sit beside them without colliding, but the `.gitignore` has to be
specific.

Worth having `entrypoint-opencode.sh` warn when it creates the folder in a git repo whose
`.gitignore` does not cover it.

#### What this buys, and what it costs

| | |
|---|---|
| ✅ | One folder, named after the tool, next to the code |
| ✅ | Moves and copies with the project — code and history stay together |
| ✅ | Survives `docker system prune` and rebuilds |
| ✅ | No extra mount; the two current OpenCode mounts are deleted |
| ✅ | Host's `~/.local/share/opencode` is never touched, so a host v1 install keeps working (§4b) |
| ⚠️ | Credentials live in the project tree — `.gitignore` is mandatory |
| ⚠️ | Login is **per project**, not once per machine |

That last one is a genuine trade. Per-project isolation is arguably the right default for
a sandbox, but it is a change in feel from the Claude variants, which share one
`${HOME}/.claude` across every project. If sharing one login across projects matters more,
the same symlink scheme works unchanged against `${HOME}/.opencode` with an explicit
bind mount — the only differences are the symlink target and that the binary then has to
be relocated out of `/home/node/.opencode/bin`, which the installer hardcodes.

#### Two image details

1. **Install with `--no-modify-path`.** The installer appends
   `export PATH=$HOME/.opencode/bin:$PATH` to `.zshrc` *(verified — it is in the image's
   `.zshrc` today)*. Harmless with the project-relative layout, but it is noise pointing
   at a directory nothing else uses, and it becomes actively wrong if the `${HOME}`
   variant above is ever adopted.
2. **The binary stays where it is.** With nothing mounted over `/home/node/.opencode`,
   the current `ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode` keeps
   working — no relocation needed.

#### Why not environment variables

Pointing all four `XDG_*_HOME` vars at a single root does collapse the paths — *verified*,
`debug paths` then reports one directory for config, data, state and cache. It was rejected
anyway: OpenCode spawns shell commands and MCP servers that **inherit its environment**, so
a container-wide (or even wrapper-scoped) `XDG_CONFIG_HOME` would also relocate `gh`, whose
config the image deliberately places at `~/.config/gh`. Symlinks keep the redirection where
it belongs — on OpenCode's directories only.

`OPENCODE_CONFIG_DIR` redirects the config directory alone *(verified)* and is still worth
documenting as an escape hatch, but it does not move the database.

#### Remaining caveats

- Two containers on the same project folder means two writers on one SQLite database.
- On **Docker Desktop for macOS/Windows**, SQLite WAL shared memory over virtiofs /
  gRPC-FUSE bind mounts is unreliable. On a Linux VM this is a non-issue; if it does bite,
  `OPENCODE_DB` can move just the database file off the bind mount.

## 5. CLI surface changes *(verified by `--help` diff)*

**Removed:** `attach`, `web`, `export`, `import`, `github`, `pr`, `db`, `agent`,
`completion`, `providers` (the `auth` alias is now the canonical name), and the root-level
flags `--pure`, `--port`, `--hostname`, `--mdns`, `--mdns-domain`, `--cors`,
`-m/--model`, `--agent`, `--fork`, `--no-replay`, `--replay-limit`.

**Added:** `service`, `api`, `pair`, `plugin`, `mini` (was a flag), plus global
`--standalone`, `--server`, `--wizard`, `--completions <shell>`.

**Kept:** `run`, `serve`, `models`, `stats`, `session`, `mcp`, `acp`, `upgrade`,
`uninstall`, `debug`, and `auth login | logout | list | switch`.

`opencode run` keeps `-c/--continue`, `-s/--session`, `--fork`, `-m/--model`,
`--agent`, `--auto` and gains `--format json`, `-f/--file`, `--title`, `--thinking`.

`--log-level` choices changed from `DEBUG|INFO|WARN|ERROR` to
`all|trace|debug|info|warn|warning|error|fatal|none`.

**Impact on this repo:** none of the removed commands appear in the Dockerfile,
entrypoints, or CI. The `opencode --version` CI check still passes (output string changes
from `1.18.30` to `opencode v2.0.3`, which nothing parses). The version line in
`entrypoint-opencode.sh` will print `opencode v2.0.3` — cosmetic only.

---

## 6. `opencode.json` breaking changes

This repo ships no `opencode.json`, but the container **bind-mounts the host's config
directory**, so a config that has not been migrated breaks the container exactly as it
breaks the host. Config file *read locations are unchanged*:

```
~/.config/opencode/opencode.json(c)   # global (see §4 for where this lives in the container)
./opencode.json(c)                    # project root
./.opencode/opencode.json(c)          # project root, inside the .opencode folder
```

The guide's advice is that supported V1 fields and native V2 fields may coexist, so a
config can be ported incrementally. Plugins and anything speaking the server API cannot —
those are the intentional hard breaks.

### 6a. Providers *(the big one for external configs)*

`provider` → `providers`, and the single V1 `options` blob is split into three distinct
places: `settings` (options handed to the runtime package), `headers` (HTTP headers), and
`body` (JSON merged into request bodies). `npm` → `package`, and `api` moves to
`settings.baseURL`.

```jsonc
// V1
{
  "provider": {
    "acme": {
      "npm": "@ai-sdk/openai-compatible",
      "api": "https://llm.example.com/v1",
      "options": { "apiKey": "{env:ACME_API_KEY}" }
    }
  }
}

// V2
{
  "providers": {
    "acme": {
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "https://llm.example.com/v1",
        "apiKey": "{env:ACME_API_KEY}"
      }
    }
  }
}
```

Note the `**aisdk:` prefix** on AI SDK packages. Native V2 packages use their own path,
e.g. `"package": "@opencode/ai/providers/openai-compatible"`.

Full V2 provider field set: `name`, `env` (ordered env var names that can supply the
credential), `package`, `canonical` (inherit catalog defaults from a built-in provider
ID), `settings`, `headers`, `body`, `models`, `transport` (`"http"` | `"websocket"`),
`compaction`.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "acme": {
      "name": "Acme",
      "env": ["ACME_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://llm.acme.example/v1" },
      "headers": { "X-Gateway-Tenant": "engineering" },
      "body": { "metadata": { "application": "opencode" } },
      "models": { "qwen3-coder": { "name": "Qwen 3 Coder" } }
    }
  }
}
```

**Provider IDs consolidated** — rename these or the provider silently stops resolving:


| V1 provider ID             | V2              |
| -------------------------- | --------------- |
| `azure-cognitive-services` | `azure`         |
| `google-vertex-anthropic`  | `google-vertex` |


**Dropped provider fields (ignored in V2):** `id`, `whitelist`, `blacklist`.

### 6b. Models, limits and modalities

Per-model renames:

| V1 | V2 |
|---|---|
| `id` | `modelID` |
| `tool_call` | `capabilities.tools` |
| `modalities.input` / `.output` | `capabilities.input` / `capabilities.output` |
| `cache_read` / `cache_write` | `cost.cache.read` / `cost.cache.write` |
| `status: "deprecated"` | `disabled: true` |
| `variants: { … }` (object) | `variants: [ … ]` (array, each with an `id`) |
| **`limit.context` / `.input` / `.output`** | **unchanged** |

**Context and output limits do not move.** `limit` keeps the same three keys in V2 —
`context` (total window), `input` (max prompt) and `output` (max completion). If you
worked these out for a custom provider under V1, copy the block across verbatim. Only the
modality and tool-call flags change shape.

Full before/after for a custom OpenAI-compatible provider — the case where you have to
declare all of this by hand:

```jsonc
// V1
{
  "provider": {
    "acme": {
      "npm": "@ai-sdk/openai-compatible",
      "api": "https://llm.example.com/v1",
      "options": { "apiKey": "{env:ACME_API_KEY}" },
      "models": {
        "acme-1": {
          "name": "Acme One",
          "tool_call": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] },
          "limit": { "context": 128000, "input": 120000, "output": 8192 },
          "cost": { "input": 1.0, "output": 2.0, "cache_read": 0.1 }
        }
      }
    }
  }
}

// V2
{
  "providers": {
    "acme": {
      "name": "Acme",
      "env": ["ACME_API_KEY"],
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "https://llm.example.com/v1",
        "apiKey": "{env:ACME_API_KEY}"
      },
      "models": {
        "acme-1": {
          "modelID": "acme-1",
          "name": "Acme One",
          "capabilities": {
            "tools": true,
            "input": ["text", "image"],
            "output": ["text"]
          },
          "limit": { "context": 128000, "input": 120000, "output": 8192 },
          "cost": { "input": 1.0, "output": 2.0, "cache": { "read": 0.1 } }
        }
      }
    }
  }
}
```

Accepted modality values are `text`, `audio`, `image`, `video`, `pdf` *(read from the V2
binary's config schema)*. `attachment: true` is gone — image support is now expressed
solely by `image` appearing in `capabilities.input`.

#### Are they strictly necessary?

**For a model in the public catalog, no.** `models.opencode.ai` supplies `limit`,
`capabilities` and `cost` for every provider/model it knows, and anything you declare
locally is an override.

**For a custom or self-hosted model, yes** — a local Ollama, vLLM or corporate gateway is
not in the catalog, so nothing fills these in. Omit `limit` and OpenCode has no idea when
to compact; omit `image` from `capabilities.input` and image attachments are refused.

**In this container specifically, assume yes.** Per §2a the catalog host is blocked by
default, so *no* model gets metadata from the catalog unless the user opts in. Declaring
`limit` and `capabilities` explicitly in `opencode.json` is the reliable path here — and
it is worth saying so in the README, since it is exactly the thing that is slow to
diagnose: no error, just premature compaction or silently rejected attachments.

#### V1 field names still work

The V2 binary keeps a compatibility shim: `tool_call`, `modalities.input`/`.output` and
`cost.cache_read`/`cache_write` are still read and folded into `capabilities` / `cost.cache`
*(read from the V2 binary's compatibility layer — not exercised end to end, which would
need live provider credentials)*. So an un-migrated V1 model block keeps working; the
native V2 spelling is what new config should use.

#### Variants

```jsonc
// V1
{ "variants": { "high": { "reasoningEffort": "high" } } }

// V2
{ "variants": [ { "id": "high", "settings": { "reasoningEffort": "high" } } ] }
```

Other V2 model fields: `package` (per-model runtime override), `settings`, `headers`,
`body`, `compatibility`, `transport`, `compaction`, `disabled`.

**Dropped model fields (ignored in V2):** `release_date`, `attachment`, `reasoning`,
`temperature`, `experimental`, non-`deprecated` `status`, and boolean `interleaved`.

**Model references now carry the variant inline.** Anywhere a model is named — the
top-level `model`, an agent's `model`, command frontmatter, `opencode run -m` — the
syntax is `provider/model#variant`. A separate `variant` key is no longer read.

```jsonc
// V1
{ "model": "anthropic/claude-sonnet-4-5", "variant": "high" }
// V2
{ "model": "anthropic/claude-sonnet-4-5#high" }
```

### 6c. MCP servers *(the other externally-used one)*

Servers move down one level under `**mcp.servers**`, `enabled` inverts to `**disabled**`,
and the scalar `timeout` becomes an object with distinct phases.

```jsonc
// V1
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "@playwright/mcp"],
      "enabled": true,
      "timeout": 30000
    }
  }
}

// V2
{
  "mcp": {
    "servers": {
      "playwright": {
        "type": "local",
        "command": ["npx", "@playwright/mcp"],
        "disabled": false,
        "timeout": { "catalog": 30000, "execution": 30000 }
      }
    }
  }
}
```

**Local (stdio) server** — required: `type: "local"`, `command`. Optional: `cwd`,
`environment` (V1 called this `env`; `{env:NAME}` interpolation works), `disabled`,
`codemode`, `timeout: { startup, catalog, execution }`, `protocol`
(`"legacy"` | `"auto"` | `"2026-07-28"`).

```jsonc
{
  "mcp": {
    "servers": {
      "everything": {
        "type": "local",
        "command": ["npx", "-y", "@modelcontextprotocol/server-everything"],
        "cwd": ".",
        "environment": {
          "LOG_LEVEL": "info",
          "MCP_API_KEY": "{env:MCP_API_KEY}"
        },
        "disabled": false,
        "codemode": true,
        "timeout": { "startup": 45000, "catalog": 30000, "execution": 600000 },
        "protocol": "legacy"
      }
    }
  }
}
```

**Remote (HTTP) server** — required: `type: "remote"`, `url`. Optional: `headers`,
`oauth` (object, or `false` to disable — OAuth is **on by default** in V2), `disabled`,
`codemode`, `timeout`, `protocol`.

```jsonc
{
  "mcp": {
    "servers": {
      "context7": {
        "type": "remote",
        "url": "https://mcp.context7.com/mcp",
        "headers": { "CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}" },
        "oauth": {
          "client_id": "{env:MCP_CLIENT_ID}",
          "client_secret": "{env:MCP_CLIENT_SECRET}",
          "scope": "tools:read tools:execute",
          "callback_port": 19876,
          "redirect_uri": "http://127.0.0.1:19876/callback"
        },
        "disabled": false,
        "codemode": true,
        "timeout": { "catalog": 60000 },
        "protocol": "auto"
      }
    }
  }
}
```

OAuth keys go snake_case: `clientId` → `client_id`, `clientSecret` → `client_secret`,
`callbackPort` → `callback_port`, `redirectUri` → `redirect_uri`.

**Container-specific MCP notes:**

- A `local` server running `npx …` needs `registry.npmjs.org` through the firewall —
already allowlisted.
- A `remote` server needs **its own host added to `allowed-domains.conf`**
(`mcp.context7.com` in the example above). This is the most likely "MCP worked on my
host, not in the container" failure.
- `oauth.callback_port` binds a **loopback** listener inside the container; loopback is
already accepted by `init-firewall.sh`, but the browser step of an OAuth flow has no
browser in a headless container — prefer `headers` with an API key, or `oauth: false`,
for MCP servers used from inside the sandbox.

### 6d. Permissions

Tool-keyed object → ordered array, and the action names change
(`bash` → `shell`, `task` → `subagent`, `write`/`patch` → `edit`). Order matters: the
first matching rule wins.

```jsonc
// V1
"permission": { "bash": { "git push *": "ask" }, "edit": "allow" }

// V2
"permissions": [
  { "action": "shell", "resource": "git push *", "effect": "ask" },
  { "action": "edit",  "resource": "*",          "effect": "allow" }
]
```

### 6e. Everything else

Singular → plural, and a few renames:


| V1           | V2                                                              |
| ------------ | --------------------------------------------------------------- |
| `agent`      | `agents`                                                        |
| `command`    | `commands`                                                      |
| `plugin`     | `plugins`                                                       |
| `snapshot`   | `snapshots`                                                     |
| `attachment` | `media`                                                         |
| `reference`  | `references`                                                    |
| `autoshare`  | `share: "auto" | "manual" | "disabled"`                         |
| `mode`       | primary agents in `agents` (add `mode: primary` to frontmatter) |


**Agents:** `prompt` → `system`, `disable` → `disabled`, `maxSteps` → `steps`,
`permission` → `permissions` (array form above), `temperature` / `top_p` and other
sampling options → `request.body`, `variant` folds into the model id as `#variant`.

**Commands:** frontmatter `subtask` → `subagent`; `model` + `variant` join with `#`.

**Plugins (hard break — the API itself changed):** tuple form → object form.

```jsonc
// V1
["opencode-example-plugin", ["./plugin/local.ts", { "enabled": true }]]
// V2
["opencode-example-plugin", { "package": "./plugin/local.ts", "options": { "enabled": true } }]
```

**Skills:** `{ "skills": { "paths": [...], "urls": [...] } }` → one ordered
`"skills": [...]` array.

**Compaction:** `preserve_recent_tokens` → `compaction.keep.tokens`, `reserved` →
`compaction.buffer`; `tail_turns` and `prune` are gone.

**Terminal config:** layered `tui.json(c)` → a single global
`~/.config/opencode/cli.json`, auto-migrated from V1 `tui.json` on first start. Since the
config dir is bind-mounted, that migration happens **on the host's file** the first time a
V2 container starts.

**Dropped with no equivalent:** `logLevel` (use `OPENCODE_LOG_LEVEL`), `server`, `lsp`
(parsed, not executed), top-level `subagent_depth` (→ `experimental.subagent_depth`), and
experimental `batch_tool`, `openTelemetry`, `primary_tools`, `continue_loop_on_deny`.

**Preferred on-disk locations** become `.opencode/agents/`, `.opencode/commands/`,
`.opencode/skills/<id>/SKILL.md`, `.opencode/plugins/`; the V1 singular/plural variants
still resolve.

## 7. Skills — no change needed *(confirmed in the V2 docs)*

V2 still auto-discovers, globally: `~/.config/opencode/skills`, `**~/.claude/skills**`,
`~/.agents/skills`; and per project: `.opencode/skills`, `.claude/skills`,
`.agents/skills`.

The image bakes the Playwright Agent CLI skill into `~/.claude/skills/playwright-cli`, so
it keeps working under V2 with no Dockerfile change. The README's claim at line ~793
("OpenCode also discovers skills there") remains true.

---

## 8. Useful V2 environment variables *(extracted from the binary)*

Worth adding to `.env.example` / the README:


| Variable                                                | Use                                                     |
| ------------------------------------------------------- | ------------------------------------------------------- |
| `OPENCODE_CONFIG_DIR`                                   | Override the config directory                           |
| `OPENCODE_CONFIG`                                       | Point at a specific config file                         |
| `OPENCODE_CONFIG_CONTENT`                               | Inline config JSON (handy for CI)                       |
| `OPENCODE_DB`                                           | Override the SQLite path (`:memory:` supported)         |
| `OPENCODE_LOG_LEVEL`                                    | Replaces the removed `logLevel` config field            |
| `OPENCODE_DISABLE_AUTOUPDATE`                           | Keep a pinned image from replacing its binary           |
| `OPENCODE_DISABLE_MODELS_FETCH` / `OPENCODE_MODELS_URL` | Offline or mirrored model catalog                       |
| `OPENCODE_SERVER_PASSWORD` / `OPENCODE_PASSWORD`        | Supply the service secret explicitly                    |
| `OPENCODE_API_KEY`                                      | Non-interactive credential                              |
| `OPENCODE_DISABLE_PROJECT_CONFIG`                       | Ignore in-repo config (useful for untrusted workspaces) |


---

## 9. Proposed work plan

1. **`Dockerfile`** — add an `OPENCODE_CHANNEL` build arg (default `v2`) switching the
   install URL; resolve `latest` through `update/api/latest` rather than trusting the
   script's stale `beta` default (§1); install with `--no-modify-path`; set
   `OPENCODE_DISABLE_AUTOUPDATE=1`; symlink the four XDG directories into
   `/workspace/.opencode` (§4).
2. **`allowed-domains.conf`** — add `models.opencode.ai` as a **commented-out** entry
   explaining what it is and what blocking it costs, and expand the `opencode.ai` comment
   to note that it doubles as the Zen inference endpoint (§2).
3. **Mounts** — delete both OpenCode mounts from `docker-compose.yml`,
   `devcontainer-opencode.json` and `devcontainer-opencode-dind.json`; the existing
   project mount already covers `./.opencode` (§4).
4. **`entrypoint-opencode.sh`** — create `/workspace/.opencode/{config,data,state,cache}`;
   warn when the project's `.gitignore` does not cover them; add a short V2 hint block
   (`/connect` to add a provider, `opencode service status`, `--standalone` for scripted
   runs).
5. **CI (`build.yml`)** — extend the OpenCode step beyond `--version`: `opencode debug
   paths`, then `opencode service start && opencode service status && opencode service
   stop`. Runs offline and catches a broken service or DB bootstrap.
6. **`README.md`** — V2 by default and how to pin V1
   (`OPENCODE_CHANNEL=v1 OPENCODE_VERSION=1.18.30`); the `./.opencode` layout and its
   `.gitignore` requirement; credentials now living in the database; the
   migration-in-place warning; that custom models need explicit `limit` and
   `capabilities` when the catalog host is blocked (§6b); and a link to the official
   migration guide.

### Open questions for the maintainer

- **Keep a V1 variant?** The build arg above makes it a one-line opt-in without doubling
  the CI matrix. Alternatively drop V1 entirely once V2 is confirmed working.
- **Pin the version?** Given the channel trap in §1, `latest` must at minimum be resolved
  through `update/api/latest`. Whether to go further and pin an exact version (e.g.
  `2.0.3`) is a separate call — it makes the weekly scheduled build fully reproducible at
  the cost of manual bumps.
- **Per-project vs. per-machine login.** The `./.opencode` layout means logging in once
  per project. Arguably the right default for a sandbox, but it differs from the Claude
  variants' shared `${HOME}/.claude`. §4 notes the one-line change to target
  `${HOME}/.opencode` instead if sharing one login matters more.
- **First-run migration for existing users.** Anyone already on the `opencode` variant has
  state in `~/.config/opencode` and `~/.local/share/opencode`. Worth a per-project README
  one-liner (`mkdir -p .opencode/{config,data} && cp -a ~/.config/opencode/. .opencode/config/
  && cp -a ~/.local/share/opencode/. .opencode/data/`), or should the entrypoint detect
  and offer it?
- **`.gitignore` ownership.** The four runtime subdirectories must be ignored, but
  `.opencode/` also holds committable project config (§6e). Should the entrypoint offer to
  append the four lines, or just warn?
