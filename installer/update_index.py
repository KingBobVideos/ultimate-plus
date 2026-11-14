"""Write a compressed index of the files distributed at a given Git revision."""
import gzip
import json
from pathlib import Path
import subprocess
import sys

revision, output = sys.argv[1:]
records = subprocess.check_output(["git", "ls-tree", "-rz", revision, "--",
    "Data", "README.md", "Update Ultimate+.cmd", "Play Ultimate+.cmd"])
files = {}
for record in records.split(b"\0"):
    if record:
        meta, path = record.split(b"\t", 1)
        mode, kind, sha = meta.split()
        if kind != b"blob" or mode == b"120000":
            raise ValueError(f"Unsupported package entry: {path!r}")
        files[path.decode()] = sha.decode()
data = json.dumps(files, separators=(",", ":")).encode()
Path(output, revision + ".json.gz").write_bytes(gzip.compress(data, mtime=0))
