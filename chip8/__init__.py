"""CHIP-8 emulator whose CPU fetch/decode/execute logic lives entirely in ClickHouse
SQL (see the .sql files next to this module). Python only drives timing, ROM loading,
keyboard input and rendering - it never interprets an opcode itself.
"""

import time
import uuid
from pathlib import Path

from ch_client import get_client

SQL_DIR = Path(__file__).parent
SQL_FILES = ["00_helpers.sql", "01_step.sql", "02_table.sql"]

MEM_SIZE = 4096
ROM_START = 0x200
FONT_START = 0x50
DISPLAY_W, DISPLAY_H = 64, 32
CYCLES_PER_FRAME = 8  # ~500Hz at 60fps, the classic COSMAC VIP rate of thumb

FONT = bytes([
    0xF0, 0x90, 0x90, 0x90, 0xF0,  # 0
    0x20, 0x60, 0x20, 0x20, 0x70,  # 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0,  # 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0,  # 3
    0x90, 0x90, 0xF0, 0x10, 0x10,  # 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0,  # 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0,  # 6
    0xF0, 0x10, 0x20, 0x40, 0x40,  # 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0,  # 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0,  # 9
    0xF0, 0x90, 0xF0, 0x90, 0x90,  # A
    0xE0, 0x90, 0xE0, 0x90, 0xE0,  # B
    0xF0, 0x80, 0x80, 0x80, 0xF0,  # C
    0xE0, 0x90, 0x90, 0x90, 0xE0,  # D
    0xF0, 0x80, 0xF0, 0x80, 0xF0,  # E
    0xF0, 0x80, 0xF0, 0x80, 0x80,  # F
])

STATE_COLUMNS = [
    "run_id", "step_id", "mem", "v", "i", "pc", "stack", "sp",
    "dt", "st", "disp", "keys", "waiting", "wait_reg", "rng",
]


def load_sql(client) -> None:
    """(Re)installs the CHIP-8 helper/step/table SQL. Idempotent (all CREATE OR REPLACE)."""
    for filename in SQL_FILES:
        text = (SQL_DIR / filename).read_text()
        for statement in text.split(";"):
            statement = statement.strip()
            if statement:
                client.command(statement)


def new_run(client, rom: bytes, rom_name: str = "") -> uuid.UUID:
    """Loads a ROM into a fresh initial state row and returns its run_id."""
    if len(rom) > MEM_SIZE - ROM_START:
        raise ValueError(f"ROM too large: {len(rom)} bytes, max {MEM_SIZE - ROM_START}")

    mem = bytearray(MEM_SIZE)
    mem[FONT_START:FONT_START + len(FONT)] = FONT
    mem[ROM_START:ROM_START + len(rom)] = rom

    run_id = uuid.uuid4()
    row = [
        run_id, 0, list(mem), [0] * 16, 0, ROM_START, [0] * 16, 0,
        0, 0, [0] * (DISPLAY_W * DISPLAY_H), [0] * 16, 0, 0, 0x2A2A2A2A,
    ]
    client.insert("chip8.state", [row], column_names=STATE_COLUMNS)
    client.insert("chip8.runs", [[run_id, rom_name]], column_names=["run_id", "rom_name"])
    return run_id


def run_batch(client, run_id: uuid.UUID, cycles: int = CYCLES_PER_FRAME, keys: list[int] | None = None) -> None:
    """Advances the given run by `cycles` CPU steps (+1 timer tick) and appends the new row.
    If `keys` is given (16 0/1 values), it overrides the pressed-key state for this batch,
    so live keyboard input from the web UI reaches EX9E/EXA1/FX0A."""
    cols = "run_id, step_id, mem, v, i, pc, stack, sp, dt, st, disp, keys, waiting, wait_reg, rng"
    keys_expr = "{keys:Array(UInt8)}" if keys is not None else "keys"
    query = f"""
        INSERT INTO chip8.state ({cols})
        SELECT
            run_id, step_id + 1,
            ch8_mem(ns), ch8_v(ns), ch8_i(ns), ch8_pc(ns), ch8_stack(ns), ch8_sp(ns),
            ch8_dt(ns), ch8_st(ns), ch8_disp(ns), ch8_keys(ns), ch8_waiting(ns), ch8_wait_reg(ns), ch8_rng(ns)
        FROM (
            SELECT run_id, step_id,
                ch8_run_batch(ch8_set_keys(tuple(mem, v, i, pc, stack, sp, dt, st, disp, keys, waiting, wait_reg, rng), {keys_expr}), {{cycles:UInt32}}) AS ns
            FROM chip8.state
            WHERE run_id = {{run_id:UUID}}
            ORDER BY step_id DESC
            LIMIT 1
        )
    """
    parameters = {"run_id": str(run_id), "cycles": cycles}
    if keys is not None:
        parameters["keys"] = keys
    client.command(query, parameters=parameters)


def get_state_row(client, run_id: uuid.UUID):
    # SELECT * excludes MATERIALIZED columns (opcode) by default - list columns explicitly.
    result = client.query(
        f"SELECT {', '.join(STATE_COLUMNS)}, opcode FROM chip8.state "
        "WHERE run_id = {run_id:UUID} ORDER BY step_id DESC LIMIT 1",
        parameters={"run_id": str(run_id)},
    )
    return dict(zip(result.column_names, result.result_rows[0]))


def render_ascii(disp: list[int]) -> str:
    """Each pixel is rendered as two characters wide to correct for monospace
    terminal cells being roughly twice as tall as they are wide."""
    lines = []
    for row in range(DISPLAY_H):
        chars = "".join("██" if disp[row * DISPLAY_W + col] else "  " for col in range(DISPLAY_W))
        lines.append(chars)
    return "\n".join(lines)


def render_png(disp: list[int], path: Path, scale: int = 12) -> None:
    from PIL import Image

    img = Image.new("L", (DISPLAY_W, DISPLAY_H))
    img.putdata([255 if px else 0 for px in disp])
    img = img.resize((DISPLAY_W * scale, DISPLAY_H * scale), Image.NEAREST)
    img.save(path)


def run_rom(rom_path: Path, frames: int = 60, render_every: int = 1, png_path: Path | None = None) -> str:
    """Runs a ROM for `frames` frames (~1/60s of emulated time each) and returns the
    final rendered display as a string. Intended for quick headless validation."""
    client = get_client()
    load_sql(client)
    run_id = new_run(client, rom_path.read_bytes(), rom_name=rom_path.name)

    last_render = ""
    last_disp = None
    for frame in range(frames):
        run_batch(client, run_id)
        if frame % render_every == 0:
            row = get_state_row(client, run_id)
            last_disp = row["disp"]
            last_render = render_ascii(last_disp)
    if png_path is not None and last_disp is not None:
        render_png(last_disp, png_path)
    return last_render


if __name__ == "__main__":
    import sys

    rom_path = Path(sys.argv[1]) if len(sys.argv) > 1 else SQL_DIR.parent / "roms" / "2-ibm-logo.ch8"
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    png_path = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    print(run_rom(rom_path, frames=frames, png_path=png_path))
