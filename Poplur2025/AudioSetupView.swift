import SwiftUI

/// A helper view for generating and testing dial tone sounds
/// Add this to your app temporarily to generate the audio files
struct AudioSetupView: View {
    @State private var isGenerating = false
    @State private var generatedFiles: [String] = []
    @State private var testDigit: String = "5"
    
    private let tonePlayer = DialTonePlayer()
    
    var body: some View {
        NavigationStack {
            List {
                Section("Generate Dial Tones") {
                    if generatedFiles.isEmpty {
                        Button(action: generateAllTones) {
                            HStack {
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Generate All DTMF Tones")
                                    .fontWeight(.medium)
                                Spacer()
                                if isGenerating {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isGenerating)
                        
                        Text("This will create dial tone audio files (WAV format) in your app's Documents directory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Generated Successfully!", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.headline)
                            
                            Text("Files are saved to:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(getDocumentsDirectory().path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.blue)
                                .textSelection(.enabled)
                            
                            Text("\nTo add them to your project:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("1. Go to Files app → On My iPhone/iPad → [Your App]\n2. Copy the dial_*.wav files\n3. Add them to your Xcode project\n4. Ensure they're added to your app target")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(generatedFiles, id: \.self) { file in
                            Label(file, systemImage: "music.note")
                                .font(.caption)
                        }
                    }
                }
                
                Section("Test Dial Tones") {
                    VStack(spacing: 16) {
                        Text("Test Keypad")
                            .font(.headline)
                        
                        // Dial pad grid
                        VStack(spacing: 12) {
                            ForEach(0..<4) { row in
                                HStack(spacing: 12) {
                                    ForEach(0..<3) { col in
                                        if let digit = getDigit(row: row, col: col) {
                                            Button(action: {
                                                playTestTone(digit)
                                            }) {
                                                Text(digit)
                                                    .font(.title2)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                                    .frame(width: 70, height: 70)
                                                    .background(
                                                        Circle()
                                                            .fill(Color.blue)
                                                    )
                                            }
                                        } else {
                                            Color.clear
                                                .frame(width: 70, height: 70)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        
                        Text("Tap any number to test the dial tone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Instructions") {
                    VStack(alignment: .leading, spacing: 12) {
                        InstructionRow(
                            number: "1",
                            title: "Generate Tones",
                            description: "Tap 'Generate All DTMF Tones' above"
                        )
                        
                        InstructionRow(
                            number: "2",
                            title: "Locate Files",
                            description: "Open Files app and navigate to your app's folder"
                        )
                        
                        InstructionRow(
                            number: "3",
                            title: "Add to Xcode",
                            description: "Drag the dial_*.wav files into your Xcode project"
                        )
                        
                        InstructionRow(
                            number: "4",
                            title: "Verify Target",
                            description: "Ensure files are included in your app target's Copy Bundle Resources"
                        )
                        
                        InstructionRow(
                            number: "5",
                            title: "Test",
                            description: "Use the test keypad above to verify sounds play correctly"
                        )
                    }
                }
            }
            .navigationTitle("Audio Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        clearGeneratedFiles()
                    }
                    .disabled(generatedFiles.isEmpty)
                }
            }
        }
    }
    
    private func getDigit(row: Int, col: Int) -> String? {
        let layout = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["*", "0", "#"]
        ]
        
        guard row < layout.count, col < layout[row].count else {
            return nil
        }
        
        return layout[row][col]
    }
    
    private func generateAllTones() {
        isGenerating = true
        generatedFiles.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "*", "#"]
            let documentsURL = getDocumentsDirectory()
            
            for digit in digits {
                // Generate the tone
                guard let toneData = DTMFToneGenerator.generateTone(for: digit, duration: 0.25) else {
                    continue
                }
                
                // Determine the filename
                let filename: String
                switch digit {
                case "*":
                    filename = "dial_star.wav"
                case "#":
                    filename = "dial_hash.wav"
                default:
                    filename = "dial_\(digit).wav"
                }
                
                // Save to documents directory
                let fileURL = documentsURL.appendingPathComponent(filename)
                do {
                    try toneData.write(to: fileURL)
                } catch {
                    print("Failed to write \(filename): \(error)")
                }
            }
            
            // Get list of generated files
            let fileManager = FileManager.default
            
            if let files = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
                let dialFiles = files
                    .filter { $0.lastPathComponent.hasPrefix("dial_") }
                    .map { $0.lastPathComponent }
                    .sorted()
                
                DispatchQueue.main.async {
                    generatedFiles = dialFiles
                    isGenerating = false
                }
            } else {
                DispatchQueue.main.async {
                    isGenerating = false
                }
            }
        }
    }
    
    private func playTestTone(_ digit: String) {
        testDigit = digit
        tonePlayer.playTone(for: digit)
        
        // Visual feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func clearGeneratedFiles() {
        let documentsURL = getDocumentsDirectory()
        let fileManager = FileManager.default
        
        if let files = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            let dialFiles = files.filter { $0.lastPathComponent.hasPrefix("dial_") }
            
            for file in dialFiles {
                try? fileManager.removeItem(at: file)
            }
        }
        
        generatedFiles.removeAll()
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct InstructionRow: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AudioSetupView()
}
