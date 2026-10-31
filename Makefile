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

# The target CPU, for a cross build: `make CPU=x86_64` on Apple Silicon
# builds the Intel macOS Gittan (FPC's macOS installer has ppcx64 and its
# units). Empty builds for the machine's own. The units go in
# lib/<cpu>-<os>-release, apart from the native build's, and the tests in
# tests/lib/<cpu>, but the executable is the same Gittan, so a cross build
# replaces the native one.
CPU ?=

LAZFLAGS = --widgetset=$(WIDGETSET) $(if $(CPU),--cpu=$(CPU))

# The version, Major.Minor from Gittan.lpi's version info and the build
# number CI passes as GITTAN_BUILD (0 in a local build): 0.9.123. Lazarus
# leaves a number that is 0 out of the .lpi, so a missing one is 0.
# `make version` prints it, for CI.
lpi_version_nr = $(or $(shell sed -n -E 's/.*<$(1)VersionNr Value="([0-9]+)".*/\1/p' $(LPI)),0)
GITTAN_VERSION := $(call lpi_version_nr,Major).$(call lpi_version_nr,Minor).$(or $(GITTAN_BUILD),0)

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
TESTLIB := tests/lib$(if $(CPU),/$(CPU))

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
# Its versions (0.1 and 1 from lazbuild) become GITTAN_VERSION.
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
	  /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString $(GITTAN_VERSION)' "$$plist"; \
	  /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion $(GITTAN_VERSION)' "$$plist"; \
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

.PHONY: all build debug rebuild run clean help lexlib icons wordmark dialogicon test deps ide desktop packages version

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
	@echo "  wordmark  Write src/ui/gittan.wordmark.inc from icons/wordmark/gittan-wordmark-<theme>.png"
	@echo "  dialogicon Write src/ui/gittan.dialogicon.inc from icons/dialog/gittan-dialog-<n>.png"
	@echo "  desktop   Install app.gittan.Gittan.desktop and the icons for ./Gittan in ~/.local/share (Linux)"
	@echo "  version   Print the version, $(GITTAN_VERSION) (Major.Minor from $(LPI), GITTAN_BUILD)"
	@echo "  packages  Build the Linux .deb and .rpm into pkg/ (needs fpm and rpmbuild)"
	@echo "  icons     Pack Gittan.icns and Gittan.ico from ICON_MAC_SRC=$(ICON_MAC_SRC) and ICON_PNG_DIR=$(ICON_PNG_DIR) (macOS only)"
	@echo "  clean     Remove lib/, $(LEXLIB)/, the test build and the binary"
	@echo "Current: WIDGETSET=$(WIDGETSET) CPU=$(or $(CPU),native) LAZBUILD=$(LAZBUILD)"

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

# A PNG as a Pascal byte array, for the rules below: $$f the file, $$len its
# size, $$name the constant; appended to $$out. A file missing or empty
# stops the rule, which writes to $$out.new and moves it in place at the
# end, so the include is never left with an empty array.
define png_bytes
test -s $$f || { echo "$$f is missing or empty" >&2; rm -f $$out; exit 1; }; \
echo "  $$name: array[0..$$((len - 1))] of byte = (" >> $$out; \
od -An -v -tu1 $$f | awk -v total=$$len '{ for (i = 1; i <= NF; i++) { k++; \
  printf "%s%s", (c == 0 ? "    " : ""), $$i (k < total ? "," : ""); \
  if (++c == 20) { print ""; c = 0 } } } END { if (c) print "" }' >> $$out; \
echo "  );" >> $$out
endef

# The welcome view's wordmark, icons/wordmark/gittan-wordmark-<theme>.png
# (dark and light, rendered from icons/gittan-wordmark-<theme>.svg with
# Chrome headless; see spec/icon.md), as Pascal byte arrays
# (src/ui/gittan.wordmark.inc, kept in git, so a build needs neither this
# rule nor od and awk).
wordmark:
	@set -e; dest=src/ui/gittan.wordmark.inc; out=$$dest.new; \
	echo "{ Made from icons/wordmark/gittan-wordmark-<theme>.png by make wordmark. }" > $$out; \
	echo "const" >> $$out; \
	for t in Dark Light; do \
	  f=icons/wordmark/gittan-wordmark-$$(echo $$t | tr A-Z a-z).png; len=$$(wc -c < $$f | tr -d ' '); \
	  name=Wordmark$$t; $(png_bytes); \
	done; \
	mv $$out $$dest; echo "wrote $$dest"

# The dialogs' icon, icons/dialog/gittan-dialog-<n>.png (48, 96 and 144
# pixels, rendered from icons/gittan-dialog.svg with Chrome headless; see
# spec/icon.md), as Pascal byte arrays (src/ui/gittan.dialogicon.inc, kept
# in git, so a build needs neither this rule nor od and awk).
DIALOG_ICON_SIZES = 48 96 144
dialogicon:
	@set -e; dest=src/ui/gittan.dialogicon.inc; out=$$dest.new; \
	echo "{ Made from icons/dialog/gittan-dialog-<n>.png by make dialogicon. }" > $$out; \
	echo "const" >> $$out; \
	for n in $(DIALOG_ICON_SIZES); do \
	  f=icons/dialog/gittan-dialog-$$n.png; len=$$(wc -c < $$f | tr -d ' '); \
	  name=DialogIcon$$n; $(png_bytes); \
	done; \
	mv $$out $$dest; echo "wrote $$dest"

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

