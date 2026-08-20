import Foundation
import AppKit
import ScreenSaver

@objc(MNISTMatrixSaverView)
public class MNISTMatrixSaverView: ScreenSaverView {
    
    // MARK: - Core Screen Saver Ideal Configuration Parameters
    
    /// Minimum fall speed for a rain stream in grid rows per second (Default: 6.0)
    /// Controls the velocity of the slowest falling rain streams.
    private let minFallSpeedRowsPerSecond: Double = 6.0
    
    /// Maximum fall speed for a rain stream in grid rows per second (Default: 18.0)
    /// Controls the velocity of the fastest falling rain streams.
    private let maxFallSpeedRowsPerSecond: Double = 12.0
    
    /// Minimum length of a falling rain stream in grid rows (Default: 8)
    /// Controls the minimum digit tail length of code streams.
    private let minDropLengthRows: Int = 8
    
    /// Maximum length of a falling rain stream in grid rows (Default: 36)
    /// Controls the maximum digit tail length of code streams.
    private let maxDropLengthRows: Int = 36
    
    /// Column density ratio (Default: 0.85 = 85% dense rain coverage)
    /// Fraction of screen columns containing active code streams (0.3 to 1.0).
    private let densityRatio: Double = 0.50
    
    /// Grid cell & digit size in pixels (Default: 18.0)
    /// Width and height of each handwritten MNIST digit cell on screen.
    private let baseDigitSize: CGFloat = 18.0
    
    /// Probability that an initialized digit cell morphs/swaps during its lifetime (Default: 0.50 = 50%)
    /// Controls the fraction of falling digits that change shape (0.0 = static digits, 1.0 = all digits morph).
    private let digitSwapProbability: Double = 0.50
    
    /// Minimum delay in seconds before a designated morphing digit swaps (Default: 0.25 seconds)
    private let minSwapDelaySeconds: Double = 0.25
    
    /// Maximum delay in seconds before a designated morphing digit swaps (Default: 1.25 seconds)
    private let maxSwapDelaySeconds: Double = 1.25
    
    /// Show FPS overlay counter in the top-right corner (Default: true for debugging)
    /// Set to false for clean production screensaver viewing.
    private let showFPSOverlay: Bool = true

    // MARK: - Grid Geometry & Rendering Engine
    private var columnsCount: Int = 0
    private var rowsCount: Int = 0
    private var actualCellSize: CGFloat = 18.0
    
    private var globalFrameCount: UInt64 = 0
    private var columns: [MatrixColumn] = []
    private let renderer = DirectScreenRenderer()
    
    // FPS counter & Delta time properties
    private var lastFrameTime: CFTimeInterval = 0
    private var lastFPSTime: CFTimeInterval = 0
    private var frameCounter: Int = 0
    private var currentFPS: Double = 60.0

