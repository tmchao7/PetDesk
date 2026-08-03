import CoreGraphics
import Foundation
import ImageIO
import PetDeskCore
import UniformTypeIdentifiers
import Vision

private struct CheckFailure: Error, CustomStringConvertible {
  let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw CheckFailure(description: message) }
}

private func makeSolidImage(
  width: Int,
  height: Int,
  color: (r: CGFloat, g: CGFloat, b: CGFloat)
) -> CGImage? {
  let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo.rawValue
    )
  else { return nil }
  context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  return context.makeImage()
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
  guard
    let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
    let context = CGContext(
      data: nil,
      width: 1,
      height: 1,
      bitsPerComponent: 8,
      bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    let data = context.data
  else { return (0, 0, 0, 0) }
  context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
  let bytes = data.bindMemory(to: UInt8.self, capacity: 4)
  return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
}

private func makePNGData(width: Int, height: Int, color: (r: CGFloat, g: CGFloat, b: CGFloat))
  -> Data?
{
  guard let image = makeSolidImage(width: width, height: height, color: color) else { return nil }
  let data = NSMutableData()
  guard
    let destination = CGImageDestinationCreateWithData(
      data,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else { return nil }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { return nil }
  return data as Data
}

private func makePosePNGData() -> Data? {
  let size = 256
  let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo.rawValue
    )
  else { return nil }
  context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: size, height: size))
  context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
  context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
  guard let image = context.makeImage() else { return nil }
  let data = NSMutableData()
  guard
    let destination = CGImageDestinationCreateWithData(
      data,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else { return nil }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { return nil }
  return data as Data
}

private func requestBodyData(_ request: URLRequest) -> Data {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
    let read = stream.read(&buffer, maxLength: buffer.count)
    if read <= 0 { break }
    data.append(buffer, count: read)
  }
  return data
}

/// 测试用 URLProtocol：捕获请求并返回预设响应，避免真实网络。
private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (Int, Data))?
  nonisolated(unsafe) private static var captured: [URLRequest] = []
  private static let lock = NSLock()

  static func install(handler: @escaping (URLRequest) throws -> (Int, Data)) {
    lock.lock()
    defer { lock.unlock() }
    self.handler = handler
    captured = []
  }

  static func capturedRequests() -> [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return captured
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    MockURLProtocol.lock.lock()
    let handler = MockURLProtocol.handler
    MockURLProtocol.lock.unlock()
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (statusCode, body) = try handler(request)
      MockURLProtocol.lock.lock()
      MockURLProtocol.captured.append(request)
      MockURLProtocol.lock.unlock()
      guard
        let url = request.url,
        let response = HTTPURLResponse(
          url: url,
          statusCode: statusCode,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badURL))
        return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private func feed(cpu: Double, seconds: Int, to machine: inout PetStateMachine) {
  for _ in 0..<seconds {
    machine.reduce(
      .systemMetrics(SystemMetrics(cpuLoad: cpu, thermalLevel: .nominal)),
      elapsed: .seconds(1)
    )
  }
}

private func checkStateMachine() throws {
  var normal = PetStateMachine()
  feed(cpu: 0.50, seconds: 10, to: &normal)
  try expect(normal.snapshot.baseState == .working, "normal CPU should enter working")

  var busy = PetStateMachine()
  feed(cpu: 0.70, seconds: 15, to: &busy)
  try expect(busy.snapshot.baseState == .jogging, "busy CPU should enter jogging")
  feed(cpu: 0.58, seconds: 20, to: &busy)
  try expect(busy.snapshot.baseState == .jogging, "hysteresis should prevent flapping")

  var hot = PetStateMachine()
  feed(cpu: 0.90, seconds: 15, to: &hot)
  try expect(hot.snapshot.baseState == .running, "hot CPU should enter running")
  hot.reduce(.userIdleChanged(.seconds(301)), elapsed: .zero)
  try expect(hot.snapshot.baseState == .sleeping, "idle should override CPU")
  hot.reduce(.focusCommand(.start), elapsed: .zero)
  try expect(hot.snapshot.baseState == .focusing, "focus should override idle")

  var transient = PetStateMachine()
  transient.reduce(.notificationPulse(.wechat), elapsed: .zero)
  transient.reduce(.tick(.seconds(2)), elapsed: .seconds(2))
  try expect(transient.snapshot.transientState == .startled(.wechat), "startle ended too early")
  transient.reduce(.tick(.milliseconds(500)), elapsed: .milliseconds(500))
  try expect(transient.snapshot.transientState == nil, "startle did not expire")

  var thermal = PetStateMachine()
  thermal.reduce(
    .systemMetrics(SystemMetrics(cpuLoad: 0.10, thermalLevel: .critical)),
    elapsed: .seconds(1)
  )
  try expect(thermal.snapshot.effects.contains(.smoke), "critical thermal state should add smoke")

  var sleeping = PetStateMachine()
  sleeping.reduce(.userIdleChanged(.seconds(301)), elapsed: .zero)
  try expect(sleeping.snapshot.baseState == .sleeping, "idle timeout should enter sleeping")
  try expect(sleeping.snapshot.effects == [.zzz], "sleeping state should have zzz effect")

  var activity = PetStateMachine()
  activity.reduce(.focusCommand(.showActivityReminder), elapsed: .zero)
  try expect(activity.snapshot.transientState == .stretching, "activity reminder should stretch")
  try expect(activity.snapshot.bubble == .stretchReminder, "activity reminder should show a bubble")
  activity.reduce(.focusCommand(.snoozeActivity), elapsed: .zero)
  try expect(
    activity.snapshot.transientState == nil && activity.snapshot.bubble == nil,
    "snooze should clear reminder")
}

