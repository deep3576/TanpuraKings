//import AVFoundation
//import Accelerate  // for DSP (vDSP)
//
//class PitchDetector: ObservableObject {
//
//    private let audioEngine = AVAudioEngine()
//    private var inputFormat: AVAudioFormat!
//
//    // Publishes the latest detected pitch (Hz)
//    @Published var currentPitch: Double = 0.0
//
//    // Whether the engine is running
//    @Published var isRunning: Bool = false
//
//
//    init() {
//        // Prepare the audio session / engine
//        let session = AVAudioSession.sharedInstance()
//        do {
//            // e.g., .playAndRecord or .measurement with echo cancellation
//            try session.setCategory(.playAndRecord,
//                                    mode: .measurement,
//                                    options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers])
//            try session.setActive(true)
//        } catch {
//            print("Audio session setup error: \(error)")
//        }
//
//        let inputNode = audioEngine.inputNode
//        inputFormat = inputNode.outputFormat(forBus: 0)
//    }
//
//    /// Start capturing microphone audio and detecting pitch
//    func startDetection() {
//        guard !isRunning else { return }
//
//        let inputNode = audioEngine.inputNode
//
//        // Install a tap on inputNode
//        inputNode.installTap(onBus: 0,
//                             bufferSize: 1024,
//                             format: inputFormat) { buffer, when in
//            // 1) Convert PCM buffer to float array
//            guard let channelData = buffer.floatChannelData?[0] else { return }
//            let frameCount = Int(buffer.frameLength)
//
//            // 2) Perform a naive pitch detection
//            let pitchHz = self.performAutocorrelationPitchDetection(samples: channelData,
//                                                                    sampleCount: frameCount,
//                                                                    sampleRate: Double(self.inputFormat.sampleRate))
//
//            // 3) Publish the pitch to the main thread
//            DispatchQueue.main.async {
//                self.currentPitch = pitchHz
//            }
//        }
//
//        do {
//            try audioEngine.start()
//            isRunning = true
//        } catch {
//            print("AudioEngine start error: \(error)")
//        }
//    }
//
//    /// Stop capturing audio
//    func stopDetection() {
//        guard isRunning else { return }
//
//        audioEngine.inputNode.removeTap(onBus: 0)
//        audioEngine.stop()
//        isRunning = false
//    }
//
//    // ---------------------------------------------------------
//    // A VERY basic autocorrelation-based pitch detection
//    // This is just to illustrate the concept. Real-world
//    // detection might use more advanced methods (YIN, etc).
//    // ---------------------------------------------------------
//    func performAutocorrelationPitchDetection(
//        samples: UnsafePointer<Float>,
//        sampleCount: Int,
//        sampleRate: Double
//    ) -> Double {
//        // 1) Convert incoming pointer to a Swift Array of Float
//        let n = sampleCount
//        let buffer = Array(UnsafeBufferPointer(start: samples, count: n))
//
//        // 2) We'll store the autocorrelation result in `correlation`, which needs length = 2*n - 1
//        var correlation = [Float](repeating: 0, count: 2 * n - 1)
//
//        // 3) Use the older-style C function vDSP_conv(...) to convolve `buffer` with itself
//        buffer.withUnsafeBufferPointer { bufPtr in
//            correlation.withUnsafeMutableBufferPointer { corrPtr in
//                vDSP_conv(
//                    bufPtr.baseAddress!,  1,  // signal A
//                    bufPtr.baseAddress!,  1,  // signal B
//                    corrPtr.baseAddress!, 1,  // destination
//                    vDSP_Length(n),          // Number of output points to produce
//                    vDSP_Length(n)           // Length of each input
//                )
//            }
//        }
//
//        // 4) The result array is size 2*n - 1. Typically, index 0 is the "zero-lag" + negative shifts,
//        //    but for pitch detection we look for the first major peak after index=0.
//        //    This is extremely naive. We'll just search up to half the buffer.
//
//        let halfCount = n / 2
//        var bestIndex = -1
//        var maxCorr: Float = 0
//
//        for i in 1..<halfCount {
//            let val = correlation[i]
//            if val > maxCorr {
//                maxCorr = val
//                bestIndex = i
//            }
//        }
//
//        // 5) Convert the best lag index -> frequency
//        if bestIndex > 0 {
//            let fundamentalPeriod = Double(bestIndex) / sampleRate
//            return 1.0 / fundamentalPeriod
//        } else {
//            return 0.0
//        }
//    }
//}
