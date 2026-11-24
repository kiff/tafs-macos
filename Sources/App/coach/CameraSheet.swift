import AVFoundation
import AppKit
import SwiftUI

// Take photo, as the iPad's `CameraPicker` (AttachViews.swift:91-118): this Mac's camera, for one
// photo, which goes with the next message as the iPad's does (`FilePrep.photo`, named "Photo").

/// This Mac's camera while the sheet is open: its picture, and one photo taken. It runs only while
/// the sheet shows, and stops when the sheet closes.
final class CameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "bot.tafs.camera")
    /// The camera's picture is showing, and a photo can be taken.
    @Published private(set) var running = false
    /// A photo is being taken.
    @Published private(set) var taking = false
    private var took: ((Data?) -> Void)?
    /// The sheet closed: a camera allowed after that never starts, and one starting stops at once. Read on the camera's
    /// queue too, so it's guarded.
    private let stoppedLock = NSLock()
    private var stoppedFlag = false
    private var stopped: Bool {
        stoppedLock.lock(); defer { stoppedLock.unlock() }
        return stoppedFlag
    }

    /// Take photo is offered on a Mac with a camera, as the iPad offers it only where there's one.
    static var offered: Bool { AVCaptureDevice.default(for: .video) != nil }

    /// tafs was refused the camera: Take photo says where to turn it on (`chat.file.mac_camera_off`), and no sheet opens.
    static var refused: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Asks for the camera the first time (the system's own question), then starts it. False
    /// when it can't run: refused, or no camera.
    func start() async -> Bool {
        guard await Self.allowed(), !stopped, let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }
        let session = self.session
        let output = self.output
        let started: Bool = await withCheckedContinuation { done in
            queue.async { [self] in
                // Closed while the system asked, or while this waited its turn: nothing starts.
                guard !self.stopped else {
                    done.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    done.resume(returning: false)
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                // Closed while it started: it stops at once.
                if self.stopped { session.stopRunning() }
                done.resume(returning: session.isRunning)
            }
        }
        await MainActor.run { self.running = started }
        return started
    }

    /// Stops the camera, as the sheet closes.
    func stop() {
        stoppedLock.lock()
        stoppedFlag = true
        stoppedLock.unlock()
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        running = false
    }

    /// One photo, as the camera's own data (a JPEG or HEIC); nil when it couldn't be taken.
    func take(_ done: @escaping (Data?) -> Void) {
        guard running, !taking else { return }
        taking = true
        took = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        DispatchQueue.main.async {
            self.taking = false
            let done = self.took
            self.took = nil
            done?(data)
        }
    }

    /// The camera may be used: already allowed, or allowed now at the system's question.
    private static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { done in
                AVCaptureDevice.requestAccess(for: .video) { done.resume(returning: $0) }
            }
        default: return false
        }
    }
}

/// The camera's picture, live.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// The sheet: the camera's picture, Take photo and Cancel. A photo taken goes to the next message
/// (`took`), and the sheet closes; one that can't be read says so in the tray, as a chosen photo's.
struct CameraSheet: View {
    @Environment(\.words) private var words
    @StateObject private var camera = CameraSession()
    let took: (Data?) -> Void
    let close: () -> Void
    /// The camera was refused at the system's question: the sheet closes and the tray says where to turn it on.
    var refused: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                if camera.running {
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 520, height: 390)
            HStack(spacing: 12) {
                Button(words("common.cancel")) { close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    camera.take { data in
                        took(data)
                        close()
                    }
                } label: {
                    Label(words("chat.file.take_photo"), systemImage: "camera")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!camera.running || camera.taking)
            }
        }
        .padding(20)
        .background(Theme.background)
        .task {
            // Refused at the system's question, or no camera: the sheet closes, nothing taken. Refused, it says
            // where to turn the camera on.
            if !(await camera.start()) {
                if CameraSession.refused { refused() }
                close()
            }
        }
        .onDisappear { camera.stop() }
    }
}
