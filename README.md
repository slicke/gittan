<p align="center">
  <img src="https://gittan.app/assets/icon-256.png" width="96" height="96" alt="">
</p>

<h1 align="center">Gittan</h1>

<p align="center"><strong>Git Tree Analyzer &amp; Navigator</strong><br>
A free, native git client built around the diff. See what you changed as you change it, who wrote each line and the history behind it, then commit, sync and merge without leaving it.</p>

<p align="center">
  <a href="https://github.com/slicke/gittan/releases/latest">Download</a> ·
  <a href="https://gittan.app">gittan.app</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="LICENSE">GPLv3</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://gittan.app/assets/shots/unified-dark.png">
    <img src="https://gittan.app/assets/shots/unified-light.png" alt="Gittan showing a unified diff of a Vue project, with the changed files and their counts in the sidebar" width="900">
  </picture>
</p>

Gittan runs on macOS, Windows and Linux. It is written in Free Pascal with Lazarus and talks to the `git` command line tool, so it works with whatever git, hooks and signing you already have set up.

## Download

Packaged builds for every platform are on the [Releases page](https://github.com/slicke/gittan/releases/latest). Every push to `main` is built on GitHub Actions and published as the next `build-<n>` release.

| Platform | File |
| --- | --- |
| macOS (Apple Silicon) | `Gittan-macos-silicon.dmg` |
| Windows (x64) | `Gittan-windows-x64.zip` |
| Linux (amd64, GTK 3) | `Gittan-linux-amd64.tar.gz` |

Gittan needs git 2.30 or later on your `PATH`. The macOS build is signed ad hoc, so macOS blocks it at first: drag it to Applications, then run `xattr -cr /Applications/Gittan.app` in Terminal. The GitHub features (pull requests and review comments) use the `gh` CLI when it is installed and signed in. The AI features, off until you turn them on, use [Claude Code](https://code.claude.com/docs) or [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli) with your own sign-in.

## What it does

**The diff first.** The work tree against HEAD, or against any branch, tag, commit or snapshot. A background thread watches the repository, so the tree, the counts and the diff follow your editor as you save. Unified or side by side, with changed words marked within a line, unchanged lines hidden with a few lines of context, folding, and syntax highlighting from the CudaText lexer collection. A changed image shows as two pictures at the same scale, a `.po` file as originals and translations row for row, and a Markdown, HTML or SVG file can be drawn beside its diff with its changes marked on the page, with no browser engine.

**History beside the code.** Blame puts who last changed each line, and when, in a column beside the diff. Code History lays the earlier versions of the selected lines, or the function the caret is in, under the lines themselves, one color per commit. The commit graph draws every branch and tag, marks what is not pushed or not pulled, and filters as you type (`author:`, `since:`, `until:`, `path:`). Browse the files of any commit as they were then, or turn the graph into commits per week and author.

**Commit, sync and merge.** Tick the files that belong together, skip a block of a file for a later commit, write the message and commit. Pull, push and fetch sit in the status bar with the ahead and behind counts; a failed command tells in a banner with git's reason instead of a dialog. Branches, stashes, tags, reflog, remotes, clone and init, patches, cherry-pick, revert, reset, interactive rebase, bisect, and a conflict view with Use Mine, Use Theirs and one conflict at a time. Anything that would throw work away asks first.

**AI when you want it.** Turn it on in the settings and pick Claude Code or GitHub Copilot, whichever you already use; Gittan runs its command line tool in the repository with your own sign-in and has no account or API key of its own. ✦ AI in the Commit section writes the message for the ticked files, short and in the style of the repository's recent commits. Review Changes with AI goes through what the diff compares and puts what it finds, bugs, risks and questions, as cards under the lines they are about, beside a pull request's review comments. The agent may read the repository to check a finding but gets no tool that writes, runs a command or goes to the network, and nothing is sent until you ask.

**At home on each desktop.** The actions sit in the title bar on every platform, the window follows the system's dark mode (on Windows the native controls too), and Tools > Install CLI Command gives you a `gittan` command that opens a folder in it.

<table>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://gittan.app/assets/shots/history-dark.png">
        <img src="https://gittan.app/assets/shots/history-light.png" alt="Code History: the earlier versions of a line laid under it, one color per commit">
      </picture>
      <p align="center"><sub>Code History</sub></p>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://gittan.app/assets/shots/commit-dark.png">
        <img src="https://gittan.app/assets/shots/commit-light.png" alt="The Commit section: ticked files, a message and the Commit button">
      </picture>
      <p align="center"><sub>Commit from the tree</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://gittan.app/assets/shots/graph-dark.png">
        <img src="https://gittan.app/assets/shots/graph-light.png" alt="The commit graph with branches, tags and the commits not pushed yet">
      </picture>
      <p align="center"><sub>Commit graph</sub></p>
    </td>
    <td width="50%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://gittan.app/assets/shots/conflicts-dark.png">
        <img src="https://gittan.app/assets/shots/conflicts-light.png" alt="A conflict with your side, the base and theirs in their own colors">
      </picture>
      <p align="center"><sub>Conflicts</sub></p>
    </td>
  </tr>
</table>

The [website](https://gittan.app) has the full tour, and the files in [spec/](spec/) describe how each area works.

## Build from source

You need [Lazarus](https://www.lazarus-ide.org/) 5.0 (the CI uses 5.0RC1) with Free Pascal 3.2.2 or later, and git. The editor, the lexers, dark mode on Windows and the preview come from packages vendored as submodules under `vendor/`, so clone with them:

```sh
git clone --recursive https://github.com/slicke/gittan.git
cd gittan
```

A fresh Lazarus knows none of the vendored packages. Register them once with `lazbuild --add-package-link <package>.lpk`, in dependency order: ATFlatControls, EncConv, BGRABitmap, ATSynEdit, EControl, ATSynEdit_Ex, MetaDarkStyle and LazInk (the exact list is `VENDOR_PACKAGES` in [.github/workflows/build.yml](.github/workflows/build.yml)). lazbuild then compiles them as dependencies of `Gittan.lpi`. If you build from the IDE, install ATSynEdit and its dependencies there instead.

Then build with make:

```sh
make            # build Gittan.lpi optimized (cocoa on macOS, gtk3 on Linux)
make run        # build and start
make debug      # debug info (DWARF 2 on macOS)
make rebuild    # recompile every unit
make test       # build and run the unit tests with plain fpc
make help       # every target
```

On macOS, make finds lazbuild in `/Applications/lazarus` when it is not on `PATH`. On Linux you need GTK 3's headers (`libgtk-3-dev` on Debian and Ubuntu, `gtk3-devel` on Fedora). On Windows there is no make: `.\make.ps1` has the same targets and finds lazbuild on `PATH`, in `C:\lazarus` or in `C:\fpcupdeluxe\lazarus`.

Every build copies the lexers into `lexlib/`, which must sit beside the executable (inside `Contents/Resources` in the macOS bundle). A build from the IDE does not do that, so run `make lexlib` (or `.\make.ps1 lexlib`) once.

## Repository layout

- `src/core/`: the units without the LCL, which plain `fpc` builds and the tests use: the git wrapper, the diff and history parsing, settings, the CLI command, updates.
- `src/ui/`: the controls, the main form (`umain.pp` and its `umain.*.inc` files) and everything that needs a widgetset.
- `tests/`: fpcunit tests, run with `make test` on every CI leg.
- `spec/`: one file per area, describing how it works and which units it covers. [AGENTS.md](AGENTS.md) has the rules that apply everywhere.
- `vendor/`: the submodules. Nothing in there is edited here; a package is updated by moving its submodule.
- `lexers/`: Gittan's own lexers, copied into `lexlib/` together with the CudaText collection.
- `icons/` and `tools/`: the application icon and the script that regenerates it (`make icons`).

## Contributing

Issues and pull requests are welcome at [github.com/slicke/gittan](https://github.com/slicke/gittan). Read [AGENTS.md](AGENTS.md) and the spec file for the area you change before you start; CI builds every pull request on all three platforms and runs the tests.

## License

Gittan is free software under the [GNU General Public License, version 3](LICENSE). The packages under `vendor/` are separate projects with licenses of their own, kept in their submodules.
