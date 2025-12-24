# CaleNote - アプリ仕様書

## この仕様書について

**重要**: この仕様書は**実装準拠**です。つまり、現在動作しているコードを「仕様」として明文化したものです。理想や将来の計画ではなく、**今動いている実装が唯一の真実**です。

- 実装済みの機能は確定仕様として記載
- 未実装の機能は「未実装」または「制限」として明記
- Google Calendarは**唯一の永続データストア**であり、アプリ内のSwiftDataはキャッシュにすぎない
- 実装の詳細（`extendedProperties.private`の構造など）は仕様として固定

この方針により、次の担当者が「なぜこうなっているのか」を理解しやすくし、事故を防ぎます。

---

## 1. 概要

### 1.1 アプリ名
**CaleNote**（Calendar + Note）

### 1.2 コンセプト
Googleカレンダーを**唯一の真実のソース（Single Source of Truth）**として利用し、日々の出来事や内省を「書く」のではなく「存在させる」ジャーナルアプリ。**Googleカレンダーが唯一の永続データストア**であり、アプリ内のSwiftDataはキャッシュおよび編集補助にすぎない。カレンダーの予定と一緒に1日単位で振り返ることができ、過去の同じ日を振り返る機能で、自分の歩みを実感できる。

### 1.3 ターゲットユーザー
- 日々の出来事や思考を手軽に記録したい人
- Googleカレンダーで予定管理している人
- 後から振り返り・検索したい人

### 1.4 プラットフォーム
- iOS 17.0以上
- iPhone対応（iPad対応は将来検討）

---

## 1.5 データ保存方針

**重要**: Google Calendarは「外部保存」ではなく、**唯一の永続データストア**である。アプリ内のSwiftDataはキャッシュおよび編集補助にすぎない。

| データ種別 | 保存先 | 備考 |
|-----------|--------|------|
| ジャーナル本文・メタ情報 | 端末内（SwiftData） | **キャッシュ**。Google Calendarが正 |
| 写真 | 端末内ファイル保存 + SwiftData参照 | ローカル保存（Google Calendarには保存しない） |
| 設定情報 | UserDefaults | ローカル保存 |
| 認証トークン | Keychain | セキュア保存 |
| **永続データストア** | **Google Calendar（イベント）** | **唯一の真実のソース** |
| クラッシュレポート等 | Firebase（Crashlytics / App Distribution / Remote Config） | ユーザーデータ保存は行わない |

### 1.5.1 キャッシュの2層構造

アプリは2種類のキャッシュを管理する：

**短期キャッシュ（CachedCalendarEvent）**
- 同期対象期間内のイベントを保持
- Timeline描画用
- 同期範囲外のデータは定期的に削除される（`CalendarCacheCleaner`）

**長期キャッシュ（ArchivedCalendarEvent）**
- 全期間のイベントを保持（2000年1月1日〜未来1年）
- 振り返り・検索用
- 設定画面から明示的に取り込む必要がある（`ArchiveSyncService`）
- 半年単位でAPI取得、レート制限対策として0.2秒のsleep挿入
- **レート制限対応**: 指数バックオフ + ジッター（自動リトライ、最大5回、最大60秒待機）
- **キャンセル機能**: 取り込み中にキャンセル可能。進捗はUserDefaultsに保存され、再開時に続きから実行
- **進捗保存**: カレンダー×半年レンジ単位で進捗を記録。中断・再開に対応

**注意**: CloudKitやその他のクラウド同期は**当面実装しない**。Google Calendarが唯一の外部永続先である。

---

## 2. 機能要件

### 2.1 ジャーナル機能（コア機能）

#### 2.1.1 エントリの構成要素

| 項目 | 必須 | 説明 |
|------|------|------|
| タイトル | 任意 | 短い見出し |
| 本文 | 任意 | メインのテキスト。ハッシュタグ対応 |
| 日時 | 自動 | 作成日時（手動変更可） |
| カラー | 任意 | カラーパレットから選択（デフォルト: ミュートブルー） |
| 場所 | 任意 | 位置情報または手入力 |
| 写真 | 任意 | 複数枚添付可 |

#### 2.1.2 ハッシュタグ機能

**基本方針**
- タグは `#tag` 形式で本文中に記述する
- Google Calendar 側には **description に本文 + 改行 + タグ** を保存する
- タグは独立したデータ構造として Google Calendar には持たせない

**アプリ内での扱い**
- 保存・更新時に本文から `#tag` をパース
- タグは SwiftData 内でインデックス化（エントリとの関連のみ保持）
- 全期間のタグ一覧は作成しない

**表示・UI**
- 表示するタグは「最近使われたタグ」のみ
- 最近の定義: 同期対象期間内の`JournalEntry`と有効なカレンダー（`isEnabled == true`）の`CachedCalendarEvent`での使用頻度・直近使用日時
- カレンダー側で`description`が編集された場合、同期でキャッシュが更新されるとタグ統計に自動反映
- `JournalEntry`と紐付いているイベントは重複カウントを避けるため除外
- 表示OFFにしたカレンダーのタグは表示されない
- タグ一覧は最大20件程度を表示

**検索**
- 検索バーに `#tag` を入力するとタグ検索として機能
- タグ一覧からの選択は「最近使ったタグ」に限定

#### 2.1.3 位置情報
- 設定でデフォルト動作を選択可能
  - 「現在位置を自動取得」ON/OFF
- 個別エントリで位置を変更・削除可能
- 手入力で場所名を設定可能

#### 2.1.4 入力方法
**Phase 1（MVP）**
- アプリ内から手動入力
- 新規作成ボタン（FAB）

**Phase 2（将来）**
- ホーム画面ウィジェットから素早く入力

### 2.2 タイムライン表示

- **逆時系列**で表示（新しいエントリが上、古いものが下）
- Googleカレンダーの予定とジャーナルを統合表示
- **予定とジャーナルは完全に統一されたカードデザインで表示**（区別しない）
- カードの背景色はユーザーが選択したカラーパレットから適用
- カードのアイコンは、設定でカレンダーごとに選択したアイコンパレットから適用
- 日付区切りを表示
- **初期フォーカス機能**: 初回表示時に「今日セクション」に自動スクロール
  - 上へスクロールすると未来日付（明日以降）へ、下へスクロールすると過去日付（前日以前）へ自然に移動
  - 今日セクションが存在しない場合でも空セクションを生成してフォーカス可能
  - 検索中は自動フォーカスを無効化（検索結果の先頭表示を維持）
  - 日付ジャンプ機能で選択された日がある場合は、その日を優先してフォーカス
- **ページネーション機能**: 長期キャッシュの大量データを効率的に表示
  - **カーソルベースのページネーション**: 日付キー（YYYYMMDD形式）を使用した双方向ロード
  - **初期ロード**: 「今日」を中心に未来側100件 + 過去側100件を自動ロード
  - **遅延ロード**: スクロールに応じて自動的に追加データをロード
    - 上端に到達で未来方向に150件ずつロード
    - 下端に到達で過去方向に150件ずつロード
  - **ウィンドウトリミング**: メモリ消費を抑えるため、最大600件を保持
    - 最大件数を超えた場合、スクロール方向と逆側のデータを自動削除
    - 過去方向にスクロール中は未来側を削除、未来方向にスクロール中は過去側を削除
  - **重複ロード防止**: ローディングフラグと境界キー管理で効率化
  - **短期キャッシュ（CachedCalendarEvent）は全量表示**: ページネーションは長期キャッシュ（ArchivedCalendarEvent）のみに適用

### 2.3 カレンダー機能

- カレンダーボタンタップでカレンダーモーダル/シートを表示
- 月表示カレンダー
- **ジャーナルがある日にドットマーカー表示**
- 日付タップでその日のタイムライン位置にスクロール/遷移

### 2.4 初期オンボーディングフロー

#### 2.4.1 概要
初回起動時に適切なガイダンスを提供する2ステップのオンボーディングフローを実装。

#### 2.4.2 表示判定
`RootView`が以下の条件をチェックし、全て満たさない場合はオンボーディングを表示:
- 認証トークンが有効（`auth.user != nil`）
- `CachedCalendar`が存在する
- 少なくとも1件`isEnabled == true`のカレンダーがある

#### 2.4.3 ステップ1: Google Sign-In（`GoogleSignInOnboardingView`）
- Google Sign-Inボタンを中央に配置
- サインイン成功後、カレンダー一覧の初回同期を実行（`CalendarListSyncService`）
- 同期完了後、自動で次ステップへ遷移
- エラー時はメッセージ表示＆再試行可能

