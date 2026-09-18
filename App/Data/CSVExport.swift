import Foundation
import SwiftData

/// Spec AC6, non-negotiable: prediction error has to leave the app for offline analysis,
/// because that number is what decides whether any of this is worth building further.
enum CSVExport {

    static let header = [
        "date", "readiness_state", "composite_z", "model_version", "confidence", "gate",
        "lift", "predicted_load", "predicted_reps", "target_rir",
        "achieved_load", "achieved_reps", "achieved_rir", "completed_as_prescribed",
        "load_error", "load_error_pct", "rep_error",
    ].joined(separator: ",")

    static func build(context: ModelContext) -> String {
        let prescriptions = (try? context.fetch(
            FetchDescriptor<PrescriptionRow>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let outcomes = (try? context.fetch(FetchDescriptor<OutcomeRow>())) ?? []
        let readiness = (try? context.fetch(FetchDescriptor<ReadinessRow>())) ?? []

        let outcomeByPrescription = Dictionary(
            outcomes.map { ($0.prescriptionID, $0) }, uniquingKeysWith: { a, _ in a })

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var lines = [header]
        for p in prescriptions {
            let day = readiness.first { Calendar.current.isDate($0.date, inSameDayAs: p.date) }
            let outcome = outcomeByPrescription[p.id]

            let error = outcome.map { $0.achievedLoad - p.predictedLoad }
            let errorPct = (error != nil && p.predictedLoad > 0)
                ? error! / p.predictedLoad : nil

            let fields: [String] = [
                formatter.string(from: p.date),
                p.state.rawValue,
                day.map { String(format: "%.4f", $0.composite) } ?? "",
                day?.modelVersion ?? "",
                day?.confidenceRaw ?? "",
                day?.gateRaw ?? "",
                escape(p.liftName),
                String(format: "%.2f", p.predictedLoad),
                String(p.predictedReps),
                String(p.targetRIR),
                outcome.map { String(format: "%.2f", $0.achievedLoad) } ?? "",
                outcome.map { String($0.achievedReps) } ?? "",
                outcome.map { String($0.achievedRIR) } ?? "",
                outcome.map { $0.completedAsPrescribed ? "true" : "false" } ?? "",
                error.map { String(format: "%.2f", $0) } ?? "",
                errorPct.map { String(format: "%.4f", $0) } ?? "",
                // A rep shortfall at the prescribed load is prediction error too, and
                // on a hard day it is the signal that shows up first.
                outcome.map { String($0.achievedReps - p.predictedReps) } ?? "",
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func writeToTemporaryFile(context: ModelContext) -> URL? {
        let csv = build(context: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readiness-export.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }
}
