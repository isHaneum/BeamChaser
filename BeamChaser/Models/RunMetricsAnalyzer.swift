import Foundation
import CoreLocation

enum RunSensorSource: String, Codable, Equatable {
    case none
    case gps
    case watch
    case ble
    case phoneIMU
    case estimated
    case corrected
}

enum RunGPSQuality: String, Codable, Equatable {
    case good
    case fair
    case poor
}

struct RunDataQuality: Codable, Equatable {
    var heartRateSource: RunSensorSource = .none
    var cadenceSource: RunSensorSource = .none
    var elevationSource: RunSensorSource = .none
    var gpsQuality: RunGPSQuality = .poor
    var hasReliableElevation = false
    var hasReliableSpeed = false
    var hasReliableHeartRate = false
    var hasReliableCadence = false
}

struct RunMetricAnalysis: Equatable {
    let averageGPSAccuracyMeters: Double?
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double?
    let elevationGainMeters: Double?
    let caloriesEstimatedKcal: Double
    let caloriesUseDefaultWeight: Bool
    let dataQuality: RunDataQuality
}

enum RunMetricsAnalyzer {
    static let maxReliableHorizontalAccuracy = 20.0
    static let maxReliableVerticalAccuracy = 15.0
    static let maxReliableSpeedMps = 8.0
    static let minMovementSpeedMps = 0.5
    static let minElevationDeltaMeters = 1.5
    static let maxElevationSpikeMeters = 10.0
    static let minDistanceForElevationMeters = 500.0
    static let minDistanceForCadenceMeters = 150.0
    static let minDistanceForMaxSpeedMeters = 150.0
    static let minCadenceDurationSeconds = 10.0
    static let sustainedMaxSpeedWindowSeconds: TimeInterval = 3.0
    static let minSegmentIntervalSeconds: TimeInterval = 0.5
    static let maxSegmentIntervalSeconds: TimeInterval = 10.0
    static let defaultWeightKg = 70.0
    private static let altitudeSmoothingFactor = 0.25

    static func analyze(record: RunRecord, weightKg: Double? = nil) -> RunMetricAnalysis {
        let positiveAccuracies = record.routePoints
            .map(\.horizontalAccuracy)
            .filter { $0.isFinite && $0 > 0 }
        let averageAccuracy = positiveAccuracies.isEmpty
            ? nil
            : positiveAccuracies.reduce(0, +) / Double(positiveAccuracies.count)
        let validGPSPointCount = record.routePoints.filter(isValidGPSPoint).count
        let gpsQuality = resolveGPSQuality(
            pointCount: record.routePoints.count,
            validPointCount: validGPSPointCount,
            averageAccuracy: averageAccuracy,
            totalDistanceMeters: record.totalDistanceMeters
        )

        let speedSegments = buildSpeedSegments(from: record.routePoints)
        let derivedMaxSpeed = sustainedMaxSpeedKmh(
            from: speedSegments,
            totalDistanceMeters: record.totalDistanceMeters,
            gpsQuality: gpsQuality
        )
        let derivedAverageSpeed = record.elapsedSeconds > 0
            ? (record.totalDistanceMeters / 1000.0) / (record.elapsedSeconds / 3600.0)
            : 0

        let derivedElevation = filteredElevationGainMeters(
            from: record.routePoints,
            totalDistanceMeters: record.totalDistanceMeters,
            gpsQuality: gpsQuality
        )

        let defaultHeartRateSource: RunSensorSource = {
            guard let value = record.averageHeartRateBpm, value > 0 else { return .none }
            return .watch
        }()
        let defaultCadenceSource: RunSensorSource = {
            guard let value = record.averageCadenceSpm, value > 0 else { return .none }
            guard record.elapsedSeconds >= minCadenceDurationSeconds else { return .none }
            guard record.totalDistanceMeters >= minDistanceForCadenceMeters else { return .none }
            return .phoneIMU
        }()

        let weight = weightKg ?? defaultWeightKg
        let caloriesEstimated = record.caloriesEstimatedKcal
            ?? estimatedCalories(
                averageSpeedKmh: derivedAverageSpeed,
                elapsedSeconds: record.elapsedSeconds,
                weightKg: weight
            )

        let mergedQuality = RunDataQuality(
            heartRateSource: record.dataQuality?.heartRateSource ?? defaultHeartRateSource,
            cadenceSource: record.dataQuality?.cadenceSource ?? defaultCadenceSource,
            elevationSource: record.dataQuality?.elevationSource ?? (derivedElevation != nil ? .corrected : .none),
            gpsQuality: record.dataQuality?.gpsQuality ?? gpsQuality,
            hasReliableElevation: record.dataQuality?.hasReliableElevation ?? (derivedElevation != nil),
            hasReliableSpeed: record.dataQuality?.hasReliableSpeed ?? (derivedMaxSpeed != nil),
            hasReliableHeartRate: record.dataQuality?.hasReliableHeartRate ?? ((record.averageHeartRateBpm ?? 0) > 0),
            hasReliableCadence: record.dataQuality?.hasReliableCadence ?? (defaultCadenceSource != .none)
        )

        return RunMetricAnalysis(
            averageGPSAccuracyMeters: averageAccuracy,
            averageSpeedKmh: derivedAverageSpeed,
            maxSpeedKmh: mergedQuality.hasReliableSpeed ? derivedMaxSpeed : nil,
            elevationGainMeters: mergedQuality.hasReliableElevation ? derivedElevation : nil,
            caloriesEstimatedKcal: caloriesEstimated,
            caloriesUseDefaultWeight: weightKg == nil,
            dataQuality: mergedQuality
        )
    }