#### 2.4.4 ステップ2: カレンダー選択（`CalendarSelectionOnboardingView`）
- `CachedCalendar`一覧を表示（primaryを先頭に）
- 各カレンダーにトグル（`isEnabled`）を配置
- 初期値: primaryカレンダーを自動的にON（ない場合は先頭）
- 「続ける」ボタン: `isEnabled == true`が1件以上で有効化
- 完了時に`JournalWriteSettings`を自動設定（primaryまたは先頭の有効カレンダー）
- **完了時に選択されたカレンダーの長期キャッシュ取得を自動開始**（`ArchiveImportSettings`）

#### 2.4.5 フロー管理（`OnboardingCoordinatorView`）
- 2ステップのフローを管理
- ステップ1完了 → ステップ2へ遷移
- ステップ2完了 → オンボーディング終了

#### 2.4.6 動作フロー
**初回起動時:**
1. `RootView`が判定条件をチェック
2. 条件を満たさない → `OnboardingCoordinatorView`を表示
3. ステップ1: Google Sign-In → カレンダー一覧同期
4. ステップ2: カレンダー選択（primaryが自動ON）
5. 「続ける」→ 書き込み先カレンダー自動設定 → **選択されたカレンダーの長期キャッシュ取得を開始** → 通常UIへ

**2回目以降の起動時:**
1. `RootView`が判定条件をチェック
2. 条件を満たす → 通常の`TabView`を表示

**ログアウト時:**
1. `auth.user`がnilになる
2. `RootView`の`onChange(of: auth.user)`が発火
3. 判定条件をチェック → オンボーディングに戻る

**カレンダー表示ON時:**
1. カレンダー設定画面で表示トグルをONにする
2. `ArchiveImportSettings.startBackgroundImport()`が呼び出される
3. 既に取得済みまたは取得中の場合はスキップ
4. バックグラウンドタスクで長期キャッシュ取得を開始
5. 取得完了後、`ArchiveImportSettings`に完了フラグを保存

### 2.5 Googleカレンダー連携

#### 2.5.1 認証
- Google Sign-In SDK使用
- Calendar API読み取り・書き込み権限

#### 2.5.2 カレンダー選択
- 複数カレンダーから表示対象を選択
- カレンダーごとの表示ON/OFF（`CachedCalendar.isEnabled`）
- 各カレンダーの設定（色、アイコン、表示設定、書き込み先、長期キャッシュ）はカレンダー設定画面（`CalendarSettingsView`）で行う

#### 2.5.3 予定の表示
- タイムライン上に予定を表示
- 予定のカード背景色は、設定でカレンダーごとに選択したカラーパレットから適用
- 予定のカードアイコンは、設定でカレンダーごとに選択したアイコンパレットから適用
- **予定の編集**: 短期キャッシュ（`CachedCalendarEvent`）と長期キャッシュ（`ArchivedCalendarEvent`）の両方から編集可能
  - 詳細画面の編集ボタンから`JournalEditorView`を開く
  - 既にジャーナルと紐付いている場合はそのジャーナルを編集
  - 紐付いていない場合は新規ジャーナルを作成してリンク
- **書き込み先カレンダーの変更**: エントリー編集画面で書き込み先カレンダーを変更可能
  - 書き込み先カレンダー表示部分をタップでカレンダー選択シートを表示
  - 有効なカレンダー一覧から選択可能
  - 既存エントリの場合は`linkedCalendarId`を更新
  - 新規エントリの場合は選択したカレンダーに保存

#### 2.5.4 同期範囲（実装準拠）
- **デフォルト: 過去30日〜未来30日**（`SyncSettings`）
- ユーザーが設定画面で変更可能（UserDefaults管理）
- 同期対象はイベントの必要最小限フィールド（title / description / start / end / updated / status / extendedProperties 等）
- タグ抽出は同期対象期間内の`JournalEntry`と有効なカレンダー（`isEnabled == true`）の`CachedCalendarEvent`の両方から行う
- カレンダー側で`description`が編集された場合、同期でキャッシュが更新されるとタグ統計に自動反映
- `JournalEntry`と紐付いているイベントは重複カウントを避けるため除外
- 表示OFFにしたカレンダーのタグは表示されない
- タグ一覧・頻出度はこの範囲のみで構築
- 全期間のタグ網羅は行わない（古いタグを探したい場合は、手入力検索で対応）

#### 2.5.5 Google Calendarを正とする設計

**ジャーナルとイベントの1:1対応**
- 1つの`JournalEntry`は1つのGoogle Calendar Eventと対応する
- 対応関係は`extendedProperties.private`によって保証される
- このJSON構造は**確定仕様**である：

```json
extendedProperties.private = {
  "app": "calenote",
  "schema": "1",
  "journalId": "<UUID文字列>"
}
```

**双方向同期の仕組み**
- ジャーナル → カレンダー: `JournalCalendarSyncService`が`insertEvent`/`updateEvent`を実行
  - エントリー作成時にカレンダーに登録するイベントの時間は設定画面で指定可能（デフォルト30分、1〜480分、5分刻み）
  - イベントの開始時刻は`JournalEntry.eventDate`、終了時刻は開始時刻 + 設定された時間（分）
- カレンダー → ジャーナル: `CalendarToJournalSyncService`が`CachedCalendarEvent`の変更を`JournalEntry`に反映
- `description`の編集有無に依存せず、`extendedProperties.private`の`journalId`で紐付けを判定
- サーバーを介さず双方向同期が成立する理由は、この実装依存仕様による
- **カレンダー変更時の処理**: 書き込み先カレンダーが変更された場合、古いカレンダーのイベントを削除してから新しいカレンダーに作成
  - 古いカレンダーのキャッシュ（短期・長期）も削除
  - 404エラーは「すでに削除済み」として無視

**競合処理（実装準拠）**
- Googleカレンダー側の`updated`が新しければアプリを更新
- ローカルとカレンダーの両方が更新された場合（競合検知条件）:
  - 既にリンク済み（`linkedEventUpdatedAt`存在）かつ
  - ローカルがカレンダーより新しく（`entry.updatedAt > calendarUpdatedAt`）
  - 30秒以上の差がある場合に競合と判定
- 競合時は`JournalEntry`に競合フラグを設定し、カレンダー版のスナップショットを保存
- ユーザーに競合解決UIを表示（`ConflictResolutionView`）、ローカル版・カレンダー版のどちらを採用するか選択可能
- イベントが`status == "cancelled"`の場合は、ジャーナルのリンクを解除（`linkedEventId = nil`）

#### 2.5.6 同期仕様（実装準拠）

**同期トリガー**
- アプリ起動時（推測、実装確認要）
- メイン画面 pull-to-refresh（手動同期）
- 設定画面からの明示的操作

**差分同期**
- `events.list` + `syncToken`を使用
- `showDeleted=true`必須
- `status == "cancelled"`は削除扱い
- `syncToken`が期限切れ（HTTP 410 GONE）の場合はフル同期にフォールバック
- 同期状態はカレンダーごとに`CalendarSyncState`で管理（UserDefaults）

**レート制限**
- `SyncRateLimiter`により、5秒間隔で同期を制限
- 手動同期時は残り秒数を表示
- **指数バックオフ + ジッター**: HTTP 429（Too Many Requests）またはHTTP 403で`rateLimitExceeded`/`userRateLimitExceeded`を検出した場合、自動リトライ
  - 最大リトライ回数: 5回
  - 最大待機時間: 60秒
  - 計算式: `delay = min(baseDelay * 2^attempt + jitter, maxWaitTime)`
  - ジッター: `random(0..<0.5) * exponentialDelay`（サンダリングハード防止）
  - リトライメトリクスは`SyncLog`に記録（`retryCount`, `totalWaitTime`）

**同期失敗のCrashlytics送信**
- 同期失敗（ネットワーク、認証、410/429、パース失敗など）を検知したら、Crashlyticsに送信（`SyncErrorReporter`）
- 送信情報:
  - 失敗種別（`syncType`: "incremental", "full", "archive", "journal_push", "calendar_list"）
  - 対象カレンダーIDのハッシュ（SHA256の最初8文字、プライバシー保護）
  - HTTPステータスコード（取得可能な場合）
  - syncTokenフォールバック有無（`had410Fallback`）
  - 処理フェーズ（`phase`: "short_term", "long_term", "resend"）
- **プライバシー保護**: ユーザーコンテンツ（本文、タイトルなど）は送信しない
- 各同期サービス（`CalendarSyncService`、`JournalCalendarSyncService`、`ArchiveSyncService`、`CalendarListSyncService`）のエラーハンドリングで自動送信
- ローカルログ（`SyncLog`）にも記録され、開発者向けツール画面で確認可能

**更新優先度**
- Googleカレンダー側の`updated`が新しければアプリを更新
- ローカルが新しくても競合時は**安全側にスキップ**（`CalendarToJournalSyncService`）

