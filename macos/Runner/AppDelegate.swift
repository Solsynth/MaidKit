import Cocoa
import Darwin
import FlutterMacOS

private let kIOSSIOSPEED: UInt = 0x80045402

private func applyBaudRate(fd: Int32, baudRate: Int) -> Bool {
  let standard: speed_t
  switch baudRate {
  case 9600: standard = speed_t(B9600)
  case 19200: standard = speed_t(B19200)
  case 38400: standard = speed_t(B38400)
  case 57600: standard = speed_t(B57600)
  case 115200: standard = speed_t(B115200)
  case 230400: standard = speed_t(B230400)
  default: standard = speed_t(B230400)
  }
  var termios = Darwin.termios()
  guard tcgetattr(fd, &termios) == 0 else { return false }
  cfsetispeed(&termios, standard)
  cfsetospeed(&termios, standard)
  guard tcsetattr(fd, TCSANOW, &termios) == 0 else { return false }
  var speed = speed_t(baudRate)
  return ioctl(fd, kIOSSIOSPEED, &speed) == 0
}

private func configureSerial(
  fd: Int32,
  baudRate: Int,
  dataBits: Int,
  parity: String,
  stopBits: Int,
  flowControl: String
) -> Bool {
  var termios = Darwin.termios()
  guard tcgetattr(fd, &termios) == 0 else { return false }
  cfmakeraw(&termios)

  termios.c_cflag &= ~tcflag_t(CSIZE)
  switch dataBits {
  case 5: termios.c_cflag |= tcflag_t(CS5)
  case 6: termios.c_cflag |= tcflag_t(CS6)
  case 7: termios.c_cflag |= tcflag_t(CS7)
  default: termios.c_cflag |= tcflag_t(CS8)
  }

  termios.c_cflag &= ~tcflag_t(PARENB)
  termios.c_cflag &= ~tcflag_t(PARODD)
  if parity == "even" {
    termios.c_cflag |= tcflag_t(PARENB)
  } else if parity == "odd" {
    termios.c_cflag |= tcflag_t(PARENB | PARODD)
  }

  termios.c_cflag &= ~tcflag_t(CSTOPB)
  if stopBits == 2 {
    termios.c_cflag |= tcflag_t(CSTOPB)
  }

  termios.c_cflag &= ~tcflag_t(CRTSCTS)
  termios.c_iflag &= ~tcflag_t(IXON)
  termios.c_iflag &= ~tcflag_t(IXOFF)
  if flowControl == "hardware" {
    termios.c_cflag |= tcflag_t(CRTSCTS)
  } else if flowControl == "software" {
    termios.c_iflag |= tcflag_t(IXON | IXOFF)
  }

  termios.c_cflag |= tcflag_t(CLOCAL | CREAD)
  guard tcsetattr(fd, TCSANOW, &termios) == 0 else { return false }
  return applyBaudRate(fd: fd, baudRate: baudRate)
}

private final class SerialPortManager {
  private final class Session {
    let fileDescriptor: Int32
    let source: DispatchSourceRead

    init(fileDescriptor: Int32, source: DispatchSourceRead) {
      self.fileDescriptor = fileDescriptor
      self.source = source
    }
  }

