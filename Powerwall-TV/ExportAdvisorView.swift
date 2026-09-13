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
            error = "Add your xAI API key in Settings to enable the Home Energy Advisor."
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
                try await answer(HomeEnergyAdvisorPreferences.initialPrompt())
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
                let audio = try await client.speech(text: reply, voiceID: UserDefaults.standard.string(forKey: "homeEnergyAdvisor_voiceID") ?? "luna")
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

    private var skyColors: [Color] {
        switch advisor.context?.weatherMood ?? .clear {
        case .clear: return [.cyan, .blue, .orange]
        case .cloudy: return [.gray, .cyan, .blue]
        case .rain: return [.indigo, .blue, .teal]
        case .night: return [.indigo, .purple, .blue]
        }
    }

    private var weatherBackground: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle().fill(.background)
            LinearGradient(colors: skyColors.map { $0.opacity(colorScheme == .dark ? 0.28 : 0.14) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(skyColors[0].opacity(0.17))
                .frame(width: 380, height: 380)
                .blur(radius: 65)
                .offset(x: 130, y: -170)
            Image(systemName: advisor.context?.weatherSymbol ?? "cloud.sun.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 220, weight: .ultraLight))
                .foregroundStyle(skyColors[0].opacity(colorScheme == .dark ? 0.15 : 0.09))
                .rotationEffect(.degrees(-12))
                .offset(x: 45, y: 20)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            weatherBackground
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let context = advisor.context {
                        overview(context)
                        ForEach(Array(advisor.messages.enumerated()), id: \.offset) { index, message in
                            messageView(message, index: index)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
                            Text("Home energy insights")
                                .font(.title2.weight(.semibold))
                            Text("Considering your energy use and local weather forecast")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                    }
                    if advisor.busy {
                        ProgressView("Thinking…")
                            .font(.callout)
                            .accessibilityIdentifier("advisorBusy")
                    }
                    if let error = advisor.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("advisorError")
                    }
                    if advisor.context != nil { composer }
                    HStack {
                        Button { advisor.start(viewModel: viewModel, hour: peakEnd) } label: {
                            Label("Refresh advice", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(advisor.busy)
                        Spacer()
                    }
                    if let context = advisor.context {
                        VStack(spacing: 14) {
                            AsyncImage(url: colorScheme == .dark ? context.attribution.combinedMarkDarkURL : context.attribution.combinedMarkLightURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { Text("Apple Weather") }
                            .frame(width: 90, height: 24)
                            Link("Weather data sources", destination: context.attribution.legalPageURL)
                                .font(.caption)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 8)
                        Text("Percentages of total battery capacity, considering usage until \(context.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: context.timeZone))) tomorrow · Updated \(context.generatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .padding(.trailing, 24)
            .padding(.top, 20)
        }
#if os(macOS)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 760)
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

    private func overview(_ context: ExportAdvisorContext) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: context.weatherSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.weatherLocationName).font(.headline)
                    Text(context.weatherSummary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 12) {
                metric("Above reserve", kWh: context.budget.availableKWh, capacity: context.budget.capacityKWh, detail: "available", symbol: "battery.75percent")
                metric("Expected use", kWh: context.averageUsageKWh, capacity: context.budget.capacityKWh, detail: "\(context.sampleCount)-day average", symbol: "house")
                metric("Export potential", kWh: context.budget.exportKWh, capacity: context.budget.capacityKWh, detail: "potential export", symbol: "arrow.up.right")
            }
        }
    }

    private func metric(_ title: String, kWh: Double, capacity: Double, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(kWh / capacity, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("\(kWh, specifier: "%.1f") kWh · \(detail)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(AdvisorGlassCard(cornerRadius: 20))
    }

    private func messageView(_ message: String, index: Int) -> some View {
        let isQuestion = index.isMultiple(of: 2)
        return Text((try? AttributedString(markdown: message, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message))
            .font(isQuestion ? .callout.weight(.medium) : .body)
            .lineSpacing(isQuestion ? 4 : 7)
            .foregroundStyle(isQuestion ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isQuestion ? 4 : 22)
            .modifier(AdvisorGlassCard(cornerRadius: 24, enabled: !isQuestion))
            .accessibilityIdentifier("advisorMessage\(index)")
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Ask about your home energy…", text: $question)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityIdentifier("advisorFollowUp")
                .focused($asking)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask follow-up")
            .disabled(advisor.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .modifier(AdvisorGlassCard(cornerRadius: 20))
    }

    private func send() {
        guard !advisor.busy else { return }
        advisor.followUp(question)
        question = ""
    }
}

struct AdvisorGlassCard: ViewModifier {
    var cornerRadius: CGFloat
    var enabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
