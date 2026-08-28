"""Finder layout for dmgbuild. Coordinates are points, matching dmg-background.svg."""

from pathlib import Path


# dmgbuild injects `defines` when evaluating this file, independently of cwd.
repo = Path(defines["repo"]).resolve()
app = repo / "Fluxa.app"
guide = repo / "docs" / "First Launch.txt"

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [str(app), (str(guide), "Read Me First.txt")]
symlinks = {"Applications": "/Applications"}
# Never SetFile the signed app: its FinderInfo attribute fails strict verification.
# Finder already treats .app as an application-bundle extension.
hide_extensions = ["Read Me First.txt"]
# A custom volume icon requires a loose .VolumeIcon.icns that Show Hidden Files
# exposes. Keep the native disk icon; Fluxa's logo remains in the installer itself.
icon = None
# build-dmg.py points Finder directly at the background inside the signed app.
# dmgbuild's normal image setting would create a loose .background.tiff instead.
background = None

# Reserve room for Finder's global path/status bars even if it ignores the per-folder
# hide requests. The 800 × 600 background includes edge bleed around the 760 × 520 layout.
window_rect = ((160, 140), (760, 584))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 90  # Finder discards icon-view settings if this is >= 100.
grid_offset = (0, 0)
scroll_position = (0, 0)
show_icon_preview = False
show_item_info = False
label_pos = "bottom"
text_size = 12
icon_size = 96
icon_locations = {
    "Fluxa.app": (210, 270),
    "Applications": (550, 270),
    "Read Me First.txt": (642, 424),
}
