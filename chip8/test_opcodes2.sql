-- FX55/FX65 roundtrip, run as a real tiny program through ch8_step/arrayFold
-- (chaining exec_* calls directly, outside arrayFold, blows up the query AST).
--   200: A300  I=0x300        208: F255  store V0..V2
--   202: 6007  V0=7           20A: 6000  V0=0
--   204: 6108  V1=8           20C: 6100  V1=0
--   206: 6209  V2=9           20E: 6200  V2=0
--                             210: F265  load V0..V2 (should restore 7,8,9)
--                             212: 1212  infinite loop
SELECT
    arrayElement(ch8_v(final), 1) AS v0_expect_7,
    arrayElement(ch8_v(final), 2) AS v1_expect_8,
    arrayElement(ch8_v(final), 3) AS v2_expect_9,
    ch8_pc(final) AS pc_expect_530
FROM (
    SELECT arrayFold((acc, x) -> ch8_step(acc), range(9), ch8_mk(
        arrayMap((byte, p) -> multiIf(
                p = 513, 0xA3, p = 514, 0x00,
                p = 515, 0x60, p = 516, 0x07,
                p = 517, 0x61, p = 518, 0x08,
                p = 519, 0x62, p = 520, 0x09,
                p = 521, 0xF2, p = 522, 0x55,
                p = 523, 0x60, p = 524, 0x00,
                p = 525, 0x61, p = 526, 0x00,
                p = 527, 0x62, p = 528, 0x00,
                p = 529, 0xF2, p = 530, 0x65,
                p = 531, 0x12, p = 532, 0x12,
                byte),
            arrayResize(CAST([] AS Array(UInt8)), 4096, 0), arrayEnumerate(arrayResize(CAST([] AS Array(UInt8)), 4096, 0))),
        arrayResize(CAST([] AS Array(UInt8)), 16, 0), CAST(0 AS UInt16), CAST(512 AS UInt16),
        arrayResize(CAST([] AS Array(UInt16)), 16, 0), CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(0 AS UInt8),
        arrayResize(CAST([] AS Array(UInt8)), 2048, 0), arrayResize(CAST([] AS Array(UInt8)), 16, 0),
        CAST(0 AS UInt8), CAST(0 AS UInt8), CAST(42 AS UInt32)
    )) AS final
);
