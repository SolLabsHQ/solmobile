//
//  LocationSampler.swift
//  SolMobile
//

import CoreLocation
import Foundation

final class LocationSampler: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSampler()

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        super.init()
        manager.delegate = self
    }

    func snapshotLocation() async -> CLLocation? {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if let cached = manager.location {
                return cached
            }
            return await requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return nil
        default:
            return nil
        }
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation?.resume(returning: nil)
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
