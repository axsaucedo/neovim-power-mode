"""Particle physics system for power-mode visual effects."""

import random
import time

NEON_COLORS = [
    (0, 255, 255),      # cyan
    (255, 20, 147),      # deep pink
    (191, 0, 255),       # electric purple
    (57, 255, 20),       # neon green
    (255, 102, 0),       # neon orange
]

MAX_PARTICLES = 200
GRAVITY = 0.15
DRAG = 0.95


class Particle:
    __slots__ = ("x", "y", "vx", "vy", "color", "alpha", "lifetime", "max_lifetime", "size")

    def __init__(self, x, y, vx, vy, color, lifetime=1.0, size=3.0):
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.color = color
        self.alpha = 1.0
        self.lifetime = lifetime
        self.max_lifetime = lifetime
        self.size = size

    @property
    def alive(self):
        return self.lifetime > 0


class ParticleSystem:
    def __init__(self):
        self._particles = []
        self._last_update = time.time()

    def spawn(self, x, y, count=5, speed_range=(2.0, 8.0)):
        """Spawn particles at (x, y) with random velocities and neon colors."""
        for _ in range(count):
            if len(self._particles) >= MAX_PARTICLES:
                break
            angle = random.uniform(0, 2 * 3.14159265)
            speed = random.uniform(*speed_range)
            vx = speed * random.uniform(-1, 1)
            vy = speed * random.uniform(-1.5, 0.5)  # bias upward
            color = random.choice(NEON_COLORS)
            lifetime = random.uniform(0.4, 1.2)
            size = random.uniform(2.0, 5.0)
            p = Particle(x, y, vx, vy, color, lifetime, size)
            self._particles.append(p)

    def update(self, dt=None):
        """Update particle physics: gravity, drag, lifetime decay."""
        now = time.time()
        if dt is None:
            dt = now - self._last_update
        self._last_update = now

        # Clamp dt to avoid huge jumps
        dt = min(dt, 0.05)

        alive = []
        for p in self._particles:
            p.vy += GRAVITY
            p.vx *= DRAG
            p.vy *= DRAG
            p.x += p.vx
            p.y += p.vy
            p.lifetime -= dt
            p.alpha = max(0.0, p.lifetime / p.max_lifetime)
            if p.alive:
                alive.append(p)
        self._particles = alive

    def get_particles(self):
        """Return list of active particles."""
        return self._particles

    def clear(self):
        self._particles.clear()

    @property
    def count(self):
        return len(self._particles)
