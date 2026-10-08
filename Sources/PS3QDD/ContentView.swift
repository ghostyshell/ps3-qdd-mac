import PS3QDDCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: DecryptQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            inputs
            Divider()
            controls
            Divider()
            jobList
            Divider()
            footer
        }
        .frame(minWidth: 780, minHeight: 560)
        .fileImporter(isPresented: $model.showingISOPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setISOFolder(url) }
        }
        .fileImporter(isPresented: $model.showingKeyPicker, allowedContentTypes: [.folder, .plainText, .data]) { result in
            if case .success(let url) = result { model.setKeys(url) }
        }
        .fileImporter(isPresented: $model.showingOutputPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setOutputFolder(url) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PS3 Quick Disc Decryptor")
                .font(.title2)
                .bold()
            Text("Decrypts Redump PS3 disc images so RPCS3 can load them. Keys stay on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickerRow(
                title: "Encrypted ISOs",
                detail: model.isoFolder?.path,
                placeholder: "Choose a folder",
                action: { model.showingISOPicker = true }
            )
            pickerRow(
                title: "Key files",
                detail: model.keysURL?.path,
                placeholder: "Choose a .dkey folder or a keys file",
                action: { model.showingKeyPicker = true }
            )
            pickerRow(
                title: "Output folder",
                detail: model.outputFolder?.path,
                placeholder: "Same as the input folder",
                action: { model.showingOutputPicker = true }
            )
            Toggle("Delete the encrypted ISO after a successful decrypt", isOn: $model.deleteOriginal)
                .toggleStyle(.checkbox)
        }
        .padding(16)
    }

    private func pickerRow(
        title: String,
        detail: String?,
        placeholder: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .frame(width: 130, alignment: .leading)
            Text(detail ?? placeholder)
                .font(.callout)
                .foregroundStyle(detail == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(detail ?? placeholder)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose...", action: action)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Start Decryption") { model.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStart)
            Button("Stop All") { model.stopAll() }
                .disabled(!model.isRunning)
            Spacer()
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder private var jobList: some View {
        if model.jobs.isEmpty {
            VStack {
                Spacer()
                Text(model.emptyMessage)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.jobs) { job in
                JobRow(job: job)
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text(model.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
    }
}
