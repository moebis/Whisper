@preconcurrency import AVFoundation
import Foundation

class AudioEngine: ObservableObject, @unchecked Sendable {
    @Published var audioLevel: Double = 0.0
    @Published var isRecording: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    
    var onAudioChunk: ((String) -> Void)?
    
    init() {
        // Initialize target format: 24,000 Hz, 16-bit Linear PCM, Mono (1 channel)
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        )
    }
    
    /// Requests microphone access if it hasn't been granted yet.
    static func checkAndRequestPermission(completion: @escaping @Sendable (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    /// Starts capturing microphone input and downsampling it.
    func start() {
        guard !isRecording else { return }
        
        // Double-check permissions first
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            AppLogger.error("Whisper [AudioEngine]: Microphone permission is not authorized.")
            return
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        self.inputFormat = inputFormat
        
        guard let targetFormat = targetFormat else { return }
        
        // Create an AVAudioConverter to translate native mic format (e.g. 48kHz float) to 24kHz Int16
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            AppLogger.error("Whisper [AudioEngine]: Failed to create audio converter from \(inputFormat) to \(targetFormat)")
            return
        }
        self.audioConverter = converter
        
        // Buffer size: 1024 frames is a good sweet spot for latency (approx. 21ms at 48kHz)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // 1. Calculate RMS of the original float buffer for real-time visualizer
            var sum: Float = 0
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = frameLength > 0 ? sqrt(sum / Float(frameLength)) : 0.0
                
                let level = AudioLevelMeter.normalizedLevel(rms: rms)
                
                DispatchQueue.main.async {
                    self.audioLevel = AudioLevelMeter.smoothedLevel(
                        previous: self.audioLevel,
                        current: level
                    )
                }
            }
            
            // 2. Perform sample rate & bit depth conversion
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                AppLogger.error("Whisper [AudioEngine]: Failed to allocate output buffer")
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            
            if status == .haveData, let channelData = outputBuffer.int16ChannelData?[0] {
                let bytesCount = Int(outputBuffer.frameLength) * 2 // 16-bit PCM = 2 bytes per sample
                let data = Data(bytes: channelData, count: bytesCount)
                let base64String = data.base64EncodedString()
                
                // Fire the callback with the base64-encoded PCM chunk
                self.onAudioChunk?(base64String)
            } else if let error = error {
                AppLogger.error("Whisper [AudioEngine]: Conversion failed: \(error.localizedDescription)")
            }
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            AppLogger.info("Whisper [AudioEngine]: Started recording")
        } catch {
            AppLogger.error("Whisper [AudioEngine]: Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
        }
    }
    
    /// Stops the audio recording.
    func stop() {
        guard isRecording else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        DispatchQueue.main.async {
            self.audioLevel = 0.0
        }
        AppLogger.info("Whisper [AudioEngine]: Stopped recording")
    }
}
