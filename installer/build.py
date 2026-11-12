"""Build a fresh portable folder from the active mod lab."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
name = sys.argv[1]
if Path(name).name != name or name in {".", ".."}:
    raise ValueError("Choose a new folder name under releases")
target = root / "releases" / name
target.mkdir(parents=True, exist_ok=False)
source = root.parent / "Ultimate Mod Lab/Emulator/Eden"
eden = target / "Data/Eden"
sd = eden / "user/sdmc"
for folder in (
    "ultimate/mods",
    "ultimate/config",
    "ultimate/arcropolis/config",
    "ultimate/arcropolis/resources",
    "atmosphere/contents/01006A800016E000",
):
    shutil.copytree(source / "user/sdmc" / folder, sd / folder)
echo_patch = Path("user/load/01006A800016E000/Ultimate+ Stacked Echoes")
shutil.copytree(root / "Data/Eden" / echo_patch, eden / echo_patch)
for filename in ("eden.exe", "LICENSE.txt", "README.md"):
    shutil.copy2(source / filename, eden / filename)
shutil.copytree(source / "LICENSES", eden / "LICENSES")
shutil.copy2(root / "Data/Update.ps1", target / "Data/Update.ps1")
shutil.copy2(root / "Update Ultimate+.cmd", target / "Update Ultimate+.cmd")

for name in ("Play Ultimate+.cmd", "Data/Play.ps1", "Data/SmashContent.json"):
    shutil.copy2(root / name, target / name)