### 2.6 関連するエントリー機能

エントリー詳細画面（ジャーナル詳細・予定詳細のどちらでも）に、長期キャッシュ ArchivedCalendarEvent を使った「関連エントリー」セクションを表示する。

#### 2.6.1 検索条件

以下の3つの条件でマッチするエントリーを検索する（設定で有効/無効を切り替え可能、デフォルト: 同日のみON）：

1. **同じ日（MMDD一致）**: 同じ月日（例: 12月23日）の過去・未来のエントリーを表示
2. **同じ週の同じ曜日**: ISO週番号と曜日が一致するエントリーを表示（過去10年 + 未来10年）
3. **同じ祝日**: 同じ祝日（例: 元日）の過去・未来のエントリーを表示

#### 2.6.2 除外条件

- **同じ年月日のエントリーは除外**: 同じ日付（年・月・日が全て一致）のエントリーは関連エントリーに含めない
- **同じ年のエントリーは除外**: 各検索条件で、対象日と同じ年のエントリーは除外

#### 2.6.3 表示形式

- **年でグルーピング**: 関連エントリーは年ごとにグループ化して表示
- **年ヘッダー**: 「2021年　4年前」形式で表示（年を主、相対年を副として表示）
  - 年は`DateFormatter`で`yyyy年`形式を使用（カンマ区切りなし）
  - 相対年は対象日（詳細画面のエントリー日付）との年差を表示
- **各エントリー行**:
  - **タイトル**: エントリーのタイトル
  - **日付**: 必ず表示
    - 終日イベント: `YYYY/MM/DD`形式のみ
    - 時間指定イベント: `YYYY/MM/DD  HH:mm`形式（開始時刻）
  - **一致理由バッジ**: 「同日」「同週同曜」「同祝日」のバッジを表示（複数条件に一致する場合は複数表示）
- **ソート順**: 年ごとに降順（新しい年から）、同一年内では絶対距離が近い順

#### 2.6.4 パフォーマンス最適化

- `startMonthDayKey`: MMDD形式の整数インデックス（例: 1223）で高速検索
- `holidayId`: 祝日IDで高速検索（例: "JP:NEW_YEAR"）
- `startDayKey`: YYYYMMDD形式の整数インデックス（例: 20241223）で高速検索

#### 2.6.5 祝日システム

- **プロトコルベース**: `HolidayProvider`プロトコルで国際化対応
- **日本祝日**: `JapanHolidayProvider`で日本の祝日を実装（固定祝日・移動祝日・春分/秋分を含む）
- **祝日ID**: "JP:NEW_YEAR"などの安定したIDで管理

#### 2.6.6 UI

- **セクションヘッダー**: 「関連するエントリー」
- **有効条件表示**: 現在有効な検索条件を表示（例: 「同日・同週同曜」）
- **空状態**:
  - 長期キャッシュ未取り込み → 設定画面への誘導リンク表示
  - 条件が全て無効 → 設定画面への誘導リンク表示
  - 該当なし → 「関連する過去のエントリーは見つかりませんでした」と表示
- **エントリー一覧**: タイトル、日時、年数、一致理由バッジを表示
- **タップ動作**: `ArchivedCalendarEventDetailView`に遷移（詳細→詳細のナビゲーション）

#### 2.6.7 設定

設定画面の「関連する過去の表示設定」セクション（`RelatedMemorySettingsSection`）で以下を設定可能：

- 同じ日（MMDD一致）ON/OFF
- 同じ週の同じ曜日 ON/OFF
- 同じ祝日 ON/OFF
- 現在有効な条件の表示

### 2.7 検索機能

- ツールバーの左上に検索アイコン（🔍）を配置
- 検索アイコンをタップすると検索バーがドロワー形式で表示される
- フリーテキスト検索（タイトル、本文、ハッシュタグ）
- 検索バーに `#tag` を入力するとタグ検索として機能
- 検索結果はタイムライン形式で表示
- タグ一覧からの選択は「最近使ったタグ」に限定（最大10件程度）

### 2.8 競合解決機能

#### 2.8.1 競合検知

ローカルとGoogle Calendar両方でジャーナルが変更された場合に競合を検知する。

**検知条件**:
- `linkedEventUpdatedAt`が存在する（既にカレンダーと同期済み）
- `entry.updatedAt > calendarUpdatedAt`（ローカルの方が新しい）
- 差分が30秒以上（タイムスタンプのずれによる誤検知を防ぐ）

**競合時の動作**:
- `hasConflict = true`を設定
- カレンダー版のスナップショットを保存（title, body, updatedAt, eventDate）
- 同期ステータスに競合カウントを表示
- タイムライン上にオレンジの三角バッジを表示

#### 2.8.2 競合解決UI

**JournalDetailView**:
- 競合状態の場合、メタデータセクションに警告表示
- 「競合を解決」ボタンを表示（オレンジ）

**ConflictResolutionView（モーダル）**:
- ローカル版とカレンダー版を並べて表示
- 各版の表示内容: タイトル、本文、更新日時、イベント日時
- 「この版を使う」ボタンで解決方法を選択

**解決方法**:
- **useLocal**: ローカル版を採用し、カレンダーに再送信（`needsCalendarSync = true`）
- **useRemote**: カレンダー版を採用し、ローカルを上書き

**解決後**:
- 競合フラグをクリア（`hasConflict = false`、スナップショットも削除）
- タイムライン上のバッジが消える
- エラー発生時は画面上にエラーメッセージを表示

#### 2.8.3 自動解決

以下の場合は自動的に競合フラグをクリア:
- カレンダーからの変更が正常にローカルに適用された場合
- リモートイベントが削除された場合（`status == "cancelled"`）

### 2.9 同期状態バッジ表示

#### 2.9.1 タイムライン上のバッジ表示

**表示位置**: ジャーナルカードの時刻の右側

**バッジの種類** (優先順位: 同期中 → 競合 → 同期失敗 → 同期済み):
- **同期中バッジ** (同期処理実行中):
  - アイコン: 青い回転アイコン（`arrow.triangle.2.circlepath`、回転アニメーション付き）
  - 意味: カレンダーへの同期処理が進行中
  - タップ動作: なし

- **競合バッジ** (`hasConflict == true`):
  - アイコン: オレンジの三角形（`exclamationmark.triangle.fill`）
  - 意味: ローカルとカレンダーの両方が更新されている
  - タップ動作: 詳細画面に遷移（NavigationLinkの通常動作）

- **同期失敗バッジ** (`needsCalendarSync == true`):
  - アイコン: 黄色の円形感嘆符（`exclamationmark.circle.fill`）
  - 意味: カレンダーへの同期が失敗している
  - タップ動作: 確認アラート表示 → 「再送」で個別再送実行

- **同期済み**: バッジなし（何も表示しない）

#### 2.9.2 個別再送機能

**動線**:
1. タイムライン上の同期失敗バッジをタップ
2. 確認アラート表示: 「「タイトル」をカレンダーに再送します。」
3. 「再送」ボタンをタップ → バックグラウンドで`JournalCalendarSyncService.syncOne()`実行
4. 成功時: バッジが消える、ステータスに「再送成功」表示
5. 失敗時: エラーアラート表示

#### 2.9.3 設定画面の「同期待ち」セクション

**表示内容**:
- 同期待ちのジャーナル件数（`needsCalendarSync == true`）
- **「まとめて再送」ボタン**: 全ての同期待ちジャーナルを一括再送
- **エントリプレビュー**: 最初の5件を表示
  - タイトル、日付、黄色の感嘆符アイコン
  - 5件以上ある場合「他N件」と表示
- **空状態**: 「同期待ちのジャーナルはありません」とグレー表示

**まとめて再送の動作**:
- `pendingEntries`（`needsCalendarSync == true`のジャーナル）を順次再送
- 各エントリは`JournalCalendarSyncService.syncOne()`で処理
- エラー発生時はエラーメッセージを表示

---

## 3. 画面構成

### 3.1 オンボーディング画面

#### 3.1.1 ステップ1: Google Sign-In画面（`GoogleSignInOnboardingView`）

