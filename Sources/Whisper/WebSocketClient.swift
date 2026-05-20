import Foundation

class WebSocketClient: NSObject, @unchecked Sendable {
    var onTranscriptDelta: ((String) -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?
    var onConnectionStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onTranscriptionCompleted: ((String) -> Void)?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var isConnected = false
    private var audioQueue: [String] = []
    private var apiKey: String = ""
    private var accumulatedTranscript: String = ""
    
    var accumulatedTranscriptText: String {
        return accumulatedTranscript
    }
    
    var isConnectedState: Bool {
        return isConnected
    }
    
    /// Connects to the OpenAI Realtime WebSocket API using the pre-configured API Key.
    func connect(apiKey: String) {
        guard !apiKey.isEmpty else {
            self.onError?("OpenAI API Key is missing or empty. Please set it in Settings.")
            return
        }
        
        // If already connected with the same API key, do not reconnect
        if isConnected && self.apiKey == apiKey && webSocketTask != nil {
            AppLogger.info("Whisper [WebSocketClient]: Already connected and pre-warmed.")
            return
        }
        
        // If connecting with a different API key, cancel the current task
        if self.apiKey != apiKey && webSocketTask != nil {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isConnected = false
        }
        
        self.apiKey = apiKey
        self.isConnected = false
        self.audioQueue.removeAll()
        self.accumulatedTranscript = ""
        
        // Connect to OpenAI Realtime API endpoint using a transcription intent
        let urlString = "wss://api.openai.com/v1/realtime?intent=transcription"
        guard let url = URL(string: urlString) else {
            self.onError?("Invalid WebSocket URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0
        
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        
        AppLogger.info("Whisper [WebSocketClient]: Connecting to \(urlString)...")
        receiveMessages()
    }
    
    /// Commits the audio buffer and gracefully disconnects from the API.
    func disconnect() {
        if isConnected {
            sendCommit()
        }
        
        // Wait a brief moment to allow the commit to register, then cancel task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.isConnected = false
            self.onConnectionStateChange?(false)
            AppLogger.info("Whisper [WebSocketClient]: Disconnected")
        }
    }
    
    /// Commits the audio buffer and triggers background pre-warming of the next session.
    func stopAndPrepareNext() {
        if isConnected {
            sendCommit()
        }
        
        // Wait up to 1.5 seconds for completed transcription event before forcing a reset.
        let currentTask = self.webSocketTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            if self.webSocketTask === currentTask && self.webSocketTask != nil {
                AppLogger.info("Whisper [WebSocketClient]: Timeout waiting for completion. Reconnecting...")
                self.reconnectAndPrewarm()
            }
        }
    }
    
    /// Closes the current session and pre-warms a fresh session in the background.
    func reconnectAndPrewarm() {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        self.webSocketTask = nil
        self.isConnected = false
        self.onConnectionStateChange?(false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, !self.apiKey.isEmpty else { return }
            AppLogger.info("Whisper [WebSocketClient]: Pre-warming next session connection...")
            self.connect(apiKey: self.apiKey)
        }
    }
    
    /// Sends the raw transcript text to OpenAI's GPT-5.4-nano model to perform self-correction, removal of fillers, etc.
    func polishTranscript(_ rawText: String, apiKey: String, completion: @escaping @Sendable (String) -> Void) {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(rawText)
            return
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": "gpt-5.4-nano",
            "messages": [
                [
                    "role": "system",
                    "content": "Clean up the following spoken dictation. Remove verbal hesitations, filler words (uh, um), and self-corrections (e.g. rewrite 'going to the beach, no wait, I mean the shore' to 'going to the shore'). Preserve the original meaning, capitalization, and punctuation. Return ONLY the polished final text, without quotes, comments, or introductory/concluding remarks."
                ],
                [
                    "role": "user",
                    "content": rawText
                ]
            ],
            "temperature": 0.0
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(rawText)
            return
        }
        request.httpBody = httpBody
        
        AppLogger.info("Whisper [WebSocketClient]: Polishing transcript with gpt-5.4-nano: \"\(rawText)\"")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                AppLogger.error("Whisper [WebSocketClient]: Polish request failed: \(error?.localizedDescription ?? "no data")")
                completion(rawText)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                let polished = content.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.info("Whisper [WebSocketClient]: Polishing success: \"\(polished)\"")
                completion(polished)
            } else {
                if let responseString = String(data: data, encoding: .utf8) {
                    AppLogger.error("Whisper [WebSocketClient]: Invalid polish response: \(responseString)")
                }
                completion(rawText)
            }
        }
        task.resume()
    }
    
    /// Sends base64-encoded PCM audio to the server. If not connected yet, buffers the audio.
    func sendAudio(base64Data: String) {
        if isConnected {
            sendAudioChunk(base64Data)
        } else {
            audioQueue.append(base64Data)
        }
    }
    
    private func sendAudioChunk(_ base64Data: String) {
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Data
        ]
        sendJson(event)
    }
    
    private func sendCommit() {
        let event: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]
        sendJson(event)
        AppLogger.info("Whisper [WebSocketClient]: Sent input_audio_buffer.commit")
    }
    
    private func configureSession() {
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ],
                        "transcription": [
                            "model": "gpt-realtime-whisper",
                            "language": "en"
                        ],
                        "turn_detection": NSNull()
                    ]
                ]
            ] as [String : Any]
        ]
        sendJson(event)
        AppLogger.info("Whisper [WebSocketClient]: Configuring session options for transcription...")
    }
    
    private func sendJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { error in
            if let error = error {
                AppLogger.error("Whisper [WebSocketClient]: WebSocket send error: \(error.localizedDescription)")
            }
        }
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()
            case .failure(let error):
                let nsError = error as NSError
                // Do not report errors when cancelling connection on hotkey release
                if nsError.domain != NSURLErrorDomain || nsError.code != URLError.cancelled.rawValue {
                    AppLogger.error("Whisper [WebSocketClient]: WebSocket error: \(error.localizedDescription)")
                    self.onError?(error.localizedDescription)
                }
                self.isConnected = false
                self.onConnectionStateChange?(false)
            }
        }
    }
    
    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        guard let type = json["type"] as? String else { return }
        
        switch type {
        case "session.created":
            AppLogger.info("Whisper [WebSocketClient]: Session created on server")
            configureSession()
            onConnectionStateChange?(true)
            
        case "session.updated":
            AppLogger.info("Whisper [WebSocketClient]: Session configured successfully")
            isConnected = true
            // Flush any buffered audio chunks
            for chunk in audioQueue {
                sendAudioChunk(chunk)
            }
            audioQueue.removeAll()
            
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                self.accumulatedTranscript += delta
                onTranscriptDelta?(delta)
                onTranscriptUpdate?(self.accumulatedTranscript)
            }
            
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                AppLogger.info("Whisper [WebSocketClient]: Transcription completed: \(transcript)")
                onTranscriptionCompleted?(transcript)
            }
            reconnectAndPrewarm()
            
        case "error":
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                AppLogger.error("Whisper [WebSocketClient]: OpenAI API error: \(message)")
                onError?(message)
            }
            
        default:
            break
        }
    }
}
