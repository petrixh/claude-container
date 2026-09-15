# OpenCode V2 — Upgrade Requirements for This Container

Investigation for [#30](https://github.com/petrixh/claude-container/issues/30).
Reference: <https://opencode.ai/v2/docs/migrate-v1/>

**Status:** investigation only — no container files changed yet.

**Verified against:** OpenCode **v2.0.1** (current `latest` on the v2 channel) installed
from `https://opencode.ai/v2/install` on linux/arm64 (glibc), compared against the
**v1.18.30** binary. Everything marked *(verified)* was observed directly by running the
binary; everything else comes from the official docs.

---

## TL;DR

The container itself needs **four small changes** plus **one mount-strategy decision**:

| # | Change | Where | Severity |
|---|--------|-------|----------|
| 1 | Install URL `opencode.ai/install` → `opencode.ai/v2/install` | `Dockerfile` (opencode stage) | Required |
| 2 | Allow `models.opencode.ai` through the firewall | `allowed-domains.conf` | Required (already broken for v1) |
| 3 | Consolidate state into one `~/.opencode` bind mount (matches `~/.claude`) | `Dockerfile`, `docker-compose.yml`, `devcontainer-opencode*.json` | **Required — data-loss risk** |
| 4 | Document the new background-service model and `/connect` auth | `README.md`, `entrypoint-opencode.sh` | Recommended |

Everything else in the image keeps working unchanged: install directory, the
`/usr/local/bin/opencode` symlink, the baked-in Playwright Agent CLI skill, Java,
the firewall's loopback rule, and the CI `opencode --version` smoke test.

The heavy part of the V1→V2 migration is **user config schema**, not container plumbing.
This repo ships no `opencode.json`, so that lands on users — but the README should point
at it.

---

## 1. Distribution and install *(verified)*

| | V1 | V2 |
|---|---|---|
| Install script | `https://opencode.ai/install` | `https://opencode.ai/v2/install` |
| Artifact source | `github.com/anomalyco/opencode/releases` (+ `api.github.com` for the latest tag) | `registry.npmjs.org/@opencode/cli-<os>-<arch>/-/cli-<target>-<ver>.tgz` |
| Version metadata | GitHub releases API | `https://opencode.ai/update/api/beta/cli/npm` |
| npm package | `opencode-ai` | `@opencode/cli` |
| Docker image | — | `ghcr.io/anomalyco/opencode:<version>` |
| Binary size (linux/arm64) | 176 MB | 193 MB |
| `--version` output | `1.18.30` | `opencode v2.0.1` |

**Unchanged and therefore safe:**

- `INSTALL_DIR` is still `$HOME/.opencode/bin` — the Dockerfile's
  `ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode` still resolves.
- Flags are identical: `-v/--version <ver>`, `--binary <path>`, `--no-modify-path`.
  The existing `bash -s -- --version ${OPENCODE_VERSION}` invocation works as-is.
- Build prerequisites are the same (`curl`, `tar`, `sed`, `mkfifo`) — all present in
  `base-common`.

**Note:** V2 also drops a tiny `opencode2` shim next to the binary
(`exec "$(dirname "$0")/opencode" "$@"`). Harmless; no symlink needed for it.

### Suggested Dockerfile change

Make the channel a build arg so the v1 image stays reproducible:

```dockerfile
# OPENCODE_CHANNEL: "v2" (default) or "v1"
ARG OPENCODE_CHANNEL=v2
ARG OPENCODE_VERSION=latest

RUN if [ "${OPENCODE_CHANNEL}" = "v2" ]; then INSTALL_URL=https://opencode.ai/v2/install; \
    else INSTALL_URL=https://opencode.ai/install; fi \
    && if [ "${OPENCODE_VERSION}" = "latest" ]; then \
         su - node -c "curl -fsSL ${INSTALL_URL} | bash"; \
       else \
         su - node -c "curl -fsSL ${INSTALL_URL} | bash -s -- --version ${OPENCODE_VERSION}"; \
       fi \
    && ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode
```

Consider also `ENV OPENCODE_DISABLE_AUTOUPDATE=1` so a pinned image does not silently
replace its own binary on first run.

---

## 2. Firewall / allowed domains

The install path is *better* under V2: it now needs only `opencode.ai` and
`registry.npmjs.org`, both already allowlisted. `github.com` / `api.github.com` are no
longer required for installing OpenCode (they are still needed for `gh` and git).

**Gap found — `models.opencode.ai` is blocked.** The binary fetches its model catalog
from `https://models.opencode.ai/api.json`. `init-firewall.sh` resolves exact hostnames
only (no wildcards), and the two hosts do not share IPs *(verified)*:

```
opencode.ai        -> 172.65.90.20 .21 .22 .23
models.opencode.ai -> 172.66.173.149 104.20.32.17
```

This is **not new in V2** — v1.18 references the same host — so the current `opencode`
variant is already running with a blocked model catalog whenever the firewall is on.

Add to `allowed-domains.conf`:

```
opencode.ai
models.opencode.ai
```

Other hosts referenced by the V2 binary (`opencode.ai/config.json`, `/theme.json`,
`/v2/cli.json`, `/oauth/opencode/client.json`, `/update/api/…`) are all on `opencode.ai`
and already covered. The provider API list in the config file needs no change — it is
still "uncomment the providers you use".

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
- The shared secret lives in **`~/.config/opencode/service.json`**, is generated on first
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

| Selector | Path |
|---|---|
| `config` | `~/.config/opencode` (overridable via `OPENCODE_CONFIG_DIR`) |
| `data`   | `~/.local/share/opencode` |
| `state`  | `~/.local/state/opencode` |
| `cache`  | `~/.cache/opencode` |
| `bin`    | `~/.cache/opencode/bin` |
| `log`    | `~/.local/share/opencode/log` |
| `repos`  | `~/.local/share/opencode/repos` |
| `db`     | `~/.local/share/opencode/opencode.db` |
| `tmp`    | `/tmp/opencode` |

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

### Recommendation — one `~/.opencode` folder, bind-mounted

The bind mount stays. The problem is not the mount *type*, it is that OpenCode's state is
scattered across four XDG directories and one of them collides, file-for-file, with a host
v1 install.

The Claude Code variants already do this the right way — one folder, one mount:

```yaml
- ${HOME}/.claude:/home/node/.claude:cached      # docker-compose.yml, claude service
```

The OpenCode variant never followed that convention; it went straight to the XDG split
when it was added in `63caa64`. V2 is a good moment to fix it.

**Target: one host folder holding everything OpenCode, mounted at one path.**

```yaml
# docker-compose.yml — opencode and opencode-dind
volumes:
  - ${HOME}/.opencode:/home/node/.opencode:cached
```

```jsonc
// devcontainer-opencode*.json
"mounts": [
  "source=${localEnv:HOME}/.opencode,target=/home/node/.opencode,type=bind,consistency=cached"
]
```

Inside the image, the four XDG locations become symlinks into that one folder:

```dockerfile
RUN mkdir -p /home/node/.config /home/node/.local/share \
             /home/node/.local/state /home/node/.cache \
 && ln -s /home/node/.opencode/config /home/node/.config/opencode \
 && ln -s /home/node/.opencode/data   /home/node/.local/share/opencode \
 && ln -s /home/node/.opencode/state  /home/node/.local/state/opencode \
 && ln -s /home/node/.opencode/cache  /home/node/.cache/opencode \
 && chown -R node:node /home/node
```

The four subdirectories must be created by **`entrypoint-opencode.sh`**, not the
Dockerfile: `/home/node/.opencode` is a mount point, so anything the image puts there is
shadowed the moment the bind mount lands. The symlinks are deliberately left dangling in
the image and resolve on first start:

```bash
mkdir -p /home/node/.opencode/{config,data,state,cache}
```

On a first run this also means a brand-new `~/.opencode` on the host gets populated
automatically — no setup step for the user.

**Verified** — with those symlinks in place, starting the service and running `auth list`
puts everything in the one folder:

```
~/.opencode/config/service.json
~/.opencode/data/opencode.db
~/.opencode/data/log/opencode.log
~/.opencode/data/repos/
~/.opencode/data/shell/
~/.opencode/cache/bin/
~/.opencode/state/
```

`opencode debug paths` still reports the standard XDG paths — it resolves them through the
symlinks and neither notices nor cares.

#### Two image changes this requires

1. **Move the binary out of `/home/node/.opencode/bin`.** The installer hardcodes
   `INSTALL_DIR=$HOME/.opencode/bin` (both v1 and v2 — there is no `OPENCODE_INSTALL_DIR`
   override, despite what some third-party install guides claim). Mounting the host folder
   over it would replace the container's Linux binary with whatever the host has there —
   on a macOS host, a Darwin binary. Install, then relocate:

   ```dockerfile
   RUN su - node -c "curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path" \
    && mkdir -p /opt/opencode/bin \
    && mv /home/node/.opencode/bin/opencode /opt/opencode/bin/opencode \
    && rm -rf /home/node/.opencode \
    && ln -sf /opt/opencode/bin/opencode /usr/local/bin/opencode
   ```

   *(Verified: the v2 binary runs correctly from an arbitrary path.)*

2. **Pass `--no-modify-path`.** The installer appends
   `export PATH=$INSTALL_DIR:$PATH` to `.zshrc`, which currently puts
   `/home/node/.opencode/bin` **first** on PATH *(verified — it is in the image's `.zshrc`
   today)*. With the host folder mounted there, a stale or foreign host binary would
   shadow `/usr/local/bin/opencode` in every interactive shell.

#### Why not environment variables

Pointing all four `XDG_*_HOME` vars at a single root does collapse the paths — *verified*,
`debug paths` then reports one directory for config, data, state and cache. It was rejected
anyway: OpenCode spawns shell commands and MCP servers that **inherit its environment**, so
a container-wide (or even wrapper-scoped) `XDG_CONFIG_HOME` would also relocate `gh`, whose
config the image deliberately places at `~/.config/gh`. Symlinks keep the redirection where
it belongs — on OpenCode's directories only.

`OPENCODE_CONFIG_DIR` redirects the config directory alone *(verified)* and is still worth
documenting as an escape hatch, but it does not move the database.

#### What this gives you

- **One folder to keep track of**, named the same as the tool, next to `~/.claude`.
- **Survives `docker system prune` and container rebuilds** — it is a host directory.
- **Copy/move-able** — `rsync` `~/.opencode` to another VM and sessions, credentials and
  config all come with it. The project folder stays a separate mount, so code and history
  move independently.
- **The host's `~/.local/share/opencode` is never touched**, so a host v1 install keeps
  working and stays rollback-able — which is the whole point of §4b.

If the host already has OpenCode installed, its own binary is sitting in `~/.opencode/bin`
already. The container ignores it (that is what change 1 and 2 above are for), and it is
arguably where it belongs: one folder, everything OpenCode.

Remaining caveats, to document rather than engineer around:

- Running **two containers at once** against the same `~/.opencode` means two writers on
  one SQLite database. Give each its own folder, or accept single-container use.
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
from `1.18.30` to `opencode v2.0.1`, which nothing parses). The version line in
`entrypoint-opencode.sh` will print `opencode v2.0.1` — cosmetic only.

