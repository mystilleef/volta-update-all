# volta-update-all

A small POSIX-compliant `sh` script to update all tools managed by [Volta](https://volta.sh/).

## Features

- **Comprehensive updates:** Updates Volta-managed tools such as Node.js, npm, Yarn, pnpm, and installed global packages based on your configured channels (`lts` or `latest`).
- **Safe dry runs:** Preview potential changes with `--dry-run` before applying them.
- **Flexible exclusions:** Skip specific tools with `--exclude`.
- **User-local install:** Install the script to `~/.local/bin/volta-update-all` with `--install`.
- **pnpm-aware:** Automatically skips pnpm unless `VOLTA_FEATURE_PNPM=1` is enabled.
- **Scoped package support:** Correctly handles package names such as `@scope/pkg`.
- **Portable:** Runs with POSIX `sh`; no Bash-only features required.
- **Tested:** Includes a shell test suite for core behavior and edge cases.

## Prerequisites

- [Volta](https://volta.sh/) must be installed and available in your `PATH`.
- Standard Unix utilities used by the script: `awk`, `grep`, `sed`, `sort`, `head`, `expr`, `cp`, `chmod`, and `mkdir`.
- **To update pnpm**, enable Volta's feature flag before running the script:

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

> Ensure `~/.local/bin` is in your `PATH`.

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

## Configuration

You can configure the update channels by modifying the variables at the top of the script:

- `NODE_CHANNEL`: The update channel for Node.js. Defaults to `lts`. Change it to `latest` for the newest Node.js version.
- `DEFAULT_CHANNEL`: The update channel for all other tools. Defaults to `latest`.

## Testing

Run the shell test suite with:

```sh
./tests/test-volta-update-all.sh
```

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

_Created by Dominik Roblek © 2025_
