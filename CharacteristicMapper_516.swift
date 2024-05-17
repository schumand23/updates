//
//  CharacteristicMapper.swift
//  LevelMatePro v2
//
//  Created by Justin Trautman on 1/13/20.
//  Copyright © 2020 Logic Blue Technology. All rights reserved.
//
// swiftlint:disable large_tuple

import Foundation
import CoreBluetooth
/// Defines cases for all service types returned from LMP device.
/// Hardware info refers to harware specific data such as model number and current firmaware version.
/// Battery info refers to current battery percentage.
/// Sensor info refers to data returned from the LMP's sensors.
enum LMPService {
    case hardwareInfo
    case batteryInfo
    case sensorInfo
}

// MARK: - UUID Strings

/// Contains readable characteristic strings for data returned from LMP's hardware info.
enum DeviceUUID: String {
    case modelNumber = "2A24"
    case firmwareVersion = "2A26"
    case hardwareVersion = "2A27"
    case manufacturer = "2A29"
}

/// Contains readable characteristic strings for data returned from LMP's battery info.
enum BatteryUUID: String {
    case batteryLevel = "2A19"
}

/// Contains all readable characteristic strings for data returned from LMP's sensors.
enum SensorInfoUUID: String {
    case pitch = "AA11"
    case roll = "AA12"
    case sideHeight = "AA13"
    case frontHeight = "AA14"
    case trailerLength = "AA15"
    case trailerWidth = "AA16"
    case hitchPosition = "AA17"
    case updateRate = "AA18"
    case zeroOffsetUUID = "AA19"
    case advertiseTimeout = "AA1A"
    case motionTime = "AA1B"
    case measurementUnit = "AA1C"
    case configurationComplete = "AA1D"
    case hitchPositionDate = "AA1E"
    case hitchHeightDelta = "AA1F"
    case temperature = "AA20"
    case newTemperature = "2A1C"
    case mountingOrientation = "AA24"
    case moduleID = "AA26"
    case wakeSensitivity = "AA27"
    case trailerType = "AA2B"
    case heightResolution = "AA2C"
    case roadSide = "AA2D"
    case writePassword = "AA21"
    case accelerometer = "C4C1F6E2-4BE5-11E5-885D-FEFF819CDC9F"
    case gyroscope = "B7C4B694-BEE3-45DD-BA9F-F3B5E994F49A"
}

struct GyroscopeData {
    var roll: Double
    var pitch: Double
    var yaw: Double
    var lastUpdateTime: Date
}

struct AccelerometerData {
    var x: Double
    var y: Double
    var z: Double
    var roll: Double
    var pitch: Double
}

struct CalibrationData: Codable {
    internal init(roll: Double = 0, pitch: Double = 0, rollDegree: Double = 0, pitchDegree: Double = 0) {
        self.roll = roll
        self.pitch = pitch
        self.rollDegree = rollDegree
        self.pitchDegree = pitchDegree
    }
    
    var roll: Double
    var pitch: Double
    var rollDegree: Double
    var pitchDegree: Double
}

class CharacteristicMapper {
    static var shared = CharacteristicMapper()
    var hardwareInfo = LMPHardware()
    var batteryInfo = LMPBattery()
    var sensorData = LMPSensor()

    private var isGyroInitialized = false
    private var gyroscopeData = GyroscopeData(roll: 0.0, pitch: 0.0, yaw: 0.0, lastUpdateTime: Date())
    private var accelerometerData = AccelerometerData(x: 0.0, y: 0.0, z: 0.0, roll: 0.0, pitch: 0.0)
    private var tempCalibrationData = CalibrationData()
    var deviceOrientation: String = "Unknown"

    // Initialize calibration data with zero values
    private var calibrationData = CalibrationData(roll: 0.0, pitch: 0.0)

    // Add a flag to check if the device is calibrated
    private var isDeviceCalibrated = false

    private init() {
        if let savedData = UserDefaultsHelper.shared.localSaveFile.toLocalSaveFile() {
            if let calibrationData = savedData.calibrationData {
                isDeviceCalibrated = true
                self.calibrationData = calibrationData
            }
        }
    }

    func getLMPServiceFrom(uuid: String) -> LMPService? {
        if DeviceUUID(rawValue: uuid) != nil { return .hardwareInfo }
        if BatteryUUID(rawValue: uuid) != nil { return .batteryInfo }
        if SensorInfoUUID(rawValue: uuid) != nil { return .sensorInfo }
        return nil
    }

    // MARK: - Device Info Mapping

    func mapDeviceInfo(value: String?, from uuid: String) {
        guard let deviceCharacteristic = DeviceUUID(rawValue: uuid), let value = value else { return }

        let characteristicString = String(describing: value)

        switch deviceCharacteristic {
        case .modelNumber:
            hardwareInfo.model = characteristicString.contains("+") ? .plus : .standard
        case .firmwareVersion:
            hardwareInfo.firmwareVersion = characteristicString
            UserDefaultsHelper.shared.currentDeviceModel = value.substring(toIndex: 1) == "4" ? .plus : .standard
        case .hardwareVersion:
            hardwareInfo.hardwareVersion = characteristicString
        case .manufacturer:
            hardwareInfo.manufacturerName = characteristicString
        }

        saveData()
    }

    // MARK: - Battery Value Mapping

    func mapBatteryValue(value: Double?, from uuid: String) {
        guard let batteryCharacteristic = BatteryUUID(rawValue: uuid), let value = value else { return }

        NotificationCenter.default.post(name: .batteryUpdated, object: nil, userInfo: ["battery": value])

        let characteristicString = String(describing: value)

        switch batteryCharacteristic {
        case .batteryLevel:
            batteryInfo.batteryLevel = characteristicString
        }

        saveData()
    }

    // MARK: - Device Info Value Mapping