---

## 6. `opencode.json` breaking changes

This repo ships no `opencode.json`, but the container **bind-mounts the host's config
directory**, so a config that has not been migrated breaks the container exactly as it
breaks the host. Config file *read locations are unchanged*:

```
~/.config/opencode/opencode.json(c)      # global — this is what the container mounts
<project>/opencode.json(c)
<project>/.opencode/opencode.json(c)
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

Note the **`aisdk:` prefix** on AI SDK packages. Native V2 packages use their own path,
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

| V1 provider ID | V2 |
|---|---|
| `azure-cognitive-services` | `azure` |
| `google-vertex-anthropic` | `google-vertex` |

**Dropped provider fields (ignored in V2):** `id`, `whitelist`, `blacklist`.

### 6b. Models and variants

Per-model renames:

| V1 | V2 |
|---|---|
| `id` | `modelID` |
| `tool_call` | `capabilities.tools` |
| `modalities.input` / `.output` | `capabilities.input` / `capabilities.output` |
| `cache_read` / `cache_write` | `cost.cache.read` / `cost.cache.write` |
| `status: "deprecated"` | `disabled: true` |
| `variants: { … }` (object) | `variants: [ … ]` (array, each with an `id`) |

```jsonc
// V1
{ "variants": { "high": { "reasoningEffort": "high" } } }

