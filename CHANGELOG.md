# Changelog

What changes for you in each build of Gittan, newest first. Changes land under Unreleased until a build on the [Releases page](https://github.com/slicke/gittan/releases/latest) carries them.

## Unreleased

### Pull requests across your repositories

- A globe at the top right of the window opens your pull requests on GitHub across every repository, not only the one open: the ones you have open and the ones waiting for your review, as two tabs. Click one to compare with it in the tab that has its repository, or in its clone if you have one; otherwise it opens on GitHub. Escape, the globe or Cmd+W (Ctrl+W) takes you back to your repositories. This replaces the GitHub page each tab had.
- The two lists have filters as chips: With feedback, Needs attention (changes requested or checks failing), No drafts and Stale (untouched for a month) on your own, Asked of me and No drafts on the ones to review. The filters are kept between runs.
- Branch > Create Pull Request... opens GitHub's page for a new pull request from the current branch. A branch not on the remote yet is pushed first, after asking; a push that went through also offers it in its banner.
- The GitHub features now show only for a repository that has a remote on GitHub, including GitHub Enterprise hosts you are logged in to with gh, remotes reached through an ssh alias in ~/.ssh/config and ones rewritten by an insteadOf rule. A repository on GitLab, Bitbucket or without a remote no longer shows them, where they failed before.
- The hosting features have one switch, "Turn on the hosting features" on the Hosting page of the settings.
- The change view shows the review comments of the branch's pull request only while it is open. A merged or closed one no longer leaves its comments on today's lines; the status bar still says Merged.

### Git LFS file locks

- Gittan shows who holds which file on the Git LFS server, read when the repository opens and after every fetch. Lock File, Unlock File and Force Unlock are in the file menu, and a file of HEAD on the Files page gets a Lock pill so you can lock it before you change it. The file header says "Locked by ..." for a file another user holds, File > Git LFS Locks... lists every lock, and a commit of files others hold is asked first, since the push would be refused.

### Commands page

- The tiles are sorted by name, laid out in one grid, and show what each command runs under its name. A terminal under the run mark runs the command in your terminal instead, for one that keeps running such as a watch or a dev server.
- A command's output is a panel with its state (Running, Done, Failed with the exit code, Stopped), its name and its time, with Stop while it runs and Run Again and Copy after. Stop ends a command that ignores the first signal too.

### Working with the agent

- Ask the agent where something is: with the AI features on, the filter field over the tree has a sparkle. Click it or press Cmd+Enter (Ctrl+Enter) and Claude Code or Copilot answers with the files that hold what you typed, each with a line and why; pick one to open it there.

### Status bar

- What is under way reads as such: a fetch, pull, push, clone or commit, and the agent writing, reviewing or looking, show with an icon and a moving line in the status bar, and the transport buttons are dimmed from the moment a job starts.
- While anything is compared (a pull request, a branch, a stash, a commit, a snapshot) a cross after the base label goes back to the working tree.

### Fixes

- A file opened from a link in a comment, or from the agent's answer, now scrolls to its line, and the status bar and the header follow it.
- Checking for updates no longer runs curl: it goes through the system's own networking (libcurl on Linux) and its proxy settings.