```
┌─────────────────────────────────┐
│                                 │
│         📅 (アイコン)            │
│                                 │
│    CaleNote へようこそ          │
│                                 │
│  Google Calendar と同期して     │
│  ジャーナルを記録しましょう      │
│                                 │
│                                 │
│  ┌─────────────────────────┐   │
│  │  🌐 Google でサインイン  │   │
│  └─────────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

**構成要素**:
- ロゴ・タイトルエリア: カレンダーアイコン、アプリ名、説明文
- Google Sign-Inボタン: 中央配置、タップでサインイン開始
- ローディング表示: サインイン中・カレンダー同期中はProgressViewを表示
- エラーメッセージ: サインイン失敗時に表示

**インタラクション**:
- Google Sign-Inボタンタップ → サインイン開始
- サインイン成功 → カレンダー一覧の初回同期を実行
- 同期完了 → 自動でステップ2へ遷移
- エラー時 → エラーメッセージ表示、再試行可能

#### 3.1.2 ステップ2: カレンダー選択画面（`CalendarSelectionOnboardingView`）

```
┌─────────────────────────────────┐
│         📅 (アイコン)            │
│                                 │
│      カレンダーを選択            │
│                                 │
│  表示するカレンダーを選んで      │
│  ください（後から変更できます）  │
│  ────────────────────────────   │
│                                 │
│  ☑ カレンダー1                  │
│     メイン                      │
│                                 │
│  ☐ カレンダー2                  │
│                                 │
│  ☐ カレンダー3                  │
│                                 │
│  ────────────────────────────   │
│                                 │
│  ┌─────────────────────────┐   │
│  │        続ける           │   │
│  └─────────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

**構成要素**:
- ヘッダー: カレンダーアイコン、タイトル、説明文
- カレンダー一覧: 各カレンダーにトグル（`isEnabled`）を配置、primaryを先頭に表示
- 「続ける」ボタン: `isEnabled == true`が1件以上で有効化
- エラーメッセージ: カレンダー選択エラー時に表示

**インタラクション**:
- カレンダートグル: ON/OFF切り替え
- 初期値: primaryカレンダーを自動的にON（ない場合は先頭）
- 「続ける」ボタンタップ → 書き込み先カレンダー自動設定 → オンボーディング完了 → 通常UIへ

### 3.2 画面一覧（2タブ構成）

```
タブ1: メイン画面
├── 検索アイコン（左上）
├── カレンダーボタン
├── 過去の同じ日セクション
├── タイムライン（逆時系列）
└── 新規作成ボタン（FAB）

タブ2: 設定画面
├── Googleアカウント連携
├── カレンダー選択
├── 位置情報デフォルト設定
├── 表示設定
└── データ管理
```

### 3.3 画面詳細

#### 3.3.1 メイン画面

```
┌─────────────────────────────────┐
│  🔍 ジャーナル            📅  + │  ← 検索アイコン + タイトル + 新規作成
├─────────────────────────────────┤
│  ┌─────────────────────────┐   │
│  │ 📅 この日の思い出        │   │  ← 過去の同じ日（折りたたみ可）
│  │ 1年前: ○○へ旅行...      │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  ── 2024年12月20日 ──          │  ← 日付区切り
│  ┌─────────────────────────┐   │
│  │ 📝 14:30               │   │  ← カード（統一デザイン）
│  │ ミーティングメモ        │   │
│  │ 今日の打ち合わせで...    │   │
│  └─────────────────────────┘   │
│  ┌─────────────────────────┐   │
│  │ 📅 13:00-14:00         │   │  ← カード（統一デザイン）
│  │ チームMTG              │   │
│  └─────────────────────────┘   │
│  ┌─────────────────────────┐   │
│  │ 💡 10:15               │   │  ← カード（統一デザイン）
│  │ アイデア               │   │
│  │ 新機能について #仕事    │   │
│  └─────────────────────────┘   │
│                                 │
│  ── 2024年12月19日 ──          │
│  ...                            │
│                                 │
│                          [＋]   │  ← FAB（新規作成）
├─────────────────────────────────┤
│    [メイン]      [設定]         │  ← タブバー
└─────────────────────────────────┘
```

**構成要素**:
- 検索アイコン（ツールバー左上）
- カレンダーボタン（ツールバー右上）
- 過去の同じ日セクション（折りたたみ可能）
- タイムライン（逆時系列、日付区切りあり）
- 新規作成ボタン（ツールバー右上）
- Toastメッセージ（画面下部、自動消去）

**インタラクション**:
- 検索アイコンタップ → 検索バーがドロワー形式で表示、キーボード表示、検索実行
- カレンダーボタンタップ → カレンダーシート表示
- 予定カードタップ → 予定詳細（読み取りのみ）
- ジャーナルカードタップ → 編集画面
- 過去エントリタップ → 該当日へスクロール
- FABタップ → 新規作成画面
- 下スクロール → 過去のエントリを読み込み
- pull-to-refresh → 手動同期実行

**メッセージ表示**:
- 同期状態、同期エラー、削除エラーなどのメッセージはtoast/snackbar形式で画面下部に表示
- メッセージタイプ（info/success/error/warning）に応じた色とアイコンを表示
- 4秒後に自動で消える
- アニメーション付きで表示/非表示

**カードの統一**:
- **予定とジャーナルは完全に統一されたカードデザインを使用**（視覚的な区別は行わない）
- カードの左側に4px幅のカラーバーを表示（カレンダーの色を反映）
- アイコンは非表示（視認性向上のため）
- ジャーナルエントリ作成時: カラーを選択可能（カラーバーとして表示）
- 予定表示時: 設定でカレンダーごとに選択したカラーをカラーバーとして表示

#### 3.3.2 カレンダーシート（モーダル）

```
┌─────────────────────────────────┐
│         2024年12月         ▼   │
├─────────────────────────────────┤
│  日  月  火  水  木  金  土    │
│                              1 │
│   2   3   4   5●  6   7   8  │  ← ●はジャーナル記録日
│   9  10  11● 12  13  14  15  │
│  16  17  18  19● 20◉ 21  22  │  ← ◉は今日
│  23  24  25  26  27  28  29  │
│  30  31                       │
└─────────────────────────────────┘
```

**インタラクション**:
- 日付タップ → シート閉じる → その日のタイムラインへ遷移
- 月スワイプ → 前後の月へ移動
- 外側タップ → シート閉じる

#### 3.3.3 ジャーナル作成/編集画面（モーダル）

```
┌─────────────────────────────────┐
│  ✕ 新規エントリ        保存    │
├─────────────────────────────────┤
│  基本        📅 カレンダー1  >  │  ← 書き込み先カレンダー（タップで変更可）
│  ─────────────────────────     │
│  タイトル（任意）              │
│  ─────────────────────────     │
│                                 │
│  今日あったこと...              │
│                                 │
│                                 │
│                                 │
├─────────────────────────────────┤
│  🎨 カラー: ミュートブルー  ▼  │
│  📍 渋谷区（現在地）      ✕    │
│  📷 写真を追加                  │
│  🕐 2024/12/20 14:30     変更  │
└─────────────────────────────────┘
```

**構成要素**:
- 閉じるボタン（左上）
- 保存ボタン（右上）
- 書き込み先カレンダー表示（タップで変更可能）
  - カレンダーアイコンと名前を表示
  - タップでカレンダー選択シートを表示
  - 既存エントリの場合は`linkedCalendarId`を更新
  - 新規エントリの場合は選択したカレンダーに保存
- タイトル入力欄
- 本文入力欄
- カラー選択（カラーパレットから選択、デフォルト: ミュートブルー）
- 場所（デフォルト設定に応じて自動入力）
- 写真追加ボタン
- 日時表示/変更

#### 3.3.4 設定画面（実装準拠）

```
┌─────────────────────────────────┐
│           設定                  │
├─────────────────────────────────┤
│  Google連携                     │
│  ┌─────────────────────────┐   │
│  │ ログイン中: user@gmail  │   │
│  │ [ログアウト]            │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  表示するカレンダー             │
│  ┌─────────────────────────┐   │
│  │ 📅 カレンダー1      ✓  > │   │
│  │ 📅 カレンダー2          > │   │
│  │ [カレンダー一覧を再同期] │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  同期待ち                       │
│  ┌─────────────────────────┐   │
│  │ 3件の同期待ちがあります  │   │
│  │ [まとめて再送]          │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│    [メイン]      [設定]         │
└─────────────────────────────────┘
```

**構成要素（実装準拠）**:
- Google連携: ログイン/ログアウト、ログイン成功後は自動的にカレンダー一覧を同期
- 表示するカレンダー: カレンダー一覧表示（カラーチップとアイコン付き）、カレンダー名をタップでカレンダー設定画面に遷移、表示状態をインジケーター（✓）で表示、カレンダー一覧の再同期ボタン
- ジャーナル設定: エントリー作成時にカレンダーに登録するエントリーの時間を設定（1〜480分、5分刻み、デフォルト30分）
- 同期待ち: `needsCalendarSync == true`のジャーナルを一覧表示、まとめて再送ボタン

**各カレンダーの設定は、カレンダー名をタップして開くカレンダー設定画面（`CalendarSettingsView`）で行う**:
- 表示ON/OFF切り替え（ONにすると自動的に長期キャッシュ取得が開始される）
- デフォルトの書き込み先設定
- カラーの選択