// V2
{ "variants": [ { "id": "high", "settings": { "reasoningEffort": "high" } } ] }
```

A fuller V2 model entry:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "openai": {
      "models": {
        "gpt-5.2": {
          "modelID": "gpt-5.2",
          "name": "GPT-5.2 Coding",
          "family": "gpt-5",
          "capabilities": { "tools": true, "input": ["text"], "output": ["text"] },
          "cost": {
            "input": 3.0,
            "output": 15.0,
            "cache": { "read": 0.3, "write": 3.75 }
          },
          "limit": { "context": 128000, "input": 128000, "output": 4096 },
          "variants": [ { "id": "batch", "body": { "service_tier": "flex" } } ]
        }
      }
    }
  }
}
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

Servers move down one level under **`mcp.servers`**, `enabled` inverts to **`disabled`**,
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

| V1 | V2 |
|---|---|
| `agent` | `agents` |
| `command` | `commands` |
| `plugin` | `plugins` |
| `snapshot` | `snapshots` |
| `attachment` | `media` |
| `reference` | `references` |
| `autoshare` | `share: "auto" \| "manual" \| "disabled"` |
| `mode` | primary agents in `agents` (add `mode: primary` to frontmatter) |

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

V2 still auto-discovers, globally: `~/.config/opencode/skills`, **`~/.claude/skills`**,
`~/.agents/skills`; and per project: `.opencode/skills`, `.claude/skills`,
`.agents/skills`.

The image bakes the Playwright Agent CLI skill into `~/.claude/skills/playwright-cli`, so
it keeps working under V2 with no Dockerfile change. The README's claim at line ~793
("OpenCode also discovers skills there") remains true.

---

## 8. Useful V2 environment variables *(extracted from the binary)*

Worth adding to `.env.example` / the README:

| Variable | Use |
|---|---|
| `OPENCODE_CONFIG_DIR` | Override the config directory |
| `OPENCODE_CONFIG` | Point at a specific config file |
| `OPENCODE_CONFIG_CONTENT` | Inline config JSON (handy for CI) |
| `OPENCODE_DB` | Override the SQLite path (`:memory:` supported) |
| `OPENCODE_LOG_LEVEL` | Replaces the removed `logLevel` config field |
| `OPENCODE_DISABLE_AUTOUPDATE` | Keep a pinned image from replacing its binary |
| `OPENCODE_DISABLE_MODELS_FETCH` / `OPENCODE_MODELS_URL` | Offline or mirrored model catalog |
| `OPENCODE_SERVER_PASSWORD` / `OPENCODE_PASSWORD` | Supply the service secret explicitly |
| `OPENCODE_API_KEY` | Non-interactive credential |
| `OPENCODE_DISABLE_PROJECT_CONFIG` | Ignore in-repo config (useful for untrusted workspaces) |

---

## 9. Proposed work plan

1. **Dockerfile** — add `OPENCODE_CHANNEL` build arg, default `v2`, switching the install
   URL. Optionally set `OPENCODE_DISABLE_AUTOUPDATE=1`.
2. **`allowed-domains.conf`** — add `models.opencode.ai` (fixes v1 too).
3. **Mounts + image layout** — consolidate onto a single `${HOME}/.opencode` bind mount
   in `docker-compose.yml`, `devcontainer-opencode.json` and
   `devcontainer-opencode-dind.json`; in the `Dockerfile`, symlink the four XDG
   directories into it, relocate the binary to `/opt/opencode/bin`, and install with
   `--no-modify-path`. See §4.
4. **`entrypoint-opencode.sh`** — add a short V2 hint block: `/connect` to add a provider,
   `opencode service status`, and `--standalone` for scripted runs.
5. **CI (`build.yml`)** — extend the OpenCode step beyond `--version`:
   `opencode debug paths`, then `opencode service start && opencode service status &&
   opencode service stop`. Runs offline, catches a broken service/DB bootstrap.
6. **README** — update the OpenCode variant section: V2 by default, how to pin V1
   (`OPENCODE_CHANNEL=v1 OPENCODE_VERSION=1.18.30`), the credentials-are-in-the-database
   change, the migration-in-place warning, and a link to the official migration guide.

### Open questions for the maintainer

- **Keep a V1 variant?** The build arg above makes it a one-line opt-in without doubling
  the CI matrix. Alternatively drop V1 entirely once V2 is confirmed working.
- **Pin the version?** `OPENCODE_VERSION=latest` on the v2 channel currently resolves via
  a `beta`-named metadata endpoint. Pinning (e.g. `2.0.1`) would make weekly scheduled
  builds reproducible, at the cost of manual bumps.
- **First-run migration for existing users.** Anyone already using the `opencode`
  variant has state in `~/.config/opencode` and `~/.local/share/opencode`. Worth a
  README one-liner (`mkdir -p ~/.opencode/{config,data} && cp -a ~/.config/opencode/.
  ~/.opencode/config/ && cp -a ~/.local/share/opencode/. ~/.opencode/data/`), or should
  the entrypoint detect and offer it?
- **`cli.json` migration touches the host config.** The first V2 start rewrites
  `tui.json` → `cli.json` inside the bind-mounted config dir. Acceptable, or should the
  README tell users to back up `~/.config/opencode` before the first V2 run?
