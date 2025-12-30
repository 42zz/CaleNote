# Changelog

All notable changes to CaleNote will be documented in this file.

## [Unreleased]

### Added - 2025/12/30

#### Issue #1: SwiftData ScheduleEntry Model
- ScheduleEntry.swift でスケジュールエントリのコアデータモデルを実装
- Google Calendar との同期状態を追跡するための syncStatus プロパティを追加
- タグベースの検索をサポート
- CaleNoteApp.swift に ModelContainer を登録

#### Issue #16: Error Handling and Retry Logic
- CaleNoteError.swift で包括的なエラー型システムを実装
  - NetworkError: ネットワーク関連エラー
  - APIError: Google Calendar API エラー
  - LocalDataError: ローカルデータ永続化エラー
- RetryPolicy.swift で指数バックオフによるリトライロジックを実装
  - デフォルト、アグレッシブ、コンサバティブの3つのプリセットポリシー
  - RetryExecutor actor による並行安全なリトライ実行
- ErrorHandler.swift で一元的なエラー管理サービスを実装

#### Issue #2: Google Sign-In Authentication
- GoogleAuthService.swift で OAuth 2.0 認証フローを実装
  - サインイン / サインアウト
  - アクセストークンの自動更新
  - 追加スコープのリクエスト
  - Keychain ベースのセッション永続化
- GOOGLE_AUTH_SETUP.md でセットアップガイドを追加
  - Google Cloud Console の設定手順
  - OAuth クライアントの構成方法
  - URL スキームのセットアップ

#### Issue #3: Google Calendar API Client
- CalendarModels.swift で Google Calendar API v3 のデータ構造を実装
  - CalendarEvent: イベントデータ
  - EventListResponse: イベントリストレスポンス
  - CalendarList: カレンダーリスト
  - GoogleAPIErrorResponse: エラーレスポンス
- GoogleCalendarClient.swift で完全な CRUD 操作を実装
  - イベントの作成、取得、更新、削除
  - カレンダーリスト取得（ページネーション対応）
  - イベントリスト取得（時間範囲フィルタ、ページネーション、syncToken 対応）
  - レート制限（リクエスト間隔 100ms）
  - RetryExecutor による自動リトライ
  - HTTP ステータスコード処理（401, 403, 404, 410, 429, 5xx など）
  - syncToken ベースの差分同期サポート

### Technical Details

- **Swift Concurrency**: すべての API 呼び出しと DB 操作で async/await を使用
- **Actor Isolation**: RetryExecutor を actor として実装し、並行安全性を確保
- **Error Handling**: すべてのサービスで CaleNoteError を使用した一貫したエラー処理
- **Logging**: OSLog による構造化ログ
- **Rate Limiting**: Google Calendar API のレート制限に対応

### Dependencies

- GoogleSignIn SDK 9.0+ (Issue #2)
- SwiftData (Issue #1)
- Combine (Issue #16, #2)

## [0.1.0] - 2025/12/XX (Initial Reset)

### Changed
- プロジェクトを最小構成にリセット
- App Layer: CaleNoteApp.swift
- Features Layer: ContentView.swift
- Domain Layer: 空
- Infrastructure Layer: 空
