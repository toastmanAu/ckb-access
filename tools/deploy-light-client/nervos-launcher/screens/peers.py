"""
peers.py — Connected peers screen
Shows list of connected peers with addresses and protocols.
"""

import pygame
from lib.ui import Page, ScrollList, COLORS, draw_text, draw_status_bar, draw_nav_bar


class PeersPage(Page):

    def __init__(self, app, rpc):
        super().__init__(app)
        self.rpc = rpc
        self.peer_list = ScrollList([], item_height=48, visible_area_top=44, visible_area_bottom=32)
        self.refresh_timer = 0

    def on_enter(self):
        self._refresh()

    def update(self, dt):
        self.refresh_timer += dt
        if self.refresh_timer > 10000:
            self._refresh()
            self.refresh_timer = 0

    def _refresh(self):
        peers = self.rpc.peers() or []
        items = []
        for p in peers:
            node_id = p.get("node_id", "")[:16] + "..."
            addresses = p.get("addresses", [])
            addr = addresses[0].get("address", "—") if addresses else "—"
            version = p.get("version", "")
            items.append({
                "text": node_id,
                "subtext": version or "—",
                "detail": addr,
                "color": COLORS["text"],
                "subcolor": COLORS["green"],
            })
        self.peer_list.update_items(items)

    def draw(self, surface):
        peers = self.rpc.peers() or []
        draw_status_bar(surface, "Peers", f"{len(peers)} connected")

        if not self.peer_list.items:
            draw_text(surface, "No peers connected", 16, 60, COLORS["muted"], size=14)
        else:
            # Custom draw for two-line items
            y = 44
            vis = self.peer_list.visible_count
            offset = self.peer_list.scroll_offset
            items = self.peer_list.items

            for i in range(offset, min(offset + vis, len(items))):
                item = items[i]
                is_sel = (i == self.peer_list.cursor)
                rect = pygame.Rect(8, y, surface.get_width() - 16, 44)

                if is_sel:
                    pygame.draw.rect(surface, COLORS["surface2"], rect, border_radius=4)
                    pygame.draw.rect(surface, COLORS["accent"], rect, width=1, border_radius=4)

                draw_text(surface, item["text"], 16, y + 4, COLORS["text"], size=12)
                draw_text(surface, item.get("subtext", ""), surface.get_width() - 80, y + 4,
                          COLORS["green"], size=11)
                draw_text(surface, item.get("detail", ""), 16, y + 22, COLORS["muted"], size=10,
                          max_width=surface.get_width() - 32)

                y += 48

        draw_nav_bar(surface, [("B", "Back"), ("A", "Refresh"), ("D-pad", "Scroll")])

    def handle_input(self, event):
        if event.type == pygame.USEREVENT:
            d = event.dict.get("dpad", "")
            if d == "up": self.peer_list.move(-1)
            elif d == "down": self.peer_list.move(1)
            return True
        if event.type == pygame.JOYBUTTONDOWN and event.button == 0:
            self._refresh()
            return True
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_UP: self.peer_list.move(-1)
            elif event.key == pygame.K_DOWN: self.peer_list.move(1)
            elif event.key == pygame.K_RETURN: self._refresh()
            return True
        return False
