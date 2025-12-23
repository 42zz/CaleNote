import Foundation

/// アプリ全体の設定値を管理するクラス
enum AppConfig {
    /// タイムラインページネーション設定
    enum Timeline {
        /// 1回のロードで取得する件数（アーカイブイベント）
        /// パフォーマンス向上のため、150から100に削減
        static let pageSize: Int = 100

        /// タイムラインに保持する最大アイテム数
        /// この数を超えたら、スクロール方向と逆側をトリム
        /// パフォーマンス向上のため、600から150に削減
        static let maxLoadedItems: Int = 120

        /// 初期ロード時に未来側と過去側それぞれに読む件数
        /// パフォーマンス向上のため、100から50に削減
        static let initialPageSize: Int = 30
    }
}
