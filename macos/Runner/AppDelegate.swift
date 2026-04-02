import Cocoa
import FlutterMacOS
import IOKit.hid

private struct AccelerationSample {
  let timestamp: TimeInterval
  let magnitude: Double
  let highPassMagnitude: Double
}

private final class AccelerometerReader {
  private var hidManager: IOHIDManager?
  private var reportBuffers: [UnsafeMutableRawPointer: UnsafeMutablePointer<UInt8>] = [:]

  var onSample: ((Double, Double, Double, TimeInterval) -> Void)?

  func start() -> Bool {
    stop()

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDProductKey as String: "AppleSPUHIDDevice"
    ]

    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.handleDeviceMatched, Self.bridge(self))

    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      return false
    }

    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    hidManager = manager
    return true
  }

  func stop() {
    for (_, buffer) in reportBuffers {
      buffer.deallocate()
    }
    reportBuffers.removeAll()

    if let manager = hidManager {
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    hidManager = nil
  }

  private func registerReportCallback(for device: IOHIDDevice) {
    let bufferSize = 64
    let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    reportBuffer.initialize(repeating: 0, count: bufferSize)
    reportBuffers[deviceKey(device)] = reportBuffer

    IOHIDDeviceRegisterInputReportCallback(
      device,
      reportBuffer,
      bufferSize,
      Self.handleInputReport,
      Self.bridge(self)
    )

    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
  }

  private func handleReport(_ report: UnsafeMutablePointer<UInt8>?, length: CFIndex) {
    guard let report = report, length >= 22 else {
      return
    }

    let xRaw = readInt32(from: report, offset: 0)
    let yRaw = readInt32(from: report, offset: 4)
    let zRaw = readInt32(from: report, offset: 8)

    let x = Double(xRaw) / 65536.0
    let y = Double(yRaw) / 65536.0
    let z = Double(zRaw) / 65536.0

    onSample?(x, y, z, CFAbsoluteTimeGetCurrent())
  }

  private func readInt32(from report: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
    let b0 = UInt32(report[offset])
    let b1 = UInt32(report[offset + 1]) << 8
    let b2 = UInt32(report[offset + 2]) << 16
    let b3 = UInt32(report[offset + 3]) << 24
    return Int32(bitPattern: b0 | b1 | b2 | b3)
  }

  private func deviceKey(_ device: IOHIDDevice) -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(device).toOpaque()
  }

  private static func bridge(_ object: AccelerometerReader) -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(object).toOpaque()
  }

  private static func unbridge(_ pointer: UnsafeMutableRawPointer?) -> AccelerometerReader? {
    guard let pointer = pointer else {
      return nil
    }
    return Unmanaged<AccelerometerReader>.fromOpaque(pointer).takeUnretainedValue()
  }

  private static let handleDeviceMatched: IOHIDDeviceCallback = { context, _, _, device in
    guard let reader = unbridge(context) else {
      return
    }
    reader.registerReportCallback(for: device)
  }

  private static let handleInputReport: IOHIDReportCallback = {
    context,
    _,
    _,
    _,
    _,
    report,
    reportLength in
    guard let reader = unbridge(context) else {
      return
    }
    reader.handleReport(report, length: reportLength)
  }
}

private final class SlapDetector {
  private var gravityMagnitude = 1.0
  private var samples: [AccelerationSample] = []
  private var cusumValue = 0.0
  private var baselineHpMean = 0.0
  private var baselineCount = 0
  private var lastTriggerTs = 0.0

  func process(x: Double, y: Double, z: Double, timestamp: TimeInterval) -> Bool {
    let magnitude = sqrt((x * x) + (y * y) + (z * z))

    let alpha = 0.92
    gravityMagnitude = (alpha * gravityMagnitude) + ((1.0 - alpha) * magnitude)
    let hp = abs(magnitude - gravityMagnitude)

    let sample = AccelerationSample(timestamp: timestamp, magnitude: magnitude, highPassMagnitude: hp)
    samples.append(sample)

    if samples.count > 80 {
      samples.removeFirst(samples.count - 80)
    }

    updateBaseline(highPassMagnitude: hp)

    let votes = [
      highPassVote(hp),
      staLtaVote(),
      cusumVote(hp),
      kurtosisVote(),
      peakMadVote(hp)
    ].filter { $0 }.count

    let cooldown = 0.45
    if votes >= 3 && (timestamp - lastTriggerTs) > cooldown {
      lastTriggerTs = timestamp
      return true
    }

    return false
  }