**未実装項目**:
- 位置情報デフォルト設定
- テーマ設定（ダークモード）
- エクスポート/バックアップ機能

#### 3.3.5 カレンダー設定画面（モーダル）

```
┌─────────────────────────────────┐
│  カレンダー1              ✕    │
├─────────────────────────────────┤
│  カレンダー情報                 │
│  ┌─────────────────────────┐   │
│  │ 名前: カレンダー1        │   │
│  │ 種類: メイン             │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  表示設定                       │
│  ┌─────────────────────────┐   │
│  │ 表示する          [ON]  │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  書き込み先                     │
│  ┌─────────────────────────┐   │
│  │ デフォルトの書き込み先[ON]│   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  色                             │
│  ┌─────────────────────────┐   │
│  │ ● #3B82F6          ✓   │   │
│  │ ● #22C55E               │   │
│  │ ...                     │   │
│  └─────────────────────────┘   │
└─────────────────────────────────┘
```

**構成要素**:
- カレンダー情報: カレンダー名と種類（メイン）を表示
- 表示設定: カレンダーの表示ON/OFFを切り替え（最後の1つはOFF不可、ONにすると自動的に長期キャッシュ取得が開始される）
- 書き込み先: このカレンダーをデフォルトの書き込み先に設定/解除
- 色: 25色のパレットから選択（グリッドレイアウト、5x5）、選択中の色は太いボーダーと白いチェックマークで強調表示

#### 3.3.6 開発者向けツール画面（隠し機能）

```
┌─────────────────────────────────┐
│      開発者向けツール           │
├─────────────────────────────────┤
│  同期ログ                       │
│  ┌─────────────────────────┐   │
│  │ incremental              │   │
│  │ 📅 abc123de  12/23 10:30│   │
│  │ ↑5 ↓2 ⊘1    410↻       │   │
│  ├─────────────────────────┤   │
│  │ full                     │   │
│  │ 📅 abc123de  12/23 09:15│   │
│  │ ↑50 ↓10 ⊘0             │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  操作                           │
│  ┌─────────────────────────┐   │
│  │ [直近100件をコピー(JSON)]│   │
│  │ [ログを全削除]           │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  統計                           │
│  ┌─────────────────────────┐   │
│  │ ログ総数: 245           │   │
│  └─────────────────────────┘   │
└─────────────────────────────────┘
```

**アクセス方法**:
- 設定画面のバージョン情報を7回タップ
- 開発者モードが有効化され、設定画面に「開発者向けツール」セクションが表示される

**機能**:
- **同期ログ一覧**: 全ての同期操作のログを新しい順に表示
  - syncType（同期種別）、日時、カレンダーIDハッシュ、結果カウント
  - エラー、410フォールバック、429リトライのインジケーター
- **ログ詳細**: ログをタップで詳細モーダル表示
  - 基本情報（同期種別、開始/終了時刻、所要時間、カレンダーIDハッシュ）
  - 結果（更新/削除/スキップ/競合カウント、HTTPステータスコード）
  - フラグ（410フォールバック、429リトライ）
  - エラー情報（エラー種別、メッセージ）
- **JSON出力**: ログをクリップボードにコピー（デバッグ用）
- **ログ削除**: 全てのログを削除（確認ダイアログあり）

**プライバシー保護**:
- ユーザーコンテンツ（タイトル、本文）は記録しない
- カレンダーIDはSHA256ハッシュの最初の8文字のみ保存
- 同期操作のメタデータのみ記録

#### 3.3.7 エントリー詳細画面

**統一された画面構造**:
3つの詳細画面（`JournalDetailView`、`CalendarEventDetailView`、`ArchivedCalendarEventDetailView`）は共通のコンポーネントを使用し、統一された構造を持つ。

**共通構成要素**:
1. **ヘッダー** (`DetailHeaderView`): タイトル、日時情報（開始/終了時刻、全日イベントの場合は日付のみ）
2. **説明セクション** (`DetailDescriptionSection`): 本文（タグ除去済み）、タグ一覧
3. **メタ情報** (`DetailMetadataSection`): カレンダー名、同期状態、最終同期日時、追加情報（アーカイブイベントの場合）
4. **関連メモリー** (`RelatedMemoriesSection`): 過去と未来の関連エントリー
5. **ツールバー**: 統一された編集ボタン（「編集」テキスト付き、カラーボタン）

**メタ情報の表示**:
- **カレンダー名**: カレンダー所属を色ドットとカレンダー名で表示
- **同期状態**:
  - 同期済み: 「最終同期: YYYY/MM/DD HH:mm」形式で表示
    - カレンダーイベント: `cachedAt`（同期実行時刻）を表示
    - ジャーナル: 暫定として`updatedAt`を表示（将来的に同期実行時刻フィールド追加予定）
  - 同期待ち: オレンジの感嘆符アイコンと「同期待ち」テキスト
  - 未同期: グレーの円形アイコンと「未同期」テキスト
- **追加情報** (アーカイブイベントのみ):
  - ステータス（confirmed/cancelled等）
  - キャッシュ日時（`cachedAt`）
  - ジャーナル連携状態（連携済みの場合）
  - 祝日ID（祝日の場合）

**競合状態の表示** (ジャーナルのみ):
- 競合が検出された場合、メタ情報セクションの前にオレンジの警告ボタンを表示
- 「競合を解決」ボタンをタップで`ConflictResolutionView`を表示

**インタラクション**:
- 編集ボタンタップ → `JournalEditorView`を表示（既存ジャーナルを編集、または新規ジャーナルを作成）
- タグタップ → タイムラインでタグ検索（将来実装予定）

---

## 3.4 キャッシュとデータ寿命

### 3.4.1 短期キャッシュ（CachedCalendarEvent）

**目的**: Timeline描画用の高速アクセス

**範囲**: 同期対象期間内（デフォルト: 過去30日〜未来30日）

**管理**:
- `CalendarSyncService`が差分同期で更新
- `CalendarCacheCleaner`が同期範囲外のデータを定期的に削除
- カレンダーごとに`syncToken`を保持（`CalendarSyncState`）

**データ構造**:
- `uid`: `"calendarId:eventId"`形式のユニークID
- `linkedJournalId`: `extendedProperties.private.journalId`から取得
- `status`: `"confirmed"` / `"cancelled"` など

### 3.4.2 長期キャッシュ（ArchivedCalendarEvent）

**目的**: 振り返り・検索用の全期間データ

**範囲**: 2000年1月1日〜未来1年

**管理**:
- `ArchiveSyncService`が設定画面から明示的に取り込み
- 半年単位でAPI取得（`splitIntoHalfYearRanges`）
- レート制限対策として各バッチ間に0.2秒のsleep挿入
- **レート制限対応**: 指数バックオフ + ジッター（HTTP 429/403 rateLimitExceeded時に自動リトライ）
- 進捗表示あり（`Progress`構造体）
- **キャンセル機能**: 取り込み中にキャンセル可能（`Task.checkCancellation()`を使用）
- **進捗保存**: UserDefaultsに進捗を保存し、再開時に続きから実行

**データ構造**:
- `uid`: `"calendarId:eventId"`形式のユニークID
- `startDayKey`: `YYYYMMDD`形式の日付インデックス（検索高速化用）
- `linkedJournalId`: `extendedProperties.private.journalId`から取得

**編集機能**:
- 長期キャッシュのイベントもアプリから編集可能（`ArchivedCalendarEventDetailView`）
- 詳細画面の編集ボタンから`JournalEditorView`を開く
- 既にジャーナルと紐付いている場合はそのジャーナルを編集
- 紐付いていない場合は新規ジャーナルを作成してリンク（`linkedJournalId`を設定）

**取り込み方法**:
- **自動取得**: オンボーディング時に選択したカレンダー、またはカレンダー設定画面で表示ONにしたカレンダーの長期キャッシュを自動的にバックグラウンドで取得
- **取得状態管理**: `ArchiveImportSettings`で取得済み・取得中のカレンダーを管理（UserDefaults）
- **サイレント実行**: UIには進捗を表示せず、バックグラウンドで実行
- **重複取得防止**: 既に取得済みまたは取得中のカレンダーは再取得しない

**注意**: 長期キャッシュの取得は時間がかかるため、バックグラウンドで自動的に実行される。ユーザーが手動で取り込みを開始する必要はない。

---

## 4. データモデル

### 4.1 JournalEntry（SwiftData）

**実装準拠のモデル定義**:

