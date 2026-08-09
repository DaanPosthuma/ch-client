-- Generic array element-set: returns arr with arr[idx] replaced by val (1-based idx).
CREATE OR REPLACE FUNCTION ch8_set AS (arr, idx, val) ->
    arrayMap((x, i) -> if(i = idx, val, x), arr, arrayEnumerate(arr));

-- CPU state is a positional Tuple, field order fixed by convention:
--   1 mem (Array(UInt8) len 4096)   7 dt (UInt8)
--   2 v   (Array(UInt8) len 16)     8 st (UInt8)
--   3 i   (UInt16)                  9 disp (Array(UInt8) len 2048, 64x32)
--   4 pc  (UInt16)                 10 keys (Array(UInt8) len 16)
--   5 stack (Array(UInt16) len 16) 11 waiting (UInt8, 1 = blocked in FX0A)
--   6 sp  (UInt8)                  12 wait_reg (UInt8)
--                                  13 rng (UInt32, LCG state for CXNN)
CREATE OR REPLACE FUNCTION ch8_mk AS (mem, v, i, pc, stack, sp, dt, st, disp, keys, waiting, wait_reg, rng) ->
    tuple(mem, v, i, pc, stack, sp, dt, st, disp, keys, waiting, wait_reg, rng);

CREATE OR REPLACE FUNCTION ch8_mem      AS (s) -> s.1;
CREATE OR REPLACE FUNCTION ch8_v        AS (s) -> s.2;
CREATE OR REPLACE FUNCTION ch8_i        AS (s) -> s.3;
CREATE OR REPLACE FUNCTION ch8_pc       AS (s) -> s.4;
CREATE OR REPLACE FUNCTION ch8_stack    AS (s) -> s.5;
CREATE OR REPLACE FUNCTION ch8_sp       AS (s) -> s.6;
CREATE OR REPLACE FUNCTION ch8_dt       AS (s) -> s.7;
CREATE OR REPLACE FUNCTION ch8_st       AS (s) -> s.8;
CREATE OR REPLACE FUNCTION ch8_disp     AS (s) -> s.9;
CREATE OR REPLACE FUNCTION ch8_keys     AS (s) -> s.10;
CREATE OR REPLACE FUNCTION ch8_waiting  AS (s) -> s.11;
CREATE OR REPLACE FUNCTION ch8_wait_reg AS (s) -> s.12;
CREATE OR REPLACE FUNCTION ch8_rng      AS (s) -> s.13;

-- Fetch the big-endian 16-bit opcode at mem[pc], mem[pc+1] (0-based addr -> 1-based array index).
CREATE OR REPLACE FUNCTION ch8_opcode AS (mem, pc) ->
    CAST(arrayElement(mem, pc + 1) * 256 + arrayElement(mem, pc + 2) AS UInt16);

-- Opcode nibble/byte decoding.
CREATE OR REPLACE FUNCTION ch8_op_family AS (op) -> CAST(bitShiftRight(op, 12) AS UInt8);
CREATE OR REPLACE FUNCTION ch8_op_x      AS (op) -> CAST(bitAnd(bitShiftRight(op, 8), 0x0F) AS UInt8);
CREATE OR REPLACE FUNCTION ch8_op_y      AS (op) -> CAST(bitAnd(bitShiftRight(op, 4), 0x0F) AS UInt8);
CREATE OR REPLACE FUNCTION ch8_op_n      AS (op) -> CAST(bitAnd(op, 0x0F) AS UInt8);
CREATE OR REPLACE FUNCTION ch8_op_nn     AS (op) -> CAST(bitAnd(op, 0xFF) AS UInt8);
CREATE OR REPLACE FUNCTION ch8_op_nnn    AS (op) -> CAST(bitAnd(op, 0x0FFF) AS UInt16);

-- Sprite pixel contribution: 0 if (row,col) falls outside the sprite's N-row x 8-col
-- footprint anchored at (sx,sy) or off-screen, else the actual bit from mem[i + row-sy].
-- XOR-ing this into the display naturally implements both drawing and edge clipping.
CREATE OR REPLACE FUNCTION ch8_sprite_px AS (mem, i, sx, sy, n, row, col) ->
    if(row < sy OR row >= sy + n OR col < sx OR col >= sx + 8 OR row >= 32 OR col >= 64,
       CAST(0 AS UInt8),
       CAST(bitAnd(bitShiftRight(arrayElement(mem, CAST(i + (row - sy) AS UInt16) + 1), 7 - (col - sx)), 1) AS UInt8));
