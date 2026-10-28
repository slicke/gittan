# Changelog

## Unreleased

### Added
- Command palette: Go > Command Palette... (Cmd+P, Ctrl+P elsewhere) lists every action the menus offer right now, filtered by the words typed in any order, with the ones used last first. Undo, Redo and Stash stand to its left and Pull, Push and New Branch to its right.
- Undo and Redo in the Branch menu take back what moved the branches and do it again: a commit, an amend, a merge, a cherry-pick, a revert, a reset, a pull, a rebase, a switch, a branch made, deleted or renamed, whether Gittan or git elsewhere did it.
- Back and Forward (Cmd+[ and Cmd+], Alt+Left and Alt+Right elsewhere) step through the places a tab has shown, as a browser does, with chevrons in the title bar.
- Time-lapse: Go > Time-lapse (Cmd+Alt+H) plays the shown file through its versions, up to the newest 1000 commits, with play, pause, stepping and a track to drag.
- Worktrees: Branch > Worktrees... lists the repository's worktrees and opens one in a tab, and adds, locks, unlocks, removes and prunes them.
- Pull requests can be reviewed and merged from Gittan: approve, request changes, comment, merge, squash and merge, rebase and merge, and mark a draft ready, from the Pull Requests page, the GitHub view and the status bar's pull request chip.
- Fixup commits: Fixup with the Ticked Files on a commit in the commit menu, and Fold It In... to rebase it into its commit. The interactive rebase sorts fixup! and squash! commits as git rebase --autosquash does.
- Drag a commit onto HEAD's row in the commit graph to merge it.
- The commit graph's search takes change:<text> and change:/<regex>/ for the commits that add or remove a text.
- Several gh accounts: the Hosting page of the settings lists the accounts gh is logged in to and switches between them, and a switch made outside Gittan is noticed.
- The forge view shows the user's picture.
- The Repository page shows the repository's composition: code, test and documentation files and their lines. The summary's totals drop the same for the change.
- The image view and the Markdown preview show many more formats: WebP, PSD, XPM, PNM/PBM/PGM/PPM, CUR, XWD, OpenRaster, Paint.NET, LazPaint and PhoXo, and AVIF where libavif is installed.

### Changed
- Go to Symbol moves from Cmd+P to Cmd+Enter (Ctrl+Enter elsewhere).
- The editors draw their own scroll bars in the theme's colors on every platform, so on macOS the minimap and the last line reach the edges.
- In the Markdown preview a picture beside text sits in the line (a heading's icon, a row of badges) instead of standing as a block of its own.
- Merging a branch from the commit graph writes "Merge branch 'name'" rather than "Merge commit '<id>'".

### Fixed
- Dialogs such as questions and messages come up centered on the window, not on the primary screen.
- Searching the commit graph for an author with a letter such as ö, as the Repository page does, found no commits on macOS.
- An amend's check of locked Git LFS files failed with git older than 2.31.
- The settings file is made readable only by its owner before an API key is first written to it.
