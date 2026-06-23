# Agent

## Commands

- **Install:** `./volta-update-all.sh --install`
- **Test:** `./tests/test-volta-update-all.sh`

## Rules

- Adhere to the shell script guide in kb when editing shell scripts.
- Adhere to the shell command guide in kb when running shell scripts.

## Gotchas

- Resolve symlinks for all paths.
- Preserve function declaration format in `volta-update-all.sh` (regex
  `^name()` and `^}`). The test harness extracts functions via `sed`.
- Failed upgrades skip writing `volta-packages.txt` to protect the
  previous snapshot.
- Dry runs bypass writing the snapshot file.
- `--install` symlinks `~/.local/bin/volta-update-all` to the repository
  script. Keep the repository directory post-installation.
