import sys
import os
# Set dummy video driver for headless environments
os.environ["SDL_VIDEODRIVER"] = "dummy"
# Suppress Pygame welcome message
os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "hide"

import numpy as np
import pygame
import argparse
import math
import random

# --- Configuration ---
FPS = 30
SAMPLE_RATE = 44100
CHUNK_SIZE = int(SAMPLE_RATE / FPS)

def get_audio_chunk():
    raw_data = sys.stdin.buffer.read(CHUNK_SIZE * 2)
    if not raw_data or len(raw_data) < CHUNK_SIZE * 2:
        return None
    return np.frombuffer(raw_data, dtype=np.int16) / 32768.0

def get_fft(audio_data):
    window = np.hanning(len(audio_data))
    fft_data = np.abs(np.fft.rfft(audio_data * window))
    return fft_data

# --- Visualizers ---

class LavaLamp:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.blobs = []
        self.colors = [
            (255, 69, 0), (255, 140, 0), (138, 43, 226), (255, 0, 255)
        ]

    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        bass_range = int(len(fft_data) * 0.1)
        bass_energy = np.mean(fft_data[:bass_range]) / 5.0
        bass_energy = np.clip(bass_energy, 0, 1)

        if bass_energy > 0.4 and random.random() < 0.2:
            radius = random.randint(30, 80)
            x = random.randint(0, self.width)
            speed = random.uniform(2, 5)
            color = random.choice(self.colors)
            self.blobs.append({'x': x, 'y': self.height + radius, 'r': radius, 'base_r': radius, 's': speed, 'c': color, 'phase': random.uniform(0, 6.28)})

        if len(self.blobs) < 5:
             radius = random.randint(30, 80)
             x = random.randint(0, self.width)
             speed = random.uniform(2, 5)
             color = random.choice(self.colors)
             self.blobs.append({'x': x, 'y': self.height + radius, 'r': radius, 'base_r': radius, 's': speed, 'c': color, 'phase': random.uniform(0, 6.28)})

        screen.fill((20, 0, 20))
        
        for b in self.blobs:
            b['y'] -= b['s'] * (1 + bass_energy * 2)
            b['phase'] += 0.1
            b['x'] += math.sin(b['phase']) * 2
            target_r = b['base_r'] * (1 + bass_energy * 0.5)
            b['r'] = b['r'] * 0.9 + target_r * 0.1
            
            # Draw blob
            surf = pygame.Surface((int(b['r']*2), int(b['r']*2)), pygame.SRCALPHA)
            pygame.draw.circle(surf, (*b['c'], 150), (int(b['r']), int(b['r'])), int(b['r']))
            pygame.draw.circle(surf, (255, 255, 255, 200), (int(b['r']), int(b['r'])), int(b['r']*0.5))
            screen.blit(surf, (int(b['x']-b['r']), int(b['y']-b['r'])))

        self.blobs = [b for b in self.blobs if b['y'] > -b['r']*2]