```swift
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var journalId: UUID  // extendedProperties.private.journalId に保存される値
    
    var title: String?
    var body: String  // Google Calendar の description に保存
    
    var eventDate: Date  // 出来事の日時（作成日時とは別）
    var createdAt: Date
    var updatedAt: Date
    
    var colorHex: String  // UI用カラー（HEX形式）
    var iconName: String  // UI用アイコン名
    
    // Google Calendar 連携用
    var linkedCalendarId: String?  // 書き込んだカレンダーID（例: "primary"）
    var linkedEventId: String?  // Google側のeventId
    var linkedEventUpdatedAt: Date?  // カレンダー側のupdated（競合判定用）
    var needsCalendarSync: Bool  // 同期失敗したらtrue（再送用）

    // 競合解決用
    var hasConflict: Bool = false  // 競合状態フラグ
    var conflictDetectedAt: Date?  // 競合検知日時
    var conflictRemoteTitle: String?  // カレンダー版のタイトル（スナップショット）
    var conflictRemoteBody: String?  // カレンダー版の本文（スナップショット）
    var conflictRemoteUpdatedAt: Date?  // カレンダー版のupdated
    var conflictRemoteEventDate: Date?  // カレンダー版のイベント日時
}
```

**タグの扱い**
- タグは独立したデータ構造として持たない
- 本文（`body`）から`#tag`形式をパース（`TagExtractor`）
- Google Calendarの`description`には本文そのままを保存（タグは本文内に含まれる）
- 全期間のタグ一覧は作成しない
- 最近使われたタグのみ表示（同期対象期間内での使用頻度・直近使用日時、`TagStats`）

**Google Calendar連携**
- `extendedProperties.private`に`journalId`を保存（UUID文字列）
- `description`に`body`をそのまま保存
- `summary`（タイトル）は`title`が空なら`"ジャーナル"`を設定

### 4.2 Location

```swift
struct Location: Codable {
    var name: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
}
```

### 4.3 PhotoData

```swift
@Model
class PhotoData {
    var id: UUID
    var imageData: Data
    var createdAt: Date
}
```

### 4.4 CachedCalendarEvent（SwiftData）

**短期キャッシュ用モデル**:

```swift
@Model
final class CachedCalendarEvent {
    @Attribute(.unique) var uid: String  // "calendarId:eventId"
    var calendarId: String
    var eventId: String
    var linkedJournalId: String?  // extendedProperties.private.journalId
    
    var title: String
    var desc: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var status: String  // "confirmed" / "cancelled"
    
    var updatedAt: Date  // APIのupdated
    var cachedAt: Date  // 端末に保存した時刻
}
```

### 4.5 ArchivedCalendarEvent（SwiftData）

**長期キャッシュ用モデル**:

```swift
@Model
final class ArchivedCalendarEvent {
    @Attribute(.unique) var uid: String  // "calendarId:eventId"
    var calendarId: String
    var eventId: String

    var title: String
    var desc: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var status: String

    var updatedAt: Date
    var startDayKey: Int  // YYYYMMDD形式（検索高速化用）
    var linkedJournalId: String?
    var cachedAt: Date

    // 関連メモリー検索用インデックス
    var startMonthDayKey: Int?   // MMDD形式（例: 1223）
    var holidayId: String?       // 祝日ID（例: "JP:NEW_YEAR"）

    // computedプロパティ
    var computedMonthDayKey: Int {
        if let stored = startMonthDayKey {
            return stored
        }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: start)
        return (components.month ?? 0) * 100 + (components.day ?? 0)
    }
}
```

### 4.6 GoogleCalendarEvent（APIレスポンス）

**APIクライアント内部で使用するドメインモデル**:

```swift
struct GoogleCalendarEvent {
    var id: String
    var title: String
    var description: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var status: String  // "confirmed" / "cancelled"
    var updated: Date
    var privateProps: [String: String]?  // extendedProperties.private
}
```

### 4.7 CachedCalendar（SwiftData）

**カレンダーメタデータ**:

```swift
@Model
final class CachedCalendar {
    @Attribute(.unique) var calendarId: String
    var summary: String
    var isPrimary: Bool  // メインカレンダーかどうか
    var googleColorId: String?  // Google Calendar APIのカラーID
    var userColorHex: String  // ユーザーが選択したカラー（HEX形式）
    var iconName: String  // ユーザーが選択したアイコン名
    var isEnabled: Bool  // 表示ON/OFF
    var updatedAt: Date
}
```

**カラー設定**:
- `userColorHex`: ユーザーが選択したカラー（HEX形式、デフォルト: `#3B82F6`）
- `googleColorId`: Google Calendar APIから取得したカラーID（`colorIdToHex`でHEXに変換可能）
- 新規カレンダー作成時や`userColorHex`がデフォルト値の場合、Googleカレンダーのカラーを自動設定

### 4.8 AppSettings（UserDefaults）

```swift
// ジャーナルの書き込み先カレンダー設定
enum JournalWriteSettings {
    static func loadWriteCalendarId() -> String?
    static func saveWriteCalendarId(_ calendarId: String)
    static func eventDurationMinutes() -> Int  // デフォルト: 30分
    static func saveEventDurationMinutes(_ minutes: Int)
}

// 同期対象期間設定
enum SyncSettings {
    static func pastDays() -> Int  // デフォルト: 30日
    static func futureDays() -> Int  // デフォルト: 30日
    static func save(pastDays: Int, futureDays: Int)
    static func windowDates(from now: Date) -> (timeMin: Date, timeMax: Date)
}
```

**注意**: カレンダーの色・アイコン・表示設定は`CachedCalendar`モデルで管理（SwiftData）。UserDefaultsには書き込み先カレンダーIDと同期対象期間のみ保存。

### 4.9 SyncLog（SwiftData）

**開発者向け同期ログモデル**:

```swift
@Model
final class SyncLog {
    @Attribute(.unique) var id: UUID
    var timestamp: Date  // 同期開始時刻
    var endTimestamp: Date?  // 同期終了時刻
    var syncType: String  // 同期種別: "incremental", "full", "archive", "journal_push", "calendar_list"
    var calendarIdHash: String?  // カレンダーIDのSHA256ハッシュ（最初の8文字）
    var httpStatusCode: Int?
    var updatedCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var conflictCount: Int
    var had410Fallback: Bool  // syncToken期限切れでフルバックした
    var had429Retry: Bool  // レート制限でリトライした
    var retryCount: Int  // リトライ回数（429エラー時）
    var totalWaitTime: Double  // 合計待機時間（秒）
    var errorType: String?  // エラー種別
    var errorMessage: String?  // エラーメッセージ
}
```

**同期種別（syncType）**:
- `"incremental"`: 差分同期（syncToken使用）
- `"full"`: フル同期（syncToken期限切れ時）
- `"archive"`: 長期キャッシュ取り込み
- `"journal_push"`: ジャーナル→カレンダー同期
- `"calendar_list"`: カレンダーリスト取得

**プライバシー保護**:
- カレンダーIDは`SHA256.hash`で暗号化し、最初の8文字のみ保存
- ユーザーコンテンツ（タイトル、本文）は記録しない
- 同期操作のメタデータのみ記録

**JSON出力**:
- `toJSON()`メソッドで辞書形式に変換
- ISO8601形式で日時を出力
- デバッグ用にクリップボードコピー可能

**Crashlytics連携**:
- 同期失敗時に`SyncErrorReporter.reportSyncFailure()`を呼び出し、Crashlyticsに非致命的エラーとして送信
- 送信される情報は`SyncLog`と同じプライバシー保護ポリシーに準拠
- Firebase Crashlyticsが設定されていない場合はログ出力のみ（条件付きコンパイル）

### 4.10 TimelinePagingState（@Observable）

**タイムライン表示用のページネーション状態管理クラス**:

```swift
@MainActor
@Observable
final class TimelinePagingState {
    // カーソル追跡
    var earliestLoadedDayKey: Int?  // 最も古い（過去側）にロード済みの日付キー（YYYYMMDD形式）
    var latestLoadedDayKey: Int?    // 最も新しい（未来側）にロード済みの日付キー（YYYYMMDD形式）

    // ローディングフラグ
    var isLoadingPast: Bool = false    // 過去方向のロード中フラグ
    var isLoadingFuture: Bool = false  // 未来方向のロード中フラグ

    // 境界フラグ
    var hasReachedEarliestData: Bool = false  // 過去方向のロードが完了（これ以上データがない）
    var hasReachedLatestData: Bool = false    // 未来方向のロードが完了（これ以上データがない）

    // ロード済みデータ
    var loadedArchivedEvents: [ArchivedCalendarEvent] = []

    // スクロール位置の復元用アンカー（将来の拡張用）
    var scrollAnchorId: String?

    // 主要メソッド
    func initialLoad(modelContext: ModelContext, enabledCalendarIds: Set<String>) async
    func loadPastPage(modelContext: ModelContext, enabledCalendarIds: Set<String>) async
    func loadFuturePage(modelContext: ModelContext, enabledCalendarIds: Set<String>) async
    func trimIfNeeded(scrollDirection: ScrollDirection)
}
```

