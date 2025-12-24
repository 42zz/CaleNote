import SwiftUI

/// Toast/Snackbar形式のメッセージ表示コンポーネント
struct ToastView: View {
    let message: String
    let type: ToastType
    let duration: TimeInterval
    
    @State private var isVisible: Bool = false
    
    enum ToastType {
        case info
        case success
        case error
        case warning
        
        var backgroundColor: Color {
            switch self {
            case .info:
                return Color(white: 0.2)
            case .success:
                return .green
            case .error:
                return .red
            case .warning:
                return .orange
            }
        }
        
        var iconName: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .success:
                return "checkmark.circle.fill"
            case .error:
                return "exclamationmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            }
        }
    }
    
    init(message: String, type: ToastType = .info, duration: TimeInterval = 3.0) {
        self.message = message
        self.type = type
        self.duration = duration
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.iconName)
                .font(.system(size: 16, weight: .medium))
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(type.backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .offset(y: isVisible ? 0 : 100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            // 指定時間後に自動で消す
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isVisible = false
                }
            }
        }
    }
}

/// ToastViewを表示するためのViewModifier
struct ToastModifier: ViewModifier {
    @Binding var toastMessage: String?
    @Binding var toastType: ToastView.ToastType
    var duration: TimeInterval = 3.0
    
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content

            if let message = toastMessage {
                ToastView(message: message, type: toastType, duration: duration)
                    .padding(.bottom, 60)  // タブバーの上に表示
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(200)  // タブバーより前面に表示
                    .onAppear {
                        // メッセージを表示したら、duration後に自動でnilにする
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                            toastMessage = nil
                        }
                    }
            }
        }
    }
}

extension View {
    /// Toastメッセージを表示するmodifier
    func toast(
        message: Binding<String?>,
        type: Binding<ToastView.ToastType>,
        duration: TimeInterval = 3.0
    ) -> some View {
        modifier(ToastModifier(toastMessage: message, toastType: type, duration: duration))
    }
}

