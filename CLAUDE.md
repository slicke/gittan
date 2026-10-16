# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Gittan is a Free Pascal/Lazarus desktop app. AGENTS.md contains the working rules for this repo, including how macOS links, how the vendored ATSynEdit packages are installed in Lazarus, and how syntax highlighting is wired up. Read it before building.

## Commands

```sh
make            # build Gittan.lpi (cocoa on macOS)
make debug      # debug info, DWARF 2 on macOS
make rebuild    # recompile every unit
make run        # build and start
make lexlib     # refresh lexlib/ from vendor/CudaText-lexers (every build does this)
make clean
```

This machine has Lazarus 5.0 RC1 in `/Applications/lazarus` (lazbuild is not on PATH; the Makefile finds it) and FPC 3.2.4 in `/usr/local/bin`.