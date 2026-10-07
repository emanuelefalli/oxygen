enum StrapFetchType: UInt8, CaseIterable, Sendable {
    case activity = 0x01
    case manualHeartRate = 0x02
    case pai = 0x0d
    case stressManual = 0x12
    case stressAutomatic = 0x13
    case bloodOxygenNormal = 0x25
    case bloodOxygenSleep = 0x26
    case temperature = 0x2e
    case sleepRespiratoryRate = 0x38
    case restingHeartRate = 0x3a
    case maximumHeartRate = 0x3d
    case sleepSession = 0x48
    case heartRateVariability = 0x49

    static let syncOrder: [StrapFetchType] = allCases.sorted { $0.rawValue < $1.rawValue }

    var nextInSyncOrder: StrapFetchType? {
        guard let index = Self.syncOrder.firstIndex(of: self) else { return nil }
        let nextIndex = Self.syncOrder.index(after: index)
        guard nextIndex < Self.syncOrder.endIndex else { return nil }
        return Self.syncOrder[nextIndex]
    }

    var displayName: String {
        switch self {
        case .activity: return "activity"
        case .manualHeartRate: return "manual heart rate"
        case .pai: return "PAI"
        case .stressManual: return "manual stress"
        case .stressAutomatic: return "stress"
        case .bloodOxygenNormal: return "blood oxygen"
        case .bloodOxygenSleep: return "sleep blood oxygen"
        case .temperature: return "skin temperature"
        case .sleepRespiratoryRate: return "sleep respiratory rate"
        case .restingHeartRate: return "resting heart rate"
        case .maximumHeartRate: return "maximum heart rate"
        case .sleepSession: return "sleep"
        case .heartRateVariability: return "heart rate variability"
        }
    }

    var exportFileName: String { "\(self).csv" }
}
