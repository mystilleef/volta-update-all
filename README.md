# Global **Volta** package updater

Update all `npm` packages managed by `volta`.

## Features

- Upgrades `node` via `node@latest`.
- Upgrades global packages from `volta list all`.
- Routes `nightly` versions to `@nightly`; others to `@latest`.
- Supports `--dry-run`, `--exclude`, `--install`, `--version`, and help.
- Handles scoped packages (`@scope/pkg`).
- Writes `volta-packages.txt` after successful non-dry-run upgrades.
- Resolves symlinks for snapshot reads/writes.

## Requirements

- [Volta](https://volta.sh/) on `PATH`.
- POSIX `sh`; no Bash extensions.
- Unix tools: `awk`, `grep`, `sed`, `sort`, `tr`, `mkdir`, `ln`,
  `dirname`, `basename`, `pwd`, `readlink`.

## Install

```sh
./volta-update-all.sh --install
```

Restores `volta-packages.txt` entries (`volta install tool@version`),
then symlinks into `~/.local/bin/volta-update-all`. Retain the
repository directory. Add `~/.local/bin` to `PATH` as needed.

## Usage

```sh
# Run upgrades
volta-update-all

# Preview
volta-update-all --dry-run

# Skip tools
volta-update-all --exclude yarn,pnpm

# From installed symlink
volta-update-all --dry-run
```

| Flag            | Action                                                 |
| --------------- | ------------------------------------------------------ |
| `--dry-run`     | Print planned `volta install` commands; skip writes.   |
| `--exclude a,b` | Skip comma-separated tool names.                       |
| `--install`     | Restore snapshot entries; symlink into `~/.local/bin`. |
| `--version`     | Print `0.1.0`.                                         |
| `-h`, `--help`  | Print help and exit.                                   |

## Update logic

- Source list: `volta list all --format=plain` → second field → strip
  version suffix → sort unique.
- Current version: `volta list --format=plain` → match tool → trailing
  version.
- Target resolution:
  - `node` → `node@latest`
  - Version contains lowercase `nightly` → `tool@nightly`
  - Other → `tool@latest`
- Failed `volta install` exits nonzero; previous snapshot preserved.

## Snapshot

- **Path**: script directory (one symlink resolution).
- **Format**: `tool@version` or `@scope/name@version`, one per line.
- Written after successful upgrade loop. Dry runs skip writes. Failed
  upgrades preserve prior file.
- Install restore: warns on missing snapshot; skips blank lines;
  installs each entry before symlink. Failure aborts install.

## Test

```sh
./tests/test-volta-update-all.sh
```

Covers help, version, dry run, exclusions, scoped packages, snapshots,
install restore, symlink paths, and helpers.

## License

**MIT**
