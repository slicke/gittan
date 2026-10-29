# Gittan. A thin wrapper around lazbuild.

LAZBUILD ?= lazbuild
LPI ?= Gittan.lpi

# Unix: the macOS installer leaves lazbuild in /Applications/lazarus and
# fpcupdeluxe keeps it under ~/fpcupdeluxe, neither on PATH. Try those, as
# Trndi's Makefile does, when LAZBUILD was not set and PATH has none. The
# shell tests the paths, since wildcard and firstword split at spaces (a
# home folder with one in its name); the recipes quote $(LAZBUILD).
ifneq ($(OS),Windows_NT)
  ifeq ($(origin LAZBUILD),file)
    ifeq ($(shell command -v lazbuild 2>/dev/null),)
      LAZBUILD_FOUND := $(shell for f in /Applications/lazarus/lazbuild \
        "$(HOME)/fpcupdeluxe/lazarus/lazbuild"; do \
        if [ -x "$$f" ]; then echo "$$f"; break; fi; done)
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
  # gtk3: GTK draws its own window decoration under Wayland, so a form can
  # take the title bar (gtk_window_set_titlebar) and keep the shadow and
  # the rounded corners; Qt 6 would need a frameless window without them.
  WIDGETSET ?= gtk3
endif

ifeq ($(shell uname -s),Darwin)
  # FPC 3.2.x's DWARF 3 writer stops with an internal error on Objective-C
  # classes; DWARF 2 works and LLDB reads it.
  DEBUG_FLAGS := --opt=-g --opt=-gw2 --opt=-gl
else
  DEBUG_FLAGS := --opt=-g --opt=-gl
endif

LAZFLAGS = --widgetset=$(WIDGETSET)

# Gittan.lpi has two build modes: Release (-O2, no debug info, smart linked
# and stripped, its units in lib/<cpu>-<os>-release) for build, rebuild and
# run, which CI ships, and Default (debug info, line info) for debug.
# lazbuild's --opt can add flags but never take -g away, so a mode it is.
RELEASE_MODE := --bm=Release
DEBUG_MODE := --bm=Default

# Unit tests. tests/gittantests.lpr is a console program over the non-visual
# units in src/core (a tests/test<name>.pp each), built with fpc alone: no
# LCL, no lazbuild.
FPC ?= fpc
TESTBIN := tests/gittantests

# Syntax highlighting. vendor/CudaText-lexers keeps each EControl lexer in a
# subfolder of its own, but TecLexerList loads *.lcf from one flat folder, so
# copy them all into $(LEXLIB) beside the executable. Rebuilt on every build;
# it is a few hundred small files. GITTAN_LEXLIB points the app elsewhere.
# lexers/ holds Gittan's own lexers in the same layout.
LEXERS_SRC := vendor/CudaText-lexers
LEXERS_OWN := lexers
LEXLIB := lexlib

# Vendored packages, in dependency order: the list is VENDOR_PACKAGES in
# .github/workflows/build.yml, and a new package goes in both. `make deps`
# registers each with --add-package-link and compiles it, after a fresh clone
# or a submodule move; `make ide` rebuilds the Lazarus IDE, which is built with
# ATSynEdit, ATFlatControls, EncConv and BGRABitmap, with the IDE's own build
# profile (its widgetset too).
VENDOR_PACKAGES := \
  vendor/ATFlatControls/atflatcontrols/atflatcontrols_package.lpk \
  vendor/EncConv/encconv/encconv_package.lpk \
  vendor/BGRABitmap/bgrabitmap/bgrabitmappack.lpk \
  vendor/ATSynEdit/atsynedit/atsynedit_package.lpk \
  vendor/EControl/econtrol/econtrol_package.lpk \
  vendor/ATSynEdit_Ex/atsynedit_ex/atsynedit_ex_package.lpk \
  vendor/metadarkstyle/metadarkstyle.lpk \
  vendor/lazink/lazink.lpk

