"""
button_map.py — First-boot button mapping screen
Prompts user to press each button, saves mapping to data/buttons.json.
Runs automatically on first launch or if config is missing.
"""

import pygame
import json
import os
import time
from lib.ui import Page, COLORS, draw_text, draw_text_centered, draw_box, get_font


# Buttons to map in order — (internal_name, display_prompt)
BUTTONS_TO_MAP = [
    ("a",      "Press  A  (confirm)"),
    ("b",      "Press  B  (back)"),
    ("x",      "Press  X"),
    ("y",      "Press  Y"),
    ("l1",     "Press  L1  (left shoulder)"),
    ("r1",     "Press  R1  (right shoulder)"),
    ("select", "Press  SELECT"),
    ("start",  "Press  START"),
]

DEFAULT_CONFIG_PATH = "data/buttons.json"


def load_button_config(install_dir):
    """Load button mapping from file. Returns dict or None if not found."""
    path = os.path.join(install_dir, DEFAULT_CONFIG_PATH)
    try:
        with open(path) as f:
            config = json.load(f)
        # Validate it has all required keys
        required = {b[0] for b in BUTTONS_TO_MAP}
        if required.issubset(config.keys()):
            return config
    except:
        pass
    return None


def save_button_config(install_dir, config):
    """Save button mapping to file."""
    path = os.path.join(install_dir, DEFAULT_CONFIG_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(config, f, indent=2)


class ButtonMapPage(Page):
    """Interactive button mapping screen. Steps through each button."""

    def __init__(self, app, install_dir, on_complete=None):
        super().__init__(app)
        self.install_dir = install_dir
        self.on_complete = on_complete  # callback when mapping is done
        self.mapping = {}
        self.step = 0
        self.cooldown = 0  # prevent double-registering
        self.flash_timer = 0
        self.done = False
        self.countdown = 0  # brief countdown before first prompt

    def on_enter(self):
        self.mapping = {}
        self.step = 0
        self.done = False
        self.cooldown = 300  # small delay before first input accepted
        self.countdown = 1500  # 1.5s intro

    def update(self, dt):
        if self.cooldown > 0:
            self.cooldown -= dt
        if self.countdown > 0:
            self.countdown -= dt
        if self.flash_timer > 0:
            self.flash_timer -= dt

    def draw(self, surface):
        w = surface.get_width()
        h = surface.get_height()

        # Header
        draw_text_centered(surface, "BUTTON MAPPING", 30, COLORS["accent"], size=20, bold=True)
        draw_text_centered(surface, "Configure your gamepad for Nervos Launcher", 58, COLORS["muted"], size=12)

        # Progress dots
        dot_y = 90
        dot_spacing = 28
        total = len(BUTTONS_TO_MAP)
        start_x = (w - (total * dot_spacing)) // 2
        for i in range(total):
            x = start_x + i * dot_spacing
            if i < self.step:
                # Completed
                pygame.draw.circle(surface, COLORS["green"], (x, dot_y), 6)
            elif i == self.step and not self.done:
                # Current
                pulse = abs((pygame.time.get_ticks() % 1000) - 500) / 500.0
                color = (
                    int(0 + pulse * 200),
                    int(200 - pulse * 50),
                    int(255 - pulse * 55),
                )
                pygame.draw.circle(surface, color, (x, dot_y), 8)
            else:
                # Pending
                pygame.draw.circle(surface, COLORS["dim"], (x, dot_y), 5)

        if self.countdown > 0:
            # Intro
            draw_text_centered(surface, "Get ready...", h // 2 - 20, COLORS["text"], size=18)
            return

        if self.done:
            # All mapped — show summary
            self._draw_summary(surface)
            return

        # Current prompt
        if self.step < len(BUTTONS_TO_MAP):
            name, prompt = BUTTONS_TO_MAP[self.step]

            # Big prompt
            box_y = 130
            box = pygame.Rect(40, box_y, w - 80, 100)
            draw_box(surface, box, fill=COLORS["surface2"], border=COLORS["accent"])
            draw_text_centered(surface, prompt, box_y + 35, COLORS["text"], size=22, bold=True)

            # Hint
            draw_text_centered(surface, f"Step {self.step + 1} of {total}", box_y + 75, COLORS["muted"], size=11)

            # Already mapped buttons
            y = 260
            draw_text(surface, "Mapped so far:", 40, y, COLORS["muted"], size=11)
            y += 20
            for mapped_name, btn_id in self.mapping.items():
                draw_text(surface, f"  {mapped_name.upper()}", 40, y, COLORS["green"], size=12)
                draw_text(surface, f"button {btn_id}", 160, y, COLORS["muted"], size=12)
                y += 18

            # Flash feedback
            if self.flash_timer > 0:
                draw_text_centered(surface, "Got it!", h - 60, COLORS["green"], size=16, bold=True)

    def _draw_summary(self, surface):
        w = surface.get_width()
        h = surface.get_height()

        draw_text_centered(surface, "MAPPING COMPLETE", 130, COLORS["green"], size=18, bold=True)

        y = 170
        for name, btn_id in self.mapping.items():
            draw_text(surface, f"  {name.upper()}", 120, y, COLORS["text"], size=14)
            draw_text(surface, f"→  button {btn_id}", 260, y, COLORS["accent"], size=14)
            y += 24

        draw_text_centered(surface, "Press any button to continue", h - 50, COLORS["muted"], size=12)

    def handle_input(self, event):
        if self.countdown > 0:
            return True  # absorb all input during intro

        # Only handle joystick button presses
        if event.type != pygame.JOYBUTTONDOWN:
            # Also handle keyboard for desktop testing
            if event.type == pygame.KEYDOWN and not self.done:
                fake_btn = {
                    pygame.K_z: 0, pygame.K_x: 1, pygame.K_a: 2, pygame.K_s: 3,
                    pygame.K_q: 4, pygame.K_w: 5, pygame.K_TAB: 6, pygame.K_RETURN: 7,
                }.get(event.key)
                if fake_btn is not None:
                    return self._register_button(fake_btn)
            if event.type == pygame.KEYDOWN and self.done:
                self._finish()
                return True
            return False

        if self.cooldown > 0:
            return True  # absorb but don't register

        if self.done:
            # Any button after completion = save and continue
            self._finish()
            return True

        return self._register_button(event.button)

    def _register_button(self, button_id):
        if self.step >= len(BUTTONS_TO_MAP):
            return False

        # Don't allow same button for multiple actions
        if button_id in self.mapping.values():
            return True  # absorb but don't advance

        name, _ = BUTTONS_TO_MAP[self.step]
        self.mapping[name] = button_id
        self.step += 1
        self.cooldown = 250  # brief cooldown between steps
        self.flash_timer = 400

        if self.step >= len(BUTTONS_TO_MAP):
            self.done = True
            self.cooldown = 500  # longer pause before accepting "continue"

        return True

    def _finish(self):
        save_button_config(self.install_dir, self.mapping)
        # Update the app's button config
        self.app.button_map = self.mapping
        if self.on_complete:
            self.on_complete(self.mapping)
        else:
            self.app.go_home()
