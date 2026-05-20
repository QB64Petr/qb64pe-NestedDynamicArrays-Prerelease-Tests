TYPE test
    _DYNAMICFIELD c(10) AS LONG
    one AS STRING
    two(5) AS DOUBLE
    three(10) AS STRING
    four AS _UNSIGNED INTEGER
END TYPE
DIM n(5) AS test


n(0).c(1) = 4096
DIM m AS _MEM, num AS LONG
m = _MEM(n(0).c())
_MEMGET m, m.OFFSET + 4, num
PRINT num 'expected 4096
