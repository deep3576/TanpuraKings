import SwiftUI
import AVFoundation

// MARK: - AudioManager with Global Effects (EQ, Echo, Reverb)

class AudioManager: ObservableObject {
    static let shared = AudioManager()
    @Published var isEngineRunning = false
    
    private let engine = AVAudioEngine()
    private let globalMixer = AVAudioMixerNode() // Sums all note signals.
    private let eqNode: AVAudioUnitEQ
    private let delayNode: AVAudioUnitDelay
    private let reverbNode = AVAudioUnitReverb()
    
    // Active players: stores a player and its dedicated mixer for each note.
    private var activePlayers: [String: (player: AVAudioPlayerNode, mixer: AVAudioMixerNode)] = [:]
    
    private init() {
        // Configure the audio session.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("Audio session successfully configured")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        // Set up EQ with two bands for Bass (low-shelf) and Treble (high-shelf).
        self.eqNode = AVAudioUnitEQ(numberOfBands: 2)
        let bassBand = eqNode.bands[0]
        bassBand.filterType = .lowShelf
        bassBand.frequency = 100    // Hz
        bassBand.bandwidth = 1.0
        bassBand.gain = 0.0
        bassBand.bypass = false
        
        let trebleBand = eqNode.bands[1]
        trebleBand.filterType = .highShelf
        trebleBand.frequency = 5000  // Hz
        trebleBand.bandwidth = 1.0
        trebleBand.gain = 0.0
        trebleBand.bypass = false
        
        // Set up Echo (Delay)
        self.delayNode = AVAudioUnitDelay()
        delayNode.delayTime = 0.3          // seconds
        delayNode.feedback = 50            // percentage
        delayNode.lowPassCutoff = 15000    // Hz
        delayNode.wetDryMix = 0.0          // controlled via slider
        
        // Set up Reverb.
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 0.0         // controlled via slider
        
        // Attach nodes.
        engine.attach(globalMixer)
        engine.attach(eqNode)
        engine.attach(delayNode)
        engine.attach(reverbNode)
        
        // Connect the chain:
        // globalMixer → EQ → Delay (Echo) → Reverb → engine.mainMixerNode
        engine.connect(globalMixer, to: eqNode, format: nil)
        engine.connect(eqNode, to: delayNode, format: nil)
        engine.connect(delayNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
        
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            print("Error starting engine: \(error)")
        }
    }
    
    /// Converts a note’s name into the proper file name.
    /// For example, "C" becomes "c", and "C#" becomes "csharp".
    private func fileNameForNote(_ key: PianoKey) -> String {
        let note = key.name.lowercased()
        if note.contains("#") {
            return note.replacingOccurrences(of: "#", with: "sharp")
        }
        return note
    }
    
    /// Plays a note by creating a player and a dedicated mixer, then scheduling the audio file.
    /// The passed `volume` is the initial volume for that note.
    func playNote(_ key: PianoKey, volume: Float) {
        let fileName = fileNameForNote(key)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3", subdirectory: "Audio") else {
            print("Sound file for note \(key.name) not found")
            return
        }
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let player = AVAudioPlayerNode()
            let noteMixer = AVAudioMixerNode()
            noteMixer.volume = volume
            
            engine.attach(player)
            engine.attach(noteMixer)
            
            engine.connect(player, to: noteMixer, format: audioFile.processingFormat)
            engine.connect(noteMixer, to: globalMixer, format: audioFile.processingFormat)
            
            player.scheduleFile(audioFile, at: nil) {
                // When playback finishes, remove the active note.
                DispatchQueue.main.async {
                    self.activePlayers.removeValue(forKey: key.name)
                }
            }
            
            player.play()
            activePlayers[key.name] = (player: player, mixer: noteMixer)
            print("Playing note \(key.name) with volume \(volume)")
        } catch {
            print("Error playing note \(key.name): \(error)")
        }
    }
    
    /// Stops a note.
    func stopNote(_ key: PianoKey) {
        if let tuple = activePlayers[key.name] {
            tuple.player.stop()
            activePlayers.removeValue(forKey: key.name)
            print("Stopped note \(key.name)")
        }
    }
    
    /// Stops all playing notes.
    func stopAllNotes() {
        for (_, tuple) in activePlayers {
            tuple.player.stop()
        }
        activePlayers.removeAll()
        print("Stopped all notes")
    }
    
    /// Updates the volume for a specific active note.
    func updateVolume(for note: String, volume: Float) {
        if let tuple = activePlayers[note] {
            tuple.mixer.volume = volume
            print("Updated volume for note \(note) to \(volume)")
        }
    }
    
    /// Updates the global effects.
    /// - Parameters:
    ///   - bass: Low-shelf gain.
    ///   - treble: High-shelf gain.
    ///   - reverbMix: Wet/dry mix for reverb.
    ///   - echoMix: Wet/dry mix for echo (delay).
    func updateEffects(bass: Float, treble: Float, reverbMix: Float, echoMix: Float) {
        eqNode.bands[0].gain = bass
        eqNode.bands[1].gain = treble
        reverbNode.wetDryMix = reverbMix
        delayNode.wetDryMix = echoMix
        print("Effects updated: Bass=\(bass), Treble=\(treble), Reverb=\(reverbMix), Echo=\(echoMix)")
    }
}

