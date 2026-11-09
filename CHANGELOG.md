# Changelog

## Unreleased

### Added
- Signed commits show a shield in the commit graph and a line on the commit's card: filled with a check when git vouches for the signature, red for a bad or revoked one, outlined for a key not known here or a signature git could not check, which the card explains (an SSH signature wants an allowed signers file, an OpenPGP one gpg), rather than passing such a commit off as unsigned, as git's own letter does.
- Signing your own commits is set up in the Name and Email dialog: sign with an SSH key (ssh-keygen comes with macOS, Linux and Windows, and GitHub, GitLab and the others verify it) or a GPG key, pick the key from those found in ~/.ssh, the ssh agent or gpg, and Test signs a throwaway commit to show the chain works before anything is saved. Saving writes commit.gpgsign, tag.gpgSign, gpg.format and user.signingkey at the identity's scope, and for an SSH key sets up the allowed signers file, so your commits show as verified in Gittan too. When gpg is missing the dialog says where to get it.
- A commit signed with a key not known here can be trusted on GitHub's word: "Trust github.com's keys" on the commit's card, or Trust Signing Keys from github.com in its menu, asks GitHub who made the commit, fetches their GPG and SSH signing keys (a merge made on the web is GitHub's own key), puts the GPG keys into your gpg and the SSH keys into the allowed signers file, and shows those commits as verified, marked trusted through github.com. gpg's own trust settings are left alone; the fingerprints you trusted are kept in settings.json.
- Co-authors: the chevron beside Amend, and Commit > Co-authors..., open a list of the people you have credited before and the repository's recent authors to tick, or someone new as Name <e-mail>; each gets a Co-authored-by line in the commit's message. The label beside Amend shows who, and the choice lasts for one commit.
- Merging a branch asks how: a branch with no commits of its own since they parted offers Fast-forward, Merge Commit and Squash, one with commits of its own Merge and Squash, and the question says how many commits come in. A squash stages the changes with git's message in the Commit section, for one commit of yours.
- The merge editor can show the merge base, what both sides started from, as a pane between Mine and Theirs: Show Base in the header, when the conflict markers hold it. The merges, rebases, cherry-picks, reverts, pulls and stash applies Gittan runs now ask git to write the base into the markers (merge.conflictStyle zdiff3), unless the repository sets a style of its own.
- A changed image can be shown in more ways than side by side: Swipe lays the old and the new version over each other with a divider to drag, Onion Skin draws the new one over the old with an opacity to set, and Difference shows where two images of the same size differ. The pills under the captions choose, as does View > Image, and the choice is kept.
- An extension can ask with buttons of its own: `Gittan.ui.message({title, text, kind, buttons, default, cancel})` shows a message with an info, warning, error or question icon and up to six buttons, and gives the index of the one pressed. The extensions guide now describes the dialogs.
- The globe counts the pull requests waiting for your review, and GitHub is asked again every five minutes, so the count follows without opening the GitHub view.
- A card in the GitHub view has its next step as a button: Review on one waiting for your review (Review on GitHub when there is no clone to compare in), Merge with the three ways to merge on one of yours that is approved with its checks passing. Three dots open the card's menu, so what a right click offers is in sight, and the card's tooltip says where a click goes: compare in the open repository, open its clone, or open it on GitHub.
- The GitHub view has a search field (View > Find..., Cmd+F) that keeps the pull requests whose number, title, repository, author or branch hold the words typed, and works from the keyboard: Up and Down move from card to card, Return opens the one picked, the menu key opens its menu, Escape empties the search.
- The Batch tab works without GitHub: the globe is always there, and without a hosting service it opens Batch alone, with a note and a link to the Hosting settings.
- Commands of your own for a repository go in `.git/gittan/commands.toml`, which is never committed and needs no trust. The Commands page lists them under Personal, with Create… until the file exists, and the Config section lists the file. Its keys come before those of the committed files, and a table naming a script, target or tool command gives it your own key. A worktree shares the file with the main checkout.
- `.gittan/repo.toml` says what a repository wants, for everyone who clones it, and needs no trust as nothing in it runs. It can name the kinds of project (`project =`, before the line of the same name in commands.toml), give the issue tracker for the links in commit messages (`[issues]`, when git config names none), set the subject's lengths, a message template and sign-off by default, ask for Conventional Commits subjects with `types` and `scopes`, and list protected branches. The Commit section says when a subject is not of the listed types or a protected branch is checked out, without stopping the commit. The whole `.gittan` folder is described in docs/gittan-folder/README.md.
- A Haiku package, Gittan-haiku-x86_64.hpkg: `pkgman install Gittan-haiku-x86_64.hpkg` brings Qt 6 and git with it, and Gittan is then in the Deskbar menu under Applications. The tarball is still there. Like the tarball, a release does not wait for it.
- A FreeBSD build (amd64, GTK 3), Gittan-freebsd-amd64.tar.gz, for FreeBSD 15.1 or later with GTK 3 and git (`pkg install gtk3 git`). Like the Haiku and Windows on Arm builds, a release does not wait for it.

