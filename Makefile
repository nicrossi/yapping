APP        := Yapping
SCHEME     := Yapping
PROJECT    := Yapping.xcodeproj
CONFIG     ?= Debug
BUILD_DIR  := build
APP_PATH   := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP).app
XCB        := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=arm64' -quiet

.PHONY: gen build run stop test clean open

gen:
	xcodegen generate

build: gen
	$(XCB) build

run: build stop
	open $(APP_PATH)

stop:
	-pkill -x $(APP) 2>/dev/null || true

test: gen
	$(XCB) test

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

open: gen
	open $(PROJECT)
