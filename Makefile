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

# Syntax highlighting. vendor/CudaText-lexers keeps each EControl lexer in a
# subfolder of its own, but TecLexerList loads *.lcf from one flat folder, so
# copy them all into $(LEXLIB) beside the executable. Rebuilt on every build;
# it is a few hundred small files. GITTAN_LEXLIB points the app elsewhere.
LEXERS_SRC := vendor/CudaText-lexers
LEXLIB := lexlib

.PHONY: all build debug rebuild run clean help lexlib

all: build

help:
	@echo "Targets:"
	@echo "  build     Build $(LPI) (default)"
	@echo "  debug     Build with debug info (DWARF 2 on macOS)"
	@echo "  rebuild   Build with every unit recompiled (-B)"
	@echo "  run       Build, then start Gittan (RUN_ARGS forwards arguments)"
	@echo "  lexlib    Copy the lexers from $(LEXERS_SRC) into $(LEXLIB)/ (part of every build)"
	@echo "  clean     Remove lib/, $(LEXLIB)/ and the binary"
	@echo "Current: WIDGETSET=$(WIDGETSET) LAZBUILD=$(LAZBUILD) LD64_LLD=$(LD64_LLD)"

build: lexlib
	$(LAZBUILD) $(LAZFLAGS) $(LPI)

debug: lexlib
	$(LAZBUILD) $(LAZFLAGS) $(DEBUG_FLAGS) $(LPI)

rebuild: lexlib
	$(LAZBUILD) -B $(LAZFLAGS) $(LPI)

lexlib:
	@if [ ! -d "$(LEXERS_SRC)/Pascal" ]; then \
	  echo "$(LEXERS_SRC) is empty; run: git submodule update --init"; exit 1; fi
	@rm -rf "$(LEXLIB)" && mkdir -p "$(LEXLIB)"
	@find "$(LEXERS_SRC)" -mindepth 2 -maxdepth 2 -name '*.lcf' -exec cp -p {} "$(LEXLIB)/" \;
	@echo "Copied $$(ls "$(LEXLIB)" | wc -l | tr -d ' ') lexers to $(LEXLIB)/"

run: build
	./Gittan $(RUN_ARGS)

clean:
	rm -rf lib $(LEXLIB) Gittan Gittan.app Gittan.exe