// MARK: - PianoKey Model

struct PianoKey: Identifiable {
    let id = UUID()
    let name: String
    let isSharp: Bool
}

struct PianoKeys {
    static let octave0: [PianoKey] = [
        PianoKey(name: "C",  isSharp: false),
        PianoKey(name: "C#", isSharp: true),
        PianoKey(name: "D",  isSharp: false),
        PianoKey(name: "D#", isSharp: true),
        PianoKey(name: "E",  isSharp: false),
        PianoKey(name: "F",  isSharp: false),
        PianoKey(name: "F#", isSharp: true),
        PianoKey(name: "G",  isSharp: false),
        PianoKey(name: "G#", isSharp: true),
        PianoKey(name: "A",  isSharp: false),
        PianoKey(name: "A#", isSharp: true),
        PianoKey(name: "B",  isSharp: false)
    ]
}

// MARK: - PianoKeyView

struct PianoKeyView: View {
    let key: PianoKey
    let isActive: Bool
    
    var body: some View {
        ZStack {
            if key.isSharp {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.yellow : Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.yellow : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1))
            }
            Text(key.name)
                .foregroundColor(key.isSharp ? .white : .black)
                .font(.caption)
        }
    }
}

// MARK: - PianoView

struct PianoView: View {
    @Binding var activeNotes: Set<String>
    /// Binding to the dictionary of active note volumes.
    @Binding var activeNoteVolumes: [String: Float]
    let masterVolume: Float
    let keys = PianoKeys.octave0
    
    var body: some View {
        GeometryReader { geo in
            let whiteKeys = keys.filter { !$0.isSharp }
            let blackKeys = keys.filter { $0.isSharp }
            let whiteKeyWidth = geo.size.width / CGFloat(whiteKeys.count)
            let whiteKeyHeight = geo.size.height
            
            ZStack(alignment: .topLeading) {
                // Draw white keys.
                HStack(spacing: 0) {
                    ForEach(whiteKeys) { key in
                        PianoKeyView(key: key, isActive: activeNotes.contains(key.name))
                            .frame(width: whiteKeyWidth, height: whiteKeyHeight)
                            .onTapGesture {
                                handleKeyPress(key)
                            }
                    }
                }
                // Overlay black keys.
                ForEach(blackKeys) { key in
                    let blackKeyWidth = whiteKeyWidth * 0.6
                    let blackKeyHeight = whiteKeyHeight * 0.6
                    let xPos = blackKeyXPosition(note: key.name, whiteKeyWidth: whiteKeyWidth)
                    PianoKeyView(key: key, isActive: activeNotes.contains(key.name))
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .position(x: xPos, y: blackKeyHeight / 2)
                        .onTapGesture {
                            handleKeyPress(key)
                        }
                }
            }
        }
    }
    
    private func blackKeyXPosition(note: String, whiteKeyWidth: CGFloat) -> CGFloat {
        let mapping: [String: CGFloat] = [
            "C#": whiteKeyWidth * 0.75,
            "D#": whiteKeyWidth * 1.75,
            "F#": whiteKeyWidth * 3.75,
            "G#": whiteKeyWidth * 4.75,
            "A#": whiteKeyWidth * 5.75
        ]
        return mapping[note] ?? 0
    }
    
    /// Handles key tap:
    /// - If the note is active, stops it and removes its volume slider.
    /// - Otherwise, if fewer than 3 notes are active, plays the note (with default volume 1.0) and adds its volume control.
    private func handleKeyPress(_ key: PianoKey) {
        if activeNotes.contains(key.name) {
            AudioManager.shared.stopNote(key)
            activeNotes.remove(key.name)
            activeNoteVolumes.removeValue(forKey: key.name)
        } else {
            if activeNotes.count >= 3 { return }
            activeNotes.insert(key.name)
            activeNoteVolumes[key.name] = 1.0  // Default per‑note volume.
            AudioManager.shared.playNote(key, volume: 1.0)
        }
    }
}