class Bars:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.num_bars = 64
        self.bar_width = width / self.num_bars
        self.heights = np.zeros(self.num_bars)

    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        # Logarithmic binning for better visual spread
        bins = np.logspace(0, np.log10(len(fft_data)), self.num_bars + 1).astype(int)
        
        screen.fill((10, 10, 15))
        
        for i in range(self.num_bars):
            start, end = bins[i], bins[i+1]
            if end <= start: end = start + 1
            
            # Get magnitude
            mag = np.mean(fft_data[start:end]) if start < len(fft_data) else 0
            mag = np.log10(mag + 1) * 20 # dB scale-ish
            
            # Smooth decay
            target_h = min(mag * 10, self.height)
            self.heights[i] = self.heights[i] * 0.8 + target_h * 0.2
            
            h = self.heights[i]
            
            # Color gradient based on height
            hue = (i / self.num_bars) * 360
            color = pygame.Color(0)
            color.hsla = (hue, 100, 50, 100)
            
            rect = pygame.Rect(i * self.bar_width, self.height - h, self.bar_width - 2, h)
            pygame.draw.rect(screen, color, rect)
            
            # Reflection
            rect_ref = pygame.Rect(i * self.bar_width, self.height, self.bar_width - 2, h * 0.3)
            pygame.draw.rect(screen, (color.r//4, color.g//4, color.b//4), rect_ref)

class Waveform:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.points = []

    def update(self, audio_data, screen):
        screen.fill((0, 0, 0))
        
        # Subsample to fit width
        step = max(1, len(audio_data) // self.width)
        points = []
        for x in range(0, self.width):
            idx = int(x / self.width * len(audio_data))
            y = int(self.height/2 + audio_data[idx] * self.height/2)
            points.append((x, y))
            
        if len(points) > 1:
            pygame.draw.lines(screen, (0, 255, 200), False, points, 2)
            # Glow effect
            pygame.draw.lines(screen, (0, 100, 80), False, points, 6)

class Particles:
    def __init__(self, width, height, color_name="white"):
        self.width = width
        self.height = height
        self.particles = []
        self.center = (width//2, height//2)
        self.color_name = color_name
        
        # Color palettes
        self.palettes = {
            "white": [(200, 200, 255), (255, 255, 255)],
            "fire": [(255, 50, 0), (255, 150, 0), (255, 200, 50)],
            "ice": [(0, 200, 255), (100, 255, 255), (200, 200, 255)],
            "neon": [(255, 0, 255), (0, 255, 255), (255, 255, 0)],
            "matrix": [(0, 255, 0), (50, 200, 50), (100, 255, 100)]
        }
        self.current_palette = self.palettes.get(color_name, self.palettes["white"])

    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        bass = np.mean(fft_data[:10])
        mid = np.mean(fft_data[10:100])
        
        # Spawn particles - INCREASED RATE
        # Spawn more particles based on energy
        spawn_count = int(mid * 2) # Increased multiplier
        if spawn_count > 0:
            for _ in range(spawn_count):
                angle = random.uniform(0, 6.28)
                speed = random.uniform(2, 15) + bass * 2 # Faster
                color = random.choice(self.current_palette)
                self.particles.append({
                    'x': self.center[0], 'y': self.center[1],
                    'vx': math.cos(angle) * speed, 'vy': math.sin(angle) * speed,
                    'life': random.randint(100, 255), 
                    'color': color,
                    'size': random.randint(2, 5)
                })

        screen.fill((0, 0, 0))
        
        # Update and draw
        for p in self.particles:
            p['x'] += p['vx']
            p['y'] += p['vy']
            p['life'] -= 3 # Slower fade for longer trails
            
            if p['life'] > 0:
                # Fade alpha
                # Pygame surface for alpha
                s = pygame.Surface((p['size']*2, p['size']*2), pygame.SRCALPHA)
                c = (*p['color'], p['life'])
                pygame.draw.circle(s, c, (p['size'], p['size']), p['size'])
                screen.blit(s, (int(p['x']-p['size']), int(p['y']-p['size'])))
        
        self.particles = [p for p in self.particles if p['life'] > 0 and 0 <= p['x'] <= self.width and 0 <= p['y'] <= self.height]

class SpectrumRadial:
    def __init__(self, width, height, color_name="rainbow", image_path=None, logo_path=None, logo_layer="front", logo_scale=0.4):
        self.width = width
        self.height = height
        self.center = (width // 2, height // 2)
        self.radius = min(width, height) // 3
        self.num_bars = 120
        self.bars = np.zeros(self.num_bars)
        self.color_name = color_name
        self.image_surf = None
        self.logo_surf = None
        self.logo_layer = logo_layer
        
        # Load Background Image (Fill Screen)
        if image_path and os.path.exists(image_path):
            try:
                img = pygame.image.load(image_path).convert_alpha()
                self.image_surf = pygame.transform.smoothscale(img, (width, height))
            except Exception as e:
                sys.stderr.write(f"Error loading radial image: {e}\n")

        # Load Logo Image (Scaled)
        if logo_path and os.path.exists(logo_path):
            try:
                logo = pygame.image.load(logo_path).convert_alpha()
                # Scale based on screen height percentage
                target_h = int(height * logo_scale)
                aspect = logo.get_width() / logo.get_height()
                target_w = int(target_h * aspect)
                self.logo_surf = pygame.transform.smoothscale(logo, (target_w, target_h))
            except Exception as e:
                sys.stderr.write(f"Error loading logo: {e}\n")
        
    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        # Logarithmic binning
        bins = np.logspace(0, np.log10(len(fft_data)), self.num_bars + 1).astype(int)
        
        screen.fill((0, 0, 0))
        
        # 1. Draw Background Image (Always behind bars)
        if self.image_surf:
            screen.blit(self.image_surf, (0, 0))

        # 2. Draw Logo (If layer is 'back')
        if self.logo_surf and self.logo_layer == "back":
            logo_rect = self.logo_surf.get_rect(center=self.center)
            screen.blit(self.logo_surf, logo_rect)
        
        # 3. Draw circular guide
        pygame.draw.circle(screen, (20, 20, 20), self.center, self.radius, 1)
        
        # 4. Draw Bars
        for i in range(self.num_bars):
            start, end = bins[i], bins[i+1]
            if end <= start: end = start + 1
            mag = np.mean(fft_data[start:end]) if start < len(fft_data) else 0
            mag = np.log10(mag + 1) * 20
            
            # Smooth
            self.bars[i] = self.bars[i] * 0.85 + mag * 0.15
            h = self.bars[i] * 5
            
            angle = (i / self.num_bars) * 2 * math.pi
            
            # Start point (on circle)
            start_x = self.center[0] + math.cos(angle) * self.radius
            start_y = self.center[1] + math.sin(angle) * self.radius
            
            # End point (outwards)
            end_x = self.center[0] + math.cos(angle) * (self.radius + h)
            end_y = self.center[1] + math.sin(angle) * (self.radius + h)
            
            # Color Logic
            color = pygame.Color(255, 255, 255)
            if self.color_name == "rainbow":
                hue = (i / self.num_bars) * 360
                color.hsla = (hue, 100, 50, 100)
            elif self.color_name == "fire":
                val = min(255, int(h * 10))
                color = (255, val, 0)
            elif self.color_name == "ice":
                val = min(255, int(h * 10))
                color = (0, val, 255)
            elif self.color_name == "matrix":
                val = min(255, int(h * 10))
                color = (0, 255, val)
            
            pygame.draw.line(screen, color, (start_x, start_y), (end_x, end_y), 3)
            
            # Mirror (Inwards)
            end_x_in = self.center[0] + math.cos(angle) * (self.radius - h * 0.3)
            end_y_in = self.center[1] + math.sin(angle) * (self.radius - h * 0.3)
            pygame.draw.line(screen, (color.r//3, color.g//3, color.b//3), (start_x, start_y), (end_x_in, end_y_in), 3)

        # 5. Draw Logo (If layer is 'front')
        if self.logo_surf and self.logo_layer == "front":
            logo_rect = self.logo_surf.get_rect(center=self.center)
            screen.blit(self.logo_surf, logo_rect)

class Terrain3D:
    def __init__(self, width, height, color_name="cyan"):
        self.width = width
        self.height = height
        self.rows = 40
        self.cols = 40
        self.grid_w = width * 2
        self.grid_h = height * 2
        self.cell_w = self.grid_w / self.cols
        self.cell_h = self.grid_h / self.rows
        self.z_map = np.zeros((self.rows, self.cols))
        self.speed = 2
        self.color_name = color_name
        
    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        
        # Shift rows down (scrolling effect)
        self.z_map[1:] = self.z_map[:-1]
        
        # New row based on FFT
        new_row = np.zeros(self.cols)
        bins = np.linspace(0, len(fft_data)//4, self.cols).astype(int) # Linear for terrain looks better usually
        for i in range(self.cols):
            idx = bins[i]
            val = fft_data[idx] if idx < len(fft_data) else 0
            new_row[i] = np.log10(val + 1) * 50
        self.z_map[0] = new_row
        
        screen.fill((0, 0, 10))
        
        # Simple 3D Projection
        # Center of screen is vanishing point
        cx, cy = self.width // 2, self.height // 3
        
        for y in range(self.rows - 1):
            for x in range(self.cols - 1):
                # We only draw lines, no filled polys for speed
                
                # Calculate 3D coords for 4 points of a quad
                # x goes -1 to 1, y goes 0 to 1 (depth)
                
                def project(r, c):
                    # Perspective projection
                    # Z grows with row index (y)
                    z_depth = 100 + r * 20
                    scale = 400 / z_depth
                    
                    x_pos = (c - self.cols/2) * self.cell_w
                    y_pos = 200 # Floor level
                    y_pos -= self.z_map[r, c] # Height
                    
                    px = cx + x_pos * scale
                    py = cy + y_pos * scale + r * 5 # Tilt
                    return (px, py)

                p1 = project(y, x)
                p2 = project(y, x+1)
                # p3 = project(y+1, x+1) # Not needed for lines
                p4 = project(y+1, x)
                
                # Color based on height
                h_val = self.z_map[y, x]
                c_val = min(255, max(50, int(h_val * 5)))
                
                if self.color_name == "cyan":
                    color = (0, c_val, c_val)
                elif self.color_name == "magenta":
                    color = (c_val, 0, c_val)
                elif self.color_name == "green":
                    color = (0, c_val, 0)
                elif self.color_name == "red":
                    color = (c_val, 0, 0)
                else:
                    color = (c_val, c_val, c_val)
                
                # Draw grid lines
                pygame.draw.line(screen, color, p1, p2, 1)
                pygame.draw.line(screen, color, p1, p4, 1)

class RealFire:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.scale = 4
        self.w = width // self.scale
        self.h = height // self.scale
        self.buffer = np.zeros((self.h, self.w), dtype=np.uint8)
        
        # Create palette (Black -> Red -> Orange -> Yellow -> White)
        self.palette = []
        for i in range(256):
            if i < 64: # Black to Red
                r = i * 4
                g = 0
                b = 0
            elif i < 128: # Red to Yellow
                r = 255
                g = (i - 64) * 4
                b = 0
            elif i < 192: # Yellow to White
                r = 255
                g = 255
                b = (i - 128) * 4
            else: # White
                r = 255
                g = 255
                b = 255
            self.palette.append((min(255,r), min(255,g), min(255,b)))
            
        self.surf = pygame.Surface((self.w, self.h), 0, 8)
        self.surf.set_palette(self.palette)

    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        bass = np.mean(fft_data[:10])
        mid = np.mean(fft_data[10:50])
        
        # 1. Seed the bottom row (Fire Source)
        # Intensity modulated by bass
        intensity = int(min(255, 150 + bass * 100))
        
        # Randomize source slightly
        noise = np.random.randint(0, 50, self.w)
        source = np.clip(intensity - noise, 0, 255).astype(np.uint8)
        self.buffer[-1, :] = source
        
        # 2. Propagate Fire
        # Algorithm: pixel[y, x] = pixel[y+1, (x +/- rand)] - decay
        
        # Get the source (everything from row 1 downwards)
        src = self.buffer[1:].astype(np.int16)
        
        # Decay factor (higher = shorter fire)
        # Modulate decay with Mids (More mids = taller fire = less decay)
        base_decay = 3
        if mid > 0.5: base_decay = 1
        
        decay = np.random.randint(0, base_decay + 2, src.shape)
        
        # Horizontal spread (Wind/Turbulence)
        # We create 3 versions of src: shifted left, center, shifted right
        roll_l = np.roll(src, -1, axis=1)
        roll_r = np.roll(src, 1, axis=1)
        roll_c = src
        
        # Randomly choose which pixel to pull from for each spot
        choices = np.random.randint(0, 3, src.shape)
        new_vals = np.choose(choices, [roll_l, roll_c, roll_r])
        
        # Apply decay
        new_vals -= decay
        new_vals = np.clip(new_vals, 0, 255).astype(np.uint8)
        
        # Update buffer
        self.buffer[:-1] = new_vals
        
        # 3. Render
        # Blit the 8-bit buffer to the 8-bit surface
        # surfarray.blit_array expects (w, h), so we transpose our (h, w) buffer
        pygame.surfarray.blit_array(self.surf, self.buffer.T)
        
        # Scale up to full screen
        # Convert 8-bit surface to 32-bit for scaling to main screen
        surf_32 = self.surf.convert(32)
        pygame.transform.scale(surf_32, (self.width, self.height), screen)

class ReactiveText:
    def __init__(self, width, height, text=None, image_path=None):
        self.width = width
        self.height = height
        self.text = text
        self.image_path = image_path
        self.surface = None
        
        if self.image_path and os.path.exists(self.image_path):
            try:
                img = pygame.image.load(self.image_path)
                
                try:
                    img = img.convert_alpha()
                except Exception:
                    pass

                # Resize to reasonable initial size (e.g., 1/3 screen width)
                aspect = img.get_width() / img.get_height()
                target_w = width // 3
                target_h = int(target_w / aspect)
                self.surface = pygame.transform.smoothscale(img, (target_w, target_h))
            except Exception as e:
                sys.stderr.write(f"Error loading image: {e}\n")
        
        if self.surface is None: # Fallback to text
            display_text = self.text if self.text else "MUSIC"
            # Try to use a nice system font if available, else default
            font = pygame.font.Font(None, 200)
            self.surface = font.render(display_text, True, (255, 255, 255))

    def update(self, audio_data, screen):
        fft_data = get_fft(audio_data)
        bass_range = int(len(fft_data) * 0.1)
        bass_energy = np.mean(fft_data[:bass_range]) / 5.0
        bass_energy = np.clip(bass_energy, 0, 1)
        
        screen.fill((10, 10, 15))
        
        # Draw background effect (faint radial waves)
        center = (self.width // 2, self.height // 2)
        
        # Pulse circles
        for i in range(3):
            r = int(min(self.width, self.height) * (0.3 + i*0.1 + bass_energy * 0.1))
            alpha = int(50 * (1 - i*0.2))
            pygame.draw.circle(screen, (50, 0, 50), center, r, 2)

        # Scale logo/text
        scale = 1.0 + bass_energy * 0.3
        w = int(self.surface.get_width() * scale)
        h = int(self.surface.get_height() * scale)
        
        scaled_surf = pygame.transform.smoothscale(self.surface, (w, h))
        
        # Center
        x = (self.width - w) // 2
        y = (self.height - h) // 2
        
        screen.blit(scaled_surf, (x, y))
        
        # If image mode, print path for debugging (only once)
        if self.image_path and not hasattr(self, 'debug_printed'):
             # sys.stderr.write(f"Debug: Using image {self.image_path}\n")
             self.debug_printed = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--mode", type=str, default="lava", choices=["lava", "bars", "wave", "particles", "radial", "terrain", "text", "fire"])
    parser.add_argument("--text", type=str, default=None, help="Text to display in text mode")
    parser.add_argument("--image", type=str, default=None, help="Path to image for text/radial mode")
    parser.add_argument("--logo", type=str, default=None, help="Path to logo for radial mode")
    parser.add_argument("--logo_layer", type=str, default="front", choices=["front", "back"], help="Logo layer position")
    parser.add_argument("--logo_scale", type=float, default=0.4, help="Logo scale relative to screen height (0.1 to 1.0)")
    parser.add_argument("--color", type=str, default="white", help="Color palette name")
    args = parser.parse_args()

    pygame.init()
    # Initialize display even for headless to support convert_alpha()
    pygame.display.set_mode((1, 1))
    screen = pygame.Surface((args.width, args.height))

    if args.mode == "lava":
        viz = LavaLamp(args.width, args.height)
    elif args.mode == "bars":
        viz = Bars(args.width, args.height)
    elif args.mode == "wave":
        viz = Waveform(args.width, args.height)
    elif args.mode == "particles":
        viz = Particles(args.width, args.height, color_name=args.color)
    elif args.mode == "radial":
        viz = SpectrumRadial(args.width, args.height, color_name=args.color, image_path=args.image, logo_path=args.logo, logo_layer=args.logo_layer, logo_scale=args.logo_scale)
    elif args.mode == "terrain":
        viz = Terrain3D(args.width, args.height, color_name=args.color)
    elif args.mode == "text":
        viz = ReactiveText(args.width, args.height, text=args.text, image_path=args.image)
    elif args.mode == "fire":
        viz = RealFire(args.width, args.height)

    try:
        while True:
            audio = get_audio_chunk()
            if audio is None:
                break
                
            viz.update(audio, screen)
            
            video_data = pygame.image.tostring(screen, "RGB")
            sys.stdout.buffer.write(video_data)
    except Exception as e:
        sys.stderr.write(f"Error in viz_master.py: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