**ページネーション戦略**:
- **カーソルベース**: 日付キー（YYYYMMDD形式の整数）を使用した効率的なクエリ
- **双方向ロード**: 過去方向と未来方向を独立して管理
- **初期ロード**: 「今日」を中心に未来側と過去側を両方ロード（各100件）
- **追加ロード**: 各方向に150件ずつ追加
- **ウィンドウトリミング**: 最大600件を超えた場合、スクロール方向と逆側を削除
- **重複防止**: 境界キーの記録により同一範囲の重複ロードを防止

**設定値（AppConfig.Timeline）**:
- `pageSize`: 1回のロードで取得する件数（150件）
- `maxLoadedItems`: タイムラインに保持する最大アイテム数（600件）
- `initialPageSize`: 初期ロード時に未来側と過去側それぞれに読む件数（100件）

**UIとの連携**:
- `TimelineView`の番兵ビュー（sentinel view）がスクロールで表示されると自動ロードをトリガー
- 上端の番兵 → 未来方向ロード（`loadFuturePage`）
- 下端の番兵 → 過去方向ロード（`loadPastPage`）
- タイムラインは逆時系列（新しいものが上）なので、上スクロール=未来、下スクロール=過去

**パフォーマンス最適化**:
- 有効なカレンダーのイベントのみをフィルタリング
- ソート済み配列として管理（`startDayKey`降順）
- 重複イベントの自動排除（`uid`でグループ化）

---

## 5. 技術スタック

| レイヤー | 技術 |
|----------|------|
| 言語 | Swift 5.9+ |
| UIフレームワーク | SwiftUI |
| データ永続化 | SwiftData |
| 認証 | Google Sign-In SDK |
| カレンダーAPI | Google Calendar API (REST) |
| 位置情報 | CoreLocation |
| 写真 | PhotosUI (PhotosPicker) |
| キャッシュ管理 | SwiftData（CachedCalendarEvent / ArchivedCalendarEvent） |
| クラッシュレポート | Firebase Crashlytics（オプション） |

### 5.1 Firebase Crashlytics設定手順

**前提条件**:
- Firebaseプロジェクトが作成済みであること
- Xcode 14.0以上を使用していること

**設定手順**:

