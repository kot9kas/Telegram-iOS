import Foundation
import ActivityKit

@available(iOS 16.2, *)
public final class LitegramAudioActivityManager {
    public static let shared = LitegramAudioActivityManager()
    
    private var currentActivity: Activity<LitegramAudioActivityAttributes>?
    private var lastUpdateTime: CFAbsoluteTime = 0
    private let minUpdateInterval: TimeInterval = 0.5
    
    private init() {}
    
    public func startActivity(
        audioType: LitegramAudioActivityAttributes.AudioType,
        title: String,
        artist: String,
        duration: Double
    ) {
        endActivity()
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = LitegramAudioActivityAttributes(audioType: audioType)
        let state = LitegramAudioActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: true,
            elapsed: 0,
            duration: duration
        )
        
        let content = ActivityContent(state: state, staleDate: nil)
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("[LitegramAudioActivity] Failed to start: \(error)")
        }
    }
    
    public func updateActivity(
        title: String,
        artist: String,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double,
        playbackRate: Double = 1.0
    ) {
        guard let activity = currentActivity else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastUpdateTime >= minUpdateInterval else { return }
        lastUpdateTime = now
        
        let state = LitegramAudioActivityAttributes.ContentState(
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            playbackRate: playbackRate
        )
        
        let content = ActivityContent(state: state, staleDate: nil)
        
        Task {
            await activity.update(content)
        }
    }
    
    public func endActivity() {
        guard let activity = currentActivity else { return }
        
        let state = activity.content.state
        let content = ActivityContent(state: state, staleDate: nil)
        
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        
        currentActivity = nil
    }
    
    public var isActive: Bool {
        return currentActivity != nil
    }
}
