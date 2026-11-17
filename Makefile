# Builds the Quick Look extension with the Command Line Tools only — no Xcode project needed.

VERSION     ?= 2.0.0
BUNDLE_ID   ?= nl.LauLamanApps.MarkdownPreview
MIN_MACOS   ?= 14.0
ARCHS       ?= arm64
INSTALL_DIR ?= /Applications
SIGN_ID     ?= -

APP_NAME  = MarkdownEditor
LEGACY_NAME = MarkdownPreview
BUILD     = build
APP       = $(BUILD)/$(APP_NAME).app
APPEX     = $(APP)/Contents/PlugIns/$(APP_NAME)Extension.appex
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

SHARED_SRC = $(wildcard Sources/Shared/*.swift)
EXT_SRC    = $(wildcard Sources/Extension/*.swift) $(SHARED_SRC)
APP_SRC    = $(wildcard Sources/App/*.swift) $(SHARED_SRC)
CLI_SRC    = $(wildcard Sources/CLI/*.swift) $(SHARED_SRC)

SWIFTC = xcrun swiftc -O -swift-version 5

.PHONY: all app install uninstall test release clean icons

all: app

app: $(APP)

WEB_FILES  = $(shell find Resources/Web -type f)

$(APP): $(EXT_SRC) $(APP_SRC) $(WEB_FILES) Resources/Icons/*.icns Resources/*.plist Resources/*.entitlements LICENSE Makefile
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APPEX)/Contents/MacOS $(BUILD)/obj
	@for arch in $(ARCHS); do \
		echo "→ compiling ($$arch)"; \
		$(SWIFTC) -target $$arch-apple-macos$(MIN_MACOS) -module-name $(APP_NAME)Extension \
			-parse-as-library -application-extension \
			-Xlinker -e -Xlinker _NSExtensionMain \
			-framework QuickLookUI -framework UniformTypeIdentifiers \
			$(EXT_SRC) -o $(BUILD)/obj/ext-$$arch || exit 1; \
		$(SWIFTC) -target $$arch-apple-macos$(MIN_MACOS) -module-name $(APP_NAME) \
			-framework WebKit -framework SwiftUI -framework UniformTypeIdentifiers \
			$(APP_SRC) -o $(BUILD)/obj/app-$$arch || exit 1; \
	done
	@lipo -create $(foreach a,$(ARCHS),$(BUILD)/obj/ext-$(a)) -output $(APPEX)/Contents/MacOS/$(APP_NAME)Extension
	@lipo -create $(foreach a,$(ARCHS),$(BUILD)/obj/app-$(a)) -output $(APP)/Contents/MacOS/$(APP_NAME)
	@# Web assets: everything for the app, only the stylesheets for Quick Look (it can't run scripts)
	@mkdir -p $(APP)/Contents/Resources $(APPEX)/Contents/Resources/Web
	@cp -R Resources/Web $(APP)/Contents/Resources/
	@cp -R Resources/Web/base.css Resources/Web/themes $(APPEX)/Contents/Resources/Web/
	@cp -R ThirdPartyLicenses $(APP)/Contents/Resources/
	@cp LICENSE $(APP)/Contents/Resources/LICENSE.txt
	@cp Resources/Icons/AppIcon.icns Resources/Icons/MarkdownDocument.icns $(APP)/Contents/Resources/
	@sed -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' Resources/Extension-Info.plist > $(APPEX)/Contents/Info.plist
	@sed -e 's/__BUNDLE_ID__/$(BUNDLE_ID)/g' -e 's/__VERSION__/$(VERSION)/g' Resources/App-Info.plist > $(APP)/Contents/Info.plist
	@codesign --force --sign "$(SIGN_ID)" --options runtime --entitlements Resources/Extension.entitlements $(APPEX)
	@codesign --force --sign "$(SIGN_ID)" --options runtime --entitlements Resources/App.entitlements $(APP)
	@echo "✓ built $(APP)"

install: app
	@echo "→ installing to $(INSTALL_DIR)"
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@# The app used to be called Markdown Preview; its copy carries the same extension
	@if [ -d "$(INSTALL_DIR)/$(LEGACY_NAME).app" ]; then \
		pluginkit -r "$(INSTALL_DIR)/$(LEGACY_NAME).app/Contents/PlugIns/$(LEGACY_NAME)Extension.appex" 2>/dev/null; \
		$(LSREGISTER) -u "$(INSTALL_DIR)/$(LEGACY_NAME).app" 2>/dev/null; \
		rm -rf "$(INSTALL_DIR)/$(LEGACY_NAME).app"; \
		echo "→ removed old $(LEGACY_NAME).app"; \
	fi
	@cp -R $(APP) "$(INSTALL_DIR)/"
	@# Keep only the installed copy registered, so Quick Look can't pick the build folder one
	@$(LSREGISTER) -u $(APP) 2>/dev/null || true
	@$(LSREGISTER) -f -R "$(INSTALL_DIR)/$(APP_NAME).app"
	@pluginkit -a "$(INSTALL_DIR)/$(APP_NAME).app/Contents/PlugIns/$(APP_NAME)Extension.appex"
	@pluginkit -e use -i $(BUNDLE_ID).QuickLook
	@# Running Quick Look processes keep the previous build loaded until restarted
	@killall $(APP_NAME)Extension $(LEGACY_NAME)Extension QuickLookUIService 2>/dev/null; true
	@qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1; true
	@echo "✓ installed. Select a .md file in Finder and press Space."

uninstall:
	@pluginkit -r "$(INSTALL_DIR)/$(APP_NAME).app/Contents/PlugIns/$(APP_NAME)Extension.appex" 2>/dev/null || true
	@$(LSREGISTER) -u "$(INSTALL_DIR)/$(APP_NAME).app" 2>/dev/null || true
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@killall $(APP_NAME)Extension $(LEGACY_NAME)Extension QuickLookUIService 2>/dev/null; true
	@qlmanage -r >/dev/null 2>&1; true
	@echo "✓ removed $(INSTALL_DIR)/$(APP_NAME).app"

$(BUILD)/md2html: $(CLI_SRC)
	@mkdir -p $(BUILD)
	@$(SWIFTC) -module-name md2html $(CLI_SRC) -o $@

$(BUILD)/preview-check: Tests/PreviewCheck/main.swift Sources/App/WebResourceHandler.swift $(SHARED_SRC)
	@mkdir -p $(BUILD)
	@$(SWIFTC) -module-name PreviewCheck -framework WebKit Tests/PreviewCheck/main.swift Sources/App/WebResourceHandler.swift $(SHARED_SRC) -o $@

$(BUILD)/editor-check: Tests/EditorCheck/main.swift Sources/App/MarkdownTextView.swift Sources/App/Settings.swift $(SHARED_SRC)
	@mkdir -p $(BUILD)
	@$(SWIFTC) -module-name EditorCheck Tests/EditorCheck/main.swift Sources/App/MarkdownTextView.swift Sources/App/Settings.swift $(SHARED_SRC) -o $@

test: $(BUILD)/md2html $(BUILD)/preview-check $(BUILD)/editor-check
	@./Tests/run.sh $(BUILD)/md2html
	@$(BUILD)/editor-check
	@$(BUILD)/preview-check Tests/cases/extensions.md

release: clean app
	@cd $(BUILD) && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME)-$(VERSION).zip
	@shasum -a 256 $(BUILD)/$(APP_NAME)-$(VERSION).zip

# Regenerates Resources/Icons from Tools/make-icons.swift
icons:
	@xcrun swift Tools/make-icons.swift Resources/Icons

clean:
	@rm -rf $(BUILD)
