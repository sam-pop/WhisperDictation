SDK := $(shell xcrun --sdk macosx --show-sdk-path)
ARCH := $(shell uname -m)
TARGET := $(ARCH)-apple-macos26.0
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/WhisperDictation.app

SWIFT_FILES := \
	WhisperDictation/Utilities/Settings.swift \
	WhisperDictation/Engine/WhisperBridge.swift \
	WhisperDictation/Engine/AudioCapture.swift \
	WhisperDictation/Engine/TextInjector.swift \
	WhisperDictation/Engine/SoundFeedback.swift \
	WhisperDictation/Engine/ModelManager.swift \
	WhisperDictation/Utilities/HotkeyMonitor.swift \
	WhisperDictation/Utilities/PermissionManager.swift \
	WhisperDictation/Engine/DictationEngine.swift \
	WhisperDictation/UI/MenuBarView.swift \
	WhisperDictation/UI/SettingsView.swift \
	WhisperDictation/UI/OnboardingView.swift \
	WhisperDictation/App/WhisperDictationApp.swift

LIBS := -lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas -lc++
FRAMEWORKS := -framework Accelerate -framework Metal -framework MetalKit -framework AVFoundation -framework CoreGraphics -framework AppKit -framework Foundation

.PHONY: all clean whisper model app run

all: whisper app

whisper:
	./scripts/build-whisper.sh

model:
	./scripts/download-model.sh small.en

$(BUILD_DIR)/WhisperDictation: $(SWIFT_FILES) lib/libwhisper.a
	@mkdir -p $(BUILD_DIR)
	xcrun swiftc \
		-sdk "$(SDK)" \
		-target $(TARGET) \
		-import-objc-header WhisperDictation/WhisperDictation-Bridging-Header.h \
		-I lib -L lib \
		$(LIBS) $(FRAMEWORKS) \
		-parse-as-library \
		$(SWIFT_FILES) \
		-o $@

app: $(BUILD_DIR)/WhisperDictation
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp $(BUILD_DIR)/WhisperDictation "$(APP_BUNDLE)/Contents/MacOS/"
	@sed \
		-e 's/$$(EXECUTABLE_NAME)/WhisperDictation/g' \
		-e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/com.sampop.WhisperDictation/g' \
		-e 's/$$(PRODUCT_NAME)/WhisperDictation/g' \
		-e 's/$$(DEVELOPMENT_LANGUAGE)/en/g' \
		WhisperDictation/Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"
	@echo "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf $(BUILD_DIR)