  private let channel: FlutterMethodChannel
  private let lock = NSLock()
  private var sessions: [Int: Session] = [:]
  private var nextSessionId = 1

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func listDevices() -> [String] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
      return []
    }
    return entries
      .filter { $0.hasPrefix("cu.") }
      .map { "/dev/" + $0 }
      .sorted()
  }

  func open(arguments: [String: Any]) throws -> Int {
    guard let device = arguments["device"] as? String, !device.isEmpty else {
      throw serialError("A serial device is required.")
    }

    let baudRate = (arguments["baudRate"] as? NSNumber)?.intValue ?? 115200
    let dataBits = (arguments["dataBits"] as? NSNumber)?.intValue ?? 8
    let parity = arguments["parity"] as? String ?? "none"
    let stopBits = (arguments["stopBits"] as? NSNumber)?.intValue ?? 1
    let flowControl = arguments["flowControl"] as? String ?? "none"

    let fileDescriptor = Darwin.open(device, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard fileDescriptor >= 0 else {
      throw serialError("Cannot open \(device): \(String(cString: strerror(errno)))")
    }
    guard configureSerial(
      fd: fileDescriptor,
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      flowControl: flowControl
    ) else {
      let message = String(cString: strerror(errno))
      Darwin.close(fileDescriptor)
      throw serialError("Cannot configure \(device): \(message)")
    }

    let sessionId: Int
    lock.lock()
    sessionId = nextSessionId
    nextSessionId += 1
    lock.unlock()

    let queue = DispatchQueue(label: "dev.solsynth.maidKit.serial.\(sessionId)")
    let source = DispatchSource.makeReadSource(
      fileDescriptor: fileDescriptor,
      queue: queue
    )
    let session = Session(fileDescriptor: fileDescriptor, source: source)
    lock.lock()
    sessions[sessionId] = session
    lock.unlock()

    source.setEventHandler { [weak self] in
      self?.read(sessionId: sessionId)
    }
    source.setCancelHandler {
      Darwin.close(fileDescriptor)
    }
    source.resume()
    return sessionId
  }

  func write(sessionId: Int, data: Data) throws {
    guard let session = session(for: sessionId) else {
      throw serialError("Serial session is no longer open.")
    }
    data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.baseAddress else { return }
      var offset = 0
      while offset < data.count {
        let count = Darwin.write(
          session.fileDescriptor,
          baseAddress.advanced(by: offset),
          data.count - offset
        )
        if count > 0 {
          offset += count
        } else if count < 0 && errno == EAGAIN {
          usleep(1000)
        } else {
          break
        }
      }
    }
  }

  func close(sessionId: Int) {
    finish(sessionId: sessionId)
  }

  deinit {
    lock.lock()
    let ids = Array(sessions.keys)
    lock.unlock()
    ids.forEach { finish(sessionId: $0) }
  }

  private func session(for sessionId: Int) -> Session? {
    lock.lock()
    defer { lock.unlock() }
    return sessions[sessionId]
  }

  private func read(sessionId: Int) {
    guard let session = session(for: sessionId) else { return }
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bufferSize = buffer.count
    let count = buffer.withUnsafeMutableBytes { rawBuffer in
      Darwin.read(session.fileDescriptor, rawBuffer.baseAddress!, bufferSize)
    }
    if count > 0 {
      let data = Data(buffer[0..<count])
      DispatchQueue.main.async { [weak self] in
        self?.channel.invokeMethod("data", arguments: [
          "sessionId": sessionId,
          "data": FlutterStandardTypedData(bytes: data),
        ])
      }
    } else {
      finish(sessionId: sessionId)
    }
  }

  private func finish(sessionId: Int) {
    lock.lock()
    guard let session = sessions.removeValue(forKey: sessionId) else {
      lock.unlock()
      return
    }
    lock.unlock()
    session.source.cancel()
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("done", arguments: ["sessionId": sessionId])
    }
  }

  fileprivate func serialError(_ message: String) -> NSError {
    NSError(
      domain: "dev.solsynth.maidKit.serial",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private static let serialPortChannel = "dev.solsynth.maidKit/serial_port"
  private var serialPortManager: SerialPortManager?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: Self.serialPortChannel,
      binaryMessenger: controller.engine.binaryMessenger
    )
    let manager = SerialPortManager(channel: channel)
    serialPortManager = manager
    channel.setMethodCallHandler { [weak self] call, result in
      guard let manager = self?.serialPortManager else {
        result(FlutterError(code: "unavailable", message: "Serial ports are unavailable.", details: nil))
        return
      }
      do {
        switch call.method {
        case "listDevices":
          result(manager.listDevices())
        case "open":
          guard let arguments = call.arguments as? [String: Any] else {
            throw manager.serialError("Invalid serial configuration.")
          }
          result(try manager.open(arguments: arguments))
        case "write":
          guard
            let arguments = call.arguments as? [String: Any],
            let sessionId = (arguments["sessionId"] as? NSNumber)?.intValue,
            let typedData = arguments["data"] as? FlutterStandardTypedData
          else {
            throw manager.serialError("Invalid serial write request.")
          }
          try manager.write(sessionId: sessionId, data: typedData.data)
          result(nil)
        case "close":
          guard
            let arguments = call.arguments as? [String: Any],
            let sessionId = (arguments["sessionId"] as? NSNumber)?.intValue
          else {
            throw manager.serialError("Invalid serial close request.")
          }
          manager.close(sessionId: sessionId)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(
          code: "serial_error",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
  }
}