    static func estimatedCalories(averageSpeedKmh: Double, elapsedSeconds: TimeInterval, weightKg: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }

        let met: Double
        switch averageSpeedKmh {
        case ..<8.0:
            met = 8.3
        case ..<9.7:
            met = 9.8
        case ..<11.3:
            met = 11.0
        case ..<12.1:
            met = 11.8
        case ..<12.9:
            met = 12.8
        default:
            met = 14.5
        }

        return met * weightKg * (elapsedSeconds / 3600.0)
    }

    private static func resolveGPSQuality(
        pointCount: Int,
        validPointCount: Int,
        averageAccuracy: Double?,
        totalDistanceMeters: Double
    ) -> RunGPSQuality {
        guard pointCount >= 3, totalDistanceMeters >= 100 else { return .poor }
        guard let averageAccuracy else { return .poor }

        let validRatio = Double(validPointCount) / Double(max(pointCount, 1))
        if averageAccuracy <= 10, validRatio >= 0.85 {
            return .good
        }
        if averageAccuracy <= maxReliableHorizontalAccuracy, validRatio >= 0.6 {
            return .fair
        }
        return .poor
    }

    private static func buildSpeedSegments(from routePoints: [RoutePoint]) -> [SpeedSegment] {
        guard routePoints.count >= 2 else { return [] }

        var segments: [SpeedSegment] = []
        for index in 1..<routePoints.count {
            let previous = routePoints[index - 1]
            let current = routePoints[index]

            guard isValidGPSPoint(previous), isValidGPSPoint(current) else { continue }

            let timeDelta = current.timestamp.timeIntervalSince(previous.timestamp)
            guard timeDelta >= minSegmentIntervalSeconds, timeDelta <= maxSegmentIntervalSeconds else { continue }

            let distanceDelta = distanceBetween(previous, current)
            let derivedSpeed = distanceDelta / timeDelta
            let speed = sanitizedSpeed(current.speed) ?? sanitizedSpeed(derivedSpeed)
            guard let speed else { continue }

            segments.append(SpeedSegment(duration: timeDelta, speedMps: speed))
        }
        return segments
    }

    private static func sustainedMaxSpeedKmh(
        from segments: [SpeedSegment],
        totalDistanceMeters: Double,
        gpsQuality: RunGPSQuality
    ) -> Double? {
        guard totalDistanceMeters >= minDistanceForMaxSpeedMeters else { return nil }
        guard gpsQuality != .poor else { return nil }
        guard !segments.isEmpty else { return nil }

        var window: [SpeedSegment] = []
        var windowDuration: TimeInterval = 0
        var weightedSpeedSum: Double = 0
        var maxWindowSpeed: Double?

        for segment in segments {
            window.append(segment)
            windowDuration += segment.duration
            weightedSpeedSum += segment.speedMps * segment.duration

            while windowDuration > sustainedMaxSpeedWindowSeconds, let first = window.first {
                let overflow = windowDuration - sustainedMaxSpeedWindowSeconds
                if overflow >= first.duration {
                    window.removeFirst()
                    windowDuration -= first.duration
                    weightedSpeedSum -= first.speedMps * first.duration
                } else {
                    window[0] = SpeedSegment(duration: first.duration - overflow, speedMps: first.speedMps)
                    windowDuration -= overflow
                    weightedSpeedSum -= first.speedMps * overflow
                }
            }

            guard windowDuration >= sustainedMaxSpeedWindowSeconds else { continue }
            let windowAverage = weightedSpeedSum / windowDuration
            maxWindowSpeed = max(maxWindowSpeed ?? 0, windowAverage)
        }

        return maxWindowSpeed.map { $0 * 3.6 }
    }

    private static func filteredElevationGainMeters(
        from routePoints: [RoutePoint],
        totalDistanceMeters: Double,
        gpsQuality: RunGPSQuality
    ) -> Double? {
        guard totalDistanceMeters >= minDistanceForElevationMeters else { return nil }
        guard gpsQuality != .poor else { return nil }

        var previous: AltitudeSample?
        var gain: Double = 0
        var validSampleCount = 0

        for point in routePoints {
            // Ignore low-confidence altitude points without resetting the last good baseline.
            guard isValidAltitudePoint(point) else { continue }

            let smoothedAltitude: Double
            if let previousSample = previous {
                smoothedAltitude = (previousSample.smoothedAltitude * (1.0 - altitudeSmoothingFactor))
                    + (point.altitude * altitudeSmoothingFactor)

                let timeDelta = point.timestamp.timeIntervalSince(previousSample.point.timestamp)
                guard timeDelta >= minSegmentIntervalSeconds, timeDelta <= maxSegmentIntervalSeconds else {
                    previous = makeAltitudeSample(point: point, smoothedAltitude: smoothedAltitude)
                    validSampleCount += 1
                    continue
                }

                let distanceDelta = distanceBetween(previousSample.point, point)
                let effectiveSpeed = sanitizedSpeed(point.speed) ?? (distanceDelta / timeDelta)
                // When movement continuity breaks, restart the baseline from this valid sample.
                guard distanceDelta >= 1 || effectiveSpeed >= minMovementSpeedMps else {
                    previous = makeAltitudeSample(point: point, smoothedAltitude: smoothedAltitude)
                    validSampleCount += 1
                    continue
                }

                let delta = smoothedAltitude - previousSample.smoothedAltitude
                if delta > minElevationDeltaMeters, delta < maxElevationSpikeMeters {
                    gain += delta
                }
            } else {
                smoothedAltitude = point.altitude
            }

            previous = makeAltitudeSample(point: point, smoothedAltitude: smoothedAltitude)
            validSampleCount += 1
        }

        guard validSampleCount >= 3 else { return nil }
        return max(0, gain)
    }

    private static func makeAltitudeSample(
        point: RoutePoint,
        smoothedAltitude: Double
    ) -> AltitudeSample {
        AltitudeSample(point: point, smoothedAltitude: smoothedAltitude)
    }

    private static func isValidGPSPoint(_ point: RoutePoint) -> Bool {
        point.horizontalAccuracy.isFinite
            && point.horizontalAccuracy > 0
            && point.horizontalAccuracy <= maxReliableHorizontalAccuracy
    }

    private static func isValidAltitudePoint(_ point: RoutePoint) -> Bool {
        guard isValidGPSPoint(point) else { return false }
        guard let verticalAccuracy = point.verticalAccuracy else { return false }
        return verticalAccuracy.isFinite
            && verticalAccuracy > 0
            && verticalAccuracy <= maxReliableVerticalAccuracy
    }

    private static func sanitizedSpeed(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= maxReliableSpeedMps else { return nil }
        return value
    }

    private static func distanceBetween(_ left: RoutePoint, _ right: RoutePoint) -> Double {
        CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude))
    }

    private struct SpeedSegment {
        var duration: TimeInterval
        let speedMps: Double
    }

    private struct AltitudeSample {
        let point: RoutePoint
        let smoothedAltitude: Double
    }
}