    func mapSensorValue(value: Double?, characteristic: CBCharacteristic, from uuid: String) {
        guard let deviceCharacteristic = SensorInfoUUID(rawValue: uuid),
              let value = value else { return }

        let characteristicString = String(describing: value)

        switch deviceCharacteristic {
        case .pitch:
            sensorData.pitch = characteristicString
            NotificationCenter.default.post(name: .pitchUpdated, object: nil, userInfo: ["pitch": characteristicString])
        case .roll:
            sensorData.roll = characteristicString
            NotificationCenter.default.post(name: .rollUpdated, object: nil, userInfo: ["roll": characteristicString])
        case .sideHeight:
            sensorData.sideHeight = characteristicString
            NotificationCenter.default.post(name: .sideHeightUpdated, object: nil, userInfo: ["sideHeight": characteristicString])
        case .frontHeight:
            sensorData.frontHeight = characteristicString
            NotificationCenter.default.post(name: .frontHeightUpdated, object: nil, userInfo: ["frontHeight": characteristicString])
        case .trailerLength:
            sensorData.trailerLength = characteristicString
            saveTrailerLength(length: characteristicString)
        case .trailerWidth:
            sensorData.trailerWidth = characteristicString
            saveTrailerWidth(width: characteristicString)
        case .hitchPosition:
            sensorData.hitchPosition = characteristicString
        case .updateRate:
            sensorData.updateRate = characteristicString
        case .advertiseTimeout:
            sensorData.advertiseTimeout = characteristicString
            saveIdleTimeFrom(minuteValue: value)
        case .motionTime:
            sensorData.motionTime = characteristicString
            readWakeOnMotionStatusFrom(value: value)
        case .measurementUnit:
            setMeasurementUnitFrom(unitValue: value)
        case .configurationComplete:
            readConfigurationStatusFrom(value: value)
        case .hitchHeightDelta:
            sensorData.hitchHeightDelta = characteristicString
        case .temperature:
            sensorData.temperature = characteristicString
            NotificationCenter.default.post(name: .temperatureUpdated, object: nil, userInfo: ["temperature": characteristicString])
        case .newTemperature:
            if let data = characteristic.value {
                let temperature = data.processTemperatureData()
                sensorData.temperature = "\(temperature)"
                NotificationCenter.default.post(name: .temperatureUpdated, object: nil, userInfo: ["temperature": sensorData.temperature])
            }
        case .mountingOrientation:
            sensorData.mountingOrientation = characteristicString
            saveOrientationFrom(orientationValue: value)
        case .moduleID:
            sensorData.moduleID = characteristicString
        case .wakeSensitivity:
            sensorData.wakeSensitivity = characteristicString
        case .trailerType:
            sensorData.trailerType = value
            saveTrailerTypeFrom(trailerValue: value)
        case .heightResolution:
            sensorData.heightResolution = characteristicString
            saveResolutionFrom(resolutionValue: value)
        case .roadSide:
            sensorData.roadSide = characteristicString
            saveDrivingSideFrom(value: value)
        case .accelerometer:
            guard let data = characteristic.value else {
                print("Received empty data from characteristic \(characteristic.uuid)")
                break
            }
            let decodedData = decodeAccelerationData(data)
            sensorData.pitch = String(describing: decodedData.pitch)
            sensorData.roll = String(describing: decodedData.roll)
        case .gyroscope:
            guard let data = characteristic.value else {
                print("Received empty data from characteristic \(characteristic.uuid)")
                break
            }
            let decodedData = decodeOrientationData(data)
            sensorData.pitch = String(describing: decodedData.pitch)
            NotificationCenter.default.post(name: .pitchUpdated, object: nil, userInfo: ["pitch": sensorData.pitch])
            sensorData.roll = String(describing: decodedData.roll)
            NotificationCenter.default.post(name: .rollUpdated, object: nil, userInfo: ["roll": sensorData.roll])
            sensorData.sideHeight = String(describing: decodedData.sideHeight)
            NotificationCenter.default.post(name: .sideHeightUpdated, object: nil, userInfo: ["sideHeight": sensorData.sideHeight])
            sensorData.frontHeight = String(describing: decodedData.frontHeight)
            NotificationCenter.default.post(name: .frontHeightUpdated, object: nil, userInfo: ["frontHeight": sensorData.frontHeight])

        default:
            break
        }

        saveData()
    }

    func setLastHitchPositionDateTo(dateString: String) {
        sensorData.hitchPositionDate = dateString
        saveData()
    }

    /// Note: This is only supported on firmware 3 and higher.
    /// Returns trailer type from stored value on LMP.
    /// Defaults to travel trailer if LMP does not have a trailer type configured.
    func saveTrailerTypeFrom(trailerValue: Double) {
        // If LMP profile was created on version 1,
        // carry over trailer type from config file.
        guard let currentLMP = DocumentManager.shared.currentLMP,
              Constants.Support.firmwareVersionMajor >= 3,
              ConfigurationManager.shared.pendingDeviceWrites == false else {
            return
        }

        var trailerType: TrailerType

        switch trailerValue {
        case 1: trailerType = .fifthWheel
        case 2: trailerType = .popupCamper
        case 3: trailerType = .compactMotorhome
        case 4: trailerType = .classA
        default: trailerType = .travelTrailer
        }

        currentLMP.trailer?.trailerType = trailerType
        saveData()
    }

