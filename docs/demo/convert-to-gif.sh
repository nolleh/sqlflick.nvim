#!/bin/bash

# Convert MOV video to high-quality GIF
# This script uses 2-pass conversion method to minimize grid pattern (dithering artifacts)

INPUT_FILE="sqlflick-demo-20251203.mov"
OUTPUT_FILE="sqlflick-demo.gif"
PALETTE_FILE="palette.png"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
	echo "Error: Input file '$INPUT_FILE' not found!"
	exit 1
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &>/dev/null; then
	echo "Error: ffmpeg is not installed. Please install it first."
	exit 1
fi

echo "Step 1: Generating optimized palette..."
ffmpeg -i "$INPUT_FILE" \
	-vf "fps=10,scale=1200:-1:flags=lanczos,palettegen" \
	-y "$PALETTE_FILE"

if [ $? -ne 0 ]; then
	echo "Error: Failed to generate palette"
	exit 1
fi

echo "Step 2: Creating GIF with optimized palette..."
ffmpeg -i "$INPUT_FILE" \
	-i "$PALETTE_FILE" \
	-filter_complex "fps=10,scale=1200:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" \
	"$OUTPUT_FILE"

if [ $? -eq 0 ]; then
	echo "Success! GIF created: $OUTPUT_FILE"
	echo "Cleaning up palette file..."
	rm "$PALETTE_FILE"
else
	echo "Error: Failed to create GIF"
	exit 1
fi
