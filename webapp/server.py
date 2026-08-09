"""Web app tying together everything built in this session: a blog-style writeup,
an interactive CHIP-8 ROM runner (driven by the ClickHouse-SQL emulator), and a
SQL/database explorer over the live ClickHouse server. Run with:
    uv run uvicorn webapp.server:app --host 0.0.0.0 --port 8000
"""

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import chip8
from ch_client import get_client

APP_DIR = Path(__file__).parent
PROJECT_DIR = APP_DIR.parent
ROMS_DIR = PROJECT_DIR / "roms"

app = FastAPI(title="ClickHouse Dev Environment")
app.mount("/static", StaticFiles(directory=APP_DIR / "static"), name="static")

_client = None


def client():
    global _client
    if _client is None:
        _client = get_client()
        chip8.load_sql(_client)
    return _client


# ---------------------------------------------------------------- pages ----

def _page(name: str) -> HTMLResponse:
    return HTMLResponse((APP_DIR / "static" / name).read_text())


@app.get("/", response_class=HTMLResponse)
def home():
    return _page("story.html")


@app.get("/run", response_class=HTMLResponse)
def run_page():
    return _page("run.html")


@app.get("/explore", response_class=HTMLResponse)
def explore_page():
    return _page("explore.html")


@app.get("/favicon.ico")
def favicon():
    raise HTTPException(404)


# ---------------------------------------------------------------- ROMs -----

@app.get("/api/roms")
def list_roms():
    return sorted(p.name for p in ROMS_DIR.glob("*.ch8"))


class NewRunRequest(BaseModel):
    rom: str


@app.post("/api/runs")
def create_run(req: NewRunRequest):
    rom_path = ROMS_DIR / req.rom
    if not rom_path.is_file() or rom_path.suffix != ".ch8":
        raise HTTPException(404, f"No such ROM: {req.rom}")
    run_id = chip8.new_run(client(), rom_path.read_bytes(), rom_name=req.rom)
    return {"run_id": str(run_id)}


@app.get("/api/runs")
def list_runs(limit: int = 20):
    result = client().query(
        """
        SELECT r.run_id, r.rom_name, r.created_at, max(s.step_id) AS steps
        FROM chip8.runs r
        LEFT JOIN chip8.state s ON s.run_id = r.run_id
        GROUP BY r.run_id, r.rom_name, r.created_at
        ORDER BY r.created_at DESC
        LIMIT {limit:UInt32}
        """,
        parameters={"limit": limit},
    )
    return [dict(zip(result.column_names, row)) for row in result.result_rows]


class StepRequest(BaseModel):
    cycles: int = chip8.CYCLES_PER_FRAME
    keys: list[int] | None = None


def _state_json(row: dict) -> dict:
    return {
        "step_id": row["step_id"],
        "pc": row["pc"],
        "i": row["i"],
        "v": row["v"],
        "sp": row["sp"],
        "stack": row["stack"],
        "dt": row["dt"],
        "st": row["st"],
        "disp": row["disp"],
        "keys": row["keys"],
        "opcode": row["opcode"],
    }


@app.post("/api/runs/{run_id}/step")
def step_run(run_id: str, req: StepRequest):
    if req.keys is not None and len(req.keys) != 16:
        raise HTTPException(400, "keys must have exactly 16 entries")
    chip8.run_batch(client(), run_id, cycles=req.cycles, keys=req.keys)
    return _state_json(chip8.get_state_row(client(), run_id))


@app.get("/api/runs/{run_id}/state")
def get_run_state(run_id: str):
    row = chip8.get_state_row(client(), run_id)
    return _state_json(row)


@app.get("/api/runs/{run_id}/history")
def run_history(run_id: str, limit: int = 500):
    result = client().query(
        """
        SELECT step_id, pc, opcode, arraySum(disp) AS pixels_on, dt, st
        FROM chip8.state
        WHERE run_id = {run_id:UUID}
        ORDER BY step_id
        LIMIT {limit:UInt32}
        """,
        parameters={"run_id": run_id, "limit": limit},
    )
    return [dict(zip(result.column_names, row)) for row in result.result_rows]


# ------------------------------------------------------------- explorer ----

READONLY_PREFIXES = ("SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "WITH")


class SqlRequest(BaseModel):
    query: str


@app.post("/api/sql")
def run_sql(req: SqlRequest):
    stripped = req.query.strip().rstrip(";").strip()
    if not stripped.upper().startswith(READONLY_PREFIXES):
        raise HTTPException(400, "Only read-only queries are allowed here (SELECT/SHOW/DESCRIBE/EXPLAIN/WITH).")
    try:
        result = client().query(stripped)
    except Exception as exc:  # noqa: BLE001 - surface ClickHouse's own error text to the UI
        raise HTTPException(400, str(exc))
    return {
        "columns": result.column_names,
        "rows": [list(row) for row in result.result_rows],
    }


@app.get("/api/schema/tables")
def schema_tables():
    result = client().query(
        """
        SELECT database, name, engine, total_rows, formatReadableSize(total_bytes) AS size
        FROM system.tables
        WHERE database = 'chip8'
        ORDER BY name
        """
    )
    return [dict(zip(result.column_names, row)) for row in result.result_rows]


@app.get("/api/schema/functions")
def schema_functions():
    result = client().query(
        "SELECT name, create_query FROM system.functions WHERE name LIKE 'ch8_%' ORDER BY name"
    )
    return [dict(zip(result.column_names, row)) for row in result.result_rows]


# ------------------------------------------------------------ source view --

SOURCE_FILES = {
    "00_helpers.sql": chip8.SQL_DIR / "00_helpers.sql",
    "01_step.sql": chip8.SQL_DIR / "01_step.sql",
    "02_table.sql": chip8.SQL_DIR / "02_table.sql",
    "driver.py": chip8.SQL_DIR / "__init__.py",
}


@app.get("/api/source/{name}")
def get_source(name: str):
    path = SOURCE_FILES.get(name)
    if path is None:
        raise HTTPException(404, "Unknown source file")
    return {"name": name, "text": path.read_text()}
