# Changelog

Gittan's builds are numbered: every push to main publishes `build-<n>`. The changes since the last build are listed under Unreleased and take the build's number when it is published.

## Unreleased

### New

- **About page.** Settings has an About page last, opened from Gittan > About Gittan on macOS and Tools > About Gittan elsewhere. It shows the icon, the name, the build number, a Check for Updates of its own that answers beside the button, and what Gittan runs on and with: the build, git, gh and the AI agent's versions, the system, the CPU, the widgetset, Free Pascal and the LCL. Copy puts those lines on the clipboard for a bug report. The page links to gittan.app and the source and lists the licenses. Opened on About, the dialog is centered over the main window.
- **Who commits.** The Commit section's header has a person icon before the AI sparkle. Its hint says which name and e-mail commits are made under, and whether they are this repository's own. Clicking it opens a dialog with the two fields and an "Only for this repository" option. The same dialog asks for a name and e-mail the first time you commit on a machine without them. Saving global values clears any repository-local ones, which would otherwise take precedence.

### Improved

- **Faster startup.** The 370-odd syntax lexers load in a background thread instead of before the window appears. A file shown before they are in waits for them, and the Syntax menu fills in when they are loaded. This was most noticeable on Windows.
- **Opening a repository no longer freezes the window.** The twenty-odd git commands an open takes run in a thread. The repository you open at start opens once the window is shown and painted. While a repository opens, the welcome view says "Opening <name>..." in place of its buttons and recent list. Compare With is built from the snapshot, so no git runs on the main thread for it.
- **Search box on GTK 3.** The search field in Gittan's own title bar is as tall as the entry needs, so it no longer paints over the bar's edges with only its rounded ends showing.

### Fixed

- **.pp files are highlighted as Pascal again.** Pascal and Puppet both claim the extension, and when the neighbouring files did not settle it, the file showed as plain text.
- **Ignore Whitespace holds through a refresh.** With View > Ignore Whitespace on, the line counts a background refresh brought in still counted whitespace-only changes until the next refresh you ran yourself. Opening a repository and the watcher's refreshes now count as the setting says.

### Building

- The settings dialog takes RT_GROUP_ICON from LCLType, so the Windows build no longer stops on an unknown identifier.
- `make.ps1 ide` puts the lazbuild arguments before `--build-ide=`, which lazbuild built with FPC 3.3.1 otherwise rejects.
