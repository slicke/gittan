# Changelog

## Unreleased

### Fixed

- Reload Extensions clicked again while extensions are still being loaded or unloaded is ignored, instead of unloading them a second time while the first reload is under way.
- An extension can have at most 64 calls such as `git.run` or `fetch` under way at once; more are rejected. Before, thousands at once could use up the threads, after which every reload waited a second and quitting two seconds for tasks that did not exist.
- An extension file removed or changed while Gittan loads it no longer stops the extensions after it from loading with an error dialog, and the code that runs is the code whose permissions you approved, not the file read again.
- A program an extension runs (`git.run`, `exec.run`, the forge's tool) is stopped when the extensions are reloaded, after ten minutes, or once it has written 32 MB, instead of keeping a thread for the whole session and making every reload and quit wait for it.
- An extension can no longer register a Batch operation or a forge tab around `Gittan.batch` and `Gittan.forgeTabs`, which left a run on "Running on 1 of N…" or a tab on Loading for good.
- An extension whose promise continuation was stopped, or whose promise was rejected with a value that cannot be shown, no longer makes the next call of another extension fail with that error, which could let a commit go ahead past the other extension's `commit.before` check.
- An error thrown by an extension's command, event listener (such as a `commit.before` check), timer or unload hook is now shown in a banner under the extension's name; it went nowhere. `Gittan.log` now writes to the extension console, where it went nowhere either and slowed down the more was logged.
- Reloading extensions while one of them waits on git, a program, the forge or a fetch no longer keeps that extension's memory; after a few such reloads every extension failed with "out of memory" until Gittan was restarted.
- An extension stuck in a loop that splits a long text or parses JSON over and over is stopped after 10 seconds, instead of freezing Gittan for good (at every start, when the loop runs as the extension loads); a dialog the extension shows does not count toward the 10 seconds.
- Quitting or leaving a repository no longer waits for a background fetch, or a fetch you started, from a server that does not answer; the fetch is given up. Fetch, pull and push over ssh give up a server that stays silent for a minute or takes over 30 seconds to connect, and over HTTP a transfer that has stalled for a minute, unless your own ssh command or `http.lowSpeedLimit`/`lowSpeedTime` settings say otherwise. A pull request fetch now uses the same ssh settings as the other fetches.
- The commit graph with No Merges no longer takes seconds and hundreds of megabytes on a long history (20,000 commits took 44 s); it lays out at once.
- A large changed or untracked file no longer slows down every poll of the repository and every commit, stash or switch: its content is hashed only while it is being written (a 512 MB file cost 1.7 s a poll, now 40 ms), and those commands no longer wait for a poll under way.
- Showing a large diff or file no longer slows down with its size: git's output is read without copying all of it for every piece (a 130 MB diff took 7.5 s, now a fraction of a second).
- The Project page of a Lazarus repository no longer follows symbolic links when it looks for packages; a few committed links to the repository itself made it hang for minutes.
- Showing a file with many changed blocks no longer takes time that grows with the square of its length (a 50,000-line diff took 2.4 s on every show and refresh, now a few milliseconds).
- Two Gittan windows started as separate processes no longer undo each other's settings when they save: an extension turned off or its permissions reset, a trusted key or commands file and other changes made in one are kept when the other saves, and the settings dialog saves as it closes.
- A signed commit shows as verified only when the key stands for the committer's e-mail; a commit signed with someone's trusted key but made out to another committer now says "Signed by X, not by the committer Y" with an outlined shield. A key trusted from GitHub before this asks to be trusted again, so its verified e-mails are kept, and the card names the GitHub user rather than the key's own user id.
- A `.gittan/repo.toml` or commands file with a dotted key or table header tens of thousands of parts long is refused instead of ending Gittan when the repository opens.
- A Lazarus `.lpi` or `.lpk` nested thousands of levels deep is not read, instead of ending Gittan when the repository opens.
- JSON an extension passes nested thousands of levels deep is refused instead of ending Gittan.
- The issue expression of a cloned `.gittan/repo.toml` links issues only after you choose Use It in the banner that offers it, since an expression such as `(a+)+b` could make Gittan hang on a commit's message.
- Add to .gitignore, Track with Git LFS and the editor no longer write through a `.gitignore`, `.gitattributes` or other repository file that is a committed symbolic link, which could point at `.git/config` or outside the clone; the Config section leaves such links out.
- The Project page opens only web links, so a Cargo.toml whose repository is a `file:`, `smb:` or similar URL can no longer start a program with a click.
- An interactive rebase, a rebase onto another branch or a reset no longer goes ahead when the branch moved or was switched while you were asked, where a commit made meanwhile was dropped; a tag made at HEAD goes on the commit the question named.
- Undo of a mixed reset (Reset to Here › Mixed, or `git reset HEAD~1`) works, where git always refused it as "not uptodate" or over an untracked file. It refuses a file you have staged since with other content, rather than replace what you staged.
- A tag without a message is made when signing is on, instead of failing with "Terminal is dumb" or waiting for an editor, and no git command Gittan runs starts an editor any more.
- On Windows and Linux above 100 % scaling, the dialogs (Settings, Interactive Rebase, Remotes, Patches, Identity, Clone, Clean and the others) have their intended size instead of growing by the scale twice, and the merge view's headers and splitters are no longer twice as large.
- A tab closed while it loads a large file or waits for a parse closes once that is done, instead of going on in freed memory.
- Typing in the file filter or a refresh while a hover or Go to Symbol in Repository reads the changed files no longer reaches a file row the tree has let go of.
- Quitting with several tabs open no longer lets a tab still closing read the names of tabs already gone, and a tab closed during a save question at quit is passed over rather than skipping another.
- Closing a tab or quitting while a pull request lookup, a blame or a fetch is under way no longer lets that finish on the tab being closed.
- An argument with a NUL character is refused, so an extension can no longer slip a flag or command past the checks on what it may run with the forge's tool, git or a program.
- Switching to a remote branch from the branch list makes the local branch from the remote you picked, even when another remote has a branch of the same name or `checkout.defaultRemote` names another. Before, git refused, or quietly tracked the other remote's commit. A remote with a slash in its name now gives the right branch name.
- Batch's maintenance task that points a remote's HEAD at its new default branch now works when that branch was force-pushed since the last fetch. Before, git rejected the fetch and the HEAD was never set.
- A repository in a folder whose name ends in a space opens. Before, Gittan dropped the space from its path and git's calls failed or ran in the wrong folder.
- A Bun project with only `bun.lockb`, Bun's binary lock file before 1.2, no longer gets the "No lock file" warning on its project page.
- A BMP whose header gives a negative (top-down) height is held to the same size limit as any other image in the image comparison, so a small crafted file can no longer make Gittan allocate gigabytes on the main thread.
- Add to .gitignore on a file whose name holds a carriage return, such as macOS's folder icon file `Icon\r`, writes a pattern that hides it, and a name with a line break no longer splits into two patterns.
- Compare With > Other refuses a range one of whose sides is not a commit or starts with a dash. Before, a range went to git unchecked, so `--output=<file>..x` made `git diff` write to that file.
- Fetching a pull request with no remote to fetch it from, or with no ref from the forge, says so, instead of failing with an empty message.
- Trusting a signing key adds its line at the end of the allowed signers file instead of rewriting the file, so a full disk or a crash meanwhile can no longer leave it empty, and what was there keeps its line ends.
- A settings.json or state.json that begins with a UTF-8 byte order mark, as Notepad and PowerShell 5 write it, is read instead of reset to the defaults, and one that cannot be read (no permission, or locked by another program) is no longer written over with the defaults on the next save.
- Show History and other filtered views of the commit graph read the log once instead of twice, which halves the wait on a large repository.
- Moving the mouse from one link to the next on the commands page or the project page shows the new link's tooltip instead of keeping the last one's.
- A file that cannot be read when it is opened (no permission, locked by another program on Windows, or gone since it was listed) is said in a banner, and the view is no longer left editable with no syntax colors.
- On Haiku, Reveal opens the folder in Tracker and Open in Terminal opens Haiku's Terminal; before, both did nothing.
- Delete Gone Branches leaves out a branch checked out in another worktree, which git will not delete, and a branch it could not delete for another reason is named in a banner with git's reason. Before, the status bar told only of the ones deleted, with no word of the rest, and the row kept coming back.
- A file whose `.gitattributes` sets `conflict-marker-size` has its conflicts found: the change view's pick buttons, the merge editor's blocks and Mark Resolved's check for markers left all go by that size. Before, none were found, and Mark Resolved staged the file with its markers in it.
- A file replaced with a symbolic link shows its old lines deleted and the link added, instead of the second diff's header (`--- /dev/null`, `+++ b/x`) as changed lines; the line history reads such a commit the same way.
- Undo Revert brings a file back with the permissions it had, so a new executable script, or a change that only made a file executable, is executable again.
- A settings save whose write failed no longer counts what it took in from another Gittan as its own change, which the next save would write over a newer one.
- Undo of a mixed reset is no longer refused because a file whose name differs only in case, such as foo beside Foo, has staged changes; and when it has to move HEAD back after a failed step, it no longer drops a commit another git made in the meantime.
- Switching to a remote branch works when a tag has the same name as it, such as a tag origin/feature; git took the tag and refused to track it.
- Saving a repository file such as .gitignore checks again that it is not a link, so a pull that made it one after it was opened no longer has the save write where the link points.
- A git command or extension program given input no longer waits for a process it left running in the background that holds the input open without reading it, such as a hook's job; it returns when the command ends.
- Undo Discard after a discard that brought a deleted file back deletes the file again; before, it left an empty file, which a commit would take.
- A click on an author in the commit graph's statistics or on the repository page shows that author's commits alone: before, a click on Ann listed Anna's and Joanne's too, and on Linux and Windows an author whose name git kept in two forms of the same letters was split again.
- Absorb folds its fixups into their commits when a prepare-commit-msg hook changes their subjects, such as by putting a ticket number first; before, they stayed as commits of their own while Absorb said the changes were absorbed.
- A repository command that keeps running, such as a dev server, or an editor Gittan starts, no longer makes a background job that feeds git its input (checking signatures, Absorb, the batch actions) hang for as long as it runs.
- An image or binary file in Git LFS that is in conflict and not downloaded keeps Use Mine, Use Theirs and Mark Resolved beside Download; before, Download took their place, and a click on it asked whether to resolve with Mine.
- A clone that finishes while another tab is in front opens in the tab it was started in, which stays behind; before, it opened a new tab that took the front, and the clone's tab stayed empty.
- Keep and Unkeep in the change view leave the caret, the scroll and the hidden lines you opened where they were; before, they moved by as many lines as the keep took out or put back.
- A repository whose files were touched without being changed (by a code generator, unzip, rsync or a sync client) no longer keeps Gittan's background check slow: once two checks in a row are slow, Gittan refreshes git's index, so later checks no longer read every such file again.
- On macOS, tabs that no longer fit in the window no longer slide under the GitHub globe: the strip shows as many as fit, always with the shown one among them, and "+N" after them, which brings in the next hidden tab when clicked.
- Changing the syntax while resolving a conflict in the merge editor no longer marks the result as edited by hand, which dimmed the panes, stopped the picks and asked to save on leaving.
- A long subject or body line that wraps in the summary or a review thread keeps its quotes: Revert "Add the feature" lost them, and a line with a lone quote, such as 12" screen, had the rest of its paragraph broken letter by letter.
- The welcome view no longer hangs Gittan when it shows why a repository did not open in a pane narrower than its padding.

## 0.21 (build-146, 2026-11-17)

### Fixed

- A branch's first push goes to the remote `branch.<name>.pushRemote` or `remote.pushDefault` names, as git would, where it went to the first remote.
- On Windows, an extension's commands get the repository's environment when PATH and the like are spelled in another case.
- An extension allowed to run commands or reach the forge is given the repository in its commands' context.
- Outside Windows, temporary files go into a folder of Gittan's that only you can read.
- An extension's console cuts a very long line and counts each line of a logged text toward its limit.
- An AI fix is read as numbered lines only when its numbers run in order, so a line of the file that starts with a number keeps it.
- Discard of a change at the end of a file says the file changed instead of putting back a last newline removed meanwhile; Leave Out of a file with CRLF line ends no longer adds a carriage return to a last line without a newline, and Keep holds which lines had none.
- A Code History or Time-lapse still loading is dropped when the base or range changes, and Code History from a file changed on disk since it was opened says there is no history yet rather than count the wrong lines.
- The uncommitted changes at the top of a Code History of lines inside a replaced block show the new lines in their places, not the block's first ones.
- The project page reads npm's `^1.2.x` as `^1.2`, orders SemVer's `beta10` below `beta2`, takes Python's `>=1.0rc1` to mean `1.1rc1` too, `==1.0alpha1` to mean `1.0a1`, and reads Yarn lock entries in single quotes.
- A pull request's notice that not all review comments were read comes when more come past the limit, too.
- The Commit section's tip, hidden for room, is measured at the sidebar's width when it comes back.
- A failed rebase, interactive rebase or merge reports git's reason, not that of a command run as the view refreshed.
- Apply Patches on Linux takes two patches whose names differ only in case.
- The Commands page reads a Makefile's targets after a recipe line with `define` in it, or a variable named `define`.
- On Windows and Linux, the status bar's buttons and the check of a clean working tree have smooth edges.
- On Windows, the commit message field shows its scroll bar only while the message is longer than the field.
- At 125 % on Windows and Linux, the change badges, folders and check boxes are as large as the text around them, and sharp at 150 %.
- On Windows, the file trees in the sidebar show their scroll bars only when there is something to scroll.
- On Linux with GTK3, the empty band over the title bar (black on KDE's Wayland) is gone.
- At a high DPI in a low window, the Changes and Commit headings and the tree of changed files no longer disappear under the Commit section: its tip goes and its message box shrinks first.
- On Linux with GTK3, Gittan no longer stops at startup with "Division by zero" when no AI agent is installed.
- A pull request with more review comments than Gittan reads (over 100 replies in a thread, or 2000 threads) says so, where the rest were left out unsaid.
- At a display scale above 100 % on Windows and Linux, the rounded corners, check marks, close crosses and lines of the summary, banners, notices, popup lists and image view scale with the rest.
- The Pull Requests page lists up to 200 open pull requests, where it stopped at 50 and could offer a second pull request for a branch that had one past them.
- Approve and Request Changes are left off your own pull request when it is the only one, where they were offered until another came.
- The project page reads npm's and Cargo's `<=1.2` as every 1.2.x and `>1.2` as from 1.3.0, as they mean it.
- The summary of more changed files than fit in it (about a thousand) ends with how many more there are, where on Linux the rows past them could not be scrolled to.
- Quitting with Don't Save in one tab and Cancel in another keeps the first tab's edits marked as unsaved.
- A deleted file with a folder of its name in its place shows in the file tree as the file, so it can be shown and reverted.
- A submodule whose path ends in parentheses, `lib (fork)`, is found when it is checked out at another commit.
- Apply Patches no longer applies a patch picked twice twice.
- A Code History or Time-lapse still loading is no longer dropped when a file saved meanwhile refreshes the view.
- Code History from a file being edited counts its lines in the version compared against, where lines added in the work tree shifted the range.
- The summary with thousands of changed files no longer lags on every move of the mouse.
- A clone keeps running in its tab when another repository is opened, which now gets a tab of its own, where the clone never opened and a failure went unreported.
- Rename or Move takes a change of case alone (`README.MD` to `README.md`) on macOS and Windows, where it said the name was taken.
- A fetch, pull or push that waits for the background fetch runs after a commit started meanwhile, where it was dropped.
- A tag made or a fetch run in a terminal shows in Gittan at once, where it waited for something else to change.
- Branches whose names differ only in case are told apart in the branch lists and in the check for gone upstreams.
- A font size, zoom or tab width edited by hand in settings.json past what the settings allow falls back to the default.
- Discard and Leave Out of a change at the end of a file keep the file's last newline as the version compared against has it, where a discarded line added without a newline left the line before it without one, and the commit got a newline change nobody chose.
- An image or SVG that claims more than 64 megapixels (a 100-byte SVG can claim 40000 × 40000) is not drawn, where Gittan froze or ran out of memory.
- The project page reads a package.json or requirements.txt that starts with a byte order mark, and lists a requirement given as `name @ https://…`.
- The project page matches `1.2.*` and `1.2.x` as 1.2.x and `!=1.4.*` as leaving 1.4.x out, leaves a pre-release such as 2.0.0-rc.1 out of `<2` and `^1` unless the range names one, and puts Python's `.devN` below the release it comes before.
- Two tabs committing at the same moment no longer share temporary files, where one could commit the other's text.
- An extension's review card shows its age right, where it was off by the time zone.
- Push sends a branch made from another one's upstream (`git switch -c fix origin/main`) to a branch of its own name, where it pushed the commits onto main; it also honours `pushRemote` and `remote.pushDefault`, so in a fork setup the push goes to the fork.
- An extension's `alert`, `Gittan.confirm` and `Gittan.log` with an object whose text changes each time it is read no longer overwrite Gittan's memory.
- Saving a file in the editor that fails (a locked or read-only file) before going to another file asks again, where the edits were dropped.
- Next Conflict in the merge editor with the last row at the top no longer reads before the start of the rows.
- Quitting or closing a tab while a command from `.gittan` runs no longer reads the command after it was freed.
- An extension's command no longer gets the file's path or the selected code without the data permission, nor the repository's folder unless it may also run programs.
- Git Flow's Finish merges the branch when a tag has the same name, where git merged the tag's older commit and Finish then deleted the branch with the commits after it.
- Discard is no longer offered on a renamed file, where it emptied the file, nor on a file taken out of the index with `git rm --cached` but still on disk, where it wrote the file's content in front of itself.
- A file whose name holds `[`, `*` or `?` shows its own changes, where `[ab].txt` also showed those of `a.txt`, and Leave Out and Put into Its Commit wrote them into it.
- Undo Discard, and a discard of deleted lines, refuse a file that changed around the block since, where they put the lines back at the old line number.
- A rebase or pull whose local changes could not be put back cleanly says so, where it said it was done and left the files in conflict.
- `Gittan.ui.openFile` opens only files inside the repository, where an extension without the data permission could show any file on disk.
- Reload Extensions no longer keeps the memory of every extension it unloads, which after a few hundred reloads kept extensions from loading at all.
- An extension that failed to load or was turned off can no longer register commands, forge tabs or Batch operations, or start git, exec or fetch, from a promise it left queued.
- A branch with a tag of the same name is listed and switched to by its name, where the branch menu showed `heads/foo` and switching to it failed.
- The check for branches whose upstream is gone reads a branch whose name holds a quote, and one with a tag of the same name, by its name.
- On an orphan branch with no commit yet the commit graph, a file's history and the `change:` search show the other branches' history, where the graph was empty.
- A commit that leaves out some lines of a deleted script keeps its executable bit.
- Quitting with an unsaved file in another tab opens the tab that was shown at the next start.
- A pull request comment or review sent after the repository's remote changed while it was being written no longer crashes Gittan.
- Open on GitHub opens a file whose name starts with "-", where `-s` opened the repository's settings.
- An AI fix whose answer numbered the lines it replaces no longer writes the numbers into the file.
- The project page reads more of what lock and manifest files hold: Python packages whose names a lock spells otherwise (PyYAML as pyyaml, typing_extensions as typing-extensions), Cargo's dotted keys (`tokio.workspace = true`, which showed as a dependency named tokio.workspace) and renamed dependencies (`package = "bar"`), yarn berry's keys with several ranges, pnpm lockfile 5's peers, a pnpm-lock.yaml with Windows line ends (where a line of blanks also crashed Gittan), pip-compile's continued lines with hashes, a Lazarus package's minimum version with a release number or a 0 left out, and a go.mod `module` or `go` line with a comment after it.
- Add to .gitignore on a file whose name holds `[`, `*` or `?` ignores that file, where `pages/[id].tsx` ignored `pages/d.tsx` instead.
- A Makefile's `::=` assignments and the text of a `define` are no longer listed as commands.
- Blame, Code History, review threads and AI Why on the old side of the change view find the right lines after a reviewed (kept) line that was only added or only deleted, where every old line after it was one off.
- A reviewed deleted line in the middle of a block no longer splits the block, where Leave Out and the line selection then went to the wrong rows.
- Code History shows the uncommitted lines added at the end of the range, such as the new text of a changed last line or lines added at the end of the file.
- An SSH key a forge gives for a commit's author is added to the allowed signers only when it is one, and never read as a file of that name on this computer.
- Settings an extension no longer defines leave its settings page after Reload Extensions.
- Put into Its Commit with whitespace ignored no longer takes a change of blanks alone into the old commit with the change it puts there; it stays in the work tree.
- Undo Discard after a conflict was resolved with a side that had no lines refuses a file that changed round it, where it put the conflict back at the old line.
- The AI features run GitHub Copilot without `COPILOT_ALLOW_ALL` and the `GITHUB_COPILOT_PROMPT_MODE_` variables, which would let a cloned repository's hooks, MCP servers and extensions run when you asked for a commit message, review or summary.
- The project page shows the right locked version of a Python package with a local label or a post-release: `==2.1.0` is met by 2.1.0+cu118 again, and 1.4.post1 is above 1.4, so `<=1.4` leaves it out and `!=1.4` takes it. Two pre-releases of one version are told apart (2.0.0-beta.2 is past 2.0.0-beta.1 and below 2.0.0-rc.1, Python's 1.4b2 below 1.4rc1, beta.10 past beta.2), `=2.0.0-beta.1` is that pre-release alone, and 2.0.0 meets `>2.0.0-beta.1`.

## 0.20 (build-145, 2026-11-12)

### Fixed
- Opening a repository whose .github or .gittan folder holds a link to a folder no longer hangs Gittan: a link such as `.github/a -> .` was walked into for ever. Linked folders are left out of the Config section's files.
- A repository can no longer crash Gittan or run it out of memory on open with a .lpi or .lpk whose DOCTYPE expands entities to gigabytes, a package.json, lock file, commands.toml or repo.toml nested many thousand levels deep, or a .po file with a plural index such as `msgstr[-1]`. A commands.toml or repo.toml nested too deep says so on the Commands page.
- A package.json script whose name holds a line break is no longer listed, where running it ran the rest of its name as a second command, and a script name with spaces or other characters the shell reads is quoted. A Makefile target that starts with "-" is no longer listed, where `make -C..` would have run another folder's Makefile.
- On Windows a build mode or file name with a quote or a % in it no longer breaks out of its quotes in the command Gittan runs.
- Push and Force Push on a branch that tracks a local branch (`git switch -c feat --track main`) push it to the remote under its own name, where they moved the local branch it tracks and said it was pushed.
- An extension with only the data permission can no longer read or write files outside the repository through `Gittan.repo.commit`, `blame` or `diff`, or by replacing JavaScript's own functions.
- Undo Revert puts a symbolic link back as the link it was. It wrote the content of the file the link led to into the file the reverted link leads to, and left the link as HEAD had it; a link to a folder or to nothing is reverted and put back too, where it was left out or deleted.
- Discard on a file with a carriage return inside a line (not a Windows line end) puts a deleted line back where it was, not one line further down.
- The AI features run Claude Code with your own settings alone: a repository's .claude/settings.json, whose hooks ran when you asked for a commit message, review or summary in a repository you had cloned, is no longer read, and no MCP server is started.
- An extension whose script throws as it loads no longer keeps running what it set up before the throw (listeners that could stop a commit, commands, timers) while the Extensions page says it did not load; and one whose last line happens to be a string that starts with "Error:" is no longer taken for one that failed.
- Extension timers no longer start a thread each, and an extension can have at most 1000 at once; a timer that fired just as it was cleared, or as the extensions were reloaded, can no longer run on freed memory. Timers now fire on the engine's 50 ms tick.
- Move to a New Branch, Push, Force Push and git-flow work on a branch that has a tag of the same name, where the move left you on the new branch and Push named the branch `heads/<name>`. When a move cannot go back to the branch it started on, it says so.
- Move to a New Branch refuses a file that `git rm --cached` took out of the index but left on disk, which git would not let it switch back over, and a copy of left-out changes it could not write back is no longer replaced by a later one with the same name.
- A background task that fails unexpectedly (an AI request, a forge or update check, a signing key lookup) no longer leaves Gittan waiting for it for good: it ends with its error shown. The blame band of a repository that could not be opened is no longer left waiting either.
- The AI features through an OpenAI-compatible API work on changes to a file that is not UTF-8 (a Windows-1252 file with an é in it), where the server refused the request.
- The check for branches gone from their remote and the submodule check run ssh in batch mode, as fetch and push do, so a key with a passphrase can no longer leave them waiting on a prompt in the terminal Gittan was started from.
- Batch's Set Remote HEAD refuses a branch name from the remote that git would not take for one, where a name such as `x:refs/heads/main` made the fetch write the local main branch.
- On Windows a server that sends its answer a byte now and then can no longer keep the update check or another web request going for good: the whole request gets its time limit, as on macOS and Linux.
- A submodule's commit list shows a subject or author that starts with a quote whole, where `"Quoted" thing here` showed as `Quoted`.
- The account menu checks the active login of every host, where with gh logged in to github.com and a GitHub Enterprise host only the last host's showed a check.
- On Windows the kept menu bar (View > Menu Bar) still moves the window from its empty part and keeps its caption buttons working after the window moves to a screen with another scale.
- A link in a pull request comment or a Markdown preview opens only when it is a web or mail address, where a link of another scheme could start whatever application the system has for it.
- An AI command line tool that does not answer `--version` no longer keeps Gittan from quitting after the settings were open; it is given ten seconds.
- A Cargo.toml whose description is a multi-line string no longer has its lines read as keys and tables, where a line such as `[badge]` in it hid the version after it.
- The files Gittan replaces in one step (settings, state) are on the disk before the old one goes, and the symbol index is replaced in one step too, where a crash while saving it left a cut file that took the last files for indexed with no symbols.
- The project page shows the right locked version when a lock file has several of one package: Python's `==1.4` is 1.4 alone, not 1.4.5, an npm range such as `1.0 - 1.4` is read, and a pre-release such as 2.0.0-beta.1 counts below 2.0.0.
- An extension with the data permission can no longer read a file outside the repository with a path such as `link/../secret` through a link in the work tree, and an extension's array that holds itself twice no longer runs Gittan out of memory.
- An AI review whose answer could not be read says so, where it reported the review done with nothing found.
- A promise of an extension that ends after Reload Extensions (a slow fetch or command) is no longer settled in the extension's freed context.
- An extension can no longer exhaust Gittan's memory or stack by passing an argument that claims a huge length or contains itself, and an exception raised while Gittan reads an argument is thrown where the extension made the call, instead of breaking its next call.
- An extension with the forge permission can no longer have gh read a local file through `--recover` or `release verify-asset`.

## 0.19 (build-144, 2026-11-10)

### Added
- With the AI features on, a right click on a branch in the branch list has ✦ Summarize What (your branch) Changed Since (that branch): Gittan shows what your branch did since it left that one, as a pull request to it would, and the agent summarizes it. Any branch will do, not only the default one. A right click on a commit in the graph has ✦ Summarize Changes Since This Commit, or between it and the commit you marked for comparison.
- A right click on the globe at the top right of the window lists the accounts gh is logged in to, the one in use marked, and a pick switches to it, as the Hosting page of the settings does; the GitHub view has the same list in its new Account menu, and behind your login at the top of the page when gh is logged in to more than one account. The switch is gh's own, so the terminal's gh changes with it.
- Branch > Move Included Files to New Branch..., and Move Changes to New Branch... on a file or a folder of the tree: the changes are committed on a new branch, after a name and a message, and taken out of the branch you are on, where your other changes stay. The banner that says so offers the switch to the new branch. Changes left out of the commit stay behind too.

### Fixed
- Summarizing or reviewing the changes against an older commit no longer fails with "pathspec did not match any files" when a commit since removed a file.
- A squash merge whose changes were stashed or discarded is over for good: changes staged later are no longer taken for it, with its old message in the commit field and an Abort that would have thrown them away.
- Saving the Name and Email dialog with the signing left as it was no longer writes the signing settings: a key git picked by your e-mail is not replaced by the first one listed, and tags are not set to be signed.
- Skip in a rebase, cherry-pick or revert that git refuses (a lock on the index, a hook) shows git's reason rather than saying the commit was skipped.
- Put into Its Commit no longer takes a file that was emptied for a deleted one, or one that was empty before for a new one: an emptied file's lines go to the commit that wrote them, when there is one on the branch.

## 0.18 (build-143, 2026-11-09)

### Added
- An AI menu, shown while the AI features are on, holds all of them in one place: Write Commit Message and Split into Commits from Commit, Review Changes and Clear Review from View, Explain Line History from Go, and Summarize Changes. The shortcuts are the same.
- AI > Summarize Changes, or ✦ Summarize at the top right of the summary (with the AI features on): the agent says what the changes shown amount to, the commits since what you compare with and the diff, or what is not yet committed when you compare with HEAD. The answer comes in a panel over the window, drawn as Markdown, with Copy to take it along as text and each commit it names a link that shows that commit; the panel stays until you close it, and Stop there or in the menu ends the agent while it works.
- Pushing without the pre-push hook: Repository > Push Without Hooks, and Push Without Hooks in the notice when the hook refused a push, push with --no-verify for that push alone. When the hook is Git LFS's, Gittan warns first that the LFS files would not be uploaded.
- A Haiku package, Gittan-haiku-x86_64.hpkg: `pkgman install Gittan-haiku-x86_64.hpkg` brings Qt 6 and git with it, and Gittan is then in the Deskbar menu under Applications. The tarball is still there. Like the tarball, a release does not wait for it.
- On Windows and Linux (GTK 3), Alt or F10 shows a menu bar at the top of the window, as in Firefox: the menus' names in a row, Left and Right moving between them, also while one is open, and Alt with a letter opens that menu at once. It goes again once a command is chosen, on Escape, or when you click elsewhere. The menu button in the title bar still drops the whole menu. View > Menu Bar keeps the menu bar shown for good, with the minimize, maximize and close buttons at its right end and the menu button gone; its empty part moves the window like the title bar.
- A FreeBSD build (amd64, GTK 3), Gittan-freebsd-amd64.tar.gz, for FreeBSD 15.1 or later with GTK 3 and git (`pkg install gtk3 git`). Like the Haiku and Windows on Arm builds, a release does not wait for it.

### Fixed
- A settings.json or state.json that cannot be read as JSON, after an edit by hand that left a comma too many, is no longer overwritten with the defaults without a trace: its text is kept beside it as settings.json.damaged or state.json.damaged, and a banner says so at start.
- A settings file or repository list that is a symbolic link, into a folder of dotfiles, stays a link when Gittan saves: the file it leads to is written.
- The Batch tab deletes a gone branch only while it is still at the commit the scan found it at, so a branch that got commits while the tab stood open is kept, with the reason beside it.
- Trusting a forge's signing keys refuses an e-mail the allowed signers file would read as a pattern or as more than one name, such as one with a `*` or a comma in it, rather than writing it there.
- An extension with the forge permission alone can no longer reach `gh pr create`, `gh pr checkout`, `gh repo create` and `gh release create` through gh's other names for them (new, co).
- A squash merge can be given up: Abort is in the Commit section while its changes are staged, also when it stopped on conflicts, where there was no way back in Gittan.
- The message of a squash merge whose changes were discarded no longer comes back in the commit field for later, unrelated work.
- Putting a change into a commit that is itself a fixup of a commit not on the branch folds it into that fixup, rather than leaving a "fixup! fixup!" commit behind and saying it went in.
- On Windows a co-author already in the message's trailers is no longer added a second time.

## 0.17 (build-142, 2026-11-08)

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