private func checkCoreServices() throws {
  var calculator = CPULoadCalculator()
  try expect(
    calculator.record(CPUTicks(user: 100, system: 100, idle: 200, nice: 0)) == nil,
    "first CPU sample must establish baseline")
  let load = calculator.record(CPUTicks(user: 150, system: 150, idle: 300, nice: 0))
  try expect(abs((load ?? -1) - 0.5) < 0.0001, "CPU load should use tick deltas")
  try expect(
    calculator.record(CPUTicks(user: 10, system: 10, idle: 20, nice: 0)) == nil,
    "CPU rollback should reset baseline")

  var idleCalc = CPULoadCalculator()
  _ = idleCalc.record(CPUTicks(user: 0, system: 0, idle: 1_000, nice: 0))
  let idleLoad = idleCalc.record(CPUTicks(user: 0, system: 0, idle: 2_000, nice: 0))
  if let load = idleLoad {
    try expect(abs(load - 0.0) < 0.0001, "idle CPU should return zero load")
  } else {
    throw CheckFailure(description: "idle CPU should return a non-nil load")
  }

  var focus = FocusSession(duration: .seconds(120), idlePauseAfter: .seconds(60))
  focus.start()
  focus.advance(by: .seconds(30), userIdle: .seconds(90))
  try expect(focus.remaining == .seconds(120), "idle focus time should not count")
  focus.advance(by: .seconds(120), userIdle: .zero)
  try expect(focus.phase == .completed, "active focus time should complete session")

  var reminder = ActivityReminderAccumulator(remindAfter: .seconds(3_600), snoozeFor: .seconds(600))
  reminder.advance(by: .seconds(3_600), userIdle: .zero)
  try expect(reminder.isDue, "activity reminder should become due")
  reminder.snooze()
  reminder.advance(by: .seconds(600), userIdle: .zero)
  try expect(reminder.isDue, "snoozed activity reminder should return")

  reminder.acknowledgeBreak()
  try expect(!reminder.isDue, "acknowledgeBreak should clear isDue")
  try expect(reminder.activeElapsed < .seconds(1), "acknowledgeBreak should reset activeElapsed")
  reminder.advance(by: .seconds(3_599), userIdle: .zero)
  try expect(!reminder.isDue, "reminder should not be due after partial re-accumulation")

  let avatarPolicy = AvatarImportPolicy()
  do {
    try avatarPolicy.validate(byteCount: 20 * 1_024 * 1_024 + 1, fileExtension: "png")
    throw CheckFailure(description: "oversized avatar was accepted")
  } catch AvatarImportError.fileTooLarge {
  }
  try avatarPolicy.validate(byteCount: 1_024, fileExtension: "heic")

  let clamped = ScreenPositionResolver.clamped(
    frame: CGRect(x: 1_200, y: -300, width: 180, height: 180),
    visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
  )
  try expect(clamped.origin == CGPoint(x: 820, y: 0), "window frame should be clamped")

  var deduplicator = NotificationPulseDeduplicator(cooldown: .seconds(3))
  try expect(deduplicator.shouldEmit(source: .wechat, at: .zero), "first notification should emit")
  try expect(
    !deduplicator.shouldEmit(source: .wechat, at: .seconds(2)),
    "duplicate notification should be dropped")
  try expect(
    deduplicator.shouldEmit(source: .qq, at: .seconds(2)),
    "different notification source should emit")

  var buffer = RingBuffer<Int>(capacity: 3)
  for value in 1...4 { buffer.append(value) }
  try expect(buffer.values == [2, 3, 4], "ring buffer should retain newest values")

  let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
  guard
    let ctx = CGContext(
      data: nil, width: 100, height: 80, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo.rawValue),
    let testImage = ctx.makeImage()
  else {
    throw CheckFailure(description: "could not create test CGImage")
  }
  let cropped = AvatarCropper.crop(
    image: testImage, viewSize: 50, panOffset: .zero, zoomScale: 1.0, outputSize: 32)
  try expect(cropped != nil, "AvatarCropper should produce a cropped image")
  try expect(cropped?.width == 32, "cropped width should match outputSize")
  try expect(cropped?.height == 32, "cropped height should match outputSize")

  try expect(
    AvatarDisplayMode.circle.rawValue == "circle",
    "circle display mode raw value should be 'circle'")
  try expect(
    AvatarDisplayMode(rawValue: "original") == .original,
    "raw value 'original' should produce original mode")
  try expect(
    AvatarDisplayMode(rawValue: "invalid") == nil,
    "invalid raw value should produce nil")
}