// MARK: - ActiveNotesVolumeView

/// Displays a horizontal list of sliders—one for each active note—to control its volume.
struct ActiveNotesVolumeView: View {
    @Binding var activeNoteVolumes: [String: Float]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Active Notes Volume")
                .font(.headline)
                .foregroundColor(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(activeNoteVolumes.keys), id: \.self) { note in
                        VStack {
                            Text(note)
                                .foregroundColor(.white)
                            Slider(value: Binding(
                                get: { activeNoteVolumes[note] ?? 1.0 },
                                set: { newValue in
                                    activeNoteVolumes[note] = newValue
                                    AudioManager.shared.updateVolume(for: note, volume: newValue)
                                }
                            ), in: 0...1)
                            .accentColor(.orange)
                        }
                        .frame(width: 120)
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - EffectsPanel

struct EffectsPanel: View {
    @Binding var bass: Float
    @Binding var treble: Float
    @Binding var reverb: Float
    @Binding var echo: Float
    
    var body: some View {
        VStack(spacing: 20) {
            LabeledSlider(value: $bass, range: -20...20, label: "Bass", color: .blue)
            LabeledSlider(value: $treble, range: -20...20, label: "Treble", color: .green)
            LabeledSlider(value: $reverb, range: 0...100, label: "Reverb", color: .purple)
            LabeledSlider(value: $echo, range: 0...100, label: "Echo", color: .pink)
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}

// MARK: - LabeledSlider

struct LabeledSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float>
    var label: String
    var color: Color
    
    var body: some View {
        VStack {
            HStack {
                Text(label)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", value))
                    .foregroundColor(.white)
            }
            Slider(value: $value, in: range)
                .accentColor(color)
        }
        .padding(.horizontal)
    }
}

// MARK: - MasterControlView

struct MasterControlView: View {
    @Binding var masterVolume: Float
    
    var body: some View {
        VStack {
            Text("Master Volume")
                .font(.headline)
                .foregroundColor(.white)
            Slider(value: $masterVolume, in: 0...1)
                .accentColor(.blue)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
        .padding()
    }
}

// MARK: - GradientBackground

struct GradientBackground: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - ContentView

struct ContentView: View {
    // The app is called "Tanpura Kings".
    @StateObject private var audioManager = AudioManager.shared
    @State private var activeNotes = Set<String>()
    
    // Global control values.
    @State private var masterVolume: Float = 1.0
    @State private var bass: Float = 0.0
    @State private var treble: Float = 0.0
    @State private var reverb: Float = 0.0
    @State private var echo: Float = 0.0
    
    // Dictionary to hold per-note volumes for active notes.
    @State private var activeNoteVolumes: [String: Float] = [:]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Tanpura Kings")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding(.top)
                
                PianoView(activeNotes: $activeNotes, activeNoteVolumes: $activeNoteVolumes, masterVolume: masterVolume)
                    .frame(height: 200)
                    .padding(.horizontal)
                
                if !activeNoteVolumes.isEmpty {
                    ActiveNotesVolumeView(activeNoteVolumes: $activeNoteVolumes)
                }
                
                EffectsPanel(bass: $bass, treble: $treble, reverb: $reverb, echo: $echo)
                
                MasterControlView(masterVolume: $masterVolume)
                
                // Footer
                Text("© kingsman software solutions")
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
            }
            .padding(.bottom)
        }
        .background(GradientBackground())
        // Update global effects when sliders change.
        .onChange(of: bass) { newValue in
            audioManager.updateEffects(bass: newValue, treble: treble, reverbMix: reverb, echoMix: echo)
        }
        .onChange(of: treble) { newValue in
            audioManager.updateEffects(bass: bass, treble: newValue, reverbMix: reverb, echoMix: echo)
        }
        .onChange(of: reverb) { newValue in
            audioManager.updateEffects(bass: bass, treble: treble, reverbMix: newValue, echoMix: echo)
        }
        .onChange(of: echo) { newValue in
            audioManager.updateEffects(bass: bass, treble: treble, reverbMix: reverb, echoMix: newValue)
        }
        // When master volume changes, update all active notes.
        .onChange(of: masterVolume) { newValue in
            for note in activeNotes {
                AudioManager.shared.updateVolume(for: note, volume: newValue)
                activeNoteVolumes[note] = newValue
            }
        }
        .onDisappear {
            audioManager.stopAllNotes()
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
