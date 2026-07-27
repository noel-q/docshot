import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// Lets a test hold a capture in flight until it chooses to release it.
private actor CaptureGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for continuation in pending { continuation.resume() }
    }
}

/// Records how often the capture handler ran, and with which displays.
private final class CaptureSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestedDisplayIDs: [CGDirectDisplayID] = []

    var requestedDisplayIDs: [CGDirectDisplayID] {
        lock.lock(); defer { lock.unlock() }
        return _requestedDisplayIDs
    }

    var callCount: Int { requestedDisplayIDs.count }

    func record(_ displayID: CGDirectDisplayID) {
        lock.lock(); defer { lock.unlock() }
        _requestedDisplayIDs.append(displayID)
    }
}

@Suite("DisplaySnapshotService Tests")
struct DisplaySnapshotServiceTests {

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private func makeSolidImage(width: Int, height: Int, red: Double, green: Double, blue: Double) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Self.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(colorSpace: Self.sRGB, components: [red, green, blue, 1.0])!)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()!
    }

    private func descriptor(id: CGDirectDisplayID, origin: CGPoint = .zero, scale: CGFloat = 2) -> DisplayDescriptor {
        DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 100, height: 100)),
            scale: scale
        )
    }

    @Test("One snapshot is captured per planned display")
    @MainActor
    func testCapturesEveryPlannedDisplay() async {
        let spy = CaptureSpy()
        let service = DisplaySnapshotService { [self] descriptor in
            spy.record(descriptor.displayID)
            return makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 1, green: 0, blue: 0)
        }

        let displays = [descriptor(id: 1), descriptor(id: 2, origin: CGPoint(x: 100, y: 0))]
        let applied = await service.captureSnapshots(for: displays)

        #expect(applied)
        #expect(spy.callCount == 2)
        #expect(service.snapshots.count == 2)
        #expect(service.unavailableDescriptors.isEmpty)
        #expect(service.lastPlan?.included.count == 2)
    }

    @Test("A failure on one display leaves the others usable and marks that display unavailable")
    @MainActor
    func testPartialFailureDegradesGracefully() async {
        let service = DisplaySnapshotService { [self] descriptor in
            if descriptor.displayID == 2 {
                throw SnapshotError.captureFailed("simulated failure")
            }
            return makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 0, green: 0, blue: 1)
        }

        let displays = [descriptor(id: 1), descriptor(id: 2, origin: CGPoint(x: 100, y: 0))]
        let applied = await service.captureSnapshots(for: displays)

        #expect(applied)
        #expect(service.snapshots.map(\.descriptor.displayID) == [1])
        #expect(service.unavailableDescriptors.map(\.displayID) == [2])

        // The working display still samples correctly.
        #expect(service.sample(atGlobalPoint: CGPoint(x: 50, y: 50)) == ColorSample(red: 0, green: 0, blue: 255))
        // The failed display reports nothing rather than an invented colour.
        #expect(service.sample(atGlobalPoint: CGPoint(x: 150, y: 50)) == nil)
    }

    @Test("Displays skipped by the budget are reported as unavailable, and capture is never requested for them")
    @MainActor
    func testBudgetSkippedDisplaysNeverCaptured() async {
        let spy = CaptureSpy()
        let service = DisplaySnapshotService { [self] descriptor in
            spy.record(descriptor.displayID)
            return makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 1, green: 1, blue: 1)
        }

        let oversized = DisplayDescriptor(
            displayID: 42,
            frameInCG: CGRect(x: 0, y: 0, width: 20_000, height: 20_000),
            scale: 2
        )
        let normal = descriptor(id: 1, origin: CGPoint(x: -100, y: 0))

        let applied = await service.captureSnapshots(for: [oversized, normal])

        #expect(applied)
        #expect(spy.requestedDisplayIDs == [1])
        #expect(service.unavailableDescriptors.map(\.displayID) == [42])
    }

    @Test("Snapshots are refused while a selection overlay is visible")
    @MainActor
    func testOverlayInterlockRefusesCapture() async {
        let spy = CaptureSpy()
        let service = DisplaySnapshotService { [self] descriptor in
            spy.record(descriptor.displayID)
            return makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 1, green: 0, blue: 0)
        }

        service.setSelectionOverlayVisible(true)
        let applied = await service.captureSnapshots(for: [descriptor(id: 1)])

        #expect(applied == false)
        #expect(spy.callCount == 0, "An overlay was visible: capturing would have sampled DocShot itself")
        #expect(service.snapshots.isEmpty)
    }

    @Test("Cancelling while a capture is in flight discards the late result")
    @MainActor
    func testCancellationDiscardsLateResults() async {
        let gate = CaptureGate()
        let service = DisplaySnapshotService { [self] descriptor in
            await gate.wait()
            return makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 1, green: 0, blue: 0)
        }

        let captureTask = Task { @MainActor in
            await service.captureSnapshots(for: [descriptor(id: 1)])
        }

        // Let the capture reach its suspension point, then cancel as Escape would.
        await Task.yield()
        service.cancelPending()

        await gate.open()
        let applied = await captureTask.value

        #expect(applied == false, "A cancelled run must not apply its results")
        #expect(service.snapshots.isEmpty)
        #expect(service.unavailableDescriptors.isEmpty)
        #expect(service.sample(atGlobalPoint: CGPoint(x: 50, y: 50)) == nil)
    }

    @Test("A superseded capture does not overwrite a newer one")
    @MainActor
    func testSupersededRunIsDiscarded() async {
        let gate = CaptureGate()
        let service = DisplaySnapshotService { [self] descriptor in
            if descriptor.displayID == 1 { await gate.wait() }
            return makeSolidImage(
                width: descriptor.pixelWidth,
                height: descriptor.pixelHeight,
                red: descriptor.displayID == 1 ? 1 : 0,
                green: descriptor.displayID == 1 ? 0 : 1,
                blue: 0
            )
        }

        let firstRun = Task { @MainActor in
            await service.captureSnapshots(for: [descriptor(id: 1)])
        }
        await Task.yield()

        let secondApplied = await service.captureSnapshots(for: [descriptor(id: 2)])
        await gate.open()
        let firstApplied = await firstRun.value

        #expect(secondApplied)
        #expect(firstApplied == false)
        #expect(service.snapshots.map(\.descriptor.displayID) == [2])
    }

    @Test("Releasing snapshots frees them and stops sampling")
    @MainActor
    func testReleaseSnapshots() async {
        let service = DisplaySnapshotService { [self] descriptor in
            makeSolidImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight, red: 0, green: 1, blue: 0)
        }

        await service.captureSnapshots(for: [descriptor(id: 1)])
        #expect(service.sample(atGlobalPoint: CGPoint(x: 10, y: 10)) == ColorSample(red: 0, green: 255, blue: 0))

        service.releaseSnapshots()

        #expect(service.snapshots.isEmpty)
        #expect(service.lastPlan == nil)
        #expect(service.sample(atGlobalPoint: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test("Sampling resolves the right display on a mixed-scale, negative-origin layout")
    @MainActor
    func testSamplingAcrossMixedScaleNegativeOriginDisplays() async {
        // Retina display to the left of the origin, 1x display at the origin.
        let leftRetina = DisplayDescriptor(
            displayID: 1,
            frameInCG: CGRect(x: -1440, y: -200, width: 1440, height: 900),
            scale: 2
        )
        let mainOneX = DisplayDescriptor(
            displayID: 2,
            frameInCG: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scale: 1
        )

        let service = DisplaySnapshotService { [self] descriptor in
            let isRetina = descriptor.displayID == 1
            return makeSolidImage(
                width: descriptor.pixelWidth,
                height: descriptor.pixelHeight,
                red: isRetina ? 1 : 0,
                green: 0,
                blue: isRetina ? 0 : 1
            )
        }

        await service.captureSnapshots(for: [leftRetina, mainOneX])

        #expect(service.snapshots.count == 2)
        // Each display's snapshot is captured at its own scale.
        #expect(service.snapshot(containing: CGPoint(x: -700, y: 100))?.descriptor.scale == 2)
        #expect(service.snapshot(containing: CGPoint(x: 700, y: 100))?.descriptor.scale == 1)

        #expect(service.sample(atGlobalPoint: CGPoint(x: -700, y: 100)) == ColorSample(red: 255, green: 0, blue: 0))
        #expect(service.sample(atGlobalPoint: CGPoint(x: 700, y: 100)) == ColorSample(red: 0, green: 0, blue: 255))

        // A point on no display samples nothing.
        #expect(service.sample(atGlobalPoint: CGPoint(x: 5000, y: 5000)) == nil)
    }
}
