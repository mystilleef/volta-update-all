# `volta-update-all`

A small POSIX-compliant `sh` script that updates all tools managed by
[Volta](https://volta.sh/).

## Features

- **Comprehensive updates:** Updates Node.js, `npm`, Yarn, `pnpm`, and
  global packages. Node.js targets `node@latest`; packages with
  lowercase `nightly` in installed versions target `@nightly`; all
  others target `@latest`.
- **Safe dry runs:** Preview changes with `--dry-run`.
- **Flexible exclusions:** Skip tools with `--exclude`.
- **User-local install:** Install to `~/.local/bin/volta-update-all`
  with `--install`.
- **pnpm-aware:** Skips `pnpm` unless you enable Volta's
  `VOLTA_FEATURE_PNPM=1` flag.
- **Scoped package support:** Handles names such as `@scope/pkg`.
- **Portable:** Runs with POSIX `sh`; no Bash-only features.
- **Tested:** Includes shell tests for core behavior and edge cases.

## Prerequisites

- Install [Volta](https://volta.sh/) and add it to your `PATH`.
- Provide standard Unix utilities: `awk`, `grep`, `sed`, `sort`, `cp`,
  `chmod`, and `mkdir`.
- **To update pnpm**, enable Volta's feature flag first:

  ```sh
  export VOLTA_FEATURE_PNPM=1
  ```

## Usage

### Option 1: Run from the repository

1. Make the script executable:

   ```sh
   chmod +x volta-update-all.sh
   ```

2. Run the script:

   ```sh
   ./volta-update-all.sh
   ```

### Option 2: Install to your user-local PATH

Install the script to `~/.local/bin/volta-update-all`:

```sh
./volta-update-all.sh --install
```

Then run it from anywhere:

```sh
volta-update-all
```

> Add `~/.local/bin` to your `PATH`.

### Flags

| Flag              | Description                                            |
| ----------------- | ------------------------------------------------------ |
| `--dry-run`       | Show what would change without making any installs.    |
| `--exclude a,b,c` | Comma-separated list of tool names to skip.            |
| `--install`       | Install the script to `~/.local/bin/volta-update-all`. |
| `-h`, `--help`    | Display the help message.                              |

### Examples

Update everything except `yarn`:

```sh
./volta-update-all.sh --exclude yarn
```

Perform a dry run:

```sh
./volta-update-all.sh --dry-run
```

Install the script, then run a dry run from your PATH:

```sh
./volta-update-all.sh --install
volta-update-all --dry-run
```

## Update targets

The script chooses update targets from the installed package state:

- Node.js always updates with `volta install --quiet node@latest`.
- Packages with installed version strings containing lowercase `nightly`
  update with `@nightly`.
- All other packages update with `@latest`.

Volta doesn't preserve the original install tag, so the script infers
nightly package targets from the current installed version string.

## Testing

Run the shell test suite with:

```sh
./tests/test-volta-update-all.sh
```

## License

The project uses the `MIT` License. See the `LICENSE` file for details.

---

_Created by `Dominik Roblek` © 2025_
