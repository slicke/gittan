# Changelog

## Unreleased

### Added
- A Project page, the sidebar's Project row and View > Project (Cmd+Option+7, Ctrl+Shift+7 elsewhere), shows what the repository is as a project: for each kind its files tell (Lazarus, Node, Rust, Go, Python), the file that told it, the project's version, and its dependencies with what the manifest asks for and what the lock file resolved it to (Cargo.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, uv.lock, poetry.lock, pdm.lock), the development, build and other groups under their own headings, each name a link to the package on its registry. The dependencies are compared with those at the newest tag: the heading says how many changed since it, and each row says added, removed or the old version → the new, so a release's dependency changes are read without opening a lock file's diff. Under them the checks worth a warning, with Add to .gitignore where that settles it, which also takes the files out of the index: a Lazarus session file (.lps), lib/ or backup/ committed; node_modules/, target/, a virtual environment or compiled bytecode committed; no lock file for a package.json, no go.sum, a binary crate's Cargo.lock not committed.
- The Commands page lists the commands of the project's own tools, told by the files at the root: cargo build, run, test, check, clippy, fmt and doc for a Cargo.toml, go build, run, test, vet and fmt for a go.mod, install, test, lint, fmt and typecheck for a pyproject.toml, setup.py or requirements.txt (through uv, poetry or pdm when their lock file is there, pytest, ruff, mypy, tox and nox when the project names them), and lazbuild for a Lazarus .lpi (fpc for a bare .lpr), each kind under its name beside the scripts and the Makefile targets (a package.json is a kind too, Node, with no commands of its own beyond its scripts). A section of `.gittan/commands.ini` named as one of them gives it a shortcut, and a line `project = rust, go` before the sections keeps the kinds to those named, `project = none` to none.
- A change can be put into the commit it belongs to, what the git absorb command does: the pill Put into Its Commit over a change in the change view (or Changes > Put Change into Its Commit...) finds the commit of this branch that last changed those lines, asks, and folds the change into it, and Commit > Put Changes into Their Commits... lists every change of the ticked files with its commit, or why it cannot be placed, and puts the ticked ones in at once. Each goes in as a fixup commit that a rebase folds in; what cannot be placed, a line older than the branch or a new file, stays in the work tree. Commits already pushed to the upstream, or on the default branch, are never rewritten, and Branch > Undo takes the rebase back.
- The globe at the right end of the tab bar shows your GitHub picture once GitHub has answered, with your login in its tooltip, "octocat on GitHub", and keeps it between starts. GitHub is asked when Gittan starts, so the picture and the GitHub view's lists are there before the view is first opened.

### Changed
- The Commands page groups the commands that share a name: build:run and build:test, as npm scripts are named, are listed under a heading build (with build itself first when there is one), and a Makefile's build-linux and build-win under build; the rest come first, as before. Each tile is one line, the name with its shortcut and the terminal button, and what it runs shows as its tooltip instead of under the name.
- The row that stands for the hidden lines of a diff is drawn as a row of its own instead of as text the syntax highlighting colored: a fold mark, "116 unchanged lines", the buttons ↓ 20, ↑ 20 and Show all (or Show for a short run), each lit under the mouse with a tooltip saying what it opens, and the name of the function the next change is in at the right end. The names no longer rebuild the view when they are found.
- Moving on from a large file whose syntax highlighting is still being worked out no longer waits for it to finish: the highlighting is cancelled (EControl and ATSynEdit_Ex updated).

## 0.14 (build-139, 2026-11-04)

### Changed
- A release is titled with its version alone, such as 0.14, and its notes list the changes from this changelog rather than the commits. The status bar's badge for a newer Gittan names that version, "0.14 available", not its build number.
- The File menu is split in four. File keeps the tabs, Open Repository, Open Recent, Clone, Init, the repository list and a file's Open and Save. Repository has Pull, Push, Force Push, Fetch, Remotes, Submodules, Issue Tracker, Clean, Apply Patches, Git LFS Locks and Open in Terminal. Commit has Commit, Write Commit Message, Split Changes into Commits, Sign Off, Skip Hooks, Name and Email, and the menu of the commit shown, which was in the Branch menu. Changes has Discard Change, Undo Discard, Leave Out of Commit, Resolve Conflict, Open in Merge Editor, Revert File and Undo Revert. The command palette names them by their new menus.
- One pair of words for what goes into a commit: a change or a file is included or left out. The pill over a change says Leave Out of Commit (it said Skip in Commit), the editor's menu Leave Selected Lines Out of Commit, the tree's menu Include All Files and Leave Out All Files (they said Tick All Files and Untick All Files), and Stash Included Files... and Fixup with the Included Files follow.
- An extension's alert, confirm and console.log dialogs are titled with the extension's name, Extension "name", not a bare "Extension" or a sentence about console.log.
- With nothing to commit, the Commit section folds to its header, "Commit · no changes", and unfolds again as changes come. Folding or unfolding it yourself still stands, and Commit > Commit... unfolds it, for an amend.