    // MARK: - Initialization
    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        self.animationTimeInterval = 1.0 / 60.0
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        self.animationTimeInterval = 1.0 / 60.0
    }
    
    public override func startAnimation() {
        super.startAnimation()
        MNISTAtlas.shared.loadAtlas()
        rebuildGrid()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildGrid()
    }
    
    private func rebuildGrid() {
        let bounds = self.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        actualCellSize = max(12.0, baseDigitSize)
        columnsCount = max(1, Int(ceil(bounds.width / actualCellSize)))
        rowsCount = max(1, Int(ceil(bounds.height / actualCellSize)))
        
        renderer.resize(width: Int(bounds.width), height: Int(bounds.height))
        
        columns = (0..<columnsCount).map { colIndex in
            MatrixColumn(
                columnIndex: colIndex,
                totalRows: rowsCount,
                density: densityRatio,
                swapProbability: digitSwapProbability,
                minSwapDelay: minSwapDelaySeconds,
                maxSwapDelay: maxSwapDelaySeconds,
                minSpeed: minFallSpeedRowsPerSecond,
                maxSpeed: maxFallSpeedRowsPerSecond,
                minDropLength: minDropLengthRows,
                maxDropLength: maxDropLengthRows
            )
        }
    }
    
    // MARK: - Animation Loop
    public override func animateOneFrame() {
        globalFrameCount += 1
        
        let now = CACurrentMediaTime()
        let dt = (lastFrameTime > 0) ? min(0.1, now - lastFrameTime) : (1.0 / 60.0)
        lastFrameTime = now
        
        // Measure FPS twice per second
        frameCounter += 1
        if lastFPSTime == 0 { lastFPSTime = now }
        let elapsedFPS = now - lastFPSTime
        if elapsedFPS >= 0.5 {
            currentFPS = Double(frameCounter) / elapsedFPS
            frameCounter = 0
            lastFPSTime = now
        }
        
        for col in columns {
            col.update(deltaTime: dt)
        }
        
        self.needsDisplay = true
    }
    
    // MARK: - Direct Hardware Frame Rendering Loop
    public override func draw(_ rect: NSRect) {
        super.draw(rect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let screenW = Int(bounds.width)
        let screenH = Int(bounds.height)
        let cSize = Int(actualCellSize)
        
        guard MNISTAtlas.shared.isLoaded, screenW > 0, screenH > 0 else {
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
            context.fill(rect)
            let text = "MNIST Matrix Loading..." as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor(red: 0, green: 1.0, blue: 0.4, alpha: 0.8)
            ]
            text.draw(at: NSPoint(x: rect.midX - 100, y: rect.midY), withAttributes: attrs)
            return
        }
        
        // 1. Clear offscreen pixel buffer to Pitch Black (#000000)
        renderer.clear()
        
        // 2. Direct memory pixel blit for all active matrix cells (row 0 is top of screen)
        for col in columns {
            let startX = Int(CGFloat(col.columnIndex) * actualCellSize)
            
            for row in 0..<rowsCount {
                guard let cell = col.grid[row] else { continue }
                
                // Trail opacity based strictly on distance from drop head in grid rows
                let distFromHead = col.dropHeadRow - row
                let alpha = Float(cell.getAlpha(distanceFromHead: distFromHead))
                guard alpha > 0.01 else { continue }
                
                // Row 0 starts at top of screen (Y = 0 in buffer coordinate space)
                let startY = Int(CGFloat(row) * actualCellSize)
                
                if cell.isCrossFading, let oldIdx = cell.oldMnistIndex {
                    let oldPixels = MNISTAtlas.shared.getScaledPixels(forIndex: oldIdx, targetSize: cSize)
                    let newPixels = MNISTAtlas.shared.getScaledPixels(forIndex: cell.mnistIndex, targetSize: cSize)
                    renderer.drawDigit(scaledPixels: oldPixels, cellW: cSize, cellH: cSize, startX: startX, startY: startY, type: .green, alpha: alpha * 0.5)
                    renderer.drawDigit(scaledPixels: newPixels, cellW: cSize, cellH: cSize, startX: startX, startY: startY, type: .green, alpha: alpha * 0.5)
                } else if cell.isHead {
                    let pixels = MNISTAtlas.shared.getScaledPixels(forIndex: cell.mnistIndex, targetSize: cSize)
                    renderer.drawDigit(scaledPixels: pixels, cellW: cSize, cellH: cSize, startX: startX, startY: startY, type: .white, alpha: alpha)
                } else {
                    let pixels = MNISTAtlas.shared.getScaledPixels(forIndex: cell.mnistIndex, targetSize: cSize)
                    renderer.drawDigit(scaledPixels: pixels, cellW: cSize, cellH: cSize, startX: startX, startY: startY, type: .green, alpha: alpha)
                }
            }
        }
        
        // 3. Draw entire full-screen composited frame in 1 single GPU draw call
        if let fullScreenImage = renderer.createCGImage() {
            context.draw(fullScreenImage, in: bounds)
        }
        
        // 4. Draw FPS Overlay (Top-Right Corner)
        if showFPSOverlay {
            let fpsText = String(format: "FPS: %.1f", currentFPS) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.yellow,
                .backgroundColor: NSColor.black.withAlphaComponent(0.65)
            ]
            fpsText.draw(at: NSPoint(x: bounds.width - 85, y: bounds.height - 22), withAttributes: attrs)
        }
    }
    
    // MARK: - Options Removal (Self-Contained Screen Saver)
    
    public override var hasConfigureSheet: Bool {
        return false
    }
    
    public override var configureSheet: NSWindow? {
        return nil
    }
}

// MARK: - Ultra High-Performance Direct Screen Renderer

enum MatrixCellColorType {
    case green
    case white
}

