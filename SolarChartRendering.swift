import Foundation

enum SolarChartRendering {
    // Reduce only the drawn line; the inspector still searches every original sample.
    // Preserve extrema, endpoints and separate unavailable-data segments.
    static func reduced(_ points: [HistoryPoint], buckets: Int = 512) -> [HistoryPoint] {
        let groups = Dictionary(grouping: points) { $0.entity + "|" + String($0.segment) }
        let result = groups.values.flatMap { group -> [HistoryPoint] in
            let sorted = group.sorted { $0.date < $1.date }
            guard sorted.count > max(1, buckets) * 4 else { return sorted }
            let size = Int(ceil(Double(sorted.count) / Double(max(1, buckets))))
            var selected: [HistoryPoint] = []
            for start in stride(from: 0, to: sorted.count, by: size) {
                let chunk = sorted[start..<min(start + size, sorted.count)]
                let candidates = [chunk.first!, chunk.min(by: { $0.value < $1.value })!,
                                  chunk.max(by: { $0.value < $1.value })!, chunk.last!]
                var seen = Set<String>()
                selected += candidates.sorted { $0.date < $1.date }.filter { seen.insert($0.id).inserted }
            }
            return selected
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.entity != $1.entity { return $0.entity < $1.entity }
            return $0.segment < $1.segment
        }
    }
}
