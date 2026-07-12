APP_NAME := Sutto
CONFIG ?= release
BINARY := .build/$(CONFIG)/$(APP_NAME)
BUNDLE := .build/$(APP_NAME).app

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

.PHONY: build test app run clean

build:
	swift build -c $(CONFIG)

test:
	swift test $(SWIFT_TEST_FLAGS)

# Assemble a minimal .app bundle from the SwiftPM binary. SwiftPM alone
# does not produce bundles, and LSUIElement only takes effect when the
# process runs from a bundle with an Info.plist.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Packaging/Info.plist $(BUNDLE)/Contents/Info.plist
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	plutil -lint $(BUNDLE)/Contents/Info.plist

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
