import NeedlbarCore
import SwiftUI

struct SettingsStudioSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct SettingsStudioToggle: View {
    let title: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            Text(title).font(.system(size: 17)).accessibilityHidden(true)
            Spacer()
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch)
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, minHeight: 54)
    }
}
struct SettingsStudioSidebar: View {
    @Binding var selection: SettingsStudioPage
    private func item(_ page: SettingsStudioPage, icon: String) -> some View {
        Button { selection = page } label: {
            HStack(spacing: 10) {
                if case let .provider(provider) = page {
                    ProviderBrandIcon(provider: provider, accessibility: .decorative)
                } else { Image(systemName: icon).frame(width: 20) }
                Text(page.title).font(.system(size: 15, weight: selection == page ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .padding(10).contentShape(Rectangle())
            .background(selection == page ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selection == page ? Color.white : Color.primary)
        }.buttonStyle(.plain)
         .accessibilityLabel(page.title)
         .accessibilityAddTraits(selection == page ? .isSelected : [])
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Needlbar").font(.title2.bold()).padding(.vertical, 18)
                item(.layout, icon: "rectangle.3.group")
                Text("SYSTEM").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                ForEach(MonitorModuleID.allCases.filter { $0 != .ai }, id: \.self) {
                    item(.module($0), icon: $0.systemImage)
                }
                Text("AI PROVIDERS").font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                ForEach(ProviderID.allCases, id: \.self) { item(.provider($0), icon: "") }
                Divider().padding(.vertical, 12)
                item(.notifications, icon: "bell")
                item(.data, icon: "lock.shield")
            }.padding(12)
        }.frame(width: 220).background(.regularMaterial)
    }
}