struct RunDetailMetricCardModel: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let subtitle: String?
    let isPrimary: Bool
    let isMuted: Bool
}

enum RunDetailMetricBuilder {
    static func cards(for record: RunRecord, appLanguage: AppLanguage = .current) -> [RunDetailMetricCardModel] {
        let analysis = record.analyzedMetrics
        var cards: [RunDetailMetricCardModel] = [
            RunDetailMetricCardModel(
                id: "distance",
                title: appLanguage.text("거리", "Distance"),
                value: String(format: "%.2f", record.distanceKm),
                unit: "km",
                subtitle: nil,
                isPrimary: true,
                isMuted: false
            ),
            RunDetailMetricCardModel(
                id: "time",
                title: appLanguage.text("시간", "Time"),
                value: record.formattedDuration,
                unit: "",
                subtitle: nil,
                isPrimary: true,
                isMuted: false
            ),
            RunDetailMetricCardModel(
                id: "averagePace",
                title: appLanguage.text("평균 페이스", "Average Pace"),
                value: record.formattedPace,
                unit: "/km",
                subtitle: nil,
                isPrimary: false,
                isMuted: false
            ),
            RunDetailMetricCardModel(
                id: "averageSpeed",
                title: appLanguage.text("평균 속도", "Average Speed"),
                value: String(format: "%.1f", analysis.averageSpeedKmh),
                unit: "km/h",
                subtitle: gpsAccuracyNote(for: analysis.dataQuality.gpsQuality, appLanguage: appLanguage),
                isPrimary: false,
                isMuted: false
            ),
            RunDetailMetricCardModel(
                id: "calories",
                title: appLanguage.text("칼로리(추정)", "Calories (Est.)"),
                value: String(format: "%.0f", analysis.caloriesEstimatedKcal),
                unit: "kcal",
                subtitle: analysis.caloriesUseDefaultWeight
                    ? appLanguage.text("기본 체중 가정", "Default weight assumed")
                    : appLanguage.text("MET 기반 추정", "Estimated from MET"),
                isPrimary: false,
                isMuted: false
            ),
        ]

        if let heartRate = reliableHeartRateValue(from: record, quality: analysis.dataQuality) {
            cards.append(
                RunDetailMetricCardModel(
                    id: "heartRate",
                    title: appLanguage.text("평균 심박수", "Average Heart Rate"),
                    value: "\(heartRate)",
                    unit: "bpm",
                    subtitle: sourceDetail(for: analysis.dataQuality.heartRateSource, appLanguage: appLanguage),
                    isPrimary: false,
                    isMuted: false
                )
            )
        } else {
            cards.append(
                RunDetailMetricCardModel(
                    id: "heartRateUnavailable",
                    title: appLanguage.text("심박수", "Heart Rate"),
                    value: "--",
                    unit: "bpm",
                    subtitle: appLanguage.text("심박수 측정 안 됨", "Heart rate not measured"),
                    isPrimary: false,
                    isMuted: true
                )
            )
        }

        if let cadence = reliableCadenceValue(from: record, quality: analysis.dataQuality) {
            cards.append(
                RunDetailMetricCardModel(
                    id: "cadence",
                    title: appLanguage.text("평균 케이던스", "Average Cadence"),
                    value: "\(cadence)",
                    unit: "spm",
                    subtitle: sourceDetail(for: analysis.dataQuality.cadenceSource, appLanguage: appLanguage),
                    isPrimary: false,
                    isMuted: false
                )
            )
        }

        if let elevation = analysis.elevationGainMeters {
            cards.append(
                RunDetailMetricCardModel(
                    id: "elevationGain",
                    title: appLanguage.text("고도 상승(보정)", "Elevation Gain (Adj.)"),
                    value: String(format: "%.0f", elevation),
                    unit: "m",
                    subtitle: sourceDetail(for: analysis.dataQuality.elevationSource, appLanguage: appLanguage),
                    isPrimary: false,
                    isMuted: false
                )
            )
        } else {
            cards.append(
                RunDetailMetricCardModel(
                    id: "elevationUnavailable",
                    title: appLanguage.text("총 고도 상승", "Elevation Gain"),
                    value: "--",
                    unit: "m",
                    subtitle: appLanguage.text("고도 정보 없음", "No elevation data"),
                    isPrimary: false,
                    isMuted: true
                )
            )
        }

        if let maxSpeed = analysis.maxSpeedKmh {
            cards.append(
                RunDetailMetricCardModel(
                    id: "maxSpeed",
                    title: appLanguage.text("최고 속도", "Top Speed"),
                    value: String(format: "%.1f", maxSpeed),
                    unit: "km/h",
                    subtitle: appLanguage.text("3초 유지 구간 기준", "Based on sustained 3s speed"),
                    isPrimary: false,
                    isMuted: false
                )
            )
        }

        return cards
    }

