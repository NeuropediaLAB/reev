#!/usr/bin/env python3
"""REEV Database Monitor — FastAPI backend."""

import asyncio
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="REEV DB Monitor", version="1.0.0")

# ── Configuration (env-var overridable for Docker) ────────────────────────────
DATA_DIR   = Path(os.environ.get("DATA_DIR",   "/mnt/pi-nas/raid-hdd/swarm-storage/reev-data/reev-static/data"))
LOG_FILE   = Path(os.environ.get("LOG_FILE",   "/mnt/pi-nas/raid-hdd/swarm-storage/reev-data/download-smart.log"))
NAS_HOST   = os.environ.get("NAS_HOST",   "192.168.0.193")
NAS_SCRIPT = os.environ.get("NAS_SCRIPT", "/mnt/swarm-storage/reev-data/download-smart.sh")
NAS_LOG    = os.environ.get("NAS_LOG",    "/mnt/swarm-storage/reev-data/download-smart.log")
SSH_KEY    = os.environ.get("SSH_KEY",    "/root/.ssh/id_ed25519")

# ── Database groups to monitor ─────────────────────────────────────────────────
DB_GROUPS = [
    {"id": "annonars-grch38", "label": "Annonars GRCh38",   "icon": "🧬", "path": DATA_DIR / "annonars/grch38"},
    {"id": "annonars-grch37", "label": "Annonars GRCh37",   "icon": "🧬", "path": DATA_DIR / "annonars/grch37",
     # Show download progress for these DBs inline while they're not yet symlinked
     "pending_downloads": [
         DATA_DIR / "download/annonars/dbnsfp-grch37-4.5a+0.39.0",
         DATA_DIR / "download/annonars/dbscsnv-grch37-1.1+0.39.0",
     ]},
    {"id": "annonars-genes",  "label": "Annonars Genes",    "icon": "🔗", "path": DATA_DIR / "annonars",
     "entries_filter": ["genes", "clinvar-genes"]},
    {"id": "mehari-grch38",   "label": "Mehari GRCh38",     "icon": "🔬", "path": DATA_DIR / "mehari/grch38"},
    {"id": "mehari-grch37",   "label": "Mehari GRCh37",     "icon": "🔬", "path": DATA_DIR / "mehari/grch37"},
    {"id": "dotty",           "label": "Dotty / SeqRepo",   "icon": "📍", "path": DATA_DIR / "dotty"},
    {"id": "viguno",          "label": "Viguno / HPO",      "icon": "🏥", "path": DATA_DIR / "viguno"},
    {"id": "cada-prio",       "label": "CADA-Prio Model",   "icon": "🤖", "path": DATA_DIR / "cada-prio"},
]

# ── State ──────────────────────────────────────────────────────────────────────
_update_process: Optional[subprocess.Popen] = None


