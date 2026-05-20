import SwiftUI
import AVFoundation

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var smartPolishEnabled = true
    @State private var hasMicrophonePermission = false
    @State private var hasAccessibilityPermission = false
    
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whisper Configuration")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            // API Key Configuration
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenAI API Key:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                SecureField("Enter OpenAI API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                
                Text("Saved locally on this Mac. Required before dictation can start.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Smart Polish Option
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $smartPolishEnabled) {
                    Text("Enable Smart Polish (GPT-5.4-nano)")
                        .font(.system(size: 12, weight: .bold))
                }
                .toggleStyle(.checkbox)
                
                Text("When enabled, Whisper automatically cleans up stutters, filler words, and self-corrections on stop. When disabled, the raw transcript is typed in real-time as-is.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
            
            // Permissions Section
            VStack(alignment: .leading, spacing: 10) {
                Text("System Permissions")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                // Microphone access indicator/button
                HStack {
                    Image(systemName: hasMicrophonePermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasMicrophonePermission ? .green : .orange)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone Permission")
                            .font(.system(size: 12, weight: .medium))
                        Text("Needed to record and stream your voice.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !hasMicrophonePermission {
                        Button("Grant Access") {
                            requestMicrophoneAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Text("Granted")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Accessibility access indicator/button
                HStack {
                    Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibilityPermission ? .green : .orange)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Permission")
                            .font(.system(size: 12, weight: .medium))
                        Text("Required to type text into other active apps.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !hasAccessibilityPermission {
                        Button("Grant Access") {
                            requestAccessibilityAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Text("Granted")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Usage Tips
            VStack(alignment: .leading, spacing: 6) {
                Text("How to Use Whisper:")
                    .font(.system(size: 12, weight: .bold))
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("Select any text input or text box in another app.", systemImage: "cursorarrow.and.square.on.square")
                    Label("Double-tap **Left Control** within 1 second to start dictation.", systemImage: "keyboard")
                    Label("Speak into your microphone—a floating HUD will show your text.", systemImage: "waveform")
                    Label("Tap **Left Control** once to stop dictation.", systemImage: "text.bubble")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission Issues?")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary)
                    Text("If you granted access but it still says 'Granted: No', you may need to **relaunch the Whisper app** for macOS to apply the settings. If that fails, remove Whisper from the Accessibility list in System Settings (select it and click the '-' button), re-add/toggle it, and relaunch.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                .padding(.top, 2)
            }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 500, height: 560)
        .onAppear {
            loadSettings()
            checkPermissions()
        }
        .onReceive(timer) { _ in
            checkPermissions()
        }
        .onChange(of: apiKey) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "OpenAI_API_Key")
        }
        .onChange(of: smartPolishEnabled) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "SmartPolishEnabled")
        }
    }
    
    private func loadSettings() {
        if let savedKey = UserDefaults.standard.string(forKey: "OpenAI_API_Key"), !savedKey.isEmpty {
            self.apiKey = savedKey
        } else {
            self.apiKey = ""
        }
        self.smartPolishEnabled = UserDefaults.standard.object(forKey: "SmartPolishEnabled") as? Bool ?? true
    }
    
    private func checkPermissions() {
        self.hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.hasAccessibilityPermission = AXIsProcessTrusted()
    }
    
    private func requestMicrophoneAccess() {
        AudioEngine.checkAndRequestPermission { granted in
            Task { @MainActor in
                self.hasMicrophonePermission = granted
            }
        }
    }
    
    private func requestAccessibilityAccess() {
        // Use [String: Any] typing to ensure Bool bridges to CFBoolean/NSNumber and does not segfault in C API.
        // Use "AXTrustedCheckOptionPrompt" string literal key to bypass Swift 6 global variable warnings.
        let options: [String: Any] = [
            "AXTrustedCheckOptionPrompt": true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Poll for a brief moment to see if accessibility status changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task { @MainActor in
                self.hasAccessibilityPermission = AXIsProcessTrusted()
            }
        }
    }
}