### Added
- Haiku (64-bit), Gittan-haiku-x86_64.tar.gz, with Qt 6 from HaikuPorts (`pkgman install libqt6pas`). Its tabs are in a row under the menu bar. Like the Windows on Arm build, a release does not wait for it.
- A native build for Windows on Arm, Gittan-windows-arm64.zip, built with a development version of Free Pascal (3.3.1). A release does not wait for it: it is added to the release when its build makes it. The x64 build still runs there, emulated.
- An extension can name the repositories it runs for with `@repos` in its manifest: roots such as `~/work/*` or remotes such as `github.com/you/*`. In other repositories its events are not raised and its commands are not in the menus or the command palette.
- The tab bar says that Cmd+P (Ctrl+P on Windows and Linux) opens the command palette, dimmed at its right end, until tabs fill that space.
- While a repository takes a moment to open, a busy line moves under "Opening ..." in the welcome view, as in the status bar during a fetch.

## 0.13 (build-138, 2026-11-03)

### Added
- The commit graph has First Parent and No Merges toggles beside Statistics: the first follows only the main line through each merge, the second leaves the merges out. Both are remembered.
- Export Files as Archive... in a commit's menu and a tag's menu writes the files of that commit as a zip or a tar.gz, every path under a folder named as the file.
- Notes on commits (git notes): Add Note... or Edit Note... in a commit's menu, the note shown under the message in the commit's card and searched by the graph's search field.
- References to issues in a commit's message are links in its card. File > Issue Tracker... sets the address of an issue and how a message refers to one, kept in the repository's config as the bugtraq keys other git clients read too; on GitHub, #123 links to the issue without any setup.
- A repository list in the welcome view, in folders of your own: drag a recent repository into it, or add one with + or a right-click, add every repository in a folder at once, and drag rows to order them or move them between folders. File > Repository List shows it, File > Add to Repository List adds the repository open. A right-click on a recent repository removes it from Recent, or clears Recent.
- Git flow: Branch > Git Flow sets it up, then starts and finishes feature, release and hotfix branches. Finishing merges the branch where it belongs, tags a release or hotfix and deletes the branch; after a conflict, finish again once the merge is committed. The setup is the git-flow command's own, so the two work on the same repository, and the command need not be installed.
- The row saying a branch is behind main also says whether merging main would go through cleanly, or which files would conflict, before you press Merge or Rebase. Needs git 2.38 or later.

### Changed
- The Pull requests page's filters sit in three menu chips, Review, Checks and More, under the presets instead of nine chips of their own; a chip with filters on names them ("Approved · Changes requested").
- Syntax highlighting of large files and diffs is faster: the parser (EControl) matches its rules in about two thirds of the time. Markdown emphasis right beside a code span is now marked, and in Pascal `of` is a keyword.

## 0.12 (build-137, 2026-11-02)

### Added
- Linux on arm64, such as Raspberry Pi OS (64-bit): a .deb, an .rpm and a .tar.gz beside the amd64 ones.

### Fixed
- The macOS disk image holds only Gittan and the Applications link; it also had a linux and a windows folder.
- Every package carries Gittan's license (GPLv3) as LICENSE.gittan, beside the JavaScript engine's; only the Windows installer had it. A NOTICE file beside them says what each license covers and credits the code built into Gittan.

## 0.11 (build-136, 2026-11-02)

### Added
- Extensions: JavaScript files in Gittan's extensions folder (Extensions > Open Extensions Folder) add commands to the Extensions menu, the command palette and the file and editor menus, watch what happens (a repository opened or changed, a commit, a push or a pull, which they can stop with a reason), read the repository, run git and other programs, make requests, and put cards under the lines of the change view, with a settings page of their own. Each file says what it needs, and Gittan asks before it loads one that wants to read the repositories, the network, programs or the settings. The engine is quickjs-ng, brought over from Trndi.

### Fixed
- Gittan no longer quits at once when Claude Code or Copilot ends before it has read the whole prompt Gittan gives it.
- On Windows, a user whose name has a letter outside ASCII (Björn) can commit, stash and revert again: Gittan's temporary files went to a folder that does not exist.
- On Windows, git's long outputs are read at speed; a megabyte took over ten seconds.

