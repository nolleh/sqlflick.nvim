#!/bin/bash

# Convert MOV video to high-quality GIF
# This script uses 2-pass conversion method to minimize grid pattern (dithering artifacts)
#
# Usage: ./convert-to-gif.sh <input_file> [output_file] [scale] [fps]
#   input_file:  Input video file (required)
#   output_file: Output GIF file (optional, default: same name as input with .gif extension)
#   scale:       Width in pixels (optional, default: 1200)
#   fps:         Frames per second (optional, default: 10)
#
# Examples:
#   ./convert-to-gif.sh video.mov                    # Creates video.gif (1200px, 10fps)
#   ./convert-to-gif.sh video.mov demo.gif           # Creates demo.gif (1200px, 10fps)
#   ./convert-to-gif.sh video.mov demo.gif 800       # Creates demo.gif (800px, 10fps)
#   ./convert-to-gif.sh video.mov demo.gif 800 8     # Creates demo.gif (800px, 8fps)

# Check if input file argument is provided
if [ $# -lt 1 ]; then
	echo "Error: Input file is required!"
	echo "Usage: $0 <input_file> [output_file] [scale] [fps]"
	echo ""
	echo "Examples:"
	echo "  $0 video.mov                    # Creates video.gif (1200px, 10fps)"
	echo "  $0 video.mov demo.gif           # Creates demo.gif (1200px, 10fps)"
	echo "  $0 video.mov demo.gif 800       # Creates demo.gif (800px, 10fps)"
	echo "  $0 video.mov demo.gif 800 8     # Creates demo.gif (800px, 8fps)"
	exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-${INPUT_FILE%.*}.gif}" # Default: same name with .gif extension
SCALE="${3:-1200}"                       # Default: 1200px
FPS="${4:-10}"                           # Default: 10fps
PALETTE_FILE="palette-${OUTPUT_FILE%.*}.png"

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
	-filter_complex "fps=${FPS},scale=${SCALE}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" \
	-y "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
	echo ""
	echo "Success! GIF created: $OUTPUT_FILE"
	echo "File size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
	echo "Cleaning up palette file..."
	rm "$PALETTE_FILE"
else
	echo "Error: Failed to create GIF"
	exit 1
fi
