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

## Application icon
- `icons/gittan-source.png` is the artwork (a rounded square on a white background with a gray halo). `make icons` runs `tools/makeicons.swift` (macOS only: CoreGraphics and `iconutil`), which measures the outline, cuts the icon out with a transparent background and writes `icons/gittan.png` (1024, the master), `icons/png/gittan-<n>.png` (16 to 512, for Linux desktop files), `icons/Gittan.icns` and `Gittan.ico`. Commit the generated files; other platforms only consume them.
- The halo cannot be told from the icon's light gray right side by color, so the script measures the left, top and right edges and the bottom-left corner profile, where the frame is dark blue, checks it against the dark red bottom-right corner, and mirrors it to the top corners. A new artwork must keep that layout, or the script needs new edge probes.
- `Gittan.ico` beside `Gittan.lpi` is the project icon (`<Icon Value="0"/>` in the .lpi means it is set); Lazarus compiles it into the executable's resources, which the LCL uses for the window and taskbar icon on Windows and Linux. The .icns insets the artwork to Apple's 824/1024 grid so it sits like other dock icons; the .ico and PNGs fill their canvas.
- Lazarus creates `Gittan.app` without an icon, so the Darwin build targets in the Makefile copy `icons/Gittan.icns` into `Contents/Resources` and add `CFBundleIconFile` to `Info.plist` after lazbuild. A bundle built from the Lazarus IDE lacks the icon until the next `make`. Finder caches icons; `touch Gittan.app` or a relaunch of Finder refreshes it.

## Vendored packages
- `vendor/` holds git submodules: ATSynEdit, its dependencies ATFlatControls and EncConv, and BGRABitmap; EControl and ATSynEdit_Ex for syntax highlighting; and CudaText-lexers, the lexer collection. Clone with `git clone --recursive` or run `git submodule update --init`.
- The Lazarus package links point at these copies, and the IDE is built with ATSynEdit and its dependencies. EControl and ATSynEdit_Ex are runtime-only packages, so changing them needs no IDE rebuild.
- Do not edit files under `vendor/`. Update a package by moving its submodule to a new commit; rebuild the IDE as above if it is one the IDE is built with.

## Syntax highlighting
- `gittan.lexers.pp` loads every EControl lexer (`*.lcf`) from one folder and picks a lexer by file name. `umain.pp` shows one read-only editor connected through a `TATAdapterEControl`; the Syntax menu changes its lexer.
- CudaText-lexers keeps one subfolder per lexer, but EControl loads from a flat folder. `make lexlib` copies the lexers into `lexlib/` (generated, gitignored); every build target runs it.
- At runtime the folder is found through `GITTAN_LEXLIB`, then `lexlib` beside the executable, then `Contents/Resources/lexlib` in a macOS bundle.
- After assigning a lexer, call the editor's `DoEventChange(0)`. Without it the adapter never parses and the text stays uncolored.
- `TGittanLexers.Load` normalizes every lexer style: `BgColor` is cleared so lexers only color text (line backgrounds are reserved for the diff colors), and a system font color such as `clWindowText` becomes `clNone`. Cocoa resolves system colors through the desktop theme, so in dark mode they turn white on the editor's light background and the text disappears (seen with the Delphi resources lexer on `.lfm`).
- After replacing the text through `Text` (not `LoadFromFile`), call `WrapInfo.Clear` and `Update(True)`. Setting `Text` skips the wrap rebuild while no fold ranges exist and never flags it, so once the lexer adds folds the old wrap items are reused and lines paint cut off or blank.

## Dark mode
- The native controls (toolbar, tree, status bar, menus) follow the desktop theme on their own; `Info.plist` does not set `NSRequiresAquaSystemAppearance`. Gittan only adapts what it colors itself.
- `gittan.theme.pp` holds `IsDarkMode` (the window system color darker than its text color, so it works with every widgetset), `ColorLuminance` and `LightenForDark`. Nothing forces an appearance the way Trndi's `nsutils.simpledarkmode` does.
- `ApplyTheme` in `umain.pp` resets `Edit.Colors` with `Init` and, in dark mode, sets a dark palette on top; `EditCalcBookmarkColor` picks dark or light diff colors from `FDark`. The LCL raises no event when the desktop theme changes (`OnActivate` does not fire reliably on Cocoa either), so `ThemeTimer` asks `IsDarkMode` every other second and reapplies the theme on a change; Cocoa reports the new system colors right away.
- The lexer collection uses colors tuned for a white background (clNavy, clMaroon, clBlack and so on). `TGittanLexers.NormalizeStyles` remembers every style's color, and `ApplyTheme(ADark)` restores them for light or runs them through `LightenForDark` for dark: black becomes `clNone` so the editor's text color applies, every other dark color is blended toward white until it reaches a fixed brightness.

