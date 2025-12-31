# CaleNote

Googleカレンダーを唯一の正（Single Source of Truth）として、予定と記録を同一のスケジュール体験として扱うiOSアプリ。

## プロダクト概要

CaleNoteは、ユーザーが日常的に行っている「カレンダーを見る」という行為の流れを断ち切ることなく、そのまま記録を書く行為へ自然に接続することを目的としたジャーナルアプリです。

一般的なジャーナルアプリが要求する「専用アプリを開く」「書くための意識的な切り替え」を排除し、カレンダーという既存の習慣に寄生することで、継続性を獲得することを設計思想の中核としています。

CaleNoteにおいて、予定と記録はユーザー体験上は区別されません。すべては単一の「スケジュールエントリー」として扱われ、Googleカレンダー上のイベントとして保存・同期されます。

## 基本設計原則

* **GoogleカレンダーをSSoTとする完全な双方向同期**
* **操作に対する即時UI反映（ローカル即反映・非同期同期）**
* **Rawデータ走査を避けたインデックス駆動設計**
* **学習コストを発生させないUI・操作導線**

## 主な機能

### タイムライン表示
* Googleカレンダーアプリのスケジュールビューをベンチマークとした縦方向タイムライン
* 日付ごとにセクションを分け、その日のスケジュールエントリーを時系列順に表示
* Googleカレンダー由来の予定とCaleNoteで作成された記録が同一のリスト上に混在表示

### エントリー作成・編集
* 画面右下のFAB（＋）から新規スケジュールエントリーを作成
* 入力項目：タイトル、本文（任意）、タグ（#tag形式）
* ローカルデータベースへの即時保存とUI更新、その後バックグラウンドでGoogleカレンダーへ同期

### 同期機能
* Googleカレンダーを唯一の正とする双方向同期
* アプリ操作時はローカルへ即時反映、Googleカレンダーへの反映は非同期で実行
* 同期状態の可視化と再送機能
* BackgroundTasks によるバックグラウンド同期（App Refresh / Processing）

### 検索機能
* 専用のSearch Indexを用いた高速検索
* タイトルの前方一致およびタグ検索は200ms以内のレスポンス
* 本文検索は段階的・遅延実行

### ゴミ箱機能
* 削除エントリーを論理削除として保持し、設定画面から復元可能
* 保持期間（7/30/60日）と自動削除のオン・オフを設定
* ゴミ箱内データは検索・タグ・関連表示の対象外

### 振り返り機能
* エントリー詳細画面で関連する過去・未来のエントリーを表示
* 関連判定：同一月日（MMDD一致）、同一週の同一曜日、同一祝日

## データモデル

### スケジュールエントリー

CaleNoteにおける最小データ単位は「スケジュールエントリー」です。ユーザー体験上は単一の概念として扱い、予定か記録かといった種別をユーザーに認識させません。

内部的には以下の管理情報を保持します：

* `source`（google / calenote）
* `managedByCaleNote`（boolean）
* `googleEventId`
* `startAt` / `endAt`
* `title` / `body`
* `tags`
* `syncStatus`（synced / pending / failed）
* `lastSyncedAt`
* `isDeleted` / `deletedAt`

パフォーマンス確保のため、SwiftDataのインデックスを以下の項目に付与しています：`source` / `managedByCaleNote` / `googleEventId` / `calendarId` / `startAt` / `endAt` / `syncStatus` / `isDeleted` / `deletedAt`。

### Googleカレンダーイベント対応

すべてのスケジュールエントリーは、Googleカレンダー上のイベントと1対1に対応します。CaleNoteで作成された記録は、Googleカレンダーイベントとして保存される際に、CaleNote管理イベントであることを示す識別メタデータを付与します。

ローカルデータはキャッシュおよび高速表示のための存在であり、最終的な正は常にGoogleカレンダーに置かれます。

## 技術スタック

* **Framework**: SwiftUI (iOS 17.0+)
* **Persistence**: SwiftData
* **Authentication**: Google Sign-In SDK
* **Networking**: URLSession
* **Concurrency**: Swift async/await

## セットアップ

### 必要な環境

* Xcode 15.0以上
* iOS 17.0以上
* Google Cloud Platform プロジェクト（OAuth認証用）

### ビルド方法

```bash
# プロジェクトを開く
open CaleNote.xcodeproj

# ビルド
xcodebuild -scheme CaleNote -configuration Debug build
```

### 依存関係

プロジェクトはSwift Package Managerを使用して依存関係を管理します。初回ビルド時に自動的に解決されます。

## テスト

### UIテスト

XCUITest を利用した UI テストが `CaleNoteUITests` にあります。起動引数で UI テスト用の状態を構成します。

```bash
# UIテスト実行例
xcodebuild -scheme CaleNote -destination 'platform=iOS Simulator,name=iPhone 15' test
```

主な起動引数:

* `UI_TESTING` - UIテストモード
* `UI_TESTING_RESET` - UserDefaults をリセット
* `UI_TESTING_SEED` - シードデータ投入
* `UI_TESTING_COMPLETE_ONBOARDING` - オンボーディング完了済みに設定
* `UI_TESTING_MOCK_AUTH` - Google認証をモック化
* `UI_TESTING_SKIP_SYNC` - 同期処理を無効化
* `UI_TESTING_DARK_MODE` / `UI_TESTING_LIGHT_MODE` - 画面表示モード切替

## アーキテクチャ

### レイヤー構造

```
┌─────────────────────────────────────────┐
│         Features (SwiftUI Views)        │  ← ユーザーインターフェース層
├─────────────────────────────────────────┤
│     Infrastructure (Services)           │  ← ビジネスロジック層
├─────────────────────────────────────────┤
│         Domain (Models)                 │  ← データモデル層
├─────────────────────────────────────────┤
│    SwiftData + Google Calendar API      │  ← データソース
└─────────────────────────────────────────┘
```

### 同期設計

* **即時反映**: アプリ操作時はローカルへ即時反映
* **非同期同期**: Googleカレンダーへの反映は非同期で実行
* **双方向同期**: Googleカレンダー側での変更もアプリ側へ反映
* **同期状態管理**: 各エントリーは同期状態を持ち、同期待ち・失敗状態は再送可能
* **バックグラウンド実行**: BGAppRefreshTask で定期同期、BGProcessingTask でインデックス再構築

## UI・ナビゲーション構造

UI構造はGoogleカレンダーアプリの操作感をベンチマークとします。

* 上部：表示切替トグル、月表示、検索、今日フォーカス
* 左側：サイドバー（カレンダー表示切替、設定、フィードバック導線）
* メイン：縦方向タイムライン

ユーザーに新たな概念を学習させないことを、UI設計上の制約条件とします。

## 非機能要件

* **パフォーマンス**: 起動から初期表示まで体感1秒以内
* **スムーズな操作**: スクロール・検索時のフレーム落ちを許容しない
* **データ整合性**: ローカルデータ破損時はGoogleカレンダーから再構築可能
* **検索速度**: タイトル・タグ検索は200ms以内のレスポンス

## 開発ガイドライン

詳細な開発ガイドラインについては、[CLAUDE.md](./CLAUDE.md)を参照してください。

## 更新履歴

詳細な変更履歴については、[CHANGELOG.md](./CHANGELOG.md)を参照してください。
