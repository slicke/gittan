# Gittan. A thin wrapper around lazbuild.

LAZBUILD ?= lazbuild
LPI ?= Gittan.lpi

# Unix: the macOS installer leaves lazbuild in /Applications/lazarus and
# fpcupdeluxe keeps it under ~/fpcupdeluxe, neither on PATH. Try those, as
# Trndi's Makefile does, when LAZBUILD was not set and PATH has none.
ifneq ($(OS),Windows_NT)
  ifeq ($(origin LAZBUILD),file)
    ifeq ($(shell command -v lazbuild 2>/dev/null),)
      LAZBUILD_FOUND := $(firstword $(wildcard /Applications/lazarus/lazbuild \
        $(HOME)/fpcupdeluxe/lazarus/lazbuild))
      ifneq ($(LAZBUILD_FOUND),)
        LAZBUILD := $(LAZBUILD_FOUND)
      endif
    endif
  endif
endif

ifeq ($(OS),Windows_NT)
  WIDGETSET ?= win32
else ifeq ($(shell uname -s),Darwin)
  WIDGETSET ?= cocoa
else
  WIDGETSET ?= qt6
endif

# macOS linker. Apple's ld from Xcode/CLT 27 refuses the Objective-C method
# lists FPC 3.2.x emits ("malformed method list atom"), in the LCL as much as
# in our units, and -ld_classic is gone. Gittan.lpi therefore always links
# Darwin targets through tools/darwin-lld/ld (via -FD), a shim taken from
# Trndi that translates the ld64-only flags and execs LLVM's ld64.lld
# (brew install lld). The shim finds ld64.lld itself; LD64_LLD overrides it.
# The same conditional applies to builds from the Lazarus IDE.
ifeq ($(shell uname -s),Darwin)
  LD64_LLD ?= $(shell command -v ld64.lld 2>/dev/null || \
    ls /opt/homebrew/bin/ld64.lld /usr/local/bin/ld64.lld 2>/dev/null | head -n1)
  export LD64_LLD
  # FPC 3.2.x's DWARF 3 writer stops with an internal error on Objective-C
  # classes; DWARF 2 works and LLDB reads it.
  DEBUG_FLAGS := --opt=-g --opt=-gw2 --opt=-gl
else
  DEBUG_FLAGS := --opt=-g --opt=-gl
endif

LAZFLAGS = --widgetset=$(WIDGETSET)

# Unit tests. tests/gittantests.lpr is a console program over the non-visual
# units (git, worddiff, settings), built with fpc alone: no LCL, no lazbuild.
# On macOS it links through the same lld shim as the app.
FPC ?= fpc
TESTBIN := tests/gittantests
ifeq ($(shell uname -s),Darwin)
  TESTFLAGS := -FD$(CURDIR)/tools/darwin-lld
endif

# Syntax highlighting. vendor/CudaText-lexers keeps each EControl lexer in a
# subfolder of its own, but TecLexerList loads *.lcf from one flat folder, so
# copy them all into $(LEXLIB) beside the executable. Rebuilt on every build;
# it is a few hundred small files. GITTAN_LEXLIB points the app elsewhere.
LEXERS_SRC := vendor/CudaText-lexers
LEXLIB := lexlib

# Application icon. icons/gittan-source.png is the artwork, the cut-out tile;
# `make icons` sizes it with tools/makeicons.swift (macOS only) into
# icons/gittan.png, icons/png/, icons/Gittan.icns and Gittan.ico. Lazarus
# compiles Gittan.ico into the executable for Windows and Linux, but writes no
# icon into the macOS bundle it creates, so every Darwin build copies the .icns
# into Gittan.app and names it in Info.plist. A fresh bundle's Info.plist has
# the project title as CFBundleName with its "&" unescaped, which no plist
# reader accepts; escape it and name the bundle Gittan before adding the icon.
ICON_SRC ?= icons/gittan-source.png
BUNDLE := Gittan.app
ifeq ($(shell uname -s),Darwin)
define bundle_icon
	@set -e; plist="$(BUNDLE)/Contents/Info.plist"; \
	if [ -d "$(BUNDLE)/Contents" ]; then \
	  mkdir -p "$(BUNDLE)/Contents/Resources"; \
	  cp icons/Gittan.icns "$(BUNDLE)/Contents/Resources/Gittan.icns"; \
	  sed -i '' -E 's/&([^a-zA-Z#]|$$)/\&amp;\1/g' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Gittan' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$$plist" >/dev/null 2>&1 || \
	    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Gittan.icns' "$$plist"; \
	  plutil -lint "$$plist" >/dev/null; \
	  touch "$(BUNDLE)"; \
	fi
endef
else
define bundle_icon
endef
endif

.PHONY: all build debug rebuild run clean help lexlib icons test

all: build

help:
	@echo "Targets:"
	@echo "  build     Build $(LPI) (default)"
	@echo "  debug     Build with debug info (DWARF 2 on macOS)"
	@echo "  rebuild   Build with every unit recompiled (-B)"
	@echo "  run       Build, then start Gittan (RUN_ARGS forwards arguments)"
	@echo "  test      Build and run the unit tests in tests/ (TEST_ARGS forwards options)"
	@echo "  lexlib    Copy the lexers from $(LEXERS_SRC) into $(LEXLIB)/ (part of every build)"
	@echo "  icons     Regenerate the icons from ICON_SRC=$(ICON_SRC) (macOS only)"
	@echo "  clean     Remove lib/, $(LEXLIB)/, the test build and the binary"
	@echo "Current: WIDGETSET=$(WIDGETSET) LAZBUILD=$(LAZBUILD) LD64_LLD=$(LD64_LLD)"

build: lexlib
	$(LAZBUILD) $(LAZFLAGS) $(LPI)
	$(bundle_icon)

debug: lexlib
	$(LAZBUILD) $(LAZFLAGS) $(DEBUG_FLAGS) $(LPI)
	$(bundle_icon)

rebuild: lexlib
	$(LAZBUILD) -B $(LAZFLAGS) $(LPI)
	$(bundle_icon)

icons:
	swift tools/makeicons.swift "$(ICON_SRC)" icons Gittan.ico

lexlib:
	@if [ ! -d "$(LEXERS_SRC)/Pascal" ]; then \
	  echo "$(LEXERS_SRC) is empty; run: git submodule update --init"; exit 1; fi
	@rm -rf "$(LEXLIB)" && mkdir -p "$(LEXLIB)"
	@find "$(LEXERS_SRC)" -mindepth 2 -maxdepth 2 \( -name '*.lcf' -o -name '*.cuda-lexmap' \) -exec cp -p {} "$(LEXLIB)/" \;
	@echo "Copied $$(ls "$(LEXLIB)"/*.lcf | wc -l | tr -d ' ') lexers to $(LEXLIB)/"

run: build
	./Gittan $(RUN_ARGS)

test:
	@mkdir -p tests/lib
	$(FPC) -Mobjfpc -Sh -O1 -Fu. -FUtests/lib -FEtests $(TESTFLAGS) tests/gittantests.lpr
	$(TESTBIN) --all --format=plain $(TEST_ARGS)

clean:
	rm -rf lib $(LEXLIB) Gittan Gittan.app Gittan.exe tests/lib $(TESTBIN) $(TESTBIN).exe
