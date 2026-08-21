# MNIST Matrix Screen Saver

A native macOS screen saver that recreates *The Matrix* "[digital rain](https://en.wikipedia.org/wiki/Digital_rain)" effect using handwritten digits from the [MNIST dataset](https://en.wikipedia.org/wiki/MNIST_database).

https://github.com/user-attachments/assets/7f075083-ae36-46e4-92ab-50a61d03e622

![macOS Screen Saver](https://img.shields.io/badge/platform-macOS%2012.0%2B-blue)
![Language](https://img.shields.io/badge/language-Swift%205-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Quick Start & Building

If you're on an Apple Silicon Mac, you can simply download and unzip the pre-built screen saver that's already included in this repository ([`build/MNISTMatrix.saver.zip`](build/MNISTMatrix.saver.zip)). 

If you're on an Intel based Mac, or you just want to build it yourself, you can do so with the following commands:

```bash
# 1. Clone the repository
git clone https://github.com/nathanrooy/mnist-matrix.git
cd mnist-matrix

# 2. Build and Install (Auto-detects Apple Silicon or Intel)
./build.sh

# Or explicitly target architecture:
./build.sh arm64     # Apple Silicon M1 / M2 / M3 / M4
./build.sh x86_64    # Intel Macs

# 3. Test & Preview in System Settings
open "$HOME/Library/Screen Savers/MNISTMatrix.saver"
```

## Core Configuration Parameters

All visual parameters are defined at the top of [`src/MNISTMatrixSaverView.swift`](/src/MNISTMatrixSaverView.swift):

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `minFallSpeedRowsPerSecond` | `Double` | `6.0` | Minimum fall speed for a rain stream (rows/sec) |
| `maxFallSpeedRowsPerSecond` | `Double` | `12.0` | Maximum fall speed for a rain stream (rows/sec) |
| `minDropLengthRows` | `Int` | `8` | Minimum digit tail length of rain streams |
| `maxDropLengthRows` | `Int` | `36` | Maximum digit tail length of rain streams |
| `densityRatio` | `Double` | `0.50` | Fraction of screen columns containing active streams (0.3 to 1.0) |
| `baseDigitSize` | `CGFloat` | `18.0` | Grid cell & digit size in pixels |
| `digitSwapProbability` | `Double` | `0.50` | Fraction of falling digits that morph/swap (0.0 to 1.0) |
| `minSwapDelaySeconds` | `Double` | `0.25` | Minimum delay in seconds before a digit swaps |
| `maxSwapDelaySeconds` | `Double` | `1.25` | Maximum delay in seconds before a digit swaps |
| `showFPSOverlay` | `Bool` | `true` | Toggles yellow FPS counter overlay in top-right corner |

## Generating the Binary Atlas (Optional)

The pre-built [`resources/mnist_atlas.bin`](resources/mnist_atlas.bin) asset atlas (7.49 MB) is included in the repository. If however, you want to extract `resources/mnist_atlas.bin` yourself from the raw MNIST dataset ([`data/test-00000-of-00001.parquet`](data/test-00000-of-00001.parquet)):

```bash
# Requires Python 3 with pyarrow and Pillow
python3 scripts/munge.py
```

## Directory Structure

```
mnist-matrix/
├── README.md                      # Project documentation and guide
├── build.sh                       # Pure Swift build script (compiles, signs & installs)
├── data/
│   └── test-00000-of-00001.parquet# 10,000 row raw MNIST Parquet dataset
├── resources/
│   └── mnist_atlas.bin            # Pre-generated binary atlas (10,000 28x28 grayscale digits)
├── scripts/
│   └── munge.py                   # Python script to convert Parquet -> mnist_atlas.bin
└── src/
    ├── Info.plist                 # Screen saver bundle property list
    ├── MNISTAtlas.swift           # Memory-mapped binary atlas loader & scaled pixel cache
    └── MNISTMatrixSaverView.swift # Subclass of ScreenSaverView & DirectScreenRenderer
```

## Requirements

- **macOS 12.0 (Monterey)** or newer (Fully Sonoma, Sequoia, and Tahoe compatible).
- **Swift Command Line Tools** (`swiftc`, included with Xcode / Command Line Tools).

## License

MIT License. Feel free to use, modify, and distribute!
