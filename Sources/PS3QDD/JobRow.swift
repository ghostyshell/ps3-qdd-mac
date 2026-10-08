import PS3QDDCore
import SwiftUI

struct JobRow: View {
    @ObservedObject var job: DecryptQueue.Job

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(job.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(job.name)
                Spacer(minLength: 8)
                badge
            }

            if showsProgress {
                ProgressView(value: job.fraction)
                    .progressViewStyle(.linear)
                HStack(spacing: 14) {
                    Text(percentText)
                    Text(rateText)
                    Text(etaText)
                    Spacer()
                    if job.state == .running {
                        Button("Stop") { job.cancelFlag.cancel() }
                            .controlSize(.small)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            } else if case .failed(let message) = job.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var showsProgress: Bool {
        switch job.state {
        case .running, .done, .alreadyDone, .stopped: return true
        case .queued, .skipped, .failed: return false
        }
    }

    private var percentText: String {
        String(format: "%.0f%%", job.fraction * 100)
    }

    private var rateText: String {
        guard job.bytesPerSecond > 0 else { return " " }
        return ByteCountFormatter.string(fromByteCount: Int64(job.bytesPerSecond), countStyle: .file) + "/s"
    }

    private var etaText: String {
        guard let eta = job.etaSeconds, eta.isFinite else { return " " }
        return "ETA " + Self.duration(eta)
    }

    @ViewBuilder private var badge: some View {
        switch job.state {
        case .queued: Text("Queued").badge(.gray)
        case .running: Text("Decrypting").badge(.blue)
        case .done: Text("Done").badge(.green)
        case .alreadyDone: Text("Already done").badge(.green)
        case .stopped: Text("Stopped").badge(.orange)
        case .skipped(let reason): Text(reason).badge(.gray)
        case .failed: Text("Failed").badge(.red)
        }
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
}

private extension View {
    func badge(_ color: Color) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
