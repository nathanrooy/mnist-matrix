import Foundation
import CoreGraphics
import AppKit

public class MNISTAtlas {
    public static let shared = MNISTAtlas()
    
    public private(set) var isLoaded: Bool = false
    public private(set) var totalImages: Int = 0
    public private(set) var width: Int = 28
    public private(set) var height: Int = 28
    
    private var pixelData: Data = Data()
    private var labelData: Data = Data()
    private var digitsByLabel: [[Int]] = Array(repeating: [], count: 10)
    
    // Cached scaled pixel buffers (key: (index << 16) | targetSize)
    private var scaledCache: [Int: [UInt8]] = [:]
    private let lock = NSLock()
    
    private init() {
        loadAtlas()
    }
    
    public func loadAtlas() {
        guard !isLoaded else { return }
        
        let bundle = Bundle(for: MNISTAtlas.self)
        guard let url = bundle.url(forResource: "mnist_atlas", withExtension: "bin") ??
                        Bundle.main.url(forResource: "mnist_atlas", withExtension: "bin") else {
            print("MNISTAtlas: mnist_atlas.bin not found in bundle.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count >= 16 else { return }
            
            // Header parsing: "MNST" (4 bytes) | count (UInt32 BE) | width (UInt32 BE) | height (UInt32 BE)
            let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii)
            guard magic == "MNST" else {
                print("MNISTAtlas: Invalid magic header \(String(describing: magic))")
                return
            }
            
            let countBE = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
            let widthBE = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
            let heightBE = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            self.totalImages = Int(UInt32(bigEndian: countBE))
            self.width = Int(UInt32(bigEndian: widthBE))
            self.height = Int(UInt32(bigEndian: heightBE))
            
            let labelOffset = 16
            let pixelOffset = labelOffset + self.totalImages
            let totalExpected = pixelOffset + (self.totalImages * self.width * self.height)
            
            guard data.count >= totalExpected else {
                print("MNISTAtlas: File size \(data.count) smaller than expected \(totalExpected)")
                return
            }
            
            self.labelData = data.subdata(in: labelOffset..<pixelOffset)
            self.pixelData = data.subdata(in: pixelOffset..<totalExpected)
            
            // Index digits by label (0..9)
            self.labelData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let labels = ptr.bindMemory(to: UInt8.self)
                for i in 0..<self.totalImages {
                    let label = Int(labels[i])
                    if label >= 0 && label <= 9 {
                        self.digitsByLabel[label].append(i)
                    }
                }
            }
            
            self.isLoaded = true
            print("MNISTAtlas: Loaded \(totalImages) images (\(width)x\(height)).")
        } catch {
            print("MNISTAtlas: Failed to load data: \(error)")
        }
    }
    
    public func getRandomImageIndex() -> Int {
        guard isLoaded, totalImages > 0 else { return 0 }
        return Int.random(in: 0..<totalImages)
    }
    
    public func getRandomImageIndex(forDigit digit: Int) -> Int {
        guard isLoaded, digit >= 0, digit <= 9 else { return getRandomImageIndex() }
        let indices = digitsByLabel[digit]
        guard !indices.isEmpty else { return getRandomImageIndex() }
        return indices[Int.random(in: 0..<indices.count)]
    }
    
    // MARK: - Fast Scaled Grayscale Pixel Access
    
    public func getScaledPixels(forIndex index: Int, targetSize: Int) -> [UInt8] {
        guard isLoaded, index >= 0, index < totalImages else {
            return [UInt8](repeating: 0, count: targetSize * targetSize)
        }
        
        let key = (index << 16) | targetSize
        lock.lock()
        if let cached = scaledCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let srcSize = width
        let pixelCount = srcSize * srcSize
        let start = index * pixelCount
        guard start + pixelCount <= pixelData.count else {
            return [UInt8](repeating: 0, count: targetSize * targetSize)
        }
        
        var scaled = [UInt8](repeating: 0, count: targetSize * targetSize)
        pixelData.withUnsafeBytes { ptr in
            let src = ptr.bindMemory(to: UInt8.self)
            for ty in 0..<targetSize {
                let sy = (ty * srcSize) / targetSize
                let srcRow = start + (sy * srcSize)
                let dstRow = ty * targetSize
                for tx in 0..<targetSize {
                    let sx = (tx * srcSize) / targetSize
                    scaled[dstRow + tx] = src[srcRow + sx]
                }
            }
        }
        
        lock.lock()
        scaledCache[key] = scaled
        lock.unlock()
        
        return scaled
    }
}
