-- Append-only log of CPU state snapshots: one row per batch of cycles executed.
-- The "current" state is simply the row with the highest step_id.
CREATE DATABASE IF NOT EXISTS chip8;

CREATE OR REPLACE TABLE chip8.state
(
    run_id    UUID,
    step_id   UInt64,
    mem       Array(UInt8),
    v         Array(UInt8),
    i         UInt16,
    pc        UInt16,
    stack     Array(UInt16),
    sp        UInt8,
    dt        UInt8,
    st        UInt8,
    disp      Array(UInt8),
    keys      Array(UInt8),
    waiting   UInt8,
    wait_reg  UInt8,
    rng       UInt32,
    opcode    UInt16 MATERIALIZED ch8_opcode(mem, pc)
)
ENGINE = MergeTree
ORDER BY (run_id, step_id);

-- Runs `cycles` CPU steps starting from the latest row of `run_id`, decrementing the
-- 60Hz delay/sound timers by exactly 1 (not per-opcode), and inserts the resulting row.
-- Intended to be called roughly once per video frame from the Python driver.
CREATE OR REPLACE FUNCTION ch8_run_batch AS (s, cycles) ->
    ch8_tick_timers(arrayFold((acc, x) -> ch8_step(acc), range(cycles), s));

CREATE OR REPLACE FUNCTION ch8_tick_timers AS (s) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), ch8_pc(s), ch8_stack(s), ch8_sp(s),
           CAST(if(ch8_dt(s) > 0, ch8_dt(s) - 1, 0) AS UInt8),
           CAST(if(ch8_st(s) > 0, ch8_st(s) - 1, 0) AS UInt8),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

-- Overrides the 16-key pressed/released state before running a batch, so a caller
-- (the web UI) can drive live keyboard input into EX9E/EXA1/FX0A.
CREATE OR REPLACE FUNCTION ch8_set_keys AS (s, new_keys) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), ch8_pc(s), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), new_keys, ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

-- One row per emulator run, so the UI can list run history with which ROM was loaded.
CREATE OR REPLACE TABLE chip8.runs
(
    run_id     UUID,
    rom_name   String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY created_at;