class DirectScreenRenderer {
    private var pixelBuffer: [UInt8] = []
    private var width: Int = 0
    private var height: Int = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        let totalBytes = max(1, width * height * 4)
        if pixelBuffer.count != totalBytes {
            pixelBuffer = [UInt8](repeating: 0, count: totalBytes)
        }
    }
    
    func clear() {
        pixelBuffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            // Set all R, G, B bytes to 0 (Pitch Black #000000), and Alpha to 255
            let totalPixels = width * height
            for i in 0..<totalPixels {
                let idx = i * 4
                base[idx]     = 0   // R = 0
                base[idx + 1] = 0   // G = 0
                base[idx + 2] = 0   // B = 0
                base[idx + 3] = 255 // A = 255
            }
        }
    }
    
    func drawDigit(scaledPixels: [UInt8], cellW: Int, cellH: Int, startX: Int, startY: Int, type: MatrixCellColorType, alpha: Float) {
        guard alpha > 0.01, width > 0, height > 0 else { return }
        
        let screenW = self.width
        let screenH = self.height
        
        scaledPixels.withUnsafeBufferPointer { srcPtr in
            guard let srcBase = srcPtr.baseAddress else { return }
            
            pixelBuffer.withUnsafeMutableBufferPointer { dstPtr in
                guard let dstBase = dstPtr.baseAddress else { return }
                
                for cy in 0..<cellH {
                    let sy = startY + cy
                    guard sy >= 0 && sy < screenH else { continue }
                    let dstRowOffset = (sy * screenW) * 4
                    let srcRowOffset = cy * cellW
                    
                    for cx in 0..<cellW {
                        let sx = startX + cx
                        guard sx >= 0 && sx < screenW else { continue }
                        
                        let rawVal = srcBase[srcRowOffset + cx]
                        guard rawVal > 0 else { continue }
                        
                        let v = Float(rawVal) * alpha
                        let intensity = UInt8(min(255.0, max(0.0, v)))
                        guard intensity > 0 else { continue }
                        
                        let dstIdx = dstRowOffset + (sx * 4)
                        
                        switch type {
                        case .green:
                            // Phosphor Green (#00FF66): R=0, G=intensity, B=intensity*0.4, A=255
                            dstBase[dstIdx]     = 0
                            dstBase[dstIdx + 1] = intensity
                            dstBase[dstIdx + 2] = UInt8((UInt16(intensity) * 102) / 255)
                            dstBase[dstIdx + 3] = 255
                        case .white:
                            // Pure White Glowing Lead: R=intensity, G=intensity, B=intensity, A=255
                            dstBase[dstIdx]     = intensity
                            dstBase[dstIdx + 1] = intensity
                            dstBase[dstIdx + 2] = intensity
                            dstBase[dstIdx + 3] = 255
                        }
                    }
                }
            }
        }
    }
    
    func createCGImage() -> CGImage? {
        guard width > 0 && height > 0 else { return nil }
        let cfData = Data(pixelBuffer) as CFData
        guard let provider = CGDataProvider(data: cfData) else { return nil }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

// MARK: - Helper Data Structures

class MatrixCell {
    var mnistIndex: Int
    var isHead: Bool = false
    var dropLength: Int = 15
    var canSwap: Bool = false
    
    // morphing / changing glyph state
    var changeTimer: Int = 0
    var isCrossFading: Bool = false
    var oldMnistIndex: Int?
    
    init(mnistIndex: Int, canSwap: Bool = false, swapTimer: Int = 30) {
        self.mnistIndex = mnistIndex
        self.canSwap = canSwap
        self.changeTimer = swapTimer
    }
    
    func getAlpha(distanceFromHead: Int) -> CGFloat {
        if isHead { return 1.0 }
        guard distanceFromHead >= 0 && distanceFromHead <= dropLength else { return 0.0 }
        let fadeFraction = CGFloat(distanceFromHead) / CGFloat(max(1, dropLength))
        return max(0.0, 1.0 - (fadeFraction * 0.95))
    }
}

enum DropType {
    case visible(length: Int)
    case gap(length: Int)
    case deletion(length: Int)
}

class MatrixColumn {
    let columnIndex: Int
    let totalRows: Int
    let density: Double
    let swapProbability: Double
    let minSwapDelay: Double
    let maxSwapDelay: Double
    let minSpeed: Double
    let maxSpeed: Double
    let minDropLength: Int
    let maxDropLength: Int
    
    var grid: [MatrixCell?]
    var dropHeadRow: Int = 0
    private var activeDrop: DropType?
    private var dropProgress: Double = 0.0
    private var currentDropSpeed: Double = 12.0
    
    init(columnIndex: Int, totalRows: Int, density: Double, swapProbability: Double, minSwapDelay: Double, maxSwapDelay: Double, minSpeed: Double, maxSpeed: Double, minDropLength: Int, maxDropLength: Int) {
        self.columnIndex = columnIndex
        self.totalRows = totalRows
        self.density = density
        self.swapProbability = swapProbability
        self.minSwapDelay = minSwapDelay
        self.maxSwapDelay = maxSwapDelay
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
        self.minDropLength = minDropLength
        self.maxDropLength = maxDropLength
        self.grid = Array(repeating: nil, count: totalRows)
        
        self.dropHeadRow = Int.random(in: -totalRows...0)
        spawnNextDrop()
    }
    
    private func spawnNextDrop() {
        // Uniformly sample a fresh fall speed for each new drop stream
        let lowS = min(minSpeed, maxSpeed)
        let highS = max(minSpeed, maxSpeed)
        self.currentDropSpeed = Double.random(in: lowS...highS)
        
        let rand = Double.random(in: 0...1)
        if rand > density {
            // invisible gap
            activeDrop = .gap(length: Int.random(in: 4...16))
        } else if rand < 0.15 {
            // deletion string: invisible wiper string erasing existing glyphs
            activeDrop = .deletion(length: Int.random(in: 8...24))
        } else {
            // visible rain drop string
            let low = min(minDropLength, maxDropLength)
            let high = max(minDropLength, maxDropLength)
            activeDrop = .visible(length: Int.random(in: low...high))
        }
    }
    
    func update(deltaTime: Double) {
        // Advance drop progression using this drop's freshly sampled fall speed (Rows Per Second)
        dropProgress += currentDropSpeed * deltaTime
        
        while dropProgress >= 1.0 {
            dropProgress -= 1.0
            dropHeadRow += 1
            
            let currentDrop = activeDrop ?? .gap(length: 10)
            switch currentDrop {
            case .visible(let length):
                if dropHeadRow >= 0 && dropHeadRow < totalRows {
                    // Clear previous head flag
                    for r in 0..<totalRows {
                        if let c = grid[r], c.isHead { c.isHead = false }
                    }
                    
                    let shouldSwap = (Double.random(in: 0...1) < swapProbability)
                    let minFrames = max(1, Int(minSwapDelay * 60.0))
                    let maxFrames = max(minFrames, Int(maxSwapDelay * 60.0))
                    let initialTimer = Int.random(in: minFrames...maxFrames)
                    
                    let newCell = MatrixCell(
                        mnistIndex: MNISTAtlas.shared.getRandomImageIndex(),
                        canSwap: shouldSwap,
                        swapTimer: initialTimer
                    )
                    newCell.isHead = true
                    newCell.dropLength = length
                    grid[dropHeadRow] = newCell
                }
                if dropHeadRow >= (totalRows + length) {
                    spawnNextDrop()
                    dropHeadRow = -Int.random(in: 1...5)
                }
                
            case .gap(let length):
                if dropHeadRow >= length {
                    spawnNextDrop()
                    dropHeadRow = -Int.random(in: 1...3)
                }
                
            case .deletion(let length):
                if dropHeadRow >= 0 && dropHeadRow < totalRows {
                    grid[dropHeadRow] = nil // Wipe cell
                }
                if dropHeadRow >= (totalRows + length) {
                    spawnNextDrop()
                    dropHeadRow = -Int.random(in: 1...4)
                }
            }
        }
        
        // Update changing morphing glyph timers for designated swap cells & clear expired trail cells
        for r in 0..<totalRows {
            guard let cell = grid[r] else { continue }
            
            if cell.canSwap {
                cell.changeTimer -= 1
                if cell.changeTimer <= 0 {
                    cell.oldMnistIndex = cell.mnistIndex
                    cell.mnistIndex = MNISTAtlas.shared.getRandomImageIndex()
                    cell.isCrossFading = true
                    cell.canSwap = false // Single swap completed: disable future swaps
                }
            } else if cell.isCrossFading {
                cell.isCrossFading = false
            }
            
            // Cell expires strictly when drop head has advanced beyond dropLength grid rows
            let distFromHead = dropHeadRow - r
            if distFromHead > cell.dropLength + 1 {
                grid[r] = nil
            }
        }
    }
}