## 0.10 (build-135, 2026-10-31)

### Added
- A merge editor: a conflicted file in three panes, mine and theirs side by side above and the result under them, each conflict's lines picked one by one or typed by hand. It opens from the file header's Merge Editor, File > Open in Merge Editor (Cmd+Shift+E, Ctrl+Shift+E elsewhere) or a conflict's list, and stays on for the conflicted files shown after it until Close.
- Lines can be left out of a commit one by one: select them and choose Skip Selected Lines in Commit from the editor's menu, or File > Leave Change Out of Commit.
- The editor's menu over a change offers what the buttons over it do: Reviewed, Skip in Commit or Include in Commit, and Discard Change...
- Branch > Commit holds the commit menu of the commit shown (cherry-pick, revert, reset, interactive rebase, fixup, bisect), so those are in the menu bar and the command palette, not only behind a right click in the commit graph.
- An Edit menu with Undo, Redo, Cut, Copy, Paste and Select All, and Find, Find Next and Find Previous, moved there from Go.
- A Window menu on macOS (Minimize, Zoom, Next and Previous Tab, Bring All to Front) and a Help menu with the website, the release notes and a link to report an issue.
- Alt alone and F10 open the menu on Windows and Linux, as a menu bar does there.
- commit.template fills the message field, and Sign Off and Skip Hooks are in the File menu.
- When a pull finds the branch diverged, the question says what Merge and Rebase do to the history, and Always do this in this repository keeps the choice.
- A commit made behind the upstream gets a banner that offers Pull, and a pull that leaves commits to push offers Push.
- Go > Back from a commit picked in the commit graph opens the graph again, with its search and on that commit.
- The GitHub view has filters (with feedback, needs attention, waiting for a reviewer, approved, changes requested, checks failing or passing, no drafts, stale, asked of me, new to me) and presets of them, built in and saved by you. Each card shows where the review stands and how the checks do, and a check that fails for reasons of its own can be ignored by name.
- The Commit section says that ticked files go into the commit and that a click or Space leaves one out, and the commit graph says that a commit can be dragged onto the branch to merge it; both can be put away for good.
- Linux packages: a .deb and an .rpm, which install Gittan with its icon and desktop file, and make desktop for a checkout.
- A Windows installer, beside the zip.
- An Intel macOS build, Gittan-macos-intel.dmg.

### Changed
- A new application icon and logo: a diff window with red lines joined to green ones, a minus and a plus under them.
- Hide Unchanged Lines is on at first, so a large file opens on its changes. If you turned it off, it stays off.
- Gittan no longer says "staged": a commit takes each ticked file whole, as shown. A file that git add took only part of says "partly added with git add". File > Who Commits... is now Name and Email...
- A pull of a branch rewritten here since it was pushed asks first, with Force Push as the default, and the summary says the upstream's commits were replaced.
- Tabs of folders with the same name show their parent folders, such as Projects/trailhead and conflict/trailhead, and so does the window's title.
- Syntax is a submenu of View, beside Syntax Theme, and the language's name in the file header opens the same choices as a list with a filter.
- The file menu is shorter: the conflict items show only for a file in conflict, and the .git/info/exclude and Git LFS items are under More.
- The status bar's Abort button says Abort, rather than showing a bare cross.
- The list of changed files keeps its rows in the sidebar while Config and Submodules give way.
- The indexing shows its progress for every file, with a hint that says how far it has come.
- Refreshes and the Repository page do less work, which shows in large repositories.

### Fixed
- Switching between light and dark could crash Gittan.
- The GitHub view's Waiting for your review showed pull requests you had approved, or that were merged a moment before.
- Undo took a commit's changes out of the files when git stash or a plain git reset ran after it outside Gittan, also after many such resets.
- Undo Discard of a conflict's pick did not bring the conflict back with the git of macOS 14. With git older than 2.42 it still cannot bring back a conflict resolved as a deletion, and now says so.
- The Repository page counted no lines for a file that was binary in the last commit and is text now, and kept the last commit's count for a file marked assume-unchanged or skip-worktree.
- Hide Unchanged Lines, the context lines and Side by Side moved the caret off the line it was on, so the change navigator lost its count.
- After a commit from the time-lapse or history of a file the commit took, the old time-lapse stayed.
- A submodule's page showed the change navigator of the file shown before it.
- On macOS the application menu said "Hide Git Tree Analyzer  Navigator" rather than Hide Gittan.
- During a merge the Commit section showed a lone options chevron beside Abort.
- Under Wayland on KDE Gittan's window had a generic icon.
