//
//  Rootiew.swift
//  CaleNote
//
//  Created by Masaya Kawai on 2025/12/20.
//
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("メイン", systemImage: "list.bullet")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}