## Git
- `gittan.git.pp` wraps the `git` command line tool (found on PATH) through `RunCommandIndir` from fcl-process; it does not link libgit2. `TGittanRepo.Open` resolves any folder to its work tree root with `rev-parse --show-toplevel`.
- The toolbar's "Open Repository" button uses the `TSelectDirectoryDialog` on the form (a folder on the command line, `gittan <folder>`, opens one too), then `OpenRepository` in `umain.pp` shows `git diff HEAD` (or `git diff` before the first commit) in the editor under the Diff lexer and counts changed files from `git status --porcelain` in the status bar.
- The `TTreeView` on the left lists only the changed files, taken from the same `git status --porcelain` output through `ChangedPaths` (untracked files included, a rename shown under its new path), folders first. A file node has `Data` set; folders and submodules have `Data = nil`.
- `ChangedPaths` also condenses each file's "XY" status into a `TGittanChangeKind` (`ChangeKind`), stored in the list's `Objects`. The tree shows it as an icon from `TreeImages`: `gittan.icons.pp` draws the icons at startup with BGRABitmap (a direct dependency of the project, as it already is of ATSynEdit), a folder and one colored badge per kind with git's status letter (M, A, D, R, U for untracked, ! for a conflict), at both 16 and 32 pixels through `AddMultipleResolutions` so the tree picks the sharp one on a Retina screen. There are no image files to ship.
- Selecting a file calls `ShowChanges`: `FileChanges` runs `git diff --no-renames -U99999999 HEAD -- path` so the whole file is one hunk, with deleted lines kept in place. The `+`/`-` markers are stripped from the text and become line backgrounds (green added, red deleted) through the editor's second bookmark list (`BookmarkSetForLine_2`), whose entries color a line without a gutter icon; `OnCalcBookmarkColor` maps the kind to the color. An untracked file is read from disk and shown all green. The repository diff on open gets the same colors on its `+`/`-` lines.
- The change view numbers its lines itself (`ShowLineNumbers`): the editor's own numbering would count the deleted lines kept in the text, so every line below a deletion showed a number too high. ATSynEdit has no hook for the number text, but its gutter decor (`GutterDecor`) draws a text per line in the bookmark band. So the number band is hidden, the bookmark band is widened to the number width (`OptGutterWidthBookmarks`, reapplied by the editor on every update, so the option is set rather than the band), and each kept line gets its number in the new file as decor text; a deleted line gets none. `ResetLineNumbers` restores the editor's numbering for the file view and the repository diff, `ApplyTheme` recolors the decor, and `OnChangeZoom` resizes the band. The number style is `All` so both views look alike.
- `NextChangeButton`, a `TBitBtn` floating over the editor's lower right corner, jumps to the first line of the next block of added/deleted lines after the caret (wrapping around to the first block) and scrolls it near the top. It is a child of the editor and must be a windowed control: ATSynEdit paints itself without calling `PaintControls`, so a `TSpeedButton` or any other `TGraphicControl` placed on it never shows. `UpdateNextChange` hides it while the second bookmark list is empty. Its arrow is an image from `ButtonImages` (drawn in `gittan.icons.pp`, dark gray, `GlyphShowMode = gsmAlways`), not a caption: on macOS the push button stays light in dark mode too (its bezel takes the editor's white background), while a caption follows the theme's text color and turned white on white. The same happened with the button placed on the form instead of the editor.
- The editor is a viewer: `ModeReadOnly` is set in `FormCreate`. ATSynEdit silently ignores `Text` and `LoadFromFile` while read-only, so `ShowText` and `OpenFile` clear the mode around the load and set it again. Loading does not clear the second bookmark list, so they call `BookmarkDeleteAll_2` first. There is no Save command.

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