    static func sourceLabel(_ source: RunSensorSource, appLanguage: AppLanguage = .current) -> String {
        switch source {
        case .none:
            return appLanguage.text("없음", "None")
        case .gps:
            return appLanguage.text("GPS", "GPS")
        case .watch:
            return appLanguage.text("워치", "Watch")
        case .ble:
            return appLanguage.text("BLE", "BLE")
        case .phoneIMU:
            return appLanguage.text("폰 IMU", "Phone IMU")
        case .estimated:
            return appLanguage.text("추정", "Estimated")
        case .corrected:
            return appLanguage.text("보정", "Corrected")
        }
    }

    static func sourceDetail(for source: RunSensorSource, appLanguage: AppLanguage = .current) -> String {
        switch source {
        case .none:
            return appLanguage.text("측정 안 됨", "Not measured")
        case .gps:
            return appLanguage.text("GPS 측정", "GPS measured")
        case .watch:
            return appLanguage.text("Apple Watch / HealthKit", "Apple Watch / HealthKit")
        case .ble:
            return appLanguage.text("BLE 센서", "BLE sensor")
        case .phoneIMU:
            return appLanguage.text("iPhone 동작 센서", "iPhone motion sensor")
        case .estimated:
            return appLanguage.text("추정값", "Estimated")
        case .corrected:
            return appLanguage.text("GPS 보정", "GPS corrected")
        }
    }

    static func gpsQualityLabel(_ quality: RunGPSQuality, appLanguage: AppLanguage = .current) -> String {
        switch quality {
        case .good:
            return appLanguage.text("양호", "Good")
        case .fair:
            return appLanguage.text("보통", "Fair")
        case .poor:
            return appLanguage.text("낮음", "Poor")
        }
    }

    static func gpsAccuracyNote(for quality: RunGPSQuality, appLanguage: AppLanguage = .current) -> String? {
        switch quality {
        case .good:
            return nil
        case .fair:
            return appLanguage.text("GPS 정확도 보통", "GPS accuracy fair")
        case .poor:
            return appLanguage.text("GPS 정확도 낮음", "GPS accuracy low")
        }
    }

    private static func reliableHeartRateValue(from record: RunRecord, quality: RunDataQuality) -> Int? {
        guard quality.hasReliableHeartRate else { return nil }
        guard let heartRate = record.averageHeartRateBpm, heartRate > 0 else { return nil }
        return heartRate
    }

    private static func reliableCadenceValue(from record: RunRecord, quality: RunDataQuality) -> Int? {
        guard quality.hasReliableCadence else { return nil }
        guard let cadence = record.averageCadenceSpm, cadence > 0 else { return nil }
        return cadence
    }
}