    func saveTrailerWidth(width: String) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        currentLMP.trailer?.width = width.substringBefore(character: ".") // Width value excluding any decimals
        saveData()
    }

    func saveTrailerLength(length: String) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        currentLMP.trailer?.length = length.substringBefore(character: ".") // Length value excluding any decimals
        saveData()
    }

    func saveOrientationFrom(orientationValue: Double) {
        guard let currentLMP = DocumentManager.shared.currentLMP,
              let drivingSide = DocumentManager.shared.userProfile?.drivingSide else {
            return
        }

        var orientation: InstallationOrientation

        switch orientationValue {
        case 0:
            orientation = .front
        case 1:
            if drivingSide == .right {
                orientation = .passengersSide
            } else {
                orientation = .driversSide
            }

        case 2:
            orientation = .rear
        case 3:
            if drivingSide == .right {
                orientation = .driversSide
            } else {
                orientation = .passengersSide
            }

        default:
            return
        }

        currentLMP.installationOrientation = orientation
        DocumentManager.shared.saveLMPToDisk(LMP: currentLMP)
        saveData()
    }

    func saveResolutionFrom(resolutionValue: Double) {
        // If LMP profile was created on version 1,
        // carry over measurement resolution from config file.
        guard let currentLMP = DocumentManager.shared.currentLMP,
              ConfigurationManager.shared.pendingDeviceWrites == false else { return }

        var resolution: MeasurementDisplay

        switch resolutionValue {
        case 1:
            resolution = .halfInch
        case 2:
            resolution = .inch
        case 3:
            resolution = .inchAndQuarter
        default: // Native resolution
            resolution = .quarterInch
        }

        currentLMP.measurementDisplay = resolution
        saveData()
    }

    func saveIdleTimeFrom(minuteValue: Double) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        let idleTimeInHours = Int(minuteValue / 60)

        if idleTimeInHours == 0 {
            currentLMP.runContinuously = true
            currentLMP.idleTime = 0
        } else {
            currentLMP.idleTime = idleTimeInHours
        }

        saveData()
    }

    func saveDrivingSideFrom(value: Double) {
        // If LMP profile was created on version 1,
        // carry over driving side from config file.
        guard ConfigurationManager.shared.pendingDeviceWrites == false else { return }

        guard let userProfile = DocumentManager.shared.userProfile else { return }

        switch value {
        case 1: userProfile.drivingSide = .left
        default: userProfile.drivingSide = .right
        }
    }

    func setMeasurementUnitFrom(unitValue: Double) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        guard let userProfile = DocumentManager.shared.userProfile else { return }

        switch unitValue {
        case 1:
            userProfile.measurementUnit = .metric

            // Temperature unit will be set only once after migration
            if ConfigurationManager.shared.pendingDeviceWrites {
                userProfile.temperatureUnit = .metric
                currentLMP.upgradeInProgress = false
                DocumentManager.shared.saveLMPToDisk(LMP: currentLMP)
            }
        default:
            userProfile.measurementUnit = .imperial

            // Temperature unit will be set only once after migration
            if ConfigurationManager.shared.pendingDeviceWrites {
                userProfile.temperatureUnit = .imperial
                currentLMP.upgradeInProgress = false
                DocumentManager.shared.saveLMPToDisk(LMP: currentLMP)
            }
        }

        saveData()
    }

    private func readWakeOnMotionStatusFrom(value: Double) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        if value == 0 || value == 25 { // iOS & Android readings
            currentLMP.wakeOnMotion = false
        } else {
            currentLMP.wakeOnMotion = true
        }

        saveData()
    }

    private func readConfigurationStatusFrom(value: Double) {
        guard let currentLMP = DocumentManager.shared.currentLMP else { return }

        guard currentLMP.hardwareInfo?.firmwareVersion != nil else { return }

        guard Constants.Support.firmwareVersionMajor != 0 else { return }

        if Constants.Support.firmwareVersionMajor <= 2 {
            switch value {
            case 1:
                sensorData.configurationStatus = .configurationCompleteRegistrationComplete
            default:
                sensorData.configurationStatus = .noConfigurationNoRegistration
            }
        } else {
            switch value {
            case 1:
                sensorData.configurationStatus = .configurationCompleteNoRegistration
            case 2:
                sensorData.configurationStatus = .configurationIncompleteRegistrationComplete
                currentLMP.setupProcess = .stepOne
            case 3:
                sensorData.configurationStatus = .configurationCompleteRegistrationComplete
            default:
                sensorData.configurationStatus = .noConfigurationNoRegistration
                currentLMP.setupProcess = .stepOne
            }
        }

        saveData()
        MessageScreen.configurationStatus = sensorData.configurationStatus
        NotificationCenter.default.post(name: .configurationUpdated, object: nil)
    }

    func forceConfiguration() {
        sensorData.configurationStatus = .configurationIncompleteRegistrationComplete
        MessageScreen.configurationStatus = sensorData.configurationStatus
        NotificationCenter.default.post(name: .configurationUpdated, object: nil)
    }

    private func saveData() {
        guard let user = DocumentManager.shared.userProfile, let currentLMP = DocumentManager.shared.currentLMP else { return }

        currentLMP.battery = batteryInfo
        currentLMP.hardwareInfo = hardwareInfo
        currentLMP.sensorData = sensorData

        DocumentManager.shared.saveUserToDisk(user: user)
    }
}

extension CharacteristicMapper {
//    func decodeData(from characteristic: CBCharacteristic) -> (frontHeight: Double, sideHeight: Double) {
//        guard let data = characteristic.value else {
//            print("Received empty data from characteristic \(characteristic.uuid)")
//            return (0, 0)
//        }
//
//        // Convert both UUIDs to the same case format before comparison
//        let characteristicUUID = characteristic.uuid.uuidString.lowercased()
//        switch characteristicUUID {
//        case "c4c1f6e2-4be5-11e5-885d-feff819cdc9f":
//            return decodeAccelerationData(data)
//        case "b7c4b694-bee3-45dd-ba9f-f3b5e994f49a":
//            return decodeOrientationData(data)
//        default:
//            print("Unknown characteristic UUID: \(characteristicUUID)")
//            return (0, 0)
//        }
//    }

