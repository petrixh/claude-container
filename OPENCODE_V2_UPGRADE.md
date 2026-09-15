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
| 3 | Point the data bind mount at a **dedicated** host dir, not the one v1 uses | `docker-compose.yml`, `devcontainer-opencode*.json` | **Required — data-loss risk** |
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

### Recommendation — keep the bind mount, change the path

A bind mount is the right call here and should stay: it survives `docker system prune`,
and it moves with the workspace when the whole VM is rebuilt or migrated, which a named
volume does not. The problem is not the mount *type*, it is that the container and a host
v1 install are aimed at the **same directory and the same file name**.

So: keep bind-mounting, but give the container its **own** data directory.

```yaml
# docker-compose.yml — opencode and opencode-dind
volumes:
  - ${HOME}/.config/opencode:/home/node/.config/opencode:cached                       # unchanged
  - ${OPENCODE_DATA_DIR:-${HOME}/.local/share/opencode-container}:/home/node/.local/share/opencode:cached
```

```jsonc
// devcontainer-opencode*.json
"mounts": [
  "source=${localEnv:HOME}/.config/opencode,target=/home/node/.config/opencode,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.local/share/opencode-container,target=/home/node/.local/share/opencode,type=bind,consistency=cached"
]
```

This keeps every property that made the bind mount attractive:

- **Survives `docker system prune`** — it is a host directory, not a volume.
- **Moves between VMs** — `rsync` the host directory and session history comes along.
- **Backed up by whatever already backs up `$HOME`.**

…while removing the hazard:

- **No in-place migration of a v1 database.** The host's `~/.local/share/opencode` is
  left alone, so a host v1 install keeps working and can be rolled back to.
- **One writer.** The container's v2 service is the only process on that DB.

The config directory **stays external and bind-mounted as-is** — `opencode.json`, agents,
commands, skills and the service password keep coming from the host, which is the point
of the variant.

Caveats to document rather than engineer around:

- Running **two containers at once** against the same `OPENCODE_DATA_DIR` reintroduces
  concurrent SQLite access. Give each its own directory, or accept single-container use.
- On **Docker Desktop for macOS/Windows**, SQLite WAL shared memory over virtiofs /
  gRPC-FUSE bind mounts is unreliable. On a Linux VM (the usual setup here) this is a
  non-issue. If it does bite, `OPENCODE_DB` can move just the database onto a container
  path while the rest of the data dir stays on the bind mount.

If a user genuinely wants the container to inherit host credentials and history, the
recipe is a one-time `cp -a ~/.local/share/opencode ~/.local/share/opencode-container`
**before** first v2 start — a copy, never a shared path.

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
3. **Mounts** — repoint the data bind mount at a dedicated host directory
   (`${OPENCODE_DATA_DIR:-$HOME/.local/share/opencode-container}`) in `docker-compose.yml`,
   `devcontainer-opencode.json` and `devcontainer-opencode-dind.json`. Keep the config
   bind mount and the bind-mount *type* — see §4.
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
- **Default data directory name.** `~/.local/share/opencode-container` is a guess;
  anything that is not the path a host v1 uses works.
- **`cli.json` migration touches the host config.** The first V2 start rewrites
  `tui.json` → `cli.json` inside the bind-mounted config dir. Acceptable, or should the
  README tell users to back up `~/.config/opencode` before the first V2 run?
