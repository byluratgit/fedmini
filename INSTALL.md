INSTALLATION and SAFETY NOTES
=============================

Prerequisites
-------------

- Fedora system (the script checks /etc/os-release for "Fedora").
- Run as a regular user with sudo privileges (do NOT run as root).
- Active internet connection during the run.
- Familiarity with making system changes and rebooting.

What the script does
---------------------

- Configures DNF settings (`/etc/dnf/dnf.conf`).
- Enables COPR repositories required for `niri` and Noctalia.
- Installs packages via `dnf` (may install many packages and change targets).
- Enables `lightdm` and sets the default target to `graphical.target`.
- Writes user-level configuration under `~/.config` for `niri` and portals.
- Appends a block to `~/.config/niri/config.kdl` and creates a wayland session file.

Safety and rollback
-------------------

- The script uses `sudo` for system changes. If something goes wrong you can:
  - Inspect `/etc/dnf/dnf.conf` to revert the `installonly_limit` or `max_parallel_downloads` entries.
  - Remove COPR repositories with `sudo dnf copr disable <owner>/<repo>`.
  - Uninstall packages installed by the script with `sudo dnf remove <package>`.
  - Remove the appended `niri` block in `~/.config/niri/config.kdl` if needed.

Usage
-----

Run the script after reading the file and the warnings:

```bash
bash install.sh --help   # show help
bash install.sh          # run interactively (prompts)
```

Notes
-----

- The script may install software from COPR repositories and packages marked as beta.
- Review the script before running it on a production machine.