    func decodeAccelerationData(_ data: Data) -> (pitch: Double, roll: Double) {
        let bytes = [UInt8](data)

        if bytes.count >= 6 {

            print("Bit Raw Data - 0: \(bytes[0]), 1: \(bytes[1]), 2: \(bytes[2]), 3: \(bytes[3]), 4: \(bytes[4]), 5: \(bytes[5])")

            let int16Byte0 = Int16(bitPattern: UInt16(bytes[0]))
                let int16Byte1 = Int16(bitPattern: UInt16(bytes[1]) << 8)
                let int16Byte2 = Int16(bitPattern: UInt16(bytes[2]))
                let int16Byte3 = Int16(bitPattern: UInt16(bytes[3]) << 8)
                let int16Byte4 = Int16(bitPattern: UInt16(bytes[4]))
                let int16Byte5 = Int16(bitPattern: UInt16(bytes[5]) << 8)

                print("Int16 Byte 0: \(int16Byte0)")
                print("Int16 Byte 1 (as MSB): \(int16Byte1)")
                print("Int16 Byte 2: \(int16Byte2)")
                print("Int16 Byte 3 (as MSB): \(int16Byte3)")
                print("Int16 Byte 4: \(int16Byte4)")
                print("Int16 Byte 5 (as MSB): \(int16Byte5)")

            let rawAccelX = Int16(bitPattern: UInt16(bytes[1]) << 8 | UInt16(bytes[0]))
            let rawAccelY = Int16(bitPattern: UInt16(bytes[3]) << 8 | UInt16(bytes[2]))
            let rawAccelZ = Int16(bitPattern: UInt16(bytes[5]) << 8 | UInt16(bytes[4]))

            print("Raw Acceleration Data - X: \(rawAccelX), Y: \(rawAccelY), Z: \(rawAccelZ)")

            let scale = 16384.0 // Replace with the actual sensitivity value for your device
            let accelX = Double(rawAccelX) / scale
            let accelY = Double(rawAccelY) / scale
            let accelZ = Double(rawAccelZ) / scale

            print("Scaled Acceleration Data - X: \(accelX), Y: \(accelY), Z: \(accelZ)")
            
            let threshold: Int16 = 1000 // Adjust this threshold based on your needs

            if rawAccelX == Int16.min || rawAccelY == Int16.min || rawAccelZ == Int16.min {
                print("Warning: Accelerometer saturation detected")
                // Handle the saturation case, e.g., by skipping this reading
                return (0.0, 0.0)
            }
            
            print("Before crash check - rawAccelY: \(rawAccelY), Threshold: \(threshold)")
            if abs(rawAccelY) > abs(rawAccelX) && abs(rawAccelY) > abs(rawAccelZ) && rawAccelY > threshold {
                deviceOrientation = "Standing Up"
            } else if abs(rawAccelY) > abs(rawAccelX) && abs(rawAccelY) > abs(rawAccelZ) && rawAccelY < -threshold {
                deviceOrientation = "Upside Down"
            } else if abs(rawAccelX) > abs(rawAccelY) && abs(rawAccelX) > abs(rawAccelZ) && rawAccelX > threshold {
                deviceOrientation = "Horizontal with Light on Bottom"
            } else if abs(rawAccelX) > abs(rawAccelY) && abs(rawAccelX) > abs(rawAccelZ) && rawAccelX < -threshold {
                deviceOrientation = "Horizontal with Light on Top"
            } else if abs(rawAccelZ) > abs(rawAccelX) && abs(rawAccelZ) > abs(rawAccelY) && rawAccelZ > threshold {
                deviceOrientation = "Laying Flat on Back"
            } else if abs(rawAccelZ) > abs(rawAccelX) && abs(rawAccelZ) > abs(rawAccelY) && rawAccelZ < -threshold {
                deviceOrientation = "Laying Flat on Face"
            } else {
                deviceOrientation = "Unknown Orientation"
            }

            print("Device Orientation: \(deviceOrientation)")
            if let installationOrientation = DocumentManager.shared.currentLMP?.installationOrientation {
                print("Installation Orientation: \(installationOrientation)")
            } else {
                print("Installation Orientation not set or currentLMP is nil.")
            }
            
            // Adjust accelerometer values based on orientation
            var adjustedAccelX = accelX
            var adjustedAccelY = accelY
            var adjustedAccelZ = accelZ
            
            // Get installation orientation
            let installationOrientation = DocumentManager.shared.currentLMP?.installationOrientation ?? .front

            // Adjust the accelerometer values based on device and installation orientation
            if deviceOrientation == "Standing Up" {
                switch installationOrientation {
                case .front, .rear:
                    // Facing front or rear while standing up
                    accelerometerData.pitch = atan2(accelZ, accelY) * (180 / .pi) // Roll around the Y-axis
                    accelerometerData.roll = atan2(accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi) // Pitch around the X-axis
                    if installationOrientation == .front {
                        accelerometerData.pitch *= -1
                    }
                    if installationOrientation == .rear {
                        accelerometerData.roll *= -1
                    }
                case .driversSide, .passengersSide:
                    // Roll calculation remains the same
                    accelerometerData.roll = atan2(accelZ, accelY) * (180 / .pi)

                    // Pitch calculation
                    accelerometerData.pitch = atan2(accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi)

                    // Adjust pitch direction
                    if installationOrientation == .passengersSide {
                       accelerometerData.pitch *= -1 // Invert pitch if necessary, based on the device orientation
                       accelerometerData.roll *= -1
                    }
                }
            } else if deviceOrientation == "Upside Down" {
                // When the device is upside down, invert the axes' values
                switch installationOrientation {
                case .front, .rear:
                    // Inverted from the 'Standing Up' front/rear orientation
                    accelerometerData.pitch = atan2(-accelZ, -accelY) * (180 / .pi) // Inverting both axes for pitch calculation
                    accelerometerData.roll = atan2(-accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi) // Inverting X-axis for roll calculation
                    if installationOrientation == .front {
                       // accelerometerData.pitch *= -1
                    }
                    if installationOrientation == .rear {
                        accelerometerData.pitch *= -1
                        accelerometerData.roll *= -1
                    }

                case .driversSide, .passengersSide:
                    // Inverted from the 'Standing Up' drivers/passengers side orientation
                    accelerometerData.roll = atan2(-accelZ, -accelY) * (180 / .pi) // Inverting both axes for roll calculation

                    // Pitch calculation remains same as 'Standing Up' but inverted
                    accelerometerData.pitch = atan2(-accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi) // Inverting X-axis for pitch calculation

                    if installationOrientation == .passengersSide {
                        accelerometerData.pitch *= -1
                    }
                    if installationOrientation == .driversSide {
                        accelerometerData.roll *= -1
                    }
                }

            } else if deviceOrientation == "Horizontal with Light on Bottom" {
                switch installationOrientation {
                case .front, .rear:
                    // When the device is horizontal with light facing down, facing front or rear
                    accelerometerData.pitch = atan2(accelZ, accelX) * (180 / .pi) // Roll around the Z-axis
                    accelerometerData.roll = atan2(accelY, sqrt(pow(accelX, 2) + pow(accelZ, 2))) * (180 / .pi) // Pitch around the Y-axis
                    if installationOrientation == .front {
                        accelerometerData.pitch *= -1
                        accelerometerData.roll *= -1
                    }
                  

                case .driversSide, .passengersSide:
                    // When the device is horizontal with light facing down, on the side
                    accelerometerData.roll = atan2(accelZ, accelX) * (180 / .pi) // Pitch around the Z-axis
                    accelerometerData.pitch = atan2(accelY, sqrt(pow(accelX, 2) + pow(accelZ, 2))) * (180 / .pi) // Roll around the Y-axis
                    if installationOrientation == .driversSide {
                        accelerometerData.pitch *= -1
                    }
                    if installationOrientation == .passengersSide {
                        accelerometerData.roll *= -1
                    }
                }

            } else if deviceOrientation == "Horizontal with Light on Top" {
                switch installationOrientation {
                case .front, .rear:
                    // When the device is horizontal with light facing up, facing front or rear
                    accelerometerData.pitch = atan2(-accelZ, -accelX) * (180 / .pi) // Roll around the Z-axis, inverted
                    accelerometerData.roll = atan2(-accelY, sqrt(pow(accelX, 2) + pow(accelZ, 2))) * (180 / .pi) // Pitch around the Y-axis, inverted
                    if installationOrientation == .rear {
                        accelerometerData.pitch *= -1
                    }
                    if installationOrientation == .front {
                        accelerometerData.roll *= -1
                    }
    

                case .driversSide, .passengersSide:
                    // When the device is horizontal with light facing up, on the side
                    accelerometerData.roll = atan2(-accelZ, -accelX) * (180 / .pi) // Pitch around the Z-axis, inverted
                    accelerometerData.pitch = atan2(-accelY, sqrt(pow(accelX, 2) + pow(accelZ, 2))) * (180 / .pi) // Roll around the Y-axis, inverted
                    if installationOrientation == .driversSide {
                        accelerometerData.roll *= -1
                        accelerometerData.pitch *= -1
                    }
                   
                }
            } else if deviceOrientation == "Laying Flat on Back" {
                switch installationOrientation {
                case .front, .rear:
                    // When the device is laying flat on its back, facing front or rear
                    // Pitch is determined by Y-axis movement (forward/backward tilt)
                    accelerometerData.roll = atan2(-accelY, accelZ) * (180 / .pi)

                    // Roll is determined by X-axis movement (side-to-side tilt)
                    accelerometerData.pitch = atan2(accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi)

                    if installationOrientation == .front {
                        accelerometerData.pitch *= -1 // Invert pitch for rear orientation
                        accelerometerData.roll *= -1
                    }

                case .driversSide, .passengersSide:
                    // When the device is laying flat on its back, on the side
                    // Pitch is still determined by Y-axis movement
                    accelerometerData.pitch = atan2(-accelY, accelZ) * (180 / .pi)

                    // Roll is still determined by X-axis movement
                    accelerometerData.roll = atan2(accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi)

                    if installationOrientation == .passengersSide {
                        accelerometerData.roll *= -1 // Invert roll for passenger side orientation
                    }
                    if installationOrientation == .driversSide {
                        accelerometerData.pitch *= -1 // Invert roll for passenger side orientation
                    }
                }
            } else if deviceOrientation == "Laying Flat on Face" {
                switch installationOrientation {
                case .front, .rear:
                    // When the device is laying flat on its face, facing front or rear
                    // Pitch is determined by inverted Y-axis movement (forward/backward tilt)
                    accelerometerData.roll = atan2(accelY, -accelZ) * (180 / .pi)

                    // Roll is determined by inverted X-axis movement (side-to-side tilt)
                    accelerometerData.pitch = atan2(-accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi)

                    if installationOrientation == .front {
                        accelerometerData.roll *= -1
                    }
                    if installationOrientation == .rear {
                        accelerometerData.pitch *= -1 // Invert pitch for front orientation
                    }

                case .driversSide, .passengersSide:
                    // When the device is laying flat on its face, on the side
                    // Pitch is still determined by inverted Y-axis movement
                    accelerometerData.pitch = atan2(accelY, -accelZ) * (180 / .pi)

                    // Roll is still determined by inverted X-axis movement
                    accelerometerData.roll = atan2(-accelX, sqrt(pow(accelY, 2) + pow(accelZ, 2))) * (180 / .pi)

                    if installationOrientation == .driversSide {
                        accelerometerData.roll *= -1 // Invert pitch for driver's side orientation
                        accelerometerData.pitch *= -1
                    }
                }
            }

//            switch deviceOrientation {
//            case "Standing Up":
//                // No change needed
//                break
//            case "Upside Down":
//                adjustedAccelY = -accelY
//                adjustedAccelZ = -accelZ
//            case "Horizontal with Light on Bottom":
//                adjustedAccelX = accelY
//                adjustedAccelY = accelX
//            case "Horizontal with Light on Top":
//                adjustedAccelX = -accelY
//                adjustedAccelY = -accelX
//            case "Laying Flat on Face":
//                // Adjustments when lying flat on face
//                adjustedAccelZ = -accelZ
//                break
//            default:
//                break
//            }
            
            // Update pitch and roll calculations with adjusted values
//            accelerometerData.roll = atan2(-adjustedAccelY, sqrt(pow(adjustedAccelX, 2) + pow(adjustedAccelZ, 2))) * (180 / Double.pi)
//            accelerometerData.pitch = atan2(adjustedAccelZ, sqrt(pow(adjustedAccelY, 2) + pow(adjustedAccelX, 2))) * (180 / Double.pi)

            print("Calculated from Accelerometer - Roll: \(accelerometerData.roll) degrees, Pitch: \(accelerometerData.pitch) degrees")

            if !isGyroInitialized {
                gyroscopeData.roll = accelerometerData.roll
                gyroscopeData.pitch = accelerometerData.pitch
                isGyroInitialized = true
            }
        }

        return (accelerometerData.pitch, accelerometerData.roll)
    }

