import CoreNFC
import SwiftUI

struct CommissioningView: View {
    @StateObject private var controller = FullCommissioningController()
    @ObservedObject private var nfc = NFCSessionMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var payload = ""
    @State private var dataset = ""
    @State private var acceptsTestRoot = false
    @State private var confirmReset = false
    @State private var confirmReplace = false
    @State private var nextAction: Action = .commission
    private enum Action { case commission, verify, retry }

    var body: some View {
        NavigationStack {
            Form {
                Section("Experimental NFC commissioning") {
                    Text("Commission one Thread test device into this tool's Fabric, then read ProductID over IP.")
                    Text("Requires a Nordic NFC commissioning firmware, its NFC antenna, and a reachable Thread network with IPv6 connectivity. Only the public FFF1 test attestation root is trusted.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("This port has not yet completed hardware or external-user acceptance. It does not add devices to another controller.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !NFCTagReaderSession.readingAvailable {
                        Label("NFC is unavailable on this device or configuration.", systemImage: "exclamationmark.triangle")
                    }
                }
                if !controller.hasCurrentDevice {
                    Section("Prepare") {
                        TextField("Complete MT: setup payload", text: $payload, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Thread Active Dataset (hex TLV)", text: $dataset)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Setup information must currently be entered manually. Dataset validation checks structure, not network reachability. The expected ProductID comes from the setup payload.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Toggle("I am using a dedicated board with FFF1 test credentials", isOn: $acceptsTestRoot)
                    }.disabled(controller.busy)
                }
                Section(controller.busy ? "Running" : "Status") {
                    Text(controller.message).accessibilityAddTraits(.updatesFrequently)
                    Text(sessionStatus).font(.caption).foregroundStyle(.secondary)
                    if controller.busy {
                        ProgressView("Operation in progress")
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("Elapsed: \(Int(max(0, ProcessInfo.processInfo.systemUptime - controller.startedUptime))) s")
                                .monospacedDigit()
                        }
                    }
                    if let report = controller.report, !controller.busy {
                        DisclosureGroup("Diagnostic report") {
                            Text(report).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        ShareLink("Share report", item: report)
                        Text("Save this report before leaving the app. Reports are not yet restored after relaunch.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Actions") {
                    if controller.busy {
                        Button("Cancel operation", role: .cancel) { controller.cancel() }
                    } else if controller.hasCurrentDevice {
                        Button("Re-verify current device over IP") { request(.verify) }
                            .disabled(!nfc.canStart)
                        if controller.canRetryBeforeCommissioning {
                            Button("Prepare retry before commissioning") { request(.retry) }
                                .disabled(!nfc.canStart)
                        }
                        Button("Clear reference after board factory reset", role: .destructive) { confirmReset = true }
                            .disabled(!nfc.canStart)
                    } else {
                        Button("Start NFC commissioning") { request(.commission) }
                            .disabled(!nfc.canStart || !NFCTagReaderSession.readingAvailable || !acceptsTestRoot || payload.isEmpty || dataset.isEmpty)
                    }
                }
                Section("Recovery") {
                    Text("Cancellation stops local work; it does not undo device changes. After an interruption, re-verify over IP before deciding to reset the board.")
                    Text("Use only a dedicated test board. Follow its firmware-specific factory-reset procedure before clearing the local reference. Clearing a reference does not reset the board or remove its Fabric. The tool retains its own Fabric credentials.")
                    Text("A normal board restart is not a factory reset. If app credentials are lost, reset the dedicated board before commissioning with a new app identity.")
                }.font(.footnote)
            }
            .navigationTitle("Matter NFC Test")
            .confirmationDialog("Replace the current report?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Continue") { execute(nextAction) }
                Button("Keep report", role: .cancel) {}
            } message: { Text("Share the current report first if you need it. The next operation replaces it.") }
            .confirmationDialog("Has the dedicated board been factory reset?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Clear local reference", role: .destructive) { controller.confirmBoardFactoryReset() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This clears the local device reference and report only. It does not reset the board. Share the report first if needed.") }
            .onAppear { controller.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    payload = ""; dataset = ""
                    if controller.busy { controller.cancel() }
                }
            }
        }
    }

    private func request(_ action: Action) {
        nextAction = action
        if controller.report != nil { confirmReplace = true } else { execute(action) }
    }
    private func execute(_ action: Action) {
        switch action {
        case .commission:
            controller.start(payloadText: payload, datasetText: dataset)
            payload = ""; dataset = ""; acceptsTestRoot = false
        case .verify: controller.verifyCurrent()
        case .retry: controller.prepareRetryBeforeCommissioning()
        }
    }
    private var sessionStatus: String {
        switch nfc.lifecycle.phase {
        case .idle: return "NFC reader idle."
        case .opening: return "Opening the system NFC reader."
        case .active: return "NFC session active. Follow the current operation prompt."
        case .closing: return "Waiting for the system to finish closing NFC."
        case .ended: return "NFC session ended."
        }
    }
}
