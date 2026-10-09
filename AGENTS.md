# AGENTS.md

## Scope
This file applies to the Gittan repository root and its subdirectories.

## Working Rules
- Prefer the project Makefile instead of calling `lazbuild` directly. Run `make help` before inventing a new command or target.
- On macOS use `make` (or `gmake`); it finds lazbuild in `/Applications/lazarus` when it is not on PATH.
- Prefer the smallest relevant target: `make`, `make debug`, `make rebuild`, `make run`.

## macOS linking
- Apple's ld from Xcode/CLT 27 rejects the Objective-C method lists FPC 3.2.x emits, and `-ld_classic` is gone. Darwin targets therefore link through LLVM's `ld64.lld` (`brew install lld`) via the shim in `tools/darwin-lld/ld`, taken from Trndi.
- `Gittan.lpi` adds `-FD$(ProjPath)/tools/darwin-lld` for `TargetOS='darwin'` only, so lazbuild and the Lazarus IDE both use it. Do not remove that conditional.
- Rebuilding the Lazarus IDE (for example after installing a package) also needs the shim:
  ```sh
  /Applications/lazarus/lazbuild --build-ide="-FD$PWD/tools/darwin-lld" --ws=cocoa
  ```
  Tools > Build Lazarus inside the IDE uses Apple's ld unless the build profile carries the same `-FD` option.
- Debug builds on macOS must use DWARF 2 (`-gw2`); FPC 3.2.x's DWARF 3 writer fails on Objective-C classes.

## Vendored packages
- `vendor/` holds git submodules: ATSynEdit, its dependencies ATFlatControls and EncConv, and BGRABitmap; EControl and ATSynEdit_Ex for syntax highlighting; and CudaText-lexers, the lexer collection. Clone with `git clone --recursive` or run `git submodule update --init`.
- The Lazarus package links point at these copies, and the IDE is built with ATSynEdit and its dependencies. EControl and ATSynEdit_Ex are runtime-only packages, so changing them needs no IDE rebuild.
- Do not edit files under `vendor/`. Update a package by moving its submodule to a new commit; rebuild the IDE as above if it is one the IDE is built with.

## Syntax highlighting
- `gittan.lexers.pp` loads every EControl lexer (`*.lcf`) from one folder and picks a lexer by file name. `umain.pp` shows two editors side by side, each connected through its own `TATAdapterEControl`; menu commands act on the editor that last had focus.
- CudaText-lexers keeps one subfolder per lexer, but EControl loads from a flat folder. `make lexlib` copies the lexers into `lexlib/` (generated, gitignored); every build target runs it.
- At runtime the folder is found through `GITTAN_LEXLIB`, then `lexlib` beside the executable, then `Contents/Resources/lexlib` in a macOS bundle.
- After assigning a lexer, call the editor's `DoEventChange(0)`. Without it the adapter never parses and the text stays uncolored.

## Git
- `gittan.git.pp` wraps the `git` command line tool (found on PATH) through `RunCommandIndir` from fcl-process; it does not link libgit2. `TGittanRepo.Open` resolves any folder to its work tree root with `rev-parse --show-toplevel`.
- The toolbar's "Open Repository" button uses the `TSelectDirectoryDialog` on the form, then `OpenRepository` in `umain.pp` shows `git diff HEAD` (or `git diff` before the first commit) in the right pane under the Diff lexer and counts changed files from `git status --porcelain` in the status bar.
- The `TTreeView` on the far left lists the repository's files from `git ls-files --cached --others --exclude-standard` (tracked and untracked, ignored files left out), folders first. A file node has `Data` set; folders and submodules have `Data = nil`. Selecting a file loads it into the left editor; a path still in the index but deleted from the work tree is reported in the status bar instead.
- `SetLexer`, `ShowText` and `LoadFile` take a `TPane` so content can go to a pane that does not have focus. The editor split ratio is relative to the width left after the file tree.

## Editing Guidance
- Keep changes focused and minimal. Avoid unrelated refactors or formatting-only edits.
- Unit files must use the `.pp` extension. Formatting follows `JCFSettings.xml` (JEDI Code Formatter).
- When a unit grows large (like a main form), break code out into `.inc` include files.
- PasDoc `{** ... }` comments on public APIs in interfaces; banner-style comments in implementations.
- Cross-platform gotcha: `{$IFDEF UNIX}` does not cover Haiku. Use `{$IF DEFINED(UNIX) OR DEFINED(HAIKU)}` where both apply.
- Do not edit `backup/` directories, `link*.res`, or other generated artifacts.
- Update documentation when behavior or workflow changes.

## Validation
- After code changes, run the narrowest relevant build target first.
- To check a language or RTL detail in isolation, run a snippet through `instantfpc` rather than adding a throwaway unit or project to the tree.