# Application icon. The artwork comes finished: icons/gittan-mac.png is the
# macOS icon at 1024 pixels and icons/png/gittan-<n>.png the Windows and Linux
# one at each size; `make icons` packs them with tools/makeicons.swift (macOS
# only) into icons/Gittan.icns and Gittan.ico. Lazarus
# compiles Gittan.ico into the executable for Windows and Linux, but writes no
# icon into the macOS bundle it creates, so every Darwin build copies the .icns
# into Gittan.app and names it in Info.plist. A fresh bundle's Info.plist has
# the project title as CFBundleName with its "&" unescaped, which no plist
# reader accepts; escape it and name the bundle Gittan before adding the icon.
# macOS 26 and later take the icon from icons/Assets.car instead (named by
# CFBundleIconName), which `make icons` compiles from the Icon Composer document
# icons/Gittan.icon with Xcode's actool; without it they put the .icns on a
# grey tile of their own.
ICON_MAC_SRC ?= icons/gittan-mac.png
ICON_PNG_DIR ?= icons/png
ACTOOL ?= $(or $(wildcard /Applications/Xcode.app/Contents/Developer/usr/bin/actool),$(shell xcrun --find actool 2>/dev/null),actool)
BUNDLE := Gittan.app
ifeq ($(shell uname -s),Darwin)
define bundle_icon
	@set -e; plist="$(BUNDLE)/Contents/Info.plist"; \
	if [ -d "$(BUNDLE)/Contents" ]; then \
	  mkdir -p "$(BUNDLE)/Contents/Resources"; \
	  cp icons/Gittan.icns "$(BUNDLE)/Contents/Resources/Gittan.icns"; \
	  cp icons/Assets.car "$(BUNDLE)/Contents/Resources/Assets.car"; \
	  sed -i '' -E 's/&([^a-zA-Z#]|$$)/\&amp;\1/g' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Gittan' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$$plist" >/dev/null 2>&1 || \
	    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Gittan.icns' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$$plist" >/dev/null 2>&1 || \
	    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string Gittan' "$$plist"; \
	  plutil -lint "$$plist" >/dev/null; \
	  touch "$(BUNDLE)"; \
	fi
endef
else
define bundle_icon
endef
endif

.PHONY: all build debug rebuild run clean help lexlib icons wordmark dialogicon test deps ide

all: build

help:
	@echo "Targets:"
	@echo "  build     Build $(LPI) optimized, without debug info (default)"
	@echo "  debug     Build with debug info (DWARF 2 on macOS)"
	@echo "  rebuild   Build with every unit recompiled (-B)"
	@echo "  run       Build, then start Gittan (RUN_ARGS forwards arguments)"
	@echo "  test      Build and run the unit tests in tests/ (TEST_ARGS forwards options)"
	@echo "  lexlib    Copy the lexers from $(LEXERS_SRC) and $(LEXERS_OWN) into $(LEXLIB)/ (part of every build)"
	@echo "  deps      Register the vendored packages with lazbuild and compile them"
	@echo "  ide       Rebuild the Lazarus IDE (after ATSynEdit, ATFlatControls, EncConv or BGRABitmap moves)"
	@echo "  wordmark  Write src/ui/gittan.wordmark.inc from icons/gittan-wordmark.svg"
	@echo "  dialogicon Write src/ui/gittan.dialogicon.inc from icons/dialog/gittan-dialog-<n>.png"
	@echo "  icons     Pack Gittan.icns and Gittan.ico from ICON_MAC_SRC=$(ICON_MAC_SRC) and ICON_PNG_DIR=$(ICON_PNG_DIR) (macOS only)"
	@echo "  clean     Remove lib/, $(LEXLIB)/, the test build and the binary"
	@echo "Current: WIDGETSET=$(WIDGETSET) LAZBUILD=$(LAZBUILD)"

build: lexlib
	"$(LAZBUILD)" $(LAZFLAGS) $(RELEASE_MODE) $(LPI)
	$(bundle_icon)

debug: lexlib
	"$(LAZBUILD)" $(LAZFLAGS) $(DEBUG_MODE) $(DEBUG_FLAGS) $(LPI)
	$(bundle_icon)

rebuild: lexlib
	"$(LAZBUILD)" -B $(LAZFLAGS) $(RELEASE_MODE) $(LPI)
	$(bundle_icon)

deps:
	@set -e; for lpk in $(VENDOR_PACKAGES); do \
	  if [ ! -f "$$lpk" ]; then \
	    echo "$$lpk is missing; run: git submodule update --init"; exit 1; fi; \
	  "$(LAZBUILD)" --add-package-link "$$lpk"; \
	  "$(LAZBUILD)" $(LAZFLAGS) "$$lpk"; \
	done

