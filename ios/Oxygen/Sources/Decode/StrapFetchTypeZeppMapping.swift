import ZeppKit

extension StrapFetchType {
    var zeppFetchType: ZeppFetchType {
        switch self {
        case .activity: return .activity
        case .manualHeartRate: return .manualHeartRate
        case .pai: return .pai
        case .stressManual: return .manualStress
        case .stressAutomatic: return .autoStress
        case .bloodOxygenNormal: return .spo2
        case .bloodOxygenSleep: return .sleepSpO2
        case .temperature: return .temperature
        case .sleepRespiratoryRate: return .sleepRespiratoryRate
        case .restingHeartRate: return .restingHeartRate
        case .maximumHeartRate: return .maxHeartRate
        case .sleepSession: return .sleepSession
        case .heartRateVariability: return .hrv
        }
    }
}
