SHELL := /bin/bash
APP        := Yapping
SCHEME     := Yapping
PROJECT    := Yapping.xcodeproj
CONFIG     ?= Debug
BUILD_DIR  := build
APP_PATH   := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP).app
XCB        := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=arm64' -quiet

.PHONY: gen build run stop test clean open icons

gen:
	xcodegen generate

build: gen
	$(XCB) build

run: build stop
	@sleep 1
	open $(APP_PATH)

stop:
	-pkill -x $(APP) 2>/dev/null || true

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=arm64' test 2>&1 \
	  | grep -E "error:|^✔|^✘|^◇ Test run|TEST (SUCCEEDED|FAILED)|Executed" | grep -v linkd; exit $${PIPESTATUS[0]}

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

open: gen
	open $(PROJECT)

# Regenerate app icon + menu bar glyphs from Tools/iconsmith.swift
icons:
	swiftc -O -target arm64-apple-macos26.0 Tools/iconsmith.swift -o $(BUILD_DIR)/iconsmith
	$(BUILD_DIR)/iconsmith $(BUILD_DIR)/icons
	cp $(BUILD_DIR)/icons/icon_*.png Yapping/Resources/Assets.xcassets/AppIcon.appiconset/
	cp $(BUILD_DIR)/icons/MenuBarIdle@*.png Yapping/Resources/Assets.xcassets/MenuBarIdle.imageset/
	cp $(BUILD_DIR)/icons/MenuBarActive@*.png Yapping/Resources/Assets.xcassets/MenuBarActive.imageset/
