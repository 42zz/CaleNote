import SwiftUI

/// 同期ステータスを右下に表示するインジケーター
/// idle/syncing/success/error の4状態に対応
struct SyncStatusIndicator: View {
    @ObservedObject var statusStore: SyncStatusStore
    let onRetry: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                // ステータスに応じて表示
                switch statusStore.status {
                case .idle:
                    EmptyView()

                case .syncing:
                    syncingIcon()
                        .transition(.scale.combined(with: .opacity))

                case .success:
                    successIcon()
                        .transition(.scale.combined(with: .opacity))

                case .error:
                    errorIcon()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 80)  // タブバーの上に表示（タブバー高さ約60 + マージン20）
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: statusStore.status)
    }

    // MARK: - Syncing Icon

    @ViewBuilder
    private func syncingIcon() -> some View {
        HStack(spacing: 8) {
            if isExpanded {
                Text("同期中...")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.9))
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Success Icon

    @ViewBuilder
    private func successIcon() -> some View {
        HStack(spacing: 8) {
            if isExpanded {
                if let details = statusStore.successDetails {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Text("完了")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.9))
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Error Icon

    @ViewBuilder
    private func errorIcon() -> some View {
        HStack(spacing: 8) {
            if isExpanded {
                VStack(alignment: .trailing, spacing: 4) {
                    if let errorMessage = statusStore.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Text("タップで再試行")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.9))
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onTapGesture {
            if isExpanded {
                // 展開時のタップで再試行
                onRetry()
                withAnimation {
                    isExpanded = false
                }
            } else {
                // 縮小時のタップで展開
                withAnimation {
                    isExpanded = true
                }
            }
        }
    }
}
