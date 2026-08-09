-- Ad-hoc unit tests for the expanded opcode set. Each SELECT is independent.
SELECT 'ALU ADD carry' AS test,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 4, 250, 10)), 1) AS v0_expect_4,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 4, 250, 10)), 16) AS vf_expect_1;

SELECT 'ALU SUB borrow' AS test,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 5, 3, 10)), 1) AS v0_expect_249,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 5, 3, 10)), 16) AS vf_expect_0;

SELECT 'SHR' AS test,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 6, 5, 0)), 1) AS v0_expect_2,
    arrayElement(ch8_v(ch8_exec_alu(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0, 6, 5, 0)), 16) AS vf_expect_1;

SELECT 'CALL/RET roundtrip, pc expect 514' AS test,
    ch8_pc(ch8_exec_ret(ch8_exec_call(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0x300)));

SELECT 'SKIP true, pc expect 516' AS test,
    ch8_pc(ch8_exec_skip(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 1 = 1));

SELECT 'BCD 123, expect [1,2,3]' AS test,
    arraySlice(ch8_mem(ch8_exec_bcd(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 123)), 1, 3);

SELECT 'FX55/FX65 store+load roundtrip, expect [7,8,9]' AS test,
    arraySlice(ch8_v(
        ch8_exec_load(
            ch8_exec_store(
                ch8_exec_ld_vx_byte(
                    ch8_exec_ld_vx_byte(
                        ch8_exec_ld_vx_byte(
                            ch8_exec_ld_i(ch8_mk(arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16), arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8), arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)), 0x300),
                        0, 7),
                    1, 8),
                2, 9),
            2),
        2)
    ), 1, 3);
