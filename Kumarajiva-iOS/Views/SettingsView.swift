import SwiftUI

struct SettingsView: View {
    @State private var playbackMode: PlaybackMode = UserSettings.shared.playbackMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("播放设置")) {
                    Picker("播放模式", selection: $playbackMode) {
                        ForEach(PlaybackMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .onChange(of: playbackMode) { newValue in
                        UserSettings.shared.playbackMode = newValue
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
} 