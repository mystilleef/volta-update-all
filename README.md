# `volta-update-all`

POSIX `sh` script that updates every tool managed by
[Volta](https://volta.sh/).

## Features

- Updates Node.js (`node@latest`), `npm`, and all global packages.
  Nightly packages (`nightly` in version string) target `@nightly`;
  others target `@latest`.
- `--dry-run` previews changes without installing.
- `--exclude` skips comma-separated tool names.
- `--install` symlinks to `~/.local/bin/volta-update-all`.
- Handles scoped packages (`@scope/pkg`).
- Successful upgrades write a `volta-packages.txt` snapshot; `--install`
  restores from it.
- POSIX `sh` — no Bash-only features.
- Includes shell test suite.

## Prerequisites

- [Volta](https://volta.sh/) on your `PATH`.
- Standard Unix utilities: `awk`, `grep`, `sed`, `sort`, `mkdir`.

## Usage

### Run from the repository

```sh
chmod +x volta-update-all.sh
./volta-update-all.sh
```

### Install to `~/.local/bin`

Symlinks `~/.local/bin/volta-update-all` → the script. Restores from
`volta-packages.txt` if present before symlinking.

```sh
./volta-update-all.sh --install
volta-update-all
```

Add `~/.local/bin` to your `PATH` and keep the cloned `repo`.

### Flags

| Flag              | Description                                         |
| ----------------- | --------------------------------------------------- |
| `--dry-run`       | Show changes without installing.                    |
| `--exclude a,b,c` | Comma-separated tool names to skip.                 |
| `--install`       | Install symlink to `~/.local/bin/volta-update-all`. |
| `--version`       | Print version and exit.                             |
| `-h`, `--help`    | Display help.                                       |

### Examples

```sh
# Skip yarn
./volta-update-all.sh --exclude yarn

# Dry run
./volta-update-all.sh --dry-run

# Install then dry run from PATH
./volta-update-all.sh --install
volta-update-all --dry-run
```

## Update targets

Targets derive from the installed package state:

- Node.js → `volta install --quiet node@latest`.
- Packages with lowercase `nightly` in the installed version →
  `@nightly`.
- All other packages → `@latest`.

Volta doesn't preserve the original install tag, so nightly targets
infer from the current installed version string.

## Snapshot and restore

Non-dry-run upgrades write `volta-packages.txt` next to the script after
every fully successful run. Each line: `tool@version` (preserving
`@scope/name@version`).

- **Placement**: Resolved through symlinks—
  `~/.local/bin/volta-update-all` writes to the cloned `repo`.
- **Dry-run**: Never touches the snapshot file.
- **Failure**: Any failed upgrade exits nonzero; previous snapshot stays
  intact.
- **Success**: `volta list` output replaces the previous snapshot.

### Install-time restore

`--install` checks for `volta-packages.txt` next to the script before
symlinking.

- **Present**: Each non-blank entry restores via
  `volta install tool@version`. Symlink installs after all entries
  succeed.
- **Absent**: Warns, then proceeds with install.
- **Restore failure**: Exits nonzero—no silent partial bootstrap.

Commit `volta-packages.txt` so clones reproduce the same `toolchain` via
`--install`.

## Testing

```sh
./tests/test-volta-update-all.sh
```

## License

`MIT`. See `LICENSE`.

---

_Created by `Dominik Roblek` © 2025_
