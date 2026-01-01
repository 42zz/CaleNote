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
DESTINATION := platform=iOS Simulator,name=iPhone 16

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
	@set -o pipefail && xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		build -quiet | xcbeautify || true
	@echo "📱 Launching app..."
	@xcrun simctl boot "iPhone 16" 2>/dev/null || true
	@xcrun simctl install booted $$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -showBuildSettings 2>/dev/null | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= *//')/$(SCHEME).app 2>/dev/null || true
	@xcrun simctl launch booted com.yourcompany.$(SCHEME) 2>/dev/null || echo "⚠️  アプリの起動に失敗しました。Xcodeから直接実行してください。"

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
	@swiftlint --config .swiftlint.yml || (echo "⚠️  SwiftLint がインストールされていません。brew install swiftlint でインストールしてください。" && exit 1)

clean:
	@echo "🧹 Cleaning..."
	@xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
