# Demo Video Conversion Guide

## Overview

This directory contains the demo video for sqlflick.nvim. The original video is in MOV format, which needs to be converted to GIF for GitHub README display.

## Quick Start

Simply run the conversion script:

```bash
cd docs/demo
./convert-to-gif.sh
```

This will create `sqlflick-demo.gif` from `sqlflick-demo-20251203.mov`.

## What is a Palette?

### Understanding GIF Color Limitations

GIF format has a fundamental limitation: **it can only display 256 colors at once**. This is a legacy constraint from when GIF was created in the 1980s.

### The Problem with Direct Conversion

When you convert a video (which can have millions of colors) directly to GIF using a single command, the conversion tool has to:

1. Reduce millions of colors down to just 256 colors
2. Do this reduction **on-the-fly** for each frame
3. This often results in poor color representation and **grid patterns** (dithering artifacts)

### The Solution: 2-Pass Conversion with Palette

The 2-pass method solves this by:

#### Pass 1: Palette Generation

- Analyzes the **entire video** to find the best 256 colors
- Creates an optimized color palette (`palette.png`) that represents the video's color range
- This palette is carefully chosen to minimize color loss

#### Pass 2: GIF Creation

- Uses the pre-generated palette to convert each frame
- Applies **dithering** (a technique to simulate more colors using patterns)
- The `bayer_scale=5` parameter controls dithering intensity (lower = less grid pattern, but potentially more color banding)

### Why This Works Better

1. **Better Color Selection**: By analyzing the whole video first, we pick colors that work best across all frames
2. **Consistent Colors**: All frames use the same palette, preventing color shifts
3. **Controlled Dithering**: We can fine-tune how colors are approximated, reducing grid patterns
4. **Quality vs Size Balance**: Better quality without significantly increasing file size

## Technical Details

### Parameters Explained

- `fps=10`: Reduces frame rate to 10 FPS (GIFs don't need high FPS, and this reduces file size)
- `scale=1200:-1`: Resizes to 1200px width, maintaining aspect ratio
- `flags=lanczos`: High-quality scaling algorithm
- `palettegen`: Generates an optimized 256-color palette
- `paletteuse=dither=bayer:bayer_scale=5`: Uses the palette with Bayer dithering (scale 5 = moderate dithering)

### Dithering Explained

**Dithering** is a technique used to simulate colors that aren't in the palette by creating patterns of dots. For example:

- If you need "purple" but only have "red" and "blue" in the palette
- Dithering alternates red and blue pixels in a pattern
- From a distance, it looks like purple!

**Bayer dithering** uses a specific mathematical pattern (Bayer matrix) that's more visually pleasing than random patterns.

## Comparison

### Single-Pass (Direct Conversion)

```
Video → GIF (on-the-fly color reduction)
```

- ❌ Grid patterns visible
- ❌ Inconsistent colors between frames
- ❌ Poor color representation
- ✅ Fast (one command)

### Two-Pass (Palette-Based)

```
Video → Analyze → Generate Palette → Apply Palette → GIF
```

- ✅ Minimal grid patterns
- ✅ Consistent colors
- ✅ Better color representation
- ⚠️ Slower (two commands)

## Customization

You can adjust the script parameters:

- **FPS**: Change `fps=10` to `fps=15` for smoother animation (larger file)
- **Scale**: Change `scale=1200` to `scale=800` for smaller file size
- **Dithering**: Change `bayer_scale=5` to `bayer_scale=3` for less grid pattern (but more color banding)

## Troubleshooting

### Grid pattern still visible?

- Try reducing `bayer_scale` to 3 or 2
- Or try different dithering: `dither=sierra2_4a`

### File too large?

- Reduce FPS: `fps=8` or `fps=6`
- Reduce scale: `scale=800:-1`
- Reduce video duration in the source MOV file

### Colors look washed out?

- Increase `bayer_scale` to 7 or 8
- Or try `dither=floyd_steinberg` instead of `bayer`
