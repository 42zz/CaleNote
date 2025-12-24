import SwiftUI

struct RelatedMemorySettingsSection: View {
    @State private var settings = RelatedMemorySettings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $settings.sameDayEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同じ日")
                        .font(.body)
                    Text("過去の同じ月日のエントリーを表示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.sameDayEnabled) { _, _ in
                settings.save()
            }

            Toggle(isOn: $settings.sameWeekdayEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同じ週の同じ曜日")
                        .font(.body)
                    Text("過去の同じ週番号・曜日のエントリーを表示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: settings.sameWeekdayEnabled) { _, _ in
                settings.save()
            }

            // Toggle(isOn: $settings.sameHolidayEnabled) {
            //     VStack(alignment: .leading, spacing: 4) {
            //         Text("同じ祝日")
            //             .font(.body)
            //         Text("過去の同じ祝日のエントリーを表示")
            //             .font(.caption)
            //             .foregroundStyle(.secondary)
            //     }
            // }
            // .onChange(of: settings.sameHolidayEnabled) { _, _ in
            //     settings.save()
            // }

            Divider()

            HStack {
                Text("現在有効な条件:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(settings.enabledConditionsText)
                    .font(.caption)
                    .foregroundStyle(settings.hasAnyEnabled ? .blue : .secondary)
            }
        }
    }
}