# ── Helpers ────────────────────────────────────────────────────────────────────
def _human_size(num_bytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


def _rocksdb_progress(path: Path) -> dict:
    """Return download progress for a directory expected to contain a rocksdb/ subfolder."""
    rocksdb_dir = path / "rocksdb"
    if not rocksdb_dir.exists():
        return {"sst_done": 0, "sst_total": 0, "has_current": False, "pct": 0}

    sst_files = list(rocksdb_dir.glob("*.sst"))
    has_current = (rocksdb_dir / "CURRENT").exists()

    # aria2c creates .aria2 control files while downloading; their absence = file complete
    done = sum(1 for f in sst_files if not (rocksdb_dir / (f.name + ".aria2")).exists() and f.stat().st_size > 0)
    total = len(sst_files)
    pct = int(done / total * 100) if total else 0
    return {"sst_done": done, "sst_total": total, "has_current": has_current, "pct": pct}


def _entry_info(path: Path, is_download: bool = False) -> dict:
    """Collect metadata for a single entry (file / dir / symlink)."""
    info: dict = {
        "name":       path.name,
        "is_symlink": path.is_symlink(),
        "target":     None,
        "version":    None,
        "mtime":      None,
        "mtime_iso":  None,
        "has_done":   False,
        "status":     "missing",
        "size_bytes": None,
        "size_human": "…",
        "dl_progress": None,
    }

    if path.is_symlink():
        try:
            target = os.readlink(path)
            info["target"] = target
            # Resolve for actual path
            actual = path.resolve()
            info["version"] = actual.name
        except OSError:
            return info
    else:
        actual = path

    if not actual.exists():
        return info

    try:
        st = actual.stat()
        info["mtime"] = st.st_mtime
        info["mtime_iso"] = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
    except OSError:
        pass

    if actual.is_file():
        # Files are "done" when they exist with non-zero size
        info["has_done"] = st.st_size > 0 if st else False
        info["status"] = "done" if info["has_done"] else "incomplete"
        return info

    # For download-group entries: detect RocksDB completion
    if is_download:
        prog = _rocksdb_progress(actual)
        info["dl_progress"] = prog
        if prog["has_current"] and prog["sst_done"] == prog["sst_total"] and prog["sst_total"] > 0:
            info["has_done"] = True
            info["status"] = "done"
        elif prog["sst_done"] > 0:
            info["status"] = "partial"
        else:
            info["status"] = "incomplete"
        return info

    # Directory: prefer .done mtime as "last updated"
    done = actual / ".done"
    if done.exists():
        info["has_done"] = True
        info["status"] = "done"
        try:
            dst = done.stat()
            info["mtime"] = dst.st_mtime
            info["mtime_iso"] = datetime.fromtimestamp(dst.st_mtime).strftime("%Y-%m-%d %H:%M")
        except OSError:
            pass
    else:
        # Also check for RocksDB-style completion in any sub-path
        rocksdb_current = actual / "rocksdb" / "CURRENT"
        if rocksdb_current.exists():
            info["has_done"] = True
            info["status"] = "done"
        else:
            info["status"] = "incomplete"

    return info


def _group_status(statuses: list[str]) -> str:
    if not statuses:
        return "empty"
    if all(s == "done" for s in statuses):
        return "done"
    if any(s == "done" for s in statuses):
        return "partial"
    return "incomplete"


# ── API Endpoints ──────────────────────────────────────────────────────────────

@app.get("/api/status")
def get_status():
    """Return metadata for all database groups (fast — no du)."""
    result = []
    for grp in DB_GROUPS:
        path: Path = grp["path"]
        filt: list = grp.get("entries_filter", [])

        out = {
            "id":           grp["id"],
            "label":        grp["label"],
            "icon":         grp["icon"],
            "path":         str(path),
            "exists":       path.exists(),
            "entries":      [],
            "last_update":  None,
            "last_update_iso": None,
            "status":       "missing",
            "error":        None,
        }

        if not path.exists():
            result.append(out)
            continue

        try:
            items = sorted(path.iterdir(), key=lambda p: p.name)
            for item in items:
                if item.name.startswith("."):
                    continue
                if filt and item.name not in filt:
                    continue
                info = _entry_info(item)
                out["entries"].append(info)
                if info["mtime"] and (
                    out["last_update"] is None or info["mtime"] > out["last_update"]
                ):
                    out["last_update"] = info["mtime"]
                    out["last_update_iso"] = info["mtime_iso"]
        except Exception as exc:
            out["error"] = str(exc)

        # ── Inject pending-download entries that aren't symlinked yet ──────────
        existing_names = {e["name"] for e in out["entries"]}
        import re as _re
        for dl_path in grp.get("pending_downloads", []):
            dl_path = Path(dl_path)
            # Derive short name: "dbnsfp-grch37-4.5a+0.39.0" → "dbnsfp"
            short_name = _re.sub(r"-grch\d+.*", "", dl_path.name)
            if short_name in existing_names or not dl_path.exists():
                continue
            prog = _rocksdb_progress(dl_path)
            if prog["has_current"] and prog["sst_done"] == prog["sst_total"] and prog["sst_total"] > 0:
                dl_status = "done"
            elif prog["sst_done"] > 0:
                dl_status = "partial"
            else:
                dl_status = "incomplete"
            out["entries"].append({
                "name":        short_name,
                "is_symlink":  False,
                "target":      None,
                "version":     dl_path.name,
                "mtime":       None,
                "mtime_iso":   None,
                "has_done":    dl_status == "done",
                "status":      dl_status,
                "size_bytes":  None,
                "size_human":  "…",
                "dl_progress": prog,
            })

        out["status"] = _group_status([e["status"] for e in out["entries"]])
        result.append(out)

    return result


@app.get("/api/disk")
def get_disk():
    """Return disk usage of the data mount."""
    try:
        env = {**os.environ, "LC_ALL": "C", "LANG": "C"}
        r = subprocess.run(
            ["df", "-h", str(DATA_DIR)],
            capture_output=True, text=True, timeout=10, env=env,
        )
        lines = r.stdout.strip().splitlines()
        if len(lines) >= 2:
            parts = lines[1].split()
            return {
                "filesystem": parts[0],
                "size":       parts[1],
                "used":       parts[2],
                "avail":      parts[3],
                "use_pct":    parts[4],
                "mount":      parts[5],
            }
    except Exception as exc:
        return {"error": str(exc)}
    return {}


@app.get("/api/size/{group_id}")
async def get_group_size(group_id: str):
    """Run du -sh on a group's resolved paths (can be slow on NAS)."""
    grp = next((g for g in DB_GROUPS if g["id"] == group_id), None)
    if not grp:
        raise HTTPException(404, "Unknown group")

    path: Path = grp["path"]
    filt: list = grp.get("entries_filter", [])
    sizes: dict[str, str] = {}
    total_bytes = 0

    if path.exists():
        try:
            items = [p for p in sorted(path.iterdir()) if not p.name.startswith(".")]
            if filt:
                items = [p for p in items if p.name in filt]
            for item in items:
                actual = item.resolve() if item.is_symlink() else item
                if actual.exists():
                    proc = await asyncio.create_subprocess_exec(
                        "du", "-sb", str(actual),
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    stdout, _ = await proc.communicate()
                    if stdout:
                        nb = int(stdout.split()[0])
                        total_bytes += nb
                        sizes[item.name] = _human_size(nb)
        except Exception as exc:
            return {"group_id": group_id, "error": str(exc), "sizes": sizes}

    return {
        "group_id":    group_id,
        "sizes":       sizes,
        "total_human": _human_size(total_bytes),
        "total_bytes": total_bytes,
    }


@app.get("/api/update/running")
def update_running():
    """Check whether the update script is currently running."""
    global _update_process
    if _update_process is not None:
        if _update_process.poll() is None:
            return {"running": True, "pid": _update_process.pid}
        _update_process = None
    return {"running": False, "pid": None}


@app.post("/api/update/start")
def start_update():
    """Launch download-smart.sh on the NAS via SSH (background nohup)."""
    global _update_process

    if _update_process is not None and _update_process.poll() is None:
        raise HTTPException(409, "Update already running")

    cmd = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "BatchMode=yes",
        "-i", SSH_KEY,
        NAS_HOST,
        f"nohup {NAS_SCRIPT} >> {NAS_LOG} 2>&1 &",
    ]
    try:
        _update_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return {"started": True, "pid": _update_process.pid, "cmd": " ".join(cmd)}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/log")
def get_log(lines: int = 200):
    """Return the last N lines of the download log (via SSH to NAS for freshness)."""
    try:
        r = subprocess.run(
            ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes",
             "-i", SSH_KEY, NAS_HOST, f"tail -{lines} {NAS_LOG}"],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode == 0 and r.stdout:
            return {"content": r.stdout, "file": NAS_LOG}
    except Exception:
        pass
    # Fallback: local sshfs mount
    try:
        r = subprocess.run(
            ["tail", f"-{lines}", str(LOG_FILE)],
            capture_output=True, text=True, timeout=15,
        )
        return {"content": r.stdout, "file": str(LOG_FILE)}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/log/stream")
async def stream_log():
    """SSE stream via SSH tail -f (bypasses sshfs cache for real-time updates)."""
    async def _gen():
        cmd = [
            "ssh", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=10",
            "-i", SSH_KEY, NAS_HOST,
            f"tail -n 80 -f {NAS_LOG}",
        ]
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            async for raw in proc.stdout:
                line = raw.decode("utf-8", errors="replace").rstrip()
                yield f"data: {json.dumps(line)}\n\n"
        except asyncio.CancelledError:
            proc.kill()
            await proc.wait()

    return StreamingResponse(_gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ── Static frontend ────────────────────────────────────────────────────────────
app.mount("/", StaticFiles(directory=Path(__file__).parent / "static", html=True), name="static")