### Changed
- A dialog from an extension is headed by its own title, or the extension's name for `alert` and `confirm`, rather than by Extension "name"; a dim line with a puzzle piece beside the buttons says which extension it is from. What an extension logs with `console.log` shows the same way.
- The cards of the GitHub view are easier to scan: the pull request glyph is red while changes are asked for or checks fail and yellow while checks run, "Waiting for you" stands out in yellow, "Asked again" takes its place rather than standing beside it, the reviewers line no longer repeats who the chip names, and the link to a local clone is a dim line rather than a blue one.
- The filters of the GitHub view take one row: the presets, each with how many pull requests it leaves, then one Filter menu with the filters under their groups, then the order. The Filter chip names the filters on only while no preset does, so what is on is said once. Whether changes requested and failing checks need attention is set on the Hosting page of the settings rather than in the filter menus.
- On the Batch tab the buttons that do something (Check, Scan, Delete, Run) are filled, so they no longer look like the picked operation, and repositories with the same folder name are told apart by their parent folders ("clean/trailhead", "conflict/trailhead"), in the list and on the cards.
- In a narrow window a card's chips in the GitHub view go on a line of their own rather than cut the title to a few words.
- What an action on a pull request in the GitHub view did shows in a banner over the page ("Merged #12"), and a failure shows GitHub's words there rather than in a dialog.
- Syntax highlighting is worked out faster, by about a third on large Markdown and HTML files (EControl, ATSynEdit_Ex and ATSynEdit updated).

### Fixed
- The Batch tab's scan for gone branches no longer leaves a loose commit object in each repository for every branch that was not merged: the squash check compares patch ids instead of making a commit, so Maintenance no longer finds objects to pack that the scan itself left.
- On macOS the shown tab is filled all through, so the line where the sidebar's shade meets the editor's no longer shows across it.
- The GitHub view says when GitHub has more pull requests than the fifty last changed it lists, rather than leaving the rest out without a word.
- Your own pull requests no longer offer Approve and Request Changes, which GitHub refuses for the author; Comment is still there.
- Go to Symbol, Go to Symbol in Repository and Changed Symbols open their list under the file header, or under the title bar over the summary, instead of over the tabs.
- Go to Symbol, Changed Symbols and Callers of Changed Symbols say in the status bar that a file has to be shown first, rather than doing nothing.
- Go > Time-lapse plays the file of the Code History shown, rather than asking for a file.
- After a time-lapse, a file without changes no longer shows the time-lapse's counter in its header over the Revert and Save buttons.
- Escape closes the Code History and the time-lapse and goes back to what was shown before.
- Blame and Side by Side on a new file say in the status bar that it has no committed lines, rather than showing empty panes. A file added in a commit you compare still has its blame.
- File > New Tab and Repository List go to the empty tab when there is one, rather than opening another.
- The Settings window keeps its height on About instead of growing by a line.
- While two commits are compared, an edit of `.gittan/commands.toml` is picked up without a refresh.
- Back and Forward pass over the Pull Requests page when the hosting service has been turned off since, rather than stopping there with nothing shown.
- The GitHub view says you're not logged in when gh has no account, with Log In in Terminal (runs `gh auth login`) and Hosting Settings, rather than showing gh's message in red.

## 0.16 (build-141, 2026-11-06)

