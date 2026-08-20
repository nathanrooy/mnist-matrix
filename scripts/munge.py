#!/usr/bin/env python3
import struct
import sys
from pathlib import Path
import pyarrow.parquet as pq
from PIL import Image
import io

def main():
    script_dir = Path(__file__).parent
    project_dir = script_dir.parent
    parquet_path = project_dir / "data" / "test-00000-of-00001.parquet"
    output_path = project_dir / "resources" / "mnist_atlas.bin"

    if not parquet_path.exists():
        print(f"Error: {parquet_path} does not exist.")
        sys.exit(1)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Reading {parquet_path}...")
    table = pq.read_table(str(parquet_path))
    num_rows = table.num_rows
    print(f"Found {num_rows} rows.")

    images_col = table.column("image")
    labels_col = table.column("label")

    width = 28
    height = 28
    img_size = width * height

    # File Format:
    # Header: "MNST" (4 bytes) | num_images (uint32) | width (uint32) | height (uint32) = 16 bytes
    # Labels: num_images bytes (uint8 each)
    # Pixels: num_images * 28 * 28 bytes (uint8 each)

    header = struct.pack(">4sIII", b"MNST", num_rows, width, height)
    labels_bytes = bytearray()
    pixels_bytes = bytearray()

    print("Extracting MNIST images and labels...")
    for i in range(num_rows):
        img_dict = images_col[i].as_py()
        label = labels_col[i].as_py()
        raw_png = img_dict["bytes"]

        img = Image.open(io.BytesIO(raw_png)).convert("L")
        if img.size != (width, height):
            img = img.resize((width, height), Image.Resampling.BILINEAR)

        labels_bytes.append(label)
        pixels_bytes.extend(img.tobytes())

        if (i + 1) % 2000 == 0 or (i + 1) == num_rows:
            print(f"Processed {i + 1}/{num_rows} images...")

    with open(output_path, "wb") as f:
        f.write(header)
        f.write(labels_bytes)
        f.write(pixels_bytes)

    file_size = output_path.stat().st_size
    print(f"Successfully created {output_path} ({file_size} bytes / {file_size / (1024*1024):.2f} MB)")

if __name__ == "__main__":
    main()
