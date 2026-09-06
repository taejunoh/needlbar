// SettingsPreviewView.swift
import AppKit
import SwiftUI

@MainActor
struct SettingsPreviewView: View {
    @ObservedObject var model: SettingsPreviewModel
    @Environment(\.displayScale) private var scale
    var body: some View {
        SettingsStudioSection(title: "Menu bar preview") {
            HStack {
                if let layout = MenuBarDashboardTwoLineLayout.fit(segments: model.result.segments,
                    width: 240, height: 22, scale: scale),
                   let image = MenuBarDashboardImageRenderer.render(layout: layout, scale: scale) {
                    Image(nsImage: image).accessibilityHidden(true)
                } else {
                    Image(systemName: "chart.bar.fill").accessibilityHidden(true)
                }
                Spacer()
            }.frame(minHeight: 54)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.result.tooltip)
    }
}
