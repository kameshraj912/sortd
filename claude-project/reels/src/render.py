"""Render a Reel HTML page to MP4, frame by frame.

Usage: python render.py reel1.html [more.html ...] [--stills]
Each page sets <body data-duration="14">. Output: ../out/<name>.mp4 (1080x1920, 30 fps, H.264).
--stills saves a few PNG frames per reel to ../out/stills/ for checking.
Needs: playwright (chromium), imageio-ffmpeg.
"""

import subprocess, sys
from pathlib import Path
import imageio_ffmpeg
from playwright.sync_api import sync_playwright

FPS = 30
HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "out"


def render(page, html: Path, stills: bool):
    page.goto(html.as_uri())
    page.evaluate("document.fonts.ready")
    page.wait_for_load_state("networkidle")
    page.evaluate("() => Promise.all([...document.images].map(i => i.decode()))")
    dur = float(page.evaluate("document.body.dataset.duration"))
    frames = int(round(dur * FPS))
    out = OUT / f"{html.stem}.mp4"
    cmd = [
        imageio_ffmpeg.get_ffmpeg_exe(),
        "-y",
        "-loglevel",
        "error",
        "-f",
        "image2pipe",
        "-framerate",
        str(FPS),
        "-i",
        "-",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=channel_layout=stereo:sample_rate=44100",
        "-map",
        "0:v",
        "-map",
        "1:a",
        "-shortest",
        "-c:v",
        "libx264",
        "-preset",
        "slow",
        "-crf",
        "17",
        "-pix_fmt",
        "yuv420p",
        "-r",
        str(FPS),
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-movflags",
        "+faststart",
        str(out),
    ]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    marks = {int(frames * f) for f in (0.08, 0.3, 0.5, 0.7, 0.95)} if stills else set()
    for i in range(frames):
        t = i / FPS
        page.evaluate(f"seek({t})")
        png = page.screenshot(type="png")
        ff.stdin.write(png)
        if i in marks:
            (OUT / "stills").mkdir(parents=True, exist_ok=True)
            (OUT / "stills" / f"{html.stem}_{t:05.2f}s.png").write_bytes(png)
    ff.stdin.close()
    if ff.wait() != 0:
        raise SystemExit(f"ffmpeg failed for {html.name}")
    print(f"{out.name}: {dur:.1f}s, {frames} frames")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    stills = "--stills" in sys.argv
    OUT.mkdir(exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page(viewport={"width": 540, "height": 960}, device_scale_factor=2)
        for a in args:
            render(page, (HERE / a).resolve(), stills)
        b.close()


if __name__ == "__main__":
    main()
