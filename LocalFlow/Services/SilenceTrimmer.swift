import Foundation

/// Cuts leading/trailing silence and collapses long internal pauses so
/// Whisper spends no decode time on dead air. Timestamps are not preserved,
/// which is fine because LocalFlow only uses the text.
enum SilenceTrimmer {
    private static let frameSize = 480          // 30ms at 16kHz
    private static let rmsThreshold: Float = 0.008
    private static let padFrames = 10           // 300ms of context kept around speech
    private static let maxGapFrames = 50        // pauses longer than 1.5s get collapsed...
    private static let keepGapFrames = 16       // ...down to roughly 0.5s

    static func trim(_ samples: [Float]) -> [Float] {
        guard samples.count > frameSize * 20 else { return samples }

        var voiced = [Bool]()
        voiced.reserveCapacity(samples.count / frameSize + 1)
        var i = 0
        while i < samples.count {
            let end = min(i + frameSize, samples.count)
            var sum: Float = 0
            for j in i..<end { sum += samples[j] * samples[j] }
            voiced.append((sum / Float(end - i)).squareRoot() > rmsThreshold)
            i = end
        }

        guard let first = voiced.firstIndex(of: true), let last = voiced.lastIndex(of: true) else {
            // No speech at all; hand the original to the hallucination filter.
            return samples
        }

        var keepFrame = [Bool](repeating: false, count: voiced.count)
        let lo = max(0, first - padFrames)
        let hi = min(voiced.count - 1, last + padFrames)
        var idx = lo
        while idx <= hi {
            if voiced[idx] {
                keepFrame[idx] = true
                idx += 1
                continue
            }
            var runEnd = idx
            while runEnd <= hi && !voiced[runEnd] { runEnd += 1 }
            if runEnd - idx > maxGapFrames {
                for k in idx..<(idx + keepGapFrames / 2) { keepFrame[k] = true }
                for k in (runEnd - keepGapFrames / 2)..<runEnd { keepFrame[k] = true }
            } else {
                for k in idx..<runEnd { keepFrame[k] = true }
            }
            idx = runEnd
        }

        var out = [Float]()
        out.reserveCapacity(samples.count)
        for (frame, kept) in keepFrame.enumerated() where kept {
            let start = frame * frameSize
            guard start < samples.count else { break }
            out.append(contentsOf: samples[start..<min(start + frameSize, samples.count)])
        }
        return out
    }
}
