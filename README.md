# herdr-git-detail

A [herdr](https://herdr.dev) plugin that reports **rich git status** to the
herdr sidebar as per-category workspace tokens, so each can be colored
independently.

## Why

herdr's built-in `git_status` sidebar token shows only ahead/behind counts.
This plugin adds the detail starship-style prompts give you — modified,
staged, untracked, conflict, stash, and ahead/behind — so you can move git
out of your shell prompt and into the herdr UI without losing information.

The branch is **not** reported (herdr's native `branch` token already shows
it, so we avoid duplication). Each status kind is a separate token so herdr
can color them independently via inline style tables.

## Requirements

- herdr ≥ 0.7.0 (plugin + `workspace report-metadata` support)
- `git` on `PATH`
- `python3` on `PATH` (used to parse herdr's JSON CLI output)

macOS and Linux are supported. Windows is not (shell script).

## Install

### Link (local development)

```sh
git clone https://github.com/sfroment/herdr-git-detail ~/sfroment/herdr-git-detail
herdr plugin link ~/sfroment/herdr-git-detail
```

herdr runs the `[[startup]]` hook (`git-detail.sh watch`) on server start and
on live handoff. One background process polls every workspace's first pane
cwd every `GIT_DETAIL_INTERVAL` seconds (default 5) and reports the tokens.

### From GitHub

```sh
herdr plugin install sfroment/herdr-git-detail
```

## Configure the sidebar

Add the tokens to the spaces (workspace) rows in `~/.config/herdr/config.toml`.
Each entry can be an inline style table with `token`, `fg` (hex `#RGB` or
`#RRGGBB` only — named colors are rejected), `bold`, and `dim`:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  [
    { token = "branch", fg = "#89b4fa", bold = true },
    { token = "$git_modified",  fg = "#f9e2af" },
    { token = "$git_untracked", fg = "#94e2d5" },
    { token = "$git_staged",    fg = "#a6e3a1" },
    { token = "$git_conflict",  fg = "#f38ba8", bold = true },
    { token = "$git_ahead",     fg = "#a6e3a1" },
    { token = "$git_behind",    fg = "#f38ba8" },
    { token = "$git_stash",     fg = "#cba6f7", dim = true },
  ],
]
```

`branch` is herdr's native branch token; the `$git_*` tokens are custom
metadata this plugin reports. herdr separates adjacent tokens with `·` and
hides any that are empty, so the row stays compact on clean repos.

Reload to apply:

```sh
herdr server reload-config
```

## Token legend

Each token is empty (and disappears) when its count is zero.

| Token | Symbol | Meaning | Suggested color |
| --- | --- | --- | --- |
| `$git_modified` | `!n` | n modified (unstaged) files | yellow `#f9e2af` |
| `$git_untracked` | `?n` | n untracked files | cyan `#94e2d5` |
| `$git_staged` | `+n` | n staged files | green `#a6e3a1` |
| `$git_conflict` | `✗n` | n unmerged (conflict) files | red `#f38ba8` (bold) |
| `$git_ahead` | `⇡n` | n commits ahead of upstream | green `#a6e3a1` |
| `$git_behind` | `⇣n` | n commits behind upstream | red `#f38ba8` |
| `$git_stash` | `*n` | n stash entries | mauve `#cba6f7` (dim) |

## Plugin config (optional)

Copy the sample and edit:

```sh
cp config.example.sh config.sh
```

| Variable | Default | Description |
| --- | --- | --- |
| `GIT_DETAIL_INTERVAL` | `5` | Seconds between status passes |
| `GIT_DETAIL_SOURCE` | `git-detail` | Source label reported to herdr |

`config.sh` is loaded from `$HERDR_PLUGIN_CONFIG_DIR` (herdr-managed) or the
plugin root. See `config.example.sh`.

## Commands

The plugin exposes one script, `git-detail.sh`, with three modes:

| Mode | Description |
| --- | --- |
| `watch` | Background loop; one pass then sleep forever (startup hook) |
| `once` | Single pass over all workspaces (manual / debugging) |
| `status <dir>` | Print the computed status string for a repo (testing) |

```sh
# Debug a single repo
./git-detail.sh status ~/projects/my-repo

# Force a refresh of all workspaces
./git-detail.sh once
```

## How it works

1. On herdr server start, the `[[startup]]` hook runs `git-detail.sh watch`.
2. The script lists workspaces via `herdr workspace list`, resolves each
   workspace's cwd from its first pane (`herdr pane list --workspace`).
3. For each cwd, it runs `git status --porcelain=v2 --branch` and
   `git rev-list --count` to compute modified / staged / untracked / conflict
   / ahead / behind / stash counts.
4. It reports each count as a separate token via
   `herdr workspace report-metadata <id> --source git-detail --token git_modified=... --token git_untracked=... ...`.
5. herdr renders each token as `$git_*` in the sidebar, styled by the inline
   tables in `config.toml`.

One process per herdr server; it loops with `sleep` and exits when herdr
restarts it. No state is persisted between runs.

## License

GPL-3.0
