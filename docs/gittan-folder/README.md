# The .gittan folder

A repository can tell Gittan about itself in a folder named `.gittan` at its root. You write the files by hand, commit them, and everyone who clones the repository gets them. Gittan reads them again whenever they change, whether you edit them or a pull brings a new version.

| File | What it holds | Needs trust |
| --- | --- | --- |
| `.gittan/commands.toml` | The repository's commands: buttons on the Commands page and keyboard shortcuts | Yes |
| `.gittan/commands/*.toml` | More commands, each file a section of its own | Yes |
| `.gittan/repo.toml` | The kinds of project, the issue tracker, how commit messages are written, the protected branches | No |
| `.git/gittan/commands.toml` | Your own commands for this repository, never committed | No |

The Config section at the bottom of the sidebar lists every one of these files, the personal file included, and opens them in the editor. On the Commands page, Edit… or Create… opens a commands file and writes a commented example into it the first time.

All the files are [TOML](https://toml.io). A file that is not valid TOML gives nothing, and Gittan shows the line and column where reading stopped, under the file's heading on the Commands page. A value of the wrong type, such as a number where a string belongs, is ignored as if it were not there.

## Why some files need trust

A command file can make a shortcut on your computer run anything. A file that came with a clone could do just that, so the commands in `.gittan/commands.toml` and `.gittan/commands/` stay off, dimmed under a card on the Commands page, until you press Trust Commands. Gittan remembers the exact content you trusted. If any of the files changes, even by one character, or a file is added, it asks again.

`repo.toml` only describes the repository and runs nothing, so it works as soon as it is there. Your personal file lives inside `.git`, which no clone or pull can write to, so it needs no trust either.

## Commands: .gittan/commands.toml

```toml
[commands.test]
run = "npm test"
key = "T"
description = "The unit tests"

[commands.dev]
run = "npm run dev"
terminal = true

[commands.clean]
run = { windows = "rmdir /s /q build", unix = "rm -rf build" }
confirm = "Remove the build folder?"

[commands."build:docs"]
run = "make docs"
```

Each table under `[commands]` is one command:

- `run` is the shell line. It runs from the repository root through your login shell, so your PATH is the one your terminal has. It can be a table with a line per system: `macos`, `windows`, `linux`, `freebsd`, `haiku`, then `unix` for any system but Windows, then `default`. A command with no line for the system you are on is shown dimmed.
- `key` is one letter or digit. The command then runs with Ctrl+Cmd and that key on macOS, or Ctrl+Alt and that key elsewhere, from anywhere in Gittan. If two commands ask for the same key, the first one gets it.
- `terminal = true` opens the command in a terminal window instead of under the page. Use it for anything that keeps running or asks questions, such as a dev server, a watch or a REPL.
- `description` is a line shown in the tile's tooltip.
- `confirm = true` asks before the command runs. A string asks your own question instead.
- `hidden = true` leaves the command off the page.

A name with a colon must be quoted, as in `[commands."build:docs"]`. Commands that share what comes before the colon are grouped under that name on the page.

**Giving existing commands a key.** Gittan lists the scripts of a `package.json`, the targets of a Makefile and the commands of the project's own tools by itself: `cargo test`, `go test`, `lazbuild`, `pytest` and so on. A table with no `run` line whose name matches one of them adds to that command instead of creating a new one. It can give it a key, a description, a question or `hidden`:

```toml
[commands.test]      # make test, npm test or cargo test, whichever there is
key = "T"

[commands.install]   # a Makefile target that is only a step of another
hidden = true
```

**More files.** Each `.toml` file in `.gittan/commands/` becomes a section of its own on the Commands page, headed by the file name, so a release script can live in `.gittan/commands/release.toml`, away from the everyday commands.

## Your own commands: .git/gittan/commands.toml

Commands that are yours alone go in `.git/gittan/commands.toml`. It is written the same way as `commands.toml`. The Commands page lists it under Personal, after the committed files, and offers Create… while there is none. Because it lives in the git folder, it is never committed and never shown as a change. A worktree of the repository shares it with the main checkout.

Your file comes first. A key it gives wins over the key a committed file gives, and a table naming a script, target or tool command lets you pick your own key for it:

```toml
[commands.serve]
run = "python3 -m http.server 8000"
terminal = true

[commands.test]      # the team's test, on a key you prefer
key = "X"
```

When your table and a committed one name the same command, what you leave out still comes from the committed file: its description, its question, and its key when yours gives none. A key that comes from the committed file still waits for trust.

## The repository: .gittan/repo.toml

```toml
project = ["rust", "go"]

[issues]
url = "https://tracker.example.com/issue/%BUGID%"
regex = 'GT-(\d+)'

[commit]
subject-limit = 50
subject-max = 72
template = ".gittan/commit-message.txt"
sign-off = true
types = ["feat", "fix", "docs", "refactor", "test", "chore"]
scopes = ["ui", "core"]

[branches]
protected = ["main", "release/*"]
```

Every part is optional. Where git config sets the same thing, git config wins, so one person's own setup still holds.

**`project`** names the kinds of project the Commands and Project pages show: `lazarus`, `node`, `rust`, `go` or `python`, in any case. Use it when the files would suggest another kind, for example a Rust repository with a `package.json` for its docs. `project = "none"` shows none. A kind picked on the Project page comes before this line. The same line in `commands.toml` still works, but `repo.toml` is read first.

**`[issues]`** turns references to issues in commit messages into links:

- `url` is the address of an issue, with `%BUGID%` where its id goes.
- `regex` finds a reference. Its first group is the id; without a group, the whole match is.
- `ids` is optional. Use it when `regex` finds a whole reference such as "Fixes #12, #13"; `ids` then picks the ids out of it.

These work like the `bugtraq.url` and `bugtraq.logregex` keys that several git clients read from git config. If git config sets them, or you set them under Repository > Issue Tracker..., git config is used instead. Write the expression in single quotes, as above, so a backslash stays a backslash.

**`[commit]`** says how commit messages are written:

- `subject-limit` and `subject-max` set the first line's lengths. Past the limit, its length shows beside the Commit button; past the maximum, the count turns amber. Without them, the limit is 50 and the maximum 72, where `git log --oneline` and GitHub cut the line.
- `template` is a file, as a path from the root, that fills an empty message field, in the same way as git's `commit.template`, which wins if it is set. Lines starting with `#` are left out.
- `sign-off = true` makes commits signed off (`Signed-off-by:`) unless you turn Sign Off off in the Commit section's options. Gittan then remembers that choice for this repository.
- `types` asks for subjects written as [Conventional Commits](https://www.conventionalcommits.org): `type(scope): what it does`, or `type!:` for a breaking change. The Commit section says so when the subject has no type or one the list does not have. `scopes` lists the scopes too; without it, any scope is fine. Merges, reverts and `fixup!`, `squash!` and `amend!` commits are not checked.

**`[branches] protected`** lists the branches whose changes go through pull requests: names, or patterns where `*` stands for any characters, `/` included, and `?` for one. While one of them is checked out and there is something to commit, the Commit section says so.

The rules in `repo.toml` are the team's, not git's: Gittan points them out but never stops a commit. If they must hold, enforce them on the server as well, for example with branch protection or a check in CI.
