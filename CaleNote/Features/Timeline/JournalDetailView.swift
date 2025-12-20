import SwiftUI

struct JournalDetailView: View {
    let entry: JournalEntry
    @State private var isPresentingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.title?.isEmpty == false ? entry.title! : "（タイトルなし）")
                    .font(.title2)
                    .bold()

                Text(entry.eventDate, style: .date)
                    .foregroundStyle(.secondary)

                Divider()

                Text(entry.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("編集") {
                    isPresentingEditor = true
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            JournalEditorView(entry: entry)
        }
    }
}
