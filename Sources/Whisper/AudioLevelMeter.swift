import Foundation

enum AudioLevelMeter {
    static func normalizedLevel(rms: Float) -> Double {
        guard rms > 0 else { return 0.0 }
        
        let decibels = 20.0 * log10(Double(rms))
        let noiseFloor = -48.0
        let speechCeiling = -14.0
        let normalized = (decibels - noiseFloor) / (speechCeiling - noiseFloor)
        let gated = clamp(normalized)
        
        guard gated > 0 else { return 0.0 }
        return pow(gated, 0.50)
    }
    
    static func smoothedLevel(previous: Double, current: Double) -> Double {
        let coefficient = current > previous ? 0.78 : 0.26
        return previous * (1.0 - coefficient) + current * coefficient
    }
    
    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
