import Foundation
import Observation

@MainActor @Observable
final class SolarEnergyStore {
    private(set) var report: SolarEnergyReport?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var timeZoneID = SolarEnergyRange.defaultTimeZone
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var ticket = UUID()
    @ObservationIgnored private var requested: SolarEnergyRange?

    func load(_ range: SolarEnergyRange, force: Bool = false, now: Date = Date(),
              fetch: @escaping @MainActor (SolarEnergyRange) async throws -> SolarEnergyReport) async {
        if requested == range, let task { await task.value; return }
        if !force, requested == range, error == nil, let report,
           (0..<60).contains(now.timeIntervalSince(report.loadedAt)) { return }
        cancel()
        let id = ticket
        requested = range
        // A previous range must never be shown underneath newly selected dates.
        report = nil; loading = true; error = nil
        let work = Task {
            defer { if self.ticket == id { self.task = nil; self.loading = false } }
            do {
                let result = try await fetch(range)
                guard self.ticket == id, !Task.isCancelled else { return }
                self.report = result
                self.timeZoneID = result.range.timeZoneID
            } catch {
                guard self.ticket == id, !Task.isCancelled else { return }
                self.error = error is SolarEnergyError || error is SolarError
                    ? error.localizedDescription : SolarEnergyError.requestFailed.localizedDescription
            }
        }
        task = work
        await work.value
    }

    func cancel() {
        ticket = UUID()
        task?.cancel(); task = nil; loading = false
    }
    func reset() {
        cancel(); report = nil; requested = nil; error = nil
        timeZoneID = SolarEnergyRange.defaultTimeZone
    }
}
