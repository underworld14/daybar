import SwiftUI
import DayBarCore

/// Inline SomaFM lofi/ambient radio controls in the menu-bar panel footer.
struct LofiRadioStrip: View {
    @Environment(AppState.self) private var appState

    private var radio: RadioPlayerManager { appState.radio }
    private var controlsDisabled: Bool {
        radio.isBuffering || radio.isReconnecting || appState.isRadioLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LOFI RADIO")
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                leadingIndicator
                stationMenu
                Spacer(minLength: 4)
                if appState.radioLoadError != nil || radio.playbackError != nil {
                    retryButton
                }
                transportControls
            }

            subtitleLine

            Link("SomaFM", destination: URL(string: "https://somafm.com")!)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task {
            if appState.radioChannels.isEmpty {
                await appState.loadRadioChannels()
            }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if radio.isBuffering || radio.isReconnecting || appState.isRadioLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "waveform")
                .foregroundStyle(radio.isPlaying ? Color.accentColor : .secondary)
        }
    }

    @ViewBuilder
    private var stationMenu: some View {
        if appState.isRadioLoading && appState.radioChannels.isEmpty {
            Text("Loading stations…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let error = appState.radioLoadError, appState.radioChannels.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else {
            Menu {
                ForEach(appState.radioChannels) { channel in
                    Button {
                        Task { await appState.playRadio(channel) }
                    } label: {
                        Label {
                            Text("\(channel.title) · \(channel.genre)")
                        } icon: {
                            ChannelArtwork(appState: appState, channel: channel, size: 24)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(radio.currentChannel?.title ?? "Select station")
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 6) {
            Button {
                Task { await appState.radioPreviousChannel() }
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)
            .disabled(controlsDisabled || appState.radioSkipChannels.isEmpty)
            .help("Previous station")

            Button {
                Task { await appState.toggleRadio() }
            } label: {
                Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .disabled(appState.radioChannels.isEmpty && appState.radioLoadError != nil)
            .help(radio.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(radio.isPlaying ? "Pause radio" : "Play radio")

            Button {
                Task { await appState.radioNextChannel() }
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
            .disabled(controlsDisabled || appState.radioSkipChannels.isEmpty)
            .help("Next station")
        }
        .foregroundStyle(.primary)
    }

    private var retryButton: some View {
        Button {
            Task {
                if appState.radioChannels.isEmpty {
                    await appState.loadRadioChannels()
                } else {
                    await radio.retryPlayback()
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Retry")
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if radio.isReconnecting {
            Text("Reconnecting…")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let error = radio.playbackError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if let track = radio.nowPlaying, !track.isEmpty {
            Text(track)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ChannelArtwork: View {
    var appState: AppState
    let channel: SomaFMChannel
    let size: CGFloat

    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let nsImage = RadioArtworkCache.image(from: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: channel.id) {
            imageData = await appState.artworkData(for: channel)
        }
    }
}
