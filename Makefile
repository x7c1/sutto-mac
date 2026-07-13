APP_NAME := Sutto
CONFIG ?= release
BINARY := .build/$(CONFIG)/$(APP_NAME)
BUNDLE := .build/$(APP_NAME).app

# Optional, git-ignored per-machine settings (e.g. CODESIGN_IDENTITY).
# More robust than a shell-profile export: it applies to every invocation
# in this checkout, including builds run by tools and agents.
-include local.mk

# With Command Line Tools only, SwiftPM needs explicit flags to find Swift
# Testing (empty with full Xcode). Full story: docs/guides/testing.md
DEVELOPER_DIR_PATH := $(shell xcode-select -p)
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR_PATH)))
TESTING_FRAMEWORKS := $(DEVELOPER_DIR_PATH)/Library/Developer/Frameworks
SWIFT_TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(TESTING_FRAMEWORKS) \
	-Xswiftc -plugin-path -Xswiftc $(DEVELOPER_DIR_PATH)/usr/lib/swift/host/plugins/testing \
	-Xlinker -F$(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(DEVELOPER_DIR_PATH)/Library/Developer/usr/lib
endif

.PHONY: build test e2e app run clean

build:
	swift build -c $(CONFIG)

# Unit tests only. The SuttoE2ETests module needs the Accessibility (TCC)
# permission, so the default run must never execute it (CI runs this target);
# `make e2e` runs it instead. --skip/--filter match test identifiers, which
# start with the module name, so this pair splits the suites robustly no
# matter what tests are added to either side.
test:
	swift test $(SWIFT_TEST_FLAGS) --skip SuttoE2ETests

# Local-only end-to-end suite: drives the freshly assembled bundle (hence
# the `app` dependency) with injected keystrokes and the Accessibility API.
# Needs the Accessibility permission granted to the terminal this runs
# from — see "End-to-end tests" in docs/guides/testing.md.
e2e: app
	swift test $(SWIFT_TEST_FLAGS) --filter SuttoE2ETests

# Assemble a minimal .app bundle from the SwiftPM binary. SwiftPM alone
# does not produce bundles, and LSUIElement only takes effect when the
# process runs from a bundle with an Info.plist.
#
# With CODESIGN_IDENTITY set (make variable or environment), the bundle is
# signed so that the TCC Accessibility grant survives rebuilds; unset, the
# bundle stays unsigned as before. Development-only convenience, unrelated
# to distribution signing — see "Keeping the Accessibility permission
# across rebuilds" in docs/guides/debugging.md.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Packaging/Info.plist $(BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	plutil -lint $(BUNDLE)/Contents/Info.plist
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(CODESIGN_IDENTITY)" $(BUNDLE); \
		echo "codesigned $(BUNDLE) with identity: $(CODESIGN_IDENTITY)"; \
	fi

# Quit any running instance first: `open` only activates an already-running
# app, so without this the freshly built binary would never launch.
run: app
	@if pgrep -xq $(APP_NAME); then \
		pkill -x $(APP_NAME); \
		while pgrep -xq $(APP_NAME); do sleep 0.1; done; \
	fi
	open $(BUNDLE)

clean:
	rm -rf $(BUNDLE)
	swift package clean