1. **Firebase Consoleでアプリを登録**
   - [Firebase Console](https://console.firebase.google.com/)にアクセス
   - プロジェクトを選択（または新規作成）
   - 「プロジェクトの設定」→「アプリを追加」→「iOS」を選択
   - Bundle IDを入力（例: `com.yourcompany.CaleNote`）
   - `GoogleService-Info.plist`をダウンロード

2. **XcodeプロジェクトにFirebase SDKを追加**
   - Xcodeでプロジェクトを開く
   - File → Add Package Dependencies...
   - 以下のURLを入力: `https://github.com/firebase/firebase-ios-sdk`
   - バージョン: 最新の安定版を選択
   - 追加するパッケージ: `FirebaseCrashlytics`を選択

3. **GoogleService-Info.plistを追加**
   - ダウンロードした`GoogleService-Info.plist`をXcodeプロジェクトのルートディレクトリに追加
   - 「Copy items if needed」にチェックを入れる
   - Target Membershipで`CaleNote`にチェックを入れる

4. **ビルドスクリプトを追加**
   - Xcodeでプロジェクトを選択
   - Target `CaleNote`を選択
   - 「Build Phases」タブを開く
   - 「+」ボタンをクリック → 「New Run Script Phase」を選択
   - スクリプトを以下のように設定:
   ```bash
   "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
   ```
   - 「Input Files」に以下を追加:
   ```
   $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
   ```

5. **アプリ起動時にFirebaseを初期化（オプション）**
   - `CaleNoteApp.swift`でFirebaseを初期化する場合:
   ```swift
   import FirebaseCore
   
   @main
   struct CaleNoteApp: App {
       init() {
           FirebaseApp.configure()
       }
       // ...
   }
   ```
   - ただし、`SyncErrorReporter`は条件付きコンパイル（`#if canImport(FirebaseCrashlytics)`）を使用しているため、Firebaseが設定されていない場合でも動作する

**動作確認**:
- Firebase Crashlyticsが設定されている場合、同期失敗時にCrashlyticsに送信される
- Firebase Crashlyticsが設定されていない場合、コンソールにログが出力される
- 開発者向けツール画面で`SyncLog`を確認できる

**注意事項**:
- ユーザーコンテンツ（タイトル、本文など）は送信しない
- カレンダーIDはハッシュ化して送信（SHA256の最初8文字のみ）
- 同期操作のメタデータのみ送信

---

## 6. 開発フェーズ（実装状況）

### Phase 1: MVP ✅ 完了
**目標**: 基本的なジャーナル機能が動作する

- [x] プロジェクトセットアップ
- [x] SwiftDataモデル定義
- [x] メイン画面（タイムライン表示）
- [x] ジャーナル作成/編集画面
- [ ] カレンダーシート（日付選択、記録日ドット表示） - **未実装**
- [x] 基本的な検索機能
- [x] ハッシュタグ抽出（本文から `#tag` をパース）
- [x] 手入力検索（`#tag` 形式でタグ検索）
- [x] 最近使ったタグのローカル表示（`TagStats`）
- [x] 設定画面（基本項目）
- [x] 初期オンボーディングフロー（`GoogleSignInOnboardingView`、`CalendarSelectionOnboardingView`、`OnboardingCoordinatorView`）

### Phase 2: Googleカレンダー連携 ✅ 完了
**目標**: カレンダーの予定を表示できる

- [x] Google Sign-In実装（`GoogleAuthService`）
- [x] Calendar API連携（`GoogleCalendarClient`）
- [x] 予定の取得・表示（同期範囲: 過去30日〜未来30日、設定可能）
- [x] 差分同期の実装（`syncToken`使用、`CalendarSyncService`）
- [x] 予定とジャーナルの統合タイムライン（`TimelineItem`）
- [x] 同期範囲内イベントからのタグ抽出（`TagExtractor`）
- [x] Google Calendar への保存（`JournalCalendarSyncService`、`extendedProperties.private`使用）
- [x] 双方向同期（`CalendarToJournalSyncService`）
- [x] 長期キャッシュ取り込み（`ArchiveSyncService`）

### Phase 3: 拡張機能 ✅ 完了
**目標**: 使いやすさ向上

- [x] カラー・アイコン選択機能（カラーパレット・アイコンパレット実装）
- [x] 関連するエントリー機能（過去・未来の同日/同週同曜/同祝日エントリーの表示）
- [ ] 場所情報の追加（デフォルト設定含む） - **未実装**

### Phase 4: 公開準備 🔄 進行中
**目標**: App Store申請

- [ ] アプリアイコン・スクリーンショット
- [ ] プライバシーポリシー作成
- [ ] App Store Connect設定
- [ ] TestFlight配布
- [ ] 審査申請

### Phase 5: 開発者向けツール ✅ 完了
**目標**: デバッグと問題解決の効率化

- [x] 競合検知UI（`ConflictResolutionView`）
- [x] 競合解決機能（useLocal/useRemote）
- [x] 長期キャッシュ取り込みのキャンセル機能
- [x] 開発者向けツール画面（`DeveloperToolsView`）
- [x] 同期ログ記録（`SyncLog`モデル）
- [x] 隠し開発者モード（7回タップで有効化）
- [x] 同期失敗のCrashlytics送信（`SyncErrorReporter`）

### Phase 6: 将来の拡張（公開後）
- [ ] ウィジェット対応
- [ ] カレンダーシート（日付選択、記録日ドット表示）
- [ ] ダークモード対応
- [ ] iPad対応
- [ ] 場所情報の追加（デフォルト設定含む）

**注意**: CloudKit同期は**実装予定なし**。Google Calendarが唯一の外部永続先である。

---

## 6.5 設計上の思想

### 6.5.1 基本方針
- タグは管理するものではなく「思考の痕跡」
- 完全性よりも即時性・軽さを優先
- **Google Calendar を唯一の真実のソース（Single Source of Truth）とする**
- **アプリ内のSwiftDataはキャッシュおよび編集補助にすぎない**
- **サーバー同期やクラウド保存を「将来やるかも」前提で書かない** → Firebase は Auth / Crashlytics 専用で確定
- **「双方向同期」は抽象概念ではなく、`journalId` + `extendedProperties.private` による実装依存仕様である**

### 6.5.2 タグ設計の思想
- タグは本文中に自然に記述されるもの
- 全期間のタグ網羅は行わない（必要になった場合のみ、将来的に同期期間拡張や段階的インデックス構築を検討）
- 最近使ったタグのみを表示することで、UIをシンプルに保つ

---

## 7. UI/UXガイドライン

### 7.1 デザイン原則（変更なし）

- **シンプル**: 2タブ構成、必要最小限の要素
- **モダン**: iOS標準に準拠しつつ洗練されたデザイン
- **高速**: 入力から保存まで最短ステップ
- **文章が主役で、UIは邪魔をしないこと**

---

### 7.2 カラースキーマ（更新）

本アプリは **初期リリースではライトモードのみをサポート** する。
**ダークモード対応は未実装**（将来フェーズで検討予定）。

#### 7.2.1 ベースカラー（ライトモード）

| 要素 | カラーコード | 備考 |
|------|-------------|------|
| 背景 | #FAFAFA | 純白を避け、長文閲覧時の疲労を軽減 |
| メインテキスト | #1F1F1F | 高コントラスト |
| サブテキスト | rgba(31,31,31,0.6) | 補足情報用 |
| セパレーター | rgba(0,0,0,0.08) | 目立たせない |

---

#### 7.2.2 カードの基本デザイン

**予定とジャーナルは完全に統一されたカードデザインを使用する**（視覚的な区別は行わない）。

カードの左側に4px幅のカラーバーを表示し、カレンダーの色を反映する。アイコンは非表示（視認性向上のため）。

- ジャーナルエントリ作成時: カラーパレットから選択可能
  - カラー: デフォルト: ミュートブルー #3B82F6（カラーバーとして表示）
- 予定表示時: 設定でカレンダーごとに選択したカラーをカラーバーとして表示
  - カラー: デフォルト: ミュートブルー #3B82F6

---

#### 7.2.3 アクセントカラー

| 要素 | カラーコード |
|------|-------------|
| アクセント | #4CAF50 |

使用箇所は以下に限定する。

- 新規作成ボタン（FAB）
- 選択中の日付
- トグルON状態
- リンク的テキスト

---

### 7.3 カレンダー別カラー・アイコン設定

#### 7.3.1 概要

Googleカレンダーごとに、ユーザーが表示色とアイコンを選択できる機能を提供する。
- 色はアプリ側で用意した **デフォルトカラーパレットから選択** する方式とする
- アイコンはアプリ側で用意した **アイコンパレットから選択** する方式とする
- 自由入力型のカラーピッカーやアイコン選択は提供しない
- 各カレンダーの設定は、設定画面の「表示するカレンダー」セクションでカレンダー名をタップして開くカレンダー設定画面（`CalendarSettingsView`）で行う
- Googleカレンダー側で設定されているカラーをデフォルトとして取得（`GoogleCalendarClient.colorIdToHex`）

---

#### 7.3.2 デフォルトカラーパレット

カラーパレットは**Googleカレンダーの標準色をベース**にしています（Google Calendar APIの標準24色から25色を選択）。

- 5x5グリッドレイアウトで表示（25色）
- 赤系、オレンジ・黄色系、緑系、シアン・青系、紫系、ピンク系、茶色・グレー系など、各色系統から選択
- Google Calendar APIの標準カラーパレットを参照: https://developers.google.com/calendar/api/v3/reference/colors

---

#### 7.3.3 タイムラインでのカラーとアイコンの扱い

- **カレンダー色はカラーバーとして表示する**（アイコンは非表示）
  - タイムライン一覧: カード左側に4px幅のカラーバーを表示
  - 詳細画面: ヘッダー部分に4px幅のカラーバーを表示
- ジャーナルエントリのカラーは個別に選択可能（カラーパレットから選択）
  - `entry.colorHex`が空文字列やデフォルト値（`#3B82F6`）の場合、カレンダーの色を使用
- 予定のカラーは、カレンダー設定画面でカレンダーごとに選択したものを適用
- 同一色を複数カレンダーで選択可能とする
- **予定とジャーナルは視覚的に区別しない**（完全に統一されたカードデザイン）

---

#### 7.3.4 アイコンパレット

カレンダーごとに設定するアイコンは、以下のアイコンパレットから選択する。設定したアイコンは、そのカレンダーに属する予定やジャーナルエントリのカードに表示される。

| アイコン | 名称 | 想定用途 |
|---------|------|---------|
| 📝 | メモ | 一般的な記録 |
| 📅 | カレンダー | 予定・イベント |
| 💡 | アイデア | 思いつき・発想 |
| 🎯 | 目標 | 目標・タスク |
| ❤️ | 感情 | 感情・思い出 |
| 🍽️ | 食事 | 食事・料理 |
| 🏃 | 運動 | 運動・健康 |
| 📚 | 学習 | 勉強・読書 |
| 🎨 | 創作 | 創作活動 |
| 🎵 | 音楽 | 音楽・エンタメ |
| 🚗 | 移動 | 旅行・移動 |
| 💼 | 仕事 | 仕事・ビジネス |
| 🏠 | 家 | 家庭・プライベート |
| 🌟 | 星 | 特別な日 |
| （なし） | なし | アイコンを表示しない |

---

### 7.4 カレンダー画面の配色ルール（補足）

- ジャーナルあり日付: アクセントカラーのドット
- 今日の日付: アクセントカラーで塗りつぶし
- 選択中の日付: アクセントカラーの枠線
- それ以外の日付: グレー系テキスト

---

### 7.5 タイポグラフィ

#### 7.5.1 フォント設定

| 言語 | フォント | 用途 |
|------|---------|------|
| 日本語 | Noto Sans JP | すべての日本語テキスト |
| 英数字 | Inter | すべての英数字テキスト |

#### 7.5.2 フォントサイズ

- タイトル: 18pt（セミボールド）
- 本文: 16pt（レギュラー）
- サブテキスト（日時、場所など）: 14pt（レギュラー）
- キャプション: 12pt（レギュラー）

---

## 8. 非機能要件

### 8.1 パフォーマンス
- アプリ起動: 2秒以内
- ジャーナル保存: 即座
- カレンダー読み込み: 3秒以内
- 過去の同じ日検索: 1秒以内
- タイムラインスクロール: 60fps維持

### 8.2 セキュリティ
- Google認証トークンはKeychainに保存
- ローカルデータは端末内に保存（Phase 1）

### 8.3 プライバシー
- 位置情報は許可制
- 写真アクセスは許可制
- 分析データは収集しない（Phase 1）
- Crashlytics送信時もプライバシー保護を徹底
  - ユーザーコンテンツ（タイトル、本文）は送信しない
  - カレンダーIDはハッシュ化（SHA256の最初8文字のみ）
  - 同期操作のメタデータのみ送信

---

## 9. 制約・前提条件

### 9.1 技術的制約

- iOS 17以上必須（SwiftData使用のため）
- Googleアカウント必須（カレンダー連携時）
- ネットワーク必須（カレンダー同期時）
- オフライン時はジャーナル機能のみ利用可（ローカルキャッシュの表示・編集）

### 9.2 設計上の制約

- **CloudKit同期は実装しない**: Google Calendarが唯一の外部永続先である
- **サーバー同期は実装しない**: 双方向同期はGoogle Calendar API経由で直接実現
- **ダークモードは未実装**: 初期リリースではライトモードのみサポート

### 9.3 同期に関する制約

- 同期レート制限: 5秒間隔（`SyncRateLimiter`）
- 同期範囲: デフォルト過去30日〜未来30日（設定可能、最大365日）
- `syncToken`の有効期限: Google Calendar APIの仕様に依存（期限切れ時はフル同期にフォールバック）
- 競合処理: 30秒以上の差がある場合に競合検知、ユーザーに解決UIを表示（`ConflictResolutionView`）

---

## 10. 用語集

| 用語 | 説明 |
|------|------|
| エントリ | 1つのジャーナル記録（`JournalEntry`） |
| タイムライン | 逆時系列で並んだエントリと予定の一覧 |
| タグ | ハッシュタグ形式のラベル（#仕事、#アイデア等） |
| 過去の同じ日 | 今日と同じ月日の過去年のエントリ |
| 短期キャッシュ | `CachedCalendarEvent`。同期対象期間内のイベントを保持 |
| 長期キャッシュ | `ArchivedCalendarEvent`。全期間のイベントを保持（振り返り用） |
| syncToken | Google Calendar APIの差分同期用トークン |
| extendedProperties.private | Google Calendar Eventの拡張プロパティ。`journalId`を保存 |
| Single Source of Truth | Google Calendarが唯一の真実のソースである設計原則 |
| SyncErrorReporter | 同期失敗をCrashlyticsに送信するユーティリティ |
| SyncLog | 開発者向け同期ログモデル（SwiftData） |

