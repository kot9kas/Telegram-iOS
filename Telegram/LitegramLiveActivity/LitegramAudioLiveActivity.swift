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
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
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
        }
    }
}

// MARK: - Compact Views (collapsed Dynamic Island)

@available(iOS 16.2, *)
private struct CompactLeadingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: context.attributes.audioType == .music ? "music.note" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

@available(iOS 16.2, *)
private struct CompactTrailingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
    }
}

// MARK: - Minimal View (when multiple activities)

@available(iOS 16.2, *)
private struct MinimalView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.cyan)
    }
}

// MARK: - Expanded Views (long-press Dynamic Island)

@available(iOS 16.2, *)
private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    context.attributes.audioType == .music
                    ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 44, height: 44)
            
            Image(systemName: context.attributes.audioType == .music ? "music.note" : "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

@available(iOS 16.2, *)
private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Image(systemName: "forward.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.trailing, 4)
    }
}

@available(iOS 16.2, *)
private struct ExpandedCenterView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.state.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(context.state.artist)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
    }
}

@available(iOS 16.2, *)
private struct ExpandedBottomView: View {
    let context: ActivityViewContext<LitegramAudioActivityAttributes>
    
    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
                .tint(.white)
                .background(Color.white.opacity(0.2))
            
            HStack {
                Text(formatTime(context.state.elapsed))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text(formatTime(context.state.duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var progress: Double {
        guard context.state.duration > 0 else { return 0 }
        return min(context.state.elapsed / context.state.duration, 1.0)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        context.attributes.audioType == .music
                        ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: context.attributes.audioType == .music ? "music.note" : "waveform")
                    .font(.system(size: 20, weight: .semibold))
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
                
                ProgressView(value: progress)
                    .tint(.white)
                    .background(Color.white.opacity(0.2))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
    }
    
    private var progress: Double {
        guard context.state.duration > 0 else { return 0 }
        return min(context.state.elapsed / context.state.duration, 1.0)
    }
}
