#!/usr/bin/env python3
"""Generate a simple app icon for WhisperDictation using Core Graphics via subprocess."""
import subprocess
import sys
import os
import tempfile

def generate_icon(resources_dir):
    """Generate an .icns file from a rendered PNG."""
    iconset_dir = tempfile.mkdtemp(suffix=".iconset")

    # Sizes needed for .icns: 16, 32, 128, 256, 512 (plus @2x variants)
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for size in sizes:
        png_path = os.path.join(iconset_dir, f"icon_{size}x{size}.png")
        render_icon_png(png_path, size)

    # Create the proper iconset naming convention
    proper_iconset = tempfile.mkdtemp(suffix=".iconset")
    icon_sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, name in icon_sizes:
        src = os.path.join(iconset_dir, f"icon_{size}x{size}.png")
        dst = os.path.join(proper_iconset, name)
        if os.path.exists(src):
            os.link(src, dst)

    # Convert iconset to icns
    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", proper_iconset, "-o", icns_path], check=True)

    # Cleanup
    for f in os.listdir(iconset_dir):
        os.unlink(os.path.join(iconset_dir, f))
    os.rmdir(iconset_dir)
    for f in os.listdir(proper_iconset):
        os.unlink(os.path.join(proper_iconset, f))
    os.rmdir(proper_iconset)

    print(f"[Icon] Generated {icns_path}")


def render_icon_png(path, size):
    """Render a mic+waveform icon as PNG using sips and a simple approach."""
    # Use Python to draw a simple icon with the built-in graphics
    # We'll create an SVG and convert it
    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{size}" height="{size}" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="100%" style="stop-color:#16213e"/>
    </linearGradient>
    <linearGradient id="accent" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#4facfe"/>
      <stop offset="100%" style="stop-color:#00f2fe"/>
    </linearGradient>
  </defs>
  <!-- Background -->
  <rect width="512" height="512" rx="110" fill="url(#bg)"/>
  <!-- Waveform bars -->
  <g fill="url(#accent)" opacity="0.6">
    <rect x="80" y="220" width="24" height="72" rx="12"/>
    <rect x="120" y="180" width="24" height="152" rx="12"/>
    <rect x="160" y="200" width="24" height="112" rx="12"/>
  </g>
  <!-- Microphone body -->
  <rect x="220" y="120" width="72" height="160" rx="36" fill="url(#accent)"/>
  <!-- Mic stand arc -->
  <path d="M196 260 Q196 340 256 340 Q316 340 316 260" fill="none" stroke="url(#accent)" stroke-width="20" stroke-linecap="round"/>
  <!-- Mic stand -->
  <rect x="246" y="340" width="20" height="60" rx="10" fill="url(#accent)"/>
  <rect x="216" y="390" width="80" height="20" rx="10" fill="url(#accent)"/>
  <!-- Waveform bars right -->
  <g fill="url(#accent)" opacity="0.6">
    <rect x="348" y="200" width="24" height="112" rx="12"/>
    <rect x="388" y="180" width="24" height="152" rx="12"/>
    <rect x="428" y="220" width="24" height="72" rx="12"/>
  </g>
</svg>'''

    svg_path = path.replace('.png', '.svg')
    with open(svg_path, 'w') as f:
        f.write(svg)

    # Convert SVG to PNG using built-in tools
    # Try qlmanage first, then sips
    try:
        subprocess.run(
            ["qlmanage", "-t", "-s", str(size), "-o", os.path.dirname(path), svg_path],
            check=True, capture_output=True
        )
        # qlmanage outputs as filename.svg.png
        ql_output = svg_path + ".png"
        if os.path.exists(ql_output):
            os.rename(ql_output, path)
    except Exception:
        # Fallback: create a simple colored square
        subprocess.run([
            "sips", "-s", "format", "png",
            "--resampleWidth", str(size),
            "--resampleHeight", str(size),
            "-s", "formatOptions", "best",
            svg_path, "--out", path
        ], capture_output=True)

    # Clean up SVG
    if os.path.exists(svg_path):
        os.unlink(svg_path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate-icon.py <Resources_dir>")
        sys.exit(1)
    generate_icon(sys.argv[1])
