# herdr-git-detail

A [herdr](https://herdr.dev) plugin that reports **rich git status** to the
herdr sidebar as a custom `$git_detail` workspace token.

## Why

herdr's built-in `git_status` sidebar token shows only ahead/behind counts.
This plugin adds the detail starship-style prompts give you — modified,
staged, untracked, conflict, stash, and ahead/behind — so you can move git
out of your shell prompt and into the herdr UI without losing information.

The token format:

```
<branch>  !<modified> ?<untracked> +<staged> ✗<conflict> ⇡<ahead> ⇣<behind> *<stash>
```

When the tree is clean, the token shows the branch alone (or `clean` if
detached/empty). Examples:

```
main
feature/x  !3 ?1 +2 ⇡1
(detached)  clean
```

## Requirements

- herdr ≥ 0.7.0 (plugin + `workspace report-metadata` support)
- `git` on `PATH`
- `python3` on `PATH` (used to parse herdr's JSON CLI output)

macOS and Linux are supported. Windows is not (shell script).

## Install

### Link (local development)

```sh
git clone <this repo> ~/sfroment/herdr-git-detail
herdr plugin link ~/sfroment/herdr-git-detail
```

herdr runs the `[[startup]]` hook (`git-detail.sh watch`) on server start and
on live handoff. One background process polls every workspace's first pane
cwd every `GIT_DETAIL_INTERVAL` seconds (default 5) and reports `$git_detail`.

### From GitHub

```sh
herdr plugin install sfroment/herdr-git-detail
```

## Configure the sidebar

Add `$git_detail` to the spaces (workspace) rows in `~/.config/herdr/config.toml`:

```toml
[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "$git_detail"],
]
```

`branch` is herdr's native branch token; `$git_detail` is the custom token this
plugin reports. You can drop `git_status` (native ahead/behind) since
`$git_detail` already includes `⇡`/`⇣`.

Reload to apply:

```sh
herdr server reload-config
```

## Plugin config (optional)

Copy the sample and edit:

```sh
cp config.example.sh config.sh
```

| Variable | Default | Description |
| --- | --- | --- |
| `GIT_DETAIL_INTERVAL` | `5` | Seconds between status passes |
| `GIT_DETAIL_CLEAN` | `clean` | Text shown when the tree is clean |
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
4. It reports the result with
   `herdr workspace report-metadata <id> --source git-detail --token git_detail=...`.
5. herdr renders the token as `$git_detail` in the sidebar.

One process per herdr server; it loops with `sleep` and exits when herdr
restarts it. No state is persisted between runs.

## Token legend

| Symbol | Meaning |
| --- | --- |
| `!n` | n modified (unstaged) files |
| `?n` | n untracked files |
| `+n` | n staged files |
| `✗n` | n unmerged (conflict) files |
| `⇡n` | n commits ahead of upstream |
| `⇣n` | n commits behind upstream |
| `*n` | n stash entries |

## License

MIT