private func checkSpriteSheetEyeBand() throws {
  guard
    let base = makeSolidImage(width: 192, height: 192, color: (0.4, 0.6, 0.8)),
    let sheet = SpriteSheetGenerator.generate(
      from: base,
      eyeBandInSource: CGRect(x: 12, y: 24, width: 48, height: 12)
    )
  else {
    throw CheckFailure(description: "could not generate sheet with custom eye band")
  }
  let idleFrame = PetAnimState(row: .idle).frameRect(index: 0)
  guard
    let blinkFrame = sheet.cropping(
      to: CGRect(
        x: idleFrame.minX + 2 * 192, y: idleFrame.minY, width: 192, height: 208)),
    let plainFrame = sheet.cropping(
      to: CGRect(x: idleFrame.minX, y: idleFrame.minY, width: 192, height: 208))
  else {
    throw CheckFailure(description: "could not crop idle frames")
  }
  // 帧内坐标：位图/裁剪以视觉顶部为 y=0；遮罩在 CG 坐标中为 y 24..36，
  // 对应视觉行 208-36..208-24 = 172..184，取中心 (36,178)。
  let plainPx = pixel(plainFrame, x: 36, y: 178)
  let customBandPx = pixel(blinkFrame, x: 36, y: 178)
  try expect(
    abs(customBandPx.r - plainPx.r) > 20,
    "blink frame should tint the custom eye band")
  let defaultBandPx = pixel(blinkFrame, x: 96, y: 143)
  try expect(
    abs(defaultBandPx.r - plainPx.r) < 10,
    "custom eye band should move the blink overlay away from the default band")

  guard let fallbackSheet = SpriteSheetGenerator.generate(from: base),
    let fallbackBlink = fallbackSheet.cropping(
      to: CGRect(
        x: idleFrame.minX + 2 * 192, y: idleFrame.minY, width: 192, height: 208))
  else {
    throw CheckFailure(description: "could not generate fallback sheet")
  }
  let fallbackPx = pixel(fallbackBlink, x: 96, y: 143)
  let fallbackPlain = pixel(plainFrame, x: 96, y: 143)
  try expect(
    abs(fallbackPx.r - fallbackPlain.r) > 20,
    "default band (y 60-70) should blink when no eye band is supplied")
}

private func checkRowCellGeneration() throws {
  var cells: [AnimationRow: CGImage] = [:]
  for row in AnimationRow.allCases {
    guard
      let cell = makeSolidImage(
        width: 192,
        height: 208,
        color: (0.1 + 0.1 * Double(row.rawValue), 0.4, 0.7)
      )
    else {
      throw CheckFailure(description: "could not create row cell \(row.rawValue)")
    }
    cells[row] = cell
  }
  guard let sheet = SpriteSheetGenerator.generate(fromRowCells: cells) else {
    throw CheckFailure(description: "row-cell generation returned nil")
  }
  try expect(sheet.width == 1536 && sheet.height == 1664, "row-cell sheet should be 1536x1664")

  // 用 PetAnimState.frameRect（左上原点）直接裁剪：钉住规范坐标与
  // CGImage.cropping 的 y=0=视觉顶部 一致，避免“y 翻转”类回归。
  for row in AnimationRow.allCases {
    let frame = PetAnimState(row: row).frameRect(index: 0)
    guard
      let cell = cells[row],
      let strip = sheet.cropping(
        to: CGRect(x: frame.minX, y: frame.minY, width: 192, height: 208))
    else {
      throw CheckFailure(description: "could not crop row \(row.rawValue) frame")
    }
    let cellCenter = pixel(cell, x: 96, y: 104)
    let stripCenter = pixel(strip, x: 96, y: 104)
    try expect(
      abs(stripCenter.r - cellCenter.r) <= 4 && abs(stripCenter.g - cellCenter.g) <= 4
        && abs(stripCenter.b - cellCenter.b) <= 4 && abs(stripCenter.a - cellCenter.a) <= 4,
      "row \(row.rawValue) frame should match its own cell at frameRect origin")
  }
}