  private func updateBaseline(highPassMagnitude hp: Double) {
    baselineCount += 1
    let learningRate = baselineCount < 30 ? 0.2 : 0.03
    baselineHpMean = ((1.0 - learningRate) * baselineHpMean) + (learningRate * hp)
  }

  private func highPassVote(_ hp: Double) -> Bool {
    let threshold = max(0.08, baselineHpMean * 3.6)
    return hp > threshold
  }

  private func staLtaVote() -> Bool {
    guard samples.count >= 30 else {
      return false
    }

    let shortWindows = [3, 5, 8]
    let longWindows = [18, 24, 30]

    var triggered = 0
    for (shortW, longW) in zip(shortWindows, longWindows) {
      guard samples.count >= longW else { continue }

      let shortSlice = samples.suffix(shortW).map { $0.highPassMagnitude }
      let longSlice = samples.suffix(longW).map { $0.highPassMagnitude }

      let shortAvg = shortSlice.reduce(0, +) / Double(shortSlice.count)
      let longAvg = max(0.00001, longSlice.reduce(0, +) / Double(longSlice.count))

      if (shortAvg / longAvg) > 2.2 {
        triggered += 1
      }
    }

    return triggered >= 2
  }

  private func cusumVote(_ hp: Double) -> Bool {
    let reference = max(0.015, baselineHpMean)
    cusumValue = max(0.0, cusumValue + (hp - reference))

    let threshold = max(0.18, baselineHpMean * 7.0)
    if cusumValue > threshold {
      cusumValue = 0.0
      return true
    }

    return false
  }

  private func kurtosisVote() -> Bool {
    let window = 20
    guard samples.count >= window else {
      return false
    }

    let magnitudes = samples.suffix(window).map { $0.highPassMagnitude }
    let mean = magnitudes.reduce(0, +) / Double(window)

    let variance = magnitudes
      .map { ($0 - mean) * ($0 - mean) }
      .reduce(0, +) / Double(window)

    let std = sqrt(max(variance, 0.000001))
    let fourthMoment = magnitudes
      .map { pow(($0 - mean) / std, 4) }
      .reduce(0, +) / Double(window)

    return fourthMoment > 5.0
  }

  private func peakMadVote(_ hp: Double) -> Bool {
    let window = 25
    guard samples.count >= window else {
      return false
    }

    let values = samples.suffix(window).map { $0.highPassMagnitude }.sorted()
    let median = values[values.count / 2]

    let deviations = values.map { abs($0 - median) }.sorted()
    let mad = max(0.000001, deviations[deviations.count / 2])

    let modifiedZ = 0.6745 * (hp - median) / mad
    return modifiedZ > 5.5
  }
}

@NSApplicationMain
class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let methodChannelName = "slapmac/monitoring"
  private let eventChannelName = "slapmac/events"

  private var eventSink: FlutterEventSink?
  private let accelerometerReader = AccelerometerReader()
  private let slapDetector = SlapDetector()
  private var monitoringEnabled = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate unavailable", details: nil))
        return
      }

      switch call.method {
      case "startMonitoring":
        let started = self.startSlapMonitoring()
        result(["started": started])
      case "stopMonitoring":
        self.stopSlapMonitoring()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    eventChannel.setStreamHandler(self)

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationWillTerminate(_ notification: Notification) {
    stopSlapMonitoring()
    super.applicationWillTerminate(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func startSlapMonitoring() -> Bool {
    if monitoringEnabled {
      return true
    }

    accelerometerReader.onSample = { [weak self] x, y, z, ts in
      guard let self = self else {
        return
      }

      if self.slapDetector.process(x: x, y: y, z: z, timestamp: ts) {
        self.eventSink?("Chassis slap")
      }
    }

    monitoringEnabled = accelerometerReader.start()
    return monitoringEnabled
  }

  private func stopSlapMonitoring() {
    accelerometerReader.stop()
    monitoringEnabled = false
  }
}
