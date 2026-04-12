import SwiftUI
import WidgetKit
import ActivityKit
import Litegram

@available(iOS 16.2, *)
struct LitegramAudioLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LitegramAudioActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 4) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .keylineTint(.cyan)
        }
    }
}

// MARK: - Compact Views

@available(iOS 16.2, *)
private struct CompactLeadingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    context.attributes.audioType == .music
                    ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 22, height: 22)

            Image(systemName: context.attributes.audioType == .music ? "music.note" : "mic.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

@available(iOS 16.2, *)
private struct CompactTrailingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        WaveformView(isPlaying: context.state.isPlaying, barCount: 3, color: .cyan)
            .frame(width: 16, height: 12)
    }
}

// MARK: - Minimal View

@available(iOS 16.2, *)
private struct MinimalView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)

            Image(systemName: context.attributes.audioType == .music ? "music.note" : "mic.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Expanded Leading (album art + track info)

@available(iOS 16.2, *)
private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        context.attributes.audioType == .music
                        ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 52, height: 52)

                Image(systemName: context.attributes.audioType == .music ? "music.note" : "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(context.state.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 4)
    }
}

// MARK: - Expanded Trailing (waveform)

@available(iOS 16.2, *)
private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        WaveformView(isPlaying: context.state.isPlaying, barCount: 5, color: .cyan)
            .frame(width: 30, height: 26)
            .padding([.top, .trailing], 12)
    }
}

// MARK: - Expanded Bottom (progress + controls)

@available(iOS 16.2, *)
private struct ExpandedBottomView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.white)
                    .background(Color.white.opacity(0.15))

                HStack {
                    Text(formatTime(context.state.elapsed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    Text("-\(formatTime(remaining))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: 36) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)

                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.bottom, 2)
        }
    }

    private var progress: Double {
        guard context.state.duration > 0 else { return 0 }
        return min(context.state.elapsed / context.state.duration, 1.0)
    }

    private var remaining: Double {
        return max(context.state.duration - context.state.elapsed, 0)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Lock Screen View

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            context.attributes.audioType == .music
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: context.attributes.audioType == .music ? "music.note" : "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(context.state.artist)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 20) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)

                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .tint(.white)
                    .background(Color.white.opacity(0.15))

                HStack {
                    Text(formatTime(context.state.elapsed))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    Text("-\(formatTime(remaining))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
    }

    private var progress: Double {
        guard context.state.duration > 0 else { return 0 }
        return min(context.state.elapsed / context.state.duration, 1.0)
    }

    private var remaining: Double {
        return max(context.state.duration - context.state.elapsed, 0)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Animation View

@available(iOS 16.2, *)
private struct WaveformView: View {
    let isPlaying: Bool
    let barCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(isPlaying: isPlaying, delay: Double(index) * 0.15, color: color)
            }
        }
    }
}

@available(iOS 16.2, *)
private struct WaveformBar: View {
    let isPlaying: Bool
    let delay: Double
    let color: Color

    @State private var height: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: geo.size.height * height)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .onAppear {
                    if isPlaying {
                        startAnimation()
                    }
                }
                .onChange(of: isPlaying) { playing in
                    if playing {
                        startAnimation()
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            height = 0.3
                        }
                    }
                }
        }
    }

    private func startAnimation() {
        withAnimation(
            .easeInOut(duration: 0.4 + delay)
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            height = CGFloat.random(in: 0.5...1.0)
        }
    }
}
