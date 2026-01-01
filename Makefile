# Xcode iOSアプリ用 Makefile（AIエージェントフレンドリー）
# 使い方:
#   make              → ビルド & シミュレータ起動
#   make build        → ビルドのみ
#   make run          → ビルドして実行（最新ビルド使用）
#   make test         → テスト実行
#   make test-unit   → ユニットテストのみ実行
#   make test-ui      → UIテストのみ実行
#   make lint         → SwiftLint実行
#   make clean        → クリーン

# プロジェクト/スキーム名をここで設定
PROJECT := CaleNote.xcodeproj
SCHEME := CaleNote
# 利用可能なシミュレータを確認: xcrun simctl list devices available
# xcodebuildが認識できるデバイスを使用
# iPhone 17はOS 26.2のみ、iPhone 16はOS 18.6で利用可能
# OS=latestは環境によって異なるバージョンを拾う可能性があるため、固定バージョンを推奨
DESTINATION := platform=iOS Simulator,name=iPhone 17,OS=26.2

# xcbeautify がインストールされている前提（brew install xcbeautify）
# インストールされていない場合は、xcbeautify を削除して通常の出力を使用

.PHONY: all build run test test-unit test-ui lint clean check-xcbeautify

all: build run

check-xcbeautify:
	@which xcbeautify > /dev/null || (echo "⚠️  xcbeautify がインストールされていません。brew install xcbeautify でインストールしてください。" && exit 1)

build: check-xcbeautify
	@echo "🔨 Building $(SCHEME)..."
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		clean build | xcbeautify

run: check-xcbeautify
	@echo "🚀 Running $(SCHEME) on simulator..."
	@set -euo pipefail; \
	DEST_NAME=$$(echo "$(DESTINATION)" | sed -n "s/.*name=\([^,]*\).*/\1/p"); \
	if [ -z "$$DEST_NAME" ]; then echo "DESTINATION から name を取れません: $(DESTINATION)"; exit 1; fi; \
	echo "📱 Booting simulator: $$DEST_NAME"; \
	open -a Simulator >/dev/null 2>&1 || true; \
	xcrun simctl boot "$$DEST_NAME" >/dev/null 2>&1 || true; \
	echo "🔨 Building (for simulator)..."; \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-configuration Debug \
		build | xcbeautify; \
	APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -showBuildSettings \
		| awk -F' = ' '/TARGET_BUILD_DIR/{t=$$2} /FULL_PRODUCT_NAME/{p=$$2} END{print t "/" p}'); \
	if [ ! -d "$$APP_PATH" ]; then echo "App not found: $$APP_PATH"; exit 1; fi; \
	BUNDLE_ID=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$APP_PATH/Info.plist"); \
	if [ -z "$$BUNDLE_ID" ]; then echo "Bundle id not found"; exit 1; fi; \
	echo "📦 Installing: $$APP_PATH"; \
	xcrun simctl install booted "$$APP_PATH"; \
	echo "🚀 Launching: $$BUNDLE_ID"; \
	xcrun simctl launch booted "$$BUNDLE_ID"

test: check-xcbeautify
	@echo "🧪 Running all tests..."
	@set -o pipefail && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' | xcbeautify

test-unit: check-xcbeautify
	@echo "🧪 Running unit tests..."
	@set -o pipefail && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-only-testing:CaleNoteTests | xcbeautify

test-ui: check-xcbeautify
	@echo "🧪 Running UI tests..."
	@set -o pipefail && xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-only-testing:CaleNoteUITests | xcbeautify

lint:
	@echo "🔍 Running SwiftLint..."
	@if ! command -v swiftlint > /dev/null 2>&1; then \
		echo "⚠️  SwiftLint がインストールされていません。brew install swiftlint でインストールしてください。"; \
		exit 1; \
	fi
	@if [ ! -f .swiftlint.yml ]; then \
		echo "⚠️  .swiftlint.yml が見つかりません。スキップします。"; \
	else \
		swiftlint --config .swiftlint.yml; \
	fi

clean:
	@echo "🧹 Cleaning..."
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -quiet 2>/dev/null || true