    func decodeOrientationData(_ data: Data) -> (pitch: Double, roll: Double, frontHeight: Double, sideHeight: Double) {
        guard isGyroInitialized, data.count >= 6 else {
            return (0, 0, 0, 0)
        }

        let bytes = [UInt8](data)
        if bytes.count >= 6 {
            // Scaling gyroscope data by dividing by 131
            var gyroX = Double(Int16(bytes[0]) | Int16(bytes[1]) << 8) / 131.0
            var gyroY = Double(Int16(bytes[2]) | Int16(bytes[3]) << 8) / 131.0
            var gyroZ = Double(Int16(bytes[4]) | Int16(bytes[5]) << 8) / 131.0
            print("Raw Gyroscope Data - X: \(gyroX), Y: \(gyroY), Z: \(gyroZ)")
            print("Current Timestamp: \(Date())")
            
            let installationOrientation = DocumentManager.shared.currentLMP?.installationOrientation ?? .front

                // Adjust the gyroscope values based on device and installation orientation
                if deviceOrientation == "Standing Up" {
                    switch installationOrientation {
                    case .front, .rear:
                        // For gyro data when the device is standing up facing front or rear
                        gyroscopeData.pitch = atan2(gyroZ, gyroY) * (180 / .pi) // Roll around Y-axis
                        gyroscopeData.roll = atan2(gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Pitch around X-axis

                        if installationOrientation == .front {
                            gyroscopeData.pitch *= -1
                        }
                        if installationOrientation == .rear {
                            gyroscopeData.roll *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.roll = atan2(gyroZ, gyroY) * (180 / .pi) // Roll remains the same
                        gyroscopeData.pitch = atan2(gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Pitch remains the same

                        if installationOrientation == .passengersSide {
                            gyroscopeData.pitch *= -1
                            gyroscopeData.roll *= -1
                        }
                    }
                } else if deviceOrientation == "Upside Down" {
                    switch installationOrientation {
                    case .front, .rear:
                        gyroscopeData.pitch = atan2(-gyroZ, -gyroY) * (180 / .pi) // Invert both axes for pitch
                        gyroscopeData.roll = atan2(-gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Invert X-axis for roll

                        if installationOrientation == .front {
                            // Adjust if necessary
                        }
                        if installationOrientation == .rear {
                            gyroscopeData.pitch *= -1
                            gyroscopeData.roll *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.roll = atan2(-gyroZ, -gyroY) * (180 / .pi) // Invert both axes for roll
                        gyroscopeData.pitch = atan2(-gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Invert X-axis for pitch

                        if installationOrientation == .passengersSide {
                            gyroscopeData.pitch *= -1
                        }
                        if installationOrientation == .driversSide {
                            gyroscopeData.roll *= -1
                        }
                    }
                } else if deviceOrientation == "Horizontal with Light on Bottom" {
                    switch installationOrientation {
                    case .front, .rear:
                        gyroscopeData.pitch = atan2(gyroX, gyroZ) * (180 / .pi) // Roll around Z-axis
                        gyroscopeData.roll = atan2(gyroY, sqrt(pow(gyroX, 2) + pow(gyroZ, 2))) * (180 / .pi) // Pitch around Y-axis

                        if installationOrientation == .front {
                            gyroscopeData.roll *= -1
                        }
                        if installationOrientation == .rear {
                            gyroscopeData.roll *= -1
                            gyroscopeData.pitch *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.roll = atan2(gyroX, gyroZ) * (180 / .pi) // Pitch around Z-axis
                        gyroscopeData.pitch = atan2(gyroY, sqrt(pow(gyroX, 2) + pow(gyroZ, 2))) * (180 / .pi) // Roll around Y-axis

                        if installationOrientation == .driversSide {
                            gyroscopeData.pitch *= -1
                            gyroscopeData.roll *= -1
                        }
                    }
                } else if deviceOrientation == "Horizontal with Light on Top" {
                    switch installationOrientation {
                    case .front, .rear:
                        gyroscopeData.pitch = atan2(-gyroX, -gyroZ) * (180 / .pi) // Roll around Z-axis, inverted
                        gyroscopeData.roll = atan2(-gyroY, sqrt(pow(gyroX, 2) + pow(gyroZ, 2))) * (180 / .pi) // Pitch around Y-axis, inverted

                        if installationOrientation == .front {
                            gyroscopeData.roll *= -1
                            gyroscopeData.pitch *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.roll = atan2(-gyroX, -gyroZ) * (180 / .pi) // Pitch around Z-axis, inverted
                        gyroscopeData.pitch = atan2(-gyroY, sqrt(pow(gyroX, 2) + pow(gyroZ, 2))) * (180 / .pi) // Roll around Y-axis, inverted

                        if installationOrientation == .driversSide {
                            gyroscopeData.pitch *= -1
                        }
                        if installationOrientation == .passengersSide {
                            gyroscopeData.roll *= -1
                        }
                    }
                } else if deviceOrientation == "Laying Flat on Back" {
                    switch installationOrientation {
                    case .front, .rear:
                        gyroscopeData.roll = atan2(-gyroY, gyroZ) * (180 / .pi) // Pitch based on Y-axis
                        gyroscopeData.pitch = atan2(gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Roll based on X-axis

                        if installationOrientation == .front {
                            gyroscopeData.pitch *= -1
                            gyroscopeData.roll *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.pitch = atan2(-gyroY, gyroZ) * (180 / .pi) // Pitch remains same
                        gyroscopeData.roll = atan2(gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Roll remains same

                        if installationOrientation == .passengersSide {
                            gyroscopeData.roll *= -1
                        }
                        if installationOrientation == .driversSide {
                            gyroscopeData.pitch *= -1
                        }
                    }
                } else if deviceOrientation == "Laying Flat on Face" {
                    switch installationOrientation {
                    case .front, .rear:
                        gyroscopeData.roll = atan2(gyroY, -gyroZ) * (180 / .pi) // Inverted pitch
                        gyroscopeData.pitch = atan2(-gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Inverted roll

                        if installationOrientation == .front {
                            gyroscopeData.roll *= -1
                        }
                        if installationOrientation == .rear {
                            gyroscopeData.pitch *= -1
                        }
                        
                    case .driversSide, .passengersSide:
                        gyroscopeData.pitch = atan2(gyroY, -gyroZ) * (180 / .pi) // Inverted pitch remains
                        gyroscopeData.roll = atan2(-gyroX, sqrt(pow(gyroY, 2) + pow(gyroZ, 2))) * (180 / .pi) // Inverted roll remains

                        if installationOrientation == .driversSide {
                            gyroscopeData.roll *= -1
                        }
                    }
                }
            
            
            // Adjust gyroscope data based on the orientation
//            switch deviceOrientation {
// 
//            case "Upside Down":
//                // Adjustments when the device is upside down
//                gyroY = -gyroY
//                gyroZ = -gyroZ
//
//            case "Horizontal with Light on Bottom":
//                // Adjustments when the device is horizontal with light on bottom
//                swap(&gyroX, &gyroY)
//                gyroY = -gyroY
//
//            case "Horizontal with Light on Top":
//                // Adjustments when the device is horizontal with light on top
//                swap(&gyroX, &gyroY)
//                gyroX = -gyroX
//                gyroY = -gyroY
//                
//            case "Laying Flat on Face":
//                // Adjustments when the device is laying flat on face
//                gyroZ = -gyroZ
//
//            default:
//                break
//            }

            let currentTime = Date()
            let deltaTime = currentTime.timeIntervalSince(gyroscopeData.lastUpdateTime)
            gyroscopeData.lastUpdateTime = currentTime

            // Update gyroscope data by integrating over time
            gyroscopeData.roll += gyroX * deltaTime
            gyroscopeData.pitch += gyroY * deltaTime

            // Complementary filter to combine accelerometer and gyroscope data
            let alpha = 0.00 // Alpha value can be adjusted between 0 and 1
            gyroscopeData.roll = alpha * gyroscopeData.roll + (1 - alpha) * accelerometerData.roll
            gyroscopeData.pitch = alpha * gyroscopeData.pitch + (1 - alpha) * accelerometerData.pitch
            print("Updated from Gyroscope - Roll: \(gyroscopeData.roll) degrees, Pitch: \(gyroscopeData.pitch) degrees")

            // Apply complementary filter
            return calculateFusedPitchAndRoll()
        } else {
            return (0, 0, 0, 0)
        }
    }
    
//    func decodeOrientationData(_ data: Data) -> (pitch: Double, roll: Double, frontHeight: Double, sideHeight: Double) {
//        // Ensure gyroscope is initialized
//        guard isGyroInitialized else {
//            print("Gyroscope not initialized yet")
//            return (0, 0, 0, 0)
//        }
//
//        let bytes = [UInt8](data)
//        if bytes.count >= 6 {
//            // Scaling gyroscope data by dividing by 131
//            let gyroX = Double(Int16(bytes[0]) | Int16(bytes[1]) << 8) / 131.0
//            let gyroY = Double(Int16(bytes[2]) | Int16(bytes[3]) << 8) / 131.0
//            let gyroZ = Double(Int16(bytes[4]) | Int16(bytes[5]) << 8) / 131.0
//            print("Raw Gyroscope Data - X: \(gyroX), Y: \(gyroY), Z: \(gyroZ)")
//
//            let currentTime = Date()
//            let dt = currentTime.timeIntervalSince(gyroscopeData.lastUpdateTime)
//            gyroscopeData.lastUpdateTime = currentTime
//
//            print("Gyro Integration - dt: \(dt) seconds")
//
//            // Update gyroscope data
//            gyroscopeData.roll += gyroX * dt
//            gyroscopeData.pitch += gyroY * dt
//            print("Updated from Gyroscope - Roll: \(gyroscopeData.roll) degrees, Pitch: \(gyroscopeData.pitch) degrees")
//
//            return calculateFusedPitchAndRoll()
//        } else {
//            return (0, 0, 0, 0)
//        }
//    }

    func calculateFusedPitchAndRoll() -> (pitch: Double, roll: Double, frontHeight: Double, sideHeight: Double) {
        // Complementary filter coefficient
        let r1 = 0.96
        let r2 = 1 - r1

        // Print both accelerometer and gyroscope roll values before fusion
        print("Accelerometer Roll: \(accelerometerData.roll)")
        print("Gyroscope Roll: \(gyroscopeData.roll)")
        print("Accelerometer Pitch: \(accelerometerData.pitch)")
        print("Gyroscope Pitch: \(gyroscopeData.pitch)")

        // Fused roll and pitch in degrees
        var fusedRoll = r1 * accelerometerData.roll + r2 * gyroscopeData.roll
        var fusedPitch = r1 * accelerometerData.pitch + r2 * gyroscopeData.pitch

        // Print the fused values in degrees
        print("Fused Roll: \(fusedRoll) degrees")
        print("Fused Pitch: \(fusedPitch) degrees")

        tempCalibrationData.rollDegree = fusedRoll
        tempCalibrationData.pitchDegree = fusedPitch

        // Convert fused angles to radians for level offset calculation
        let fusedRollRadians = fusedRoll * .pi / 180
        let fusedPitchRadians = fusedPitch * .pi / 180

        if isDeviceCalibrated {
            fusedRoll -= calibrationData.rollDegree
            fusedPitch -= calibrationData.pitchDegree
        }

        print("Fused Roll in Radians: \(fusedRollRadians)")
        print("Fused Pitch in Radians: \(fusedPitchRadians)")


        // Example usage:
        let lengthToJack: Double = Double(DocumentManager.shared.currentLMP?.trailer?.length ?? "240") ?? 240 // The length from center of rear wheel to jack in inches
        
        let width: Double = Double(DocumentManager.shared.currentLMP?.trailer?.width ?? "96") ?? 96 // The width of the trailer from outside to outside of the tires in inches

        var data = UserDefaultsHelper.shared.localSaveFile.toLocalSaveFile()
        let row = data?.deviceLocation?.row ?? 0
        let column = data?.deviceLocation?.column ?? 0

        print("Device Location: \(data?.deviceLocation)")

//        let distanceFromJack: Double = lengthToJack / 2 // The distance of the device from the jack in inches
//        let distanceFromRearRightWheel: Double = 20 // The distance from the device to the center rear right wheel in inches
//        let distanceFromLeftWheel: Double = width - 20 // The distance from the device to the center left wheel in inches
        
        // Grid dimensions
        let gridLength = 22  // Length of the grid (front to back of the camper)
        let gridWidth = 10   // Width of the grid

        // Calculate the size of each tile in inches
        let tileLength = lengthToJack / Double(gridLength)  // Length of each tile
        let tileWidth = width / Double(gridWidth)  // Width of each tile

        // Convert grid location to actual distance in inches
        var distanceFromJack = tileLength * Double(row)  // Distance from rear wheel to device
        distanceFromJack += 48 // add an average of 4 feet for the tongue length of the camper
        
        
        // Calculate distances from the rear wheels to the device location in terms of grid
        let distanceXFromRearWheel = tileLength * Double(gridLength - row) // Horizontal distance from the rear wheel to the device
        let distanceYFromRightWheel = tileWidth * Double(column) // Vertical distance from the right wheel to the device
        let distanceYFromLeftWheel = width - distanceYFromRightWheel // Vertical distance from the left wheel to the device

        // Calculate diagonal distances using Pythagorean theorem
        let distanceFromRearRightWheel = distanceYFromRightWheel
        let distanceFromRearLeftWheel = distanceYFromLeftWheel
        //        let distanceFromRearRightWheel = sqrt(pow(distanceXFromRearWheel, 2) + pow(distanceYFromRightWheel, 2))
        //        let distanceFromRearLeftWheel = sqrt(pow(distanceXFromRearWheel, 2) + pow(distanceYFromLeftWheel, 2))

        print("Distance from Jack: \(distanceFromJack) inches")
        print("Distance from Rear Right Wheel: \(distanceFromRearRightWheel) inches")
        print("Distance from Left Wheel: \(distanceFromRearLeftWheel) inches")
        
        
        let orientation: InstallationOrientation = DocumentManager.shared.currentLMP?.installationOrientation ?? .driversSide // The device orientation


        let height = calculateLevelOffsets(
            lengthToJack: lengthToJack,
            width: width,
            distanceFromJack: distanceFromJack,
            distanceFromRearRightWheel: distanceFromRearRightWheel,
            distanceFromLeftWheel: distanceFromRearLeftWheel,
            orientation: orientation,
            pitchRadians: fusedPitchRadians,
            rollRadians: fusedRollRadians
        )
        
        return (fusedPitch, fusedRoll, height.frontHeight, height.sideHeight)
    }

    func calculateLevelOffsets(
        lengthToJack: Double,
        width: Double,
        distanceFromJack: Double,
        distanceFromRearRightWheel: Double,
        distanceFromLeftWheel: Double,
        orientation: InstallationOrientation,
        pitchRadians: Double,
        rollRadians: Double
    ) -> (frontHeight: Double, sideHeight: Double) {

        // Calculate the offsets based on the orientation of the device
        var pitchOffset: Double
        var rollOffset: Double
        
        // Calculate the total span from left to right wheel
        let totalWidth = distanceFromLeftWheel + distanceFromRearRightWheel

        // Determine the effective width for roll calculation based on device placement
        let effectiveWidth = (distanceFromLeftWheel - distanceFromRearRightWheel).magnitude / 2

        switch orientation {
        case .front:
            pitchOffset = distanceFromJack * tan(pitchRadians) // Front-to-Back (interpreted as Pitch)
            rollOffset = effectiveWidth * tan(rollRadians) // Side-to-Side (interpreted as Roll)
        case .rear:
            pitchOffset = -distanceFromJack * tan(pitchRadians) // Front-to-Back (interpreted as Pitch), reversed
            rollOffset = effectiveWidth * tan(rollRadians) // Side-to-Side (interpreted as Roll)
        case .driversSide:
            rollOffset = effectiveWidth * tan(rollRadians) // Side-to-Side (interpreted as Pitch)
            pitchOffset = lengthToJack * tan(pitchRadians) // Front-to-Back (interpreted as Roll)
        case .passengersSide:
            rollOffset = effectiveWidth * tan(rollRadians) // Side-to-Side (interpreted as Pitch)
            pitchOffset = -lengthToJack * tan(pitchRadians) // Front-to-Back (interpreted as Roll), reversed
        }

        // Output the result
        print("Offset from level in inches (Pitch): \(pitchOffset)")
        print("Offset from level in inches (Roll): \(rollOffset)")

        tempCalibrationData.pitch = pitchOffset
        tempCalibrationData.roll = rollOffset

        // Apply calibration offset if device is calibrated
        if isDeviceCalibrated {
            rollOffset -= calibrationData.roll
            pitchOffset -= calibrationData.pitch
        }

        return (pitchOffset, rollOffset)
    }
}

extension CharacteristicMapper {
    // Add method to start calibration
    func startCalibration() {
        // Ensure the device is in a known level state here before calling this method
        // Reset calibration data to current sensor readings
        calibrationData = tempCalibrationData
        // Set the flag to indicate that the device has been calibrated
        isDeviceCalibrated = true

        var data = UserDefaultsHelper.shared.localSaveFile.toLocalSaveFile()
        data?.calibrationData = calibrationData
        UserDefaultsHelper.shared.localSaveFile = data?.toString() ?? ""
    }
    
}
