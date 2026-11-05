# Things I haven't found outside Gittan

Gittan is a git client built around the diff. Most of what it does, every git client does. This is the list of what I have not found in TortoiseGit, SourceTree, Fork, GitKraken, Tower or the git views of the IDEs, as far as I have looked. If you know one that has it, [tell me](https://github.com/slicke/gittan/issues) and I will take the line out.

## Put a change into the commit it belongs to

Hover a change and press **Put into Its Commit**: Gittan finds which commit of your branch last wrote those lines, asks, and folds the change into that commit. **Commit > Put Changes into Their Commits...** does it for everything at once, listing each change with its commit, or why it cannot be placed. The round of small fixes after a review ends up in the commits they fix, not in a "fixes" commit on top. Commits already pushed are never rewritten, and Undo takes it back. The command line has `git absorb` for this; no client I know has it.

## Time-lapse

**Go > Time-lapse** plays a file through every version it has had, oldest first. The lines a commit brought in light up, the ones it took away are struck through on their way out, and a track at the bottom has a dot per version to scrub with. A file's history as a film rather than a list.

## Code History under the lines

**Go > Code History** takes the selected lines, or the function the caret is in, and lays their earlier versions under them, one color per commit, the changed words shaded, with the author's initial on each row. No jumping between commits: the past of a function is read top to bottom in place.

## Reviewed, and gone

A change you have read and accepted gets **Reviewed**: it turns into plain code for the rest of the session, so the diff shrinks to what you have not looked at yet. The file and git are not touched. A long review is worked through like a checklist, and the counter in the corner counts down.

## A merge preview before you merge

The row that says the branch is behind main also says whether merging main would go through: "merges cleanly", or "conflicts in 3 files" with their names, computed in memory before you press Merge or Rebase. Nothing is touched to find out.

## Undo for what git did

**Branch > Undo** takes back a commit, an amend, a merge, a reset, a rebase, a switch, a deleted or renamed branch, and **Redo** does it again, named after what it was ("Undo Merge feature/x"). It follows what git did outside Gittan too, in a terminal, since it watches where the branches move. Discarded changes have their own Undo.

## No index to think about

Gittan never says "staged". A commit takes the files you ticked, whole, as the diff shows them, and a change or a selection of lines can be left out of the commit and stays in the file. The index still exists for git's sake; you do not have to know.

## The graph's search finds the commit that changed a text

The commit graph filters as you type: `author:`, `since:`, `until:`, `path:`, and `change:` for the commits that added or removed a text, or lines matching a `/regex/`, which is `git log -S` and `-G` with a text field. The same graph turns into commits per week and author, drags a commit onto a branch to merge it, starts a bisect from a commit, and shows the files of any commit as they were then.

## Symbols in a diff

The gap rows of a diff name the function the next change is in, and the file header names the one the caret is in. **Go > Changed Symbols** lists the functions a diff touched, **Callers of Changed Symbols** who calls them, and F12 or Cmd+click goes to a definition, all inside the diff view, with no IDE and no language server: the lexers that color the code also give the symbols.

## AI with the agent you already have

Turn it on and pick Claude Code or GitHub Copilot CLI: Gittan runs the command line tool you are signed into, with no account or key of its own. **Review Changes with AI** puts what it finds as cards under the lines they are about, beside a pull request's review comments, with a Fix button on each. **Split Changes into Commits** sorts the changed files into commits with messages for you to look over. **Explain Line History with AI** tells why the selected lines came to be, from `git log -L`. The agent gets no tool that writes, runs a command or goes to the network.

## Markdown, HTML and SVG drawn, with the changes marked on the page

**View > Preview** draws a Markdown, HTML or SVG file beside its diff, the changed parts marked on the drawn page, with no browser engine inside the app. A `.po` translation file shows as originals and translations row for row, and a changed image as two pictures at the same scale.

## Extensions that can say no

A JavaScript file in the extensions folder adds commands to the menu and the command palette, watches commits, pushes and pulls, and can stop one with a reason shown to the user. Each file declares what it needs, Gittan asks before loading one that wants the repository, the network or programs, and `@repos` in the file limits it to the repositories it is for. An extension can also add its own tab and Batch operations to the GitHub view and run gh as you, with a permission of its own apart from running programs; `@forges github` keeps it to repositories on GitHub, so its gh never runs against a repository hosted elsewhere. A repository's own commands (`.gittan/commands.toml`, and more files in `.gittan/commands/`) become buttons and keys, once you have trusted that version of the files.

## What changed in the dependencies since the last release

**View > Project** reads the project the way its own tools do, for Lazarus, Node, Rust, Go and Python, and compares it with the newest tag. Each dependency shows the version asked for and the version the lock file resolved, and what changed since the tag: added, removed, or `1.0.200 → 1.0.210`. A Lazarus project shows its build modes with a Build button each, and where every package comes from: a package file in the repository, a submodule at a tag, Lazarus itself, or nowhere, which a clone would then have to install. A vendored package that moved since the release shows as the move. Under it are the mistakes that end up in commits, such as a session file, build output or a virtual environment, each with a button that ignores it and stops tracking it. Other clients show a lock file as a long diff; I have not seen one read it as a list of packages.

## Clean up many repositories at once

The **Batch** tab of the GitHub view works on the repositories you pick from your repository list. **Gone branches** fetches each one and lists the local branches whose branch on the remote was deleted, each marked merged, squash-merged or not merged: a branch squash-merged on the forge is recognized as merged even though none of its commits are in main. The merged ones are picked, and one Delete clears them all. **Identity** shows who each repository commits as and whether it signs, and marks the one where the others of the same owner use another e-mail, such as a work repository committed to with a private address.

## Small things

- Scroll past the end of a file and the next changed file is pulled in.
- Git flow without the git-flow command installed, on the same config it writes.
- A Git LFS file is shown as the file, not as the pointer, and its locks are listed.
- Several `gh` accounts, switched from the settings; the GitHub picture in the corner says which.
- A branch's worktrees open as tabs, so two branches are worked on side by side.
- The Repository page counts the lines of the tracked files by kind (code, docs, tests, configuration), kept current as you edit.
- Runs on macOS, Windows (x64 and Arm), Linux (x64 and Raspberry Pi) and Haiku, from one code base, native on each.
