-- Full 35-opcode CHIP-8 instruction set.
-- No WITH/subqueries anywhere below: they break when this ends up called from inside
-- arrayFold's lambda (loses access to the enclosing accumulator variable). Instead,
-- expensive derived values (op, x, y, n, nn, nnn, vx, vy) are computed once and threaded
-- down as explicit function arguments - the SQL-UDF equivalent of a let-binding.
-- Quirk choices (where the original spec is ambiguous / interpreters disagree):
--   8XY6/8XYE shift Vx in place (ignore Vy) - the common CHIP-48/SCHIP default.
--   FX55/FX65 leave I unchanged - the common modern default.
--   DXYN clips sprites at the screen edge rather than wrapping.

CREATE OR REPLACE FUNCTION ch8_next_rng AS (rng) -> CAST(rng * 1103515245 + 12345 AS UInt32);
CREATE OR REPLACE FUNCTION ch8_rng_byte AS (rng) -> CAST(bitAnd(bitShiftRight(rng, 16), 0xFF) AS UInt8);

CREATE OR REPLACE FUNCTION ch8_exec_cls AS (s) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           arrayMap(z -> CAST(0 AS UInt8), ch8_disp(s)), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ret AS (s) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), arrayElement(ch8_stack(s), ch8_sp(s)), ch8_stack(s),
           CAST(if(ch8_sp(s) > 0, ch8_sp(s) - 1, 0) AS UInt8), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_call AS (s, nnn) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(nnn AS UInt16),
           ch8_set(ch8_stack(s), ch8_sp(s) + 1, CAST(ch8_pc(s) + 2 AS UInt16)), CAST(ch8_sp(s) + 1 AS UInt8),
           ch8_dt(s), ch8_st(s), ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_jp AS (s, nnn) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(nnn AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_bnnn AS (s, nnn) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(nnn + arrayElement(ch8_v(s), 1) AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

-- Shared by 3XNN/4XNN/5XY0/9XY0/EX9E/EXA1: pc+4 if cond else pc+2.
CREATE OR REPLACE FUNCTION ch8_exec_skip AS (s, cond) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + if(cond, 4, 2) AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_vx_byte AS (s, x, nn) ->
    ch8_mk(ch8_mem(s), ch8_set(ch8_v(s), x + 1, nn), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_add_vx_byte AS (s, x, nn, vx) ->
    ch8_mk(ch8_mem(s), ch8_set(ch8_v(s), x + 1, CAST(vx + nn AS UInt8)), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_i AS (s, nnn) ->
    ch8_mk(ch8_mem(s), ch8_v(s), CAST(nnn AS UInt16), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

-- All nine 8XY_ ALU ops in one function, keyed on the opcode's low nibble (n).
CREATE OR REPLACE FUNCTION ch8_exec_alu AS (s, x, n, vx, vy) ->
    ch8_mk(
        ch8_mem(s),
        ch8_set(
            ch8_set(ch8_v(s), x + 1,
                multiIf(
                    n = 0x0, vy,
                    n = 0x1, CAST(bitOr(vx, vy) AS UInt8),
                    n = 0x2, CAST(bitAnd(vx, vy) AS UInt8),
                    n = 0x3, CAST(bitXor(vx, vy) AS UInt8),
                    n = 0x4, CAST((vx + vy) % 256 AS UInt8),
                    n = 0x5, CAST((vx - vy + 256) % 256 AS UInt8),
                    n = 0x6, CAST(bitShiftRight(vx, 1) AS UInt8),
                    n = 0x7, CAST((vy - vx + 256) % 256 AS UInt8),
                    n = 0xE, CAST(bitAnd(bitShiftLeft(vx, 1), 0xFF) AS UInt8),
                    vx)),
            16,
            multiIf(
                n = 0x4, CAST(if(vx + vy > 255, 1, 0) AS UInt8),
                n = 0x5, CAST(if(vx >= vy, 1, 0) AS UInt8),
                n = 0x6, CAST(bitAnd(vx, 1) AS UInt8),
                n = 0x7, CAST(if(vy >= vx, 1, 0) AS UInt8),
                n = 0xE, CAST(bitAnd(bitShiftRight(vx, 7), 1) AS UInt8),
                arrayElement(ch8_v(s), 16))),
        ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_rnd AS (s, x, nn) ->
    ch8_mk(ch8_mem(s), ch8_set(ch8_v(s), x + 1, CAST(bitAnd(ch8_rng_byte(ch8_next_rng(ch8_rng(s))), nn) AS UInt8)),
           ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_next_rng(ch8_rng(s)));

CREATE OR REPLACE FUNCTION ch8_exec_drw AS (s, vx, vy, n) ->
    ch8_mk(
        ch8_mem(s),
        ch8_set(ch8_v(s), 16,
            CAST(arraySum(arrayMap((old, p) -> CAST(if(old = 1 AND ch8_sprite_px(ch8_mem(s), ch8_i(s), vx % 64, vy % 32, n,
                        intDiv(p - 1, 64), (p - 1) % 64) = 1, 1, 0) AS UInt8), ch8_disp(s), arrayEnumerate(ch8_disp(s)))) > 0 AS UInt8)),
        ch8_i(s),
        CAST(ch8_pc(s) + 2 AS UInt16),
        ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        arrayMap((old, p) -> CAST(bitXor(old, ch8_sprite_px(ch8_mem(s), ch8_i(s), vx % 64, vy % 32, n,
                    intDiv(p - 1, 64), (p - 1) % 64)) AS UInt8), ch8_disp(s), arrayEnumerate(ch8_disp(s))),
        ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_vx_dt AS (s, x) ->
    ch8_mk(ch8_mem(s), ch8_set(ch8_v(s), x + 1, ch8_dt(s)), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_dt_vx AS (s, vx) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), vx, ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_st_vx AS (s, vx) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), vx,
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_add_i_vx AS (s, vx) ->
    ch8_mk(ch8_mem(s), ch8_v(s), CAST((ch8_i(s) + vx) % 65536 AS UInt16), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_ld_f_vx AS (s, vx) ->
    ch8_mk(ch8_mem(s), ch8_v(s), CAST(0x50 + bitAnd(vx, 0xF) * 5 AS UInt16), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_bcd AS (s, vx) ->
    ch8_mk(
        ch8_set(ch8_set(ch8_set(ch8_mem(s), ch8_i(s) + 1, CAST(intDiv(vx, 100) AS UInt8)),
                         ch8_i(s) + 2, CAST(intDiv(vx % 100, 10) AS UInt8)),
                ch8_i(s) + 3, CAST(vx % 10 AS UInt8)),
        ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_store AS (s, x) ->
    ch8_mk(
        arrayMap((byte, p) -> if(p - 1 >= ch8_i(s) AND p - 1 <= ch8_i(s) + x,
                                  arrayElement(ch8_v(s), (p - 1 - ch8_i(s)) + 1), byte),
                 ch8_mem(s), arrayEnumerate(ch8_mem(s))),
        ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_load AS (s, x) ->
    ch8_mk(
        ch8_mem(s),
        arrayMap((val, p) -> if(p - 1 <= x, arrayElement(ch8_mem(s), CAST(ch8_i(s) + (p - 1) AS UInt16) + 1), val),
                 ch8_v(s), arrayEnumerate(ch8_v(s))),
        ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

-- Blocks (doesn't advance pc) until some key is down, per classic FX0A semantics.
CREATE OR REPLACE FUNCTION ch8_exec_wait_key AS (s, x) ->
    ch8_mk(
        ch8_mem(s),
        if(arrayFirstIndex(k -> k = 1, ch8_keys(s)) > 0,
           ch8_set(ch8_v(s), x + 1, CAST(arrayFirstIndex(k -> k = 1, ch8_keys(s)) - 1 AS UInt8)),
           ch8_v(s)),
        ch8_i(s),
        CAST(if(arrayFirstIndex(k -> k = 1, ch8_keys(s)) > 0, ch8_pc(s) + 2, ch8_pc(s)) AS UInt16),
        ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
        ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_exec_noop AS (s) ->
    ch8_mk(ch8_mem(s), ch8_v(s), ch8_i(s), CAST(ch8_pc(s) + 2 AS UInt16), ch8_stack(s), ch8_sp(s), ch8_dt(s), ch8_st(s),
           ch8_disp(s), ch8_keys(s), ch8_waiting(s), ch8_wait_reg(s), ch8_rng(s));

CREATE OR REPLACE FUNCTION ch8_dispatch_e AS (s, nn, vx) ->
    multiIf(
        nn = 0x9E, ch8_exec_skip(s, arrayElement(ch8_keys(s), vx + 1) = 1),
        nn = 0xA1, ch8_exec_skip(s, arrayElement(ch8_keys(s), vx + 1) = 0),
        ch8_exec_noop(s)
    );

CREATE OR REPLACE FUNCTION ch8_dispatch_f AS (s, x, nn, vx) ->
    multiIf(
        nn = 0x07, ch8_exec_ld_vx_dt(s, x),
        nn = 0x0A, ch8_exec_wait_key(s, x),
        nn = 0x15, ch8_exec_ld_dt_vx(s, vx),
        nn = 0x18, ch8_exec_ld_st_vx(s, vx),
        nn = 0x1E, ch8_exec_add_i_vx(s, vx),
        nn = 0x29, ch8_exec_ld_f_vx(s, vx),
        nn = 0x33, ch8_exec_bcd(s, vx),
        nn = 0x55, ch8_exec_store(s, x),
        nn = 0x65, ch8_exec_load(s, x),
        ch8_exec_noop(s)
    );

CREATE OR REPLACE FUNCTION ch8_dispatch AS (s, op) ->
    multiIf(
        op = 0x00E0, ch8_exec_cls(s),
        op = 0x00EE, ch8_exec_ret(s),
        ch8_op_family(op) = 0x1, ch8_exec_jp(s, ch8_op_nnn(op)),
        ch8_op_family(op) = 0x2, ch8_exec_call(s, ch8_op_nnn(op)),
        ch8_op_family(op) = 0x3, ch8_exec_skip(s, arrayElement(ch8_v(s), ch8_op_x(op) + 1) = ch8_op_nn(op)),
        ch8_op_family(op) = 0x4, ch8_exec_skip(s, arrayElement(ch8_v(s), ch8_op_x(op) + 1) != ch8_op_nn(op)),
        ch8_op_family(op) = 0x5, ch8_exec_skip(s, arrayElement(ch8_v(s), ch8_op_x(op) + 1) = arrayElement(ch8_v(s), ch8_op_y(op) + 1)),
        ch8_op_family(op) = 0x6, ch8_exec_ld_vx_byte(s, ch8_op_x(op), ch8_op_nn(op)),
        ch8_op_family(op) = 0x7, ch8_exec_add_vx_byte(s, ch8_op_x(op), ch8_op_nn(op), arrayElement(ch8_v(s), ch8_op_x(op) + 1)),
        ch8_op_family(op) = 0x8, ch8_exec_alu(s, ch8_op_x(op), ch8_op_n(op), arrayElement(ch8_v(s), ch8_op_x(op) + 1), arrayElement(ch8_v(s), ch8_op_y(op) + 1)),
        ch8_op_family(op) = 0x9, ch8_exec_skip(s, arrayElement(ch8_v(s), ch8_op_x(op) + 1) != arrayElement(ch8_v(s), ch8_op_y(op) + 1)),
        ch8_op_family(op) = 0xA, ch8_exec_ld_i(s, ch8_op_nnn(op)),
        ch8_op_family(op) = 0xB, ch8_exec_bnnn(s, ch8_op_nnn(op)),
        ch8_op_family(op) = 0xC, ch8_exec_rnd(s, ch8_op_x(op), ch8_op_nn(op)),
        ch8_op_family(op) = 0xD, ch8_exec_drw(s, arrayElement(ch8_v(s), ch8_op_x(op) + 1), arrayElement(ch8_v(s), ch8_op_y(op) + 1), ch8_op_n(op)),
        ch8_op_family(op) = 0xE, ch8_dispatch_e(s, ch8_op_nn(op), arrayElement(ch8_v(s), ch8_op_x(op) + 1)),
        ch8_op_family(op) = 0xF, ch8_dispatch_f(s, ch8_op_x(op), ch8_op_nn(op), arrayElement(ch8_v(s), ch8_op_x(op) + 1)),
        ch8_exec_noop(s)
    );

CREATE OR REPLACE FUNCTION ch8_step AS (s) -> ch8_dispatch(s, ch8_opcode(ch8_mem(s), ch8_pc(s)));
