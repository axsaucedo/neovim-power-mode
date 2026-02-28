#!/usr/bin/env python3
"""Generate particle animation frames as PNG images for iTerm2 inline display."""

from PIL import Image, ImageDraw
import math
import random
import base64
import os

FRAME_WIDTH = 120
FRAME_HEIGHT = 60
NUM_FRAMES = 20
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "frames")

# Cyberpunk neon colors (RGBA)
COLORS = [
    (0, 255, 255, 255),    # Cyan
    (255, 20, 147, 255),   # Pink
    (191, 0, 255, 255),    # Purple
    (57, 255, 20, 255),    # Green
    (255, 102, 0, 255),    # Orange
]

class Particle:
    def __init__(self, x, y):
        angle = random.uniform(0, 2 * math.pi)
        speed = random.uniform(2, 8)
        self.x = x
        self.y = y
        self.vx = math.cos(angle) * speed
        self.vy = math.sin(angle) * speed - 3  # bias upward
        self.color = random.choice(COLORS)
        self.lifetime = 1.0
        self.size = random.uniform(1.5, 4.0)

    def update(self, dt=0.05):
        self.x += self.vx
        self.y += self.vy
        self.vy += 0.3  # gravity
        self.vx *= 0.95  # drag
        self.vy *= 0.95
        self.lifetime -= dt * 1.2
        self.size *= 0.97

def generate_explosion_frames():
    """Generate frames of a particle explosion animation."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Create particles at center
    cx, cy = FRAME_WIDTH // 2, FRAME_HEIGHT // 2
    particles = [Particle(cx, cy) for _ in range(30)]
    
    for frame_idx in range(NUM_FRAMES):
        img = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        for p in particles:
            if p.lifetime > 0:
                alpha = int(255 * max(0, p.lifetime))
                color = (p.color[0], p.color[1], p.color[2], alpha)
                r = max(0.5, p.size)
                draw.ellipse(
                    [p.x - r, p.y - r, p.x + r, p.y + r],
                    fill=color
                )
                # Glow effect: larger circle with lower alpha
                glow_alpha = int(alpha * 0.3)
                glow_color = (p.color[0], p.color[1], p.color[2], glow_alpha)
                gr = r * 2.5
                draw.ellipse(
                    [p.x - gr, p.y - gr, p.x + gr, p.y + gr],
                    fill=glow_color
                )
        
        # Update particles
        for p in particles:
            p.update()
        
        path = os.path.join(OUTPUT_DIR, f"frame_{frame_idx:03d}.png")
        img.save(path)
        print(f"Generated: {path}")
    
    # Also generate a single glow frame
    glow_img = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    for r in range(20, 0, -1):
        alpha = int(80 * (r / 20))
        glow_draw.ellipse([20-r, 20-r, 20+r, 20+r], fill=(0, 255, 255, alpha))
    glow_img.save(os.path.join(OUTPUT_DIR, "glow.png"))
    print(f"Generated: {os.path.join(OUTPUT_DIR, 'glow.png')}")

def frames_to_base64():
    """Convert frames to base64 for embedding in Lua."""
    b64_dir = os.path.join(os.path.dirname(__file__), "frames_b64")
    os.makedirs(b64_dir, exist_ok=True)
    
    for fname in sorted(os.listdir(OUTPUT_DIR)):
        if fname.endswith('.png'):
            path = os.path.join(OUTPUT_DIR, fname)
            with open(path, 'rb') as f:
                b64 = base64.b64encode(f.read()).decode('ascii')
            out_path = os.path.join(b64_dir, fname.replace('.png', '.b64'))
            with open(out_path, 'w') as f:
                f.write(b64)
            print(f"Base64: {out_path} ({len(b64)} chars)")

if __name__ == "__main__":
    generate_explosion_frames()
    frames_to_base64()
    print(f"\nGenerated {NUM_FRAMES} animation frames + glow in {OUTPUT_DIR}/")
    print(f"Base64 versions in frames_b64/")