ide:
	"$(LAZBUILD)" --build-ide=

icons:
	swift tools/makeicons.swift "$(ICON_MAC_SRC)" "$(ICON_PNG_DIR)" icons Gittan.ico
	@set -e; out=$$(mktemp -d); \
	"$(ACTOOL)" "$(CURDIR)/icons/Gittan.icon" --compile "$$out" --platform macosx \
	  --minimum-deployment-target 11.0 --app-icon Gittan \
	  --output-partial-info-plist "$$out/partial.plist" >/dev/null; \
	cp "$$out/Assets.car" icons/Assets.car; rm -rf "$$out"; \
	echo "wrote icons/Assets.car"

# The welcome view's wordmark, icons/gittan-wordmark.svg, as a Pascal string
# constant (src/ui/gittan.wordmark.inc, kept in git, so a build needs neither
# this rule nor awk): one line of the constant per element.
wordmark:
	awk 'BEGIN { print "{ Made from icons/gittan-wordmark.svg by make wordmark. }" } \
	  { gsub(/></, ">\n<"); n = split($$0, L, "\n"); \
	    for (i = 1; i <= n; i++) { gsub(/\x27/, "\x27\x27", L[i]); print "  \x27" L[i] "\x27 +" } } \
	  END { print "  \x27\x27" }' icons/gittan-wordmark.svg > src/ui/gittan.wordmark.inc

# The dialogs' icon, icons/dialog/gittan-dialog-<n>.png (48, 96 and 144
# pixels, rendered from icons/gittan-dialog.svg with Chrome headless; see
# spec/icon.md), as Pascal byte arrays (src/ui/gittan.dialogicon.inc, kept
# in git, so a build needs neither this rule nor od and awk).
DIALOG_ICON_SIZES = 48 96 144
dialogicon:
	@set -e; out=src/ui/gittan.dialogicon.inc; \
	echo "{ Made from icons/dialog/gittan-dialog-<n>.png by make dialogicon. }" > $$out; \
	echo "const" >> $$out; \
	for n in $(DIALOG_ICON_SIZES); do \
	  f=icons/dialog/gittan-dialog-$$n.png; len=$$(wc -c < $$f | tr -d ' '); \
	  echo "  DialogIcon$$n: array[0..$$((len - 1))] of byte = (" >> $$out; \
	  od -An -v -tu1 $$f | awk -v total=$$len '{ for (i = 1; i <= NF; i++) { k++; \
	    printf "%s%s", (c == 0 ? "    " : ""), $$i (k < total ? "," : ""); \
	    if (++c == 20) { print ""; c = 0 } } } END { if (c) print "" }' >> $$out; \
	  echo "  );" >> $$out; \
	done; \
	echo "wrote $$out"

lexlib:
	@if [ ! -d "$(LEXERS_SRC)/Pascal" ]; then \
	  echo "$(LEXERS_SRC) is empty; run: git submodule update --init"; exit 1; fi
	@rm -rf "$(LEXLIB)" && mkdir -p "$(LEXLIB)"
	@find "$(LEXERS_SRC)" "$(LEXERS_OWN)" -mindepth 2 -maxdepth 2 \( -name '*.lcf' -o -name '*.cuda-lexmap' \) -exec cp -p {} "$(LEXLIB)/" \;
	@echo "Copied $$(ls "$(LEXLIB)"/*.lcf | wc -l | tr -d ' ') lexers to $(LEXLIB)/"

# macOS: started as ./Gittan, Gittan gets neither a Dock icon nor a menu bar;
# through the bundle's link it is the app, and still prints to the terminal.
ifeq ($(shell uname -s),Darwin)
  RUN_EXE := ./$(BUNDLE)/Contents/MacOS/Gittan
else
  RUN_EXE := ./Gittan
endif

run: build
	"$(RUN_EXE)" $(RUN_ARGS)

test:
	@mkdir -p tests/lib
	$(FPC) -Mobjfpc -Sh -O1 -Fusrc/core -FUtests/lib -FEtests tests/gittantests.lpr
	$(TESTBIN) --all --format=plain $(TEST_ARGS)

clean:
	rm -rf lib $(LEXLIB) Gittan Gittan.app Gittan.exe tests/lib $(TESTBIN) $(TESTBIN).exe