### Added
- Extensions can add to the GitHub view: a tab of their own after Batch, with rows that open a link or a repository and buttons that act on them; an operation on the Batch tab that runs once for each picked repository and says what it found, a card per repository; and commands in the view's own Extensions menu. A new permission, `forge`, lets an extension run the forge's tool with your account (`Gittan.forge.cli`, and `Gittan.forges.gh.run` for gh, which runs only where the forge is GitHub) without the `exec` permission: only gh's commands that read and change what is on GitHub (api, pr, issue, repo, run, workflow, release, search, label, status, cache), never an alias, a gh extension, its config or login, or anything that reads or writes a local file or starts another program, and `@forges github` in its manifest keeps it to repositories on GitHub and to GitHub's view. What an extension added is marked with a puzzle piece and says which extension it is from. The sample `forge-overview.js` shows a tab of your pull requests that have waited, the open pull requests and issues of each repository, and who you are logged in as.
- The GitHub view has a third tab, Batch, for work in several repositories at once. Pick repositories from the repository list and the recent ones (a folder's box picks all in it; the choice is kept), then Scan: each is fetched with --prune and its local branches whose branch on the remote was deleted are listed, each marked merged, squash-merged or not merged into the default branch. The merged ones are picked; Delete removes the picked branches after asking, and shows the commit each was at.
- The Batch tab shows one operation at a time, picked with a row of pills (Overview, Gone branches) and kept between starts, and the list of repositories folds to one line naming the picked ones once something is picked; a click on its heading, with a chevron as the welcome view's folders have, unfolds it.
- The Batch tab has an Overview of what is left undone in the picked repositories, read each time the tab is shown and with Check: a card per repository with changed and untracked files, stashes, commits not pushed and branches with commits on no remote (with their counts), a merge or rebase in progress, a detached HEAD or no remote at all. Nothing is fetched or changed, and a click on a card's head opens that repository.
- The Batch tab has an Identity check: who each picked repository commits as (name and e-mail, and whether it is set in the repository itself) and whether it signs its commits, grouped by identity. A repository is marked when the others of the same owner on the forge commit under another e-mail, such as a work repository committed to with a private address. A click on a repository opens it.
- The Batch tab has Maintenance: Scan finds, in each picked repository, a remote's HEAD left on the old default branch after it was renamed on the forge, worktrees whose folder is gone, and loose objects or packs enough to pack; Run follows the remote's new default branch locally (refs/remotes/origin/HEAD; the remote is not touched), forgets those worktrees and packs, for the tasks picked, and shows what each did.

### Changed
- `Gittan.gh.run` is now `Gittan.forges.gh.run`, which needs the `forge` permission instead of `exec` and runs only where the forge is GitHub; an extension that used it adds `forge` to `@perms`. `Gittan.exec.run("gh", ...)` still runs gh with `exec`.
- A new icon and logo: a flat window on a dark tile, a red line with a minus over a green line with a plus. The application icon, the dialogs' icon and the welcome view's wordmark follow. On Windows and Linux the icon is the window alone, without the tile, with a light rim so it shows on light and dark task bars, and the .ico has 20 and 40 pixel sizes for 125 % scaling.

### Fixed
- Removing a great many files from the repository at once no longer fails on a command line too long for the system.
- Putting changes into their commits no longer leaves the fixup commits on the branch when git refuses to start the rebase (a pre-rebase hook, an autostash that fails); they are taken back, and if that fails too, it says so. Taking them back no longer fails on a command line too long for the system when many files were picked.
- Deleting the branches whose branch on the remote was deleted no longer lists a branch that follows a local branch, and finds a branch that has the name of a tag.
- A gh path set in the settings that no longer exists counts as no gh, rather than failing each time gh runs.
- `make ide` (and `make.ps1 ide`) installs ATSynEdit and ATFlatControls in the IDE before rebuilding it, so a fresh Lazarus can open the forms in the designer.

## 0.15 (build-140, 2026-11-04)

### Added
- A Project page, the sidebar's Project row and View > Project (Cmd+Option+7, Ctrl+Shift+7 elsewhere), shows what the repository is as a project, each kind in a section of its own with what only that kind has. A Lazarus project shows its build modes, each with what it builds (the output, the platform and widgetset, the optimization, the debug info) and a Build button, and its packages with where each comes from: a package file in the repository, a submodule at a tag or commit, Lazarus itself, or nowhere, which a clone then has to install, and which submodules moved since the last tag. A Rust crate shows its edition, workspace, features and binaries (with a Run button), a Go module its Go version, toolchain and replace lines, a Node package its package manager (with an Install button), engines and workspaces, a Python project the Python it requires, its build backend and the programs it installs (with a Run button). The kinds are found from the files, or picked with the button at the top right of the page when the files do not tell it, kept per repository; the Commands page follows the pick. For every kind, the file that told it, the project's version, and its dependencies with what the manifest asks for and what the lock file resolved it to (Cargo.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, uv.lock, poetry.lock, pdm.lock), the development, build and other groups under their own headings, each name a link to the package on its registry. The dependencies are compared with those at the tag nearest HEAD (the one `git describe` names): the heading says how many changed since it, and each row says added, removed or the old version → the new, so a release's dependency changes are read without opening a lock file's diff. Under them the checks worth a warning, with Add to .gitignore where that settles it, which also takes the files out of the index: a Lazarus session file (.lps), lib/ or backup/ committed; node_modules/, target/, a virtual environment or compiled bytecode committed; no lock file for a package.json, no go.sum, a binary crate's Cargo.lock not committed.
- The Commands page lists the commands of the project's own tools, told by the files at the root: cargo build, run, test, check, clippy, fmt and doc for a Cargo.toml, go build, run, test, vet and fmt for a go.mod, install, test, lint, fmt and typecheck for a pyproject.toml, setup.py or requirements.txt (through uv, poetry or pdm when their lock file is there, pytest, ruff, mypy, tox and nox when the project names them), and lazbuild for each build mode of a Lazarus .lpi (fpc for a bare .lpr), each kind under its name beside the scripts and the Makefile targets (a package.json is a kind too, Node, with no commands of its own beyond its scripts). A table of `.gittan/commands.toml` named as one of them gives it a shortcut, and `project = ["rust", "go"]` before the tables keeps the kinds to those named, `project = "none"` to none.
- A change can be put into the commit it belongs to, what the git absorb command does: the pill Put into Its Commit over a change in the change view (or Changes > Put Change into Its Commit...) finds the commit of this branch that last changed those lines, asks, and folds the change into it, and Commit > Put Changes into Their Commits... lists every change of the ticked files with its commit, or why it cannot be placed, and puts the ticked ones in at once. Each goes in as a fixup commit that a rebase folds in; what cannot be placed, a line older than the branch or a new file, stays in the work tree. Commits already pushed to the upstream, or on the default branch, are never rewritten, and Branch > Undo takes the rebase back.
- The globe at the right end of the tab bar shows your GitHub picture once GitHub has answered, with your login in its tooltip, "octocat on GitHub", and keeps it between starts. GitHub is asked when Gittan starts, so the picture and the GitHub view's lists are there before the view is first opened.
- A command in `.gittan/commands.toml` can say more about itself. `description = "..."` is shown in its tooltip above what it runs. `confirm = true`, or a question of its own (`confirm = "Remove the build folder?"`), asks before it runs, from a click, its shortcut, the terminal button, Run Again or a Project page button that runs the same line. `hidden = true` leaves it off the page, and in a table named as a script, a Makefile target or a project's command it hides that one, for targets that are only steps of others. `run` can hold a line per system, `run = { windows = "...", unix = "..." }`, with `macos`, `linux` and `default` too; a command with no line for the system it is on shows dimmed and says so. A table that names a script or target gives it its description and question as well as its key.

### Changed
- A repository's own commands are written in TOML, in `.gittan/commands.toml`, instead of `.gittan/commands.ini`, which is no longer read: rename it and write each section as a table under `commands`, `[commands.test]` with `key = "T"`, and `command =` as `run = "..."`. A shell line can now hold quotes and run over several lines (`'...'` keeps a line as written, `"""` spans lines), and a name with a colon is quoted, `[commands."build:run"]`. More files go in `.gittan/commands/`: each `.toml` there is a section of its own on the Commands page, named after the file, and trusting the commands covers them all, so adding or changing one asks again. A file Gittan cannot read says why under its heading, with the line and column.
- The sidebar has no Recent row: it opened another repository rather than a page of this one. A new tab (Cmd+T) lists the recent repositories, as File > Open Recent does.
- The settings are kept in two JSON files, settings.json for the options you pick and state.json for what Gittan remembers (the window, the tabs, the recent repositories, what you trusted), instead of gittan.ini. The settings of an earlier build are not carried over: Gittan says so once, and you pick your options again. Each file is written through a temporary file, so a crash while saving leaves the previous one, and keys Gittan does not know are kept. An extension's storage keys now tell case, as a JavaScript object's do, and may hold `=`, `;` and `[`.
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
