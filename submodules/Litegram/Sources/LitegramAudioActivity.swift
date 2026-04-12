import Foundation
import ActivityKit

@available(iOS 16.1, *)
public struct LitegramAudioActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var isPlaying: Bool
        public var elapsed: Double
        public var duration: Double
        public var playbackRate: Double
        
        public init(title: String, artist: String, isPlaying: Bool, elapsed: Double, duration: Double, playbackRate: Double = 1.0) {
            self.title = title
            self.artist = artist
            self.isPlaying = isPlaying
            self.elapsed = elapsed
            self.duration = duration
            self.playbackRate = playbackRate
        }
    }
    
    public enum AudioType: String, Codable {
        case music
        case voice
    }
    
    public var audioType: AudioType
    
    public init(audioType: AudioType) {
        self.audioType = audioType
    }
}
