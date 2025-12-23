# CaleNote 変更履歴

このファイルはCaleNoteの仕様変更と実装の履歴を記録します。

## [0.8] - 2025-12-23

### 追加機能

#### 1. 競合解決機能
- **競合検知ロジック**:
  - `linkedEventUpdatedAt`が存在する（既に同期済み）
  - ローカルの更新時刻がカレンダーより30秒以上新しい（本当の競合）
  - タイムスタンプのずれによる誤検知を防ぐ許容時間を設定

- **データモデル拡張** (`JournalEntry`):
  - `hasConflict: Bool` - 競合状態フラグ
  - `conflictDetectedAt: Date?` - 競合検知日時
  - `conflictRemoteTitle: String?` - カレンダー版のタイトル（スナップショット）
  - `conflictRemoteBody: String?` - カレンダー版の本文（スナップショット）
  - `conflictRemoteUpdatedAt: Date?` - カレンダー版のupdated
  - `conflictRemoteEventDate: Date?` - カレンダー版のイベント日時

- **UI実装**:
  - `ConflictResolutionView`: ローカル版とカレンダー版を並べて表示
  - `TimelineRowView`: 競合エントリにオレンジの三角バッジ表示
  - `JournalDetailView`: 「競合を解決」ボタン追加

- **解決フロー** (`ConflictResolutionService`):
  - **useLocal**: ローカル版を採用し、カレンダーに再送信
  - **useRemote**: カレンダー版を採用し、ローカルを上書き

- **自動解決**:
  - カレンダーからの変更が正常にローカルに適用された場合
  - リモートイベントが削除された場合（`status == "cancelled"`）

#### 2. 長期キャッシュ取り込みのキャンセル機能
- **実装箇所**: `ArchiveSyncService`
- **機能詳細**:
  - `Task.checkCancellation()`を4箇所に配置（カレンダー開始時、バッチ開始前、sleep前後）
  - 進捗保存: UserDefaultsに`SavedProgress`を保存
  - 再開機能: 中断したカレンダー×半年レンジから続きを実行

- **UI実装** (`SettingsView`):
  - 取り込み中にキャンセルボタン表示
  - `Task`参照を保持してキャンセル実行

#### 3. 開発者向けツール
- **アクセス方法**:
  - 設定画面のバージョン情報を7回タップ
  - 開発者モードが有効化され、「開発者向けツール」セクションが表示

- **データモデル** (`SyncLog`):
  - `id: UUID` - ユニークID
  - `timestamp: Date` - 同期開始時刻
  - `endTimestamp: Date?` - 同期終了時刻
  - `syncType: String` - 同期種別（incremental/full/archive/journal_push）
  - `calendarIdHash: String?` - SHA256ハッシュ（最初の8文字）
  - `httpStatusCode: Int?`
  - `updatedCount, deletedCount, skippedCount, conflictCount: Int`
  - `had410Fallback: Bool` - syncToken期限切れでフル同期
  - `had429Retry: Bool` - レート制限でリトライ
  - `errorType: String?`, `errorMessage: String?`

- **UI実装** (`DeveloperToolsView`):
  - 同期ログ一覧（新しい順）
  - ログ詳細モーダル
  - JSON出力（クリップボードコピー）
  - ログ全削除機能

- **プライバシー保護**:
  - カレンダーIDはSHA256ハッシュ化（最初の8文字のみ）
  - ユーザーコンテンツ（タイトル、本文）は記録しない

#### 4. 同期ログ記録の実装
各同期サービスにログ記録機能を追加:

- **CalendarSyncService**:
  - `syncOneCalendar`, `syncPrimaryCalendar`にログ記録
  - 410エラー時に`had410Fallback = true`を設定

- **JournalCalendarSyncService**:
  - `syncOne`メソッドにログ記録（syncType: "journal_push"）

- **ArchiveSyncService**:
  - `importAllEventsToArchive`にログ記録（syncType: "archive"）
  - キャンセル時も適切にログ記録

### 変更内容

#### データモデル
- `JournalEntry`: 競合解決用フィールド6つ追加
- `SyncLog`: 新規モデル追加
- `CaleNoteApp`: modelContainerに`SyncLog`を登録

#### Infrastructure
- `CalendarSyncService`: ログ記録、SyncResult構造体追加
- `JournalCalendarSyncService`: ログ記録追加
- `ArchiveSyncService`: ログ記録、キャンセル対応、進捗保存
- `CalendarToJournalSyncService`: 競合検知ロジック更新（30秒許容）
- `ConflictResolutionService`: 新規サービス追加

#### Features
- `DeveloperToolsView`: 新規画面追加
- `ConflictResolutionView`: 新規モーダル追加
- `SettingsView`: 開発者モード切り替え、キャンセルボタン追加
- `TimelineRowView`: 競合バッジ追加
- `JournalDetailView`: 競合解決ボタン追加
- `TimelineView`: 同期ステータスに競合カウント追加

### 修正
- 競合検知の誤検知防止（30秒許容、linkedEventUpdatedAtチェック）
- 長期キャッシュ取り込みのキャンセル不可問題を解決

---

## [0.7] - 2025-12-22

### 変更内容
- 実装準拠に全面見直し
- Google Calendarを唯一の永続データストアとして明記
- extendedProperties仕様を確定
- キャッシュ2層構造を追加
- 同期仕様を実装準拠に更新
- 開発フェーズを実装状況に合わせて更新

---

## [0.6] - 2025-12-21

### 変更内容
- タグ設計を更新（Google Calendar連携、最近使ったタグのみ表示、同期範囲の明確化）
- データ保存方針と設計上の思想を追加

---

## [0.5] - 2025-12-21

### 追加機能
- カードのカラーとアイコン選択機能を追加
- 予定・ジャーナルの完全統一を明確化

---

## [0.4] - 2025-12-20

### 変更内容
- ジャーナルカードと予定カードを統一
- フォント設定追加（Noto Sans JP / Inter）

---

## [0.3] - 2025-12-20

### 変更内容
- 2タブ構成に簡素化
- タイムラインベースのメイン画面に変更

---

## [0.2] - 2025-12-20

### 変更内容
- アプリ名変更
- 各種機能調整

---

## [0.1] - 2025-12-20

### 初版作成
- 基本仕様策定
