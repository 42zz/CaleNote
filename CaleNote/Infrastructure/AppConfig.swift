import Foundation

/// アプリ全体の設定値を管理するクラス
enum AppConfig {
    /// タイムラインページネーション設定
    enum Timeline {
        /// 1回のロードで取得する件数（アーカイブイベント）
        static let pageSize: Int = 30

        /// タイムラインに保持する最大アイテム数
        /// この数を超えたら、スクロール方向と逆側をトリム
        static let maxLoadedItems: Int = 75

        /// 初期ロード時に未来側と過去側それぞれに読む件数
        static let initialPageSize: Int = 30

        /// 追加ロードをトリガーする位置（端からの件数）
        static let loadTriggerOffset: Int = 15
    }
}
