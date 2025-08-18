#!/usr/bin/env python3
"""
Generate a minimal valid PNG file for testing purposes.
Creates a 1x1 pixel transparent PNG.
"""
import struct
import zlib
import sys

def create_png_data():
    """Create a minimal 1x1 transparent PNG"""
    # PNG signature
    png_signature = b'\x89PNG\r\n\x1a\n'
    
    # IHDR chunk data: width=1, height=1, bit_depth=8, color_type=6 (RGBA), 
    # compression=0, filter=0, interlace=0
    ihdr_data = struct.pack('>LLBBBBB', 1, 1, 8, 6, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data) & 0xffffffff
    ihdr_chunk = struct.pack('>L', len(ihdr_data)) + b'IHDR' + ihdr_data + struct.pack('>L', ihdr_crc)
    
    # IDAT chunk: single transparent pixel (RGBA: 0,0,0,0)
    # Filter type 0 (None) + 4 bytes for RGBA
    pixel_data = b'\x00\x00\x00\x00\x00'  # Filter + RGBA
    compressed_data = zlib.compress(pixel_data)
    idat_crc = zlib.crc32(b'IDAT' + compressed_data) & 0xffffffff
    idat_chunk = struct.pack('>L', len(compressed_data)) + b'IDAT' + compressed_data + struct.pack('>L', idat_crc)
    
    # IEND chunk
    iend_crc = zlib.crc32(b'IEND') & 0xffffffff
    iend_chunk = struct.pack('>L', 0) + b'IEND' + struct.pack('>L', iend_crc)
    
    return png_signature + ihdr_chunk + idat_chunk + iend_chunk

def main():
    output_file = sys.argv[1] if len(sys.argv) > 1 else 'example.png'
    png_data = create_png_data()
    
    with open(output_file, 'wb') as f:
        f.write(png_data)
    
    print(f"Generated {output_file} ({len(png_data)} bytes)")

if __name__ == '__main__':
    main()