private func checkPoseCellProcessor() throws {
  let magenta = (r: CGFloat(1.0), g: CGFloat(0.0), b: CGFloat(1.0))
  guard
    let canvas = makeSolidImage(width: 256, height: 256, color: magenta),
    let context = CGContext(
      data: nil,
      width: 256,
      height: 256,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw CheckFailure(description: "could not create pose canvas")
  }
  context.draw(canvas, in: CGRect(x: 0, y: 0, width: 256, height: 256))
  context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
  context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
  guard let subjectImage = context.makeImage() else {
    throw CheckFailure(description: "could not make subject image")
  }

  guard let cell = PoseCellProcessor.makeCell(from: subjectImage) else {
    throw CheckFailure(description: "pose cell processing returned nil")
  }
  try expect(cell.width == 192 && cell.height == 208, "pose cell should be 192x208")
  let corner = pixel(cell, x: 0, y: 0)
  try expect(corner.a == 0, "corners should be transparent after chroma key")
  let center = pixel(cell, x: 96, y: 104)
  try expect(center.a > 200 && center.g > 150, "subject should remain opaque in the center")

  guard let magentaOnly = makeSolidImage(width: 64, height: 64, color: magenta) else {
    throw CheckFailure(description: "could not create empty canvas")
  }
  try expect(
    PoseCellProcessor.makeCell(from: magentaOnly) == nil,
    "all-chroma image should produce nil cell")
}

private func checkGPTImage2Provider() async throws {
  guard
    let pngData = makePosePNGData(),
    let baseURL = URL(string: "https://example.com/v1"),
    let reference = makeSolidImage(width: 64, height: 64, color: (0.2, 0.3, 0.4))
  else {
    throw CheckFailure(description: "could not prepare provider fixtures")
  }
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MockURLProtocol.self]
  let session = URLSession(configuration: configuration)
  let config = GPTImage2Config(
    apiKey: "test-key",
    baseURL: baseURL,
    model: "gpt-image-2",
    size: "1024x1024",
    timeout: 10,
    extraPosesEnabled: false
  )
  let provider = GPTImage2Provider(config: config, session: session)
  let encoded = pngData.base64EncodedString()

  MockURLProtocol.install { _ in
    (200, Data("{\"data\":[{\"b64_json\":\"\(encoded)\"}]}".utf8))
  }
  let sheet = try await provider.generateSpritesheet(from: reference)
  try expect(sheet != nil, "provider should decode the b64 response into an image")

  guard let request = MockURLProtocol.capturedRequests().last else {
    throw CheckFailure(description: "provider did not send a request")
  }
  try expect(request.url?.path == "/v1/images/edits", "request should hit the edits endpoint")
  try expect(
    request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
    "request should carry the bearer key")
  let body = String(decoding: requestBodyData(request), as: UTF8.self)
  try expect(body.contains("name=\"image\""), "multipart body should include the image field")
  try expect(body.contains("gpt-image-2"), "multipart body should include the model")
  try expect(body.contains("b64_json"), "multipart body should request b64_json")
  try expect(body.contains("1024x1024"), "multipart body should include the size")

  MockURLProtocol.install { _ in (500, Data("boom".utf8)) }
  do {
    _ = try await provider.generateSpritesheet(from: reference)
    throw CheckFailure(description: "provider should fail on HTTP 500")
  } catch AIPoseError.httpStatus(let code) {
    try expect(code == 500, "HTTP failure should surface the status code")
  }

  MockURLProtocol.install { _ in
    (200, Data("{\"data\":[]}".utf8))
  }
  do {
    _ = try await provider.generateSpritesheet(from: reference)
    throw CheckFailure(description: "provider should fail on an empty result")
  } catch AIPoseError.decodingFailed {
    // Expected.
  }
}

private func checkVisionEyeBandLocator() throws {
  guard let blank = makeSolidImage(width: 64, height: 64, color: (0.5, 0.5, 0.5)) else {
    throw CheckFailure(description: "could not create blank image")
  }
  let locator = VisionEyeBandLocator()
  try expect(
    locator.eyeBand(in: blank) == nil,
    "blank image should not produce an eye band")
}

private func runAllChecks() async throws {
  try checkStateMachine()
  try checkCoreServices()
  try checkRowCellGeneration()
  try checkSpriteSheetEyeBand()
  try checkPoseCellProcessor()
  try await checkGPTImage2Provider()
  try checkVisionEyeBandLocator()
}

do {
  try await runAllChecks()
  print("PetDeskCoreChecks: all checks passed")
} catch {
  FileHandle.standardError.write(Data("PetDeskCoreChecks: \(error)\n".utf8))
  exit(1)
}
