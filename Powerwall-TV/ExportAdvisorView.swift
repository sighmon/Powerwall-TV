import SwiftUI
import AVFoundation
import WeatherKit

@MainActor
final class ExportAdvisor: ObservableObject {
    @Published var context: ExportAdvisorContext?
    @Published var messages: [String] = []
    @Published var busy = false
    @Published var error: String?
    private var conversation: [[String: String]] = []
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func cancel() {
        generation = UUID()
        task?.cancel()
        player?.stop()
        busy = false
    }

    func start(viewModel: PowerwallViewModel, hour: Int) {
        cancel()
        context = nil
        messages = []
        conversation = []
        error = nil
        guard viewModel.loginMode == .fleetAPI, let siteID = viewModel.energySiteId else {
            error = "Sign in with Fleet API and select a Powerwall site first."
            return
        }
        guard !(KeychainWrapper.standard.string(forKey: "xai_apiKey") ?? "").isEmpty else {
            error = "Add your xAI API key in Settings to enable the export advisor."
            return
        }
        let service = ExportAdvisorService(baseURL: viewModel.fleetBaseURL, token: viewModel.accessToken, siteID: siteID)
        busy = true
        let requestGeneration = generation
        task = Task {
            defer { if generation == requestGeneration { busy = false } }
            do {
                let result = try await service.context(morningEndHour: hour)
                try Task.checkCancellation()
                context = result
                conversation = [["role": "system", "content": result.prompt]]
                try await answer("How much battery should we export to the grid tonight?")
            } catch is CancellationError {} catch {
                if generation == requestGeneration { self.error = error.localizedDescription }
            }
        }
    }

    func followUp(_ question: String) {
        guard !busy, let context else { return }
        guard Date().timeIntervalSince(context.generatedAt) < 900 else {
            error = "This estimate is over 15 minutes old. Refresh before asking another question."
            return
        }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        error = nil
        busy = true
        let requestGeneration = generation
        task = Task {
            defer { if generation == requestGeneration { busy = false } }
            do { try await answer(question) }
            catch is CancellationError {} catch {
                if generation == requestGeneration { self.error = error.localizedDescription }
            }
        }
    }

    private func answer(_ question: String) async throws {
        let pending = conversation + [["role": "user", "content": question]]
        let client = GrokAdvisorClient(apiKey: KeychainWrapper.standard.string(forKey: "xai_apiKey") ?? "")
        let reply = try await client.answer(messages: pending)
        conversation = pending + [["role": "assistant", "content": reply]]
        messages.append(question)
        messages.append(reply)
        if UserDefaults.standard.object(forKey: "exportAdvisor_voice") as? Bool ?? true {
            do {
                let audio = try await client.speech(text: reply)
#if !os(macOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
#endif
                player = try AVAudioPlayer(data: audio)
                player?.play()
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                self.error = "The written answer is ready, but Grok Voice failed: \(error.localizedDescription)"
            }
        }
    }
}

struct ExportAdvisorView: View {
    @ObservedObject var advisor: ExportAdvisor
    @ObservedObject var viewModel: PowerwallViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("exportAdvisor_peakEnd") private var peakEnd = 10
    @State private var question = ""
    @FocusState private var asking: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let context = advisor.context {
                        Text("Export up to: \(context.budget.exportKWh, specifier: "%.1f") kWh (\(context.budget.exportPercent, specifier: "%.1f")% of battery)")
                            .font(.headline)
                        Text("Average: \(context.averageUsageKWh, specifier: "%.1f") kWh across \(context.sampleCount) days. \(context.generatedAt.formatted()).")
                        ForEach(Array(advisor.messages.enumerated()), id: \.offset) { index, message in
                            Text((try? AttributedString(markdown: message, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("advisorMessage\(index)")
                        }
                        TextField("Ask a follow-up question", text: $question)
                            .accessibilityIdentifier("advisorFollowUp")
                            .focused($asking)
                            .onSubmit(send)
                        Button("Ask follow-up", action: send).disabled(advisor.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        VStack {
                            AsyncImage(url: colorScheme == .dark ? context.attribution.combinedMarkDarkURL : context.attribution.combinedMarkLightURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { Text("Apple Weather") }
                            .frame(width: 120, height: 28)
                            Link("Weather data sources", destination: context.attribution.legalPageURL)
                        }
                    }
                    if advisor.busy { ProgressView("Thinking...").accessibilityIdentifier("advisorBusy") }
                    if let error = advisor.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("advisorError") }
                    Button("Refresh estimate") { advisor.start(viewModel: viewModel, hour: peakEnd) }
                        .disabled(advisor.busy)
                }.padding()
            }
            .navigationTitle("Export advisor")
            .toolbar { ToolbarItem { Button("Done") { dismiss() } } }
#if os(macOS)
            .frame(minWidth: 600, minHeight: 550)
#endif
            .onAppear {
                if advisor.context == nil && !advisor.busy { advisor.start(viewModel: viewModel, hour: peakEnd) }
                else { asking = true }
            }
            .onDisappear { advisor.cancel() }
            .onChange(of: viewModel.energySiteId) { _ in
                advisor.cancel()
                advisor.context = nil
                dismiss()
            }
        }
    }

    private func send() {
        guard !advisor.busy else { return }
        advisor.followUp(question)
        question = ""
    }
}