# Linux: under Wayland the compositor takes a window's icon from the
# .desktop file named after its app_id (app.gittan.Gittan, which Gittan.lpr
# sets with g_set_prgname), never from the executable, and shows a generic
# one without it. The packages install dist/linux's desktop file and the
# icons system wide; `make desktop` installs them for this checkout's Gittan
# in the user's ~/.local/share, its Exec pointing here.
DESKTOP_ID := app.gittan.Gittan
XDG_DATA_HOME ?= $(HOME)/.local/share

# Copies icons/png/gittan-<n>.png into the hicolor theme under $(1).
define install_icons
	for f in $(ICON_PNG_DIR)/gittan-*.png; do \
	  n=$$(basename "$$f" .png); n=$${n#gittan-}; \
	  d="$(1)/icons/hicolor/$${n}x$${n}/apps"; mkdir -p "$$d"; \
	  cp "$$f" "$$d/$(DESKTOP_ID).png"; \
	done
endef

# The Exec line takes the folder from the shell, not from $(CURDIR) in the
# script, so a quote in its path cannot end the script: escaped as a quoted
# argument of the desktop file ("`$\ after a backslash), then its backslashes
# and percent signs doubled, then for sed's replacement.
desktop:
	@set -e; $(call install_icons,$(XDG_DATA_HOME)); \
	d="$(XDG_DATA_HOME)/applications"; mkdir -p "$$d"; \
	exe=$$(printf '%s' "$$(pwd)/Gittan" | sed -e 's/[\\"`$$]/\\&/g' -e 's/\\/\\\\/g' \
	  -e 's/%/%%/g' -e 's/[\\|&]/\\&/g'); \
	sed "s|^Exec=.*|Exec=\"$$exe\" %f|" dist/linux/$(DESKTOP_ID).desktop \
	  > "$$d/$(DESKTOP_ID).desktop"; \
	touch "$(XDG_DATA_HOME)/icons/hicolor"; \
	command -v update-desktop-database >/dev/null && update-desktop-database "$$d" || true; \
	echo "wrote $$d/$(DESKTOP_ID).desktop"

# Linux packages: a .deb and an .rpm made by fpm (gem install fpm; rpmbuild
# for the .rpm) from the release build, staged under $(PKG_ROOT) as they
# install: /usr/bin/gittan, the lexers in /usr/share/gittan/lexlib (which
# gittan.lexers finds from the executable), the desktop file, the AppStream
# metainfo and the icons. The .rpm owns /usr/share/gittan, so removing it
# takes the folder too (dpkg removes an emptied folder itself). The packages
# carry GITTAN_VERSION.
PKG_ROOT := pkg/root
PKG_ARCH ?= native
FPM ?= fpm
FPM_FLAGS = -s dir -n gittan -v $(GITTAN_VERSION) --license GPL-3.0-only \
  --url https://gittan.app --maintainer "Björn Lindh" \
  --description "Git Tree Analyzer & Navigator: a native git client built around the diff" \
  -C $(PKG_ROOT) -p pkg/ -f

packages: build
	@set -e; rm -rf $(PKG_ROOT); \
	mkdir -p $(PKG_ROOT)/usr/bin $(PKG_ROOT)/usr/share/gittan \
	  $(PKG_ROOT)/usr/share/applications $(PKG_ROOT)/usr/share/metainfo; \
	install -m 755 Gittan $(PKG_ROOT)/usr/bin/gittan; \
	cp -r $(LEXLIB) $(PKG_ROOT)/usr/share/gittan/lexlib; \
	install -m 644 dist/linux/$(DESKTOP_ID).desktop $(PKG_ROOT)/usr/share/applications/; \
	install -m 644 dist/linux/$(DESKTOP_ID).metainfo.xml $(PKG_ROOT)/usr/share/metainfo/; \
	$(call install_icons,$(PKG_ROOT)/usr/share)
	$(FPM) $(FPM_FLAGS) -t deb -a $(PKG_ARCH) \
	  --depends 'git >= 1:2.30' --depends 'libgtk-3-0t64 | libgtk-3-0' .
	$(FPM) $(FPM_FLAGS) -t rpm -a $(PKG_ARCH) --directories /usr/share/gittan \
	  --depends 'git >= 2.30' --depends 'libgtk-3.so.0()(64bit)' .

version:
	@echo $(GITTAN_VERSION)

run: build
	"$(RUN_EXE)" $(RUN_ARGS)

test:
	@mkdir -p $(TESTLIB)
	$(FPC) $(if $(CPU),-P$(CPU)) -Mobjfpc -Sh -O1 -Fusrc/core -FU$(TESTLIB) -FEtests tests/gittantests.lpr
	$(TESTBIN) --all --format=plain $(TEST_ARGS)

clean:
	rm -rf lib $(LEXLIB) pkg Gittan Gittan.app Gittan.exe tests/lib $(TESTBIN) $(TESTBIN).exe
