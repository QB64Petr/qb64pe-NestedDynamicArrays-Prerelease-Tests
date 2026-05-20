'expected is: No memory leak, memory consumption about 50 MB

OPTION BASE 1

DIM screenW AS LONG, screenH AS LONG
DIM histCap AS LONG, valueCap AS LONG, txtCap AS LONG
DIM startCount AS LONG

screenW = 1000
screenH = 620
startCount = 80

TYPE BlobData
    x AS SINGLE
    y AS SINGLE
    vx AS SINGLE
    vy AS SINGLE
    radius AS SINGLE
    seed AS LONG

    _DYNAMICFIELD hx(24) AS SINGLE
    _DYNAMICFIELD hy(24) AS SINGLE
    _DYNAMICFIELD value(32) AS LONG
    _DYNAMICFIELD txtSlot(6) AS STRING
END TYPE

DIM img AS LONG
DIM frameNo AS LONG
DIM i AS LONG, k AS LONG
DIM oldCount AS LONG, blobCount AS LONG, targetCount AS LONG
DIM pick AS LONG
DIM loHist AS LONG, hiHist AS LONG
DIM loVal AS LONG, hiVal AS LONG
DIM loTxt AS LONG, hiTxt AS LONG
DIM histIdx AS LONG, valIdx AS LONG, txtIdx AS LONG
DIM span AS LONG
DIM shade AS LONG
DIM payloadBytes AS DOUBLE
DIM payloadKB AS DOUBLE
DIM parentResizeCount AS LONG
DIM memberResizeCount AS LONG
DIM newHistCap AS LONG, newValueCap AS LONG, newTxtCap AS LONG
DIM keyPress AS STRING
DIM info AS STRING
DIM watchIdx AS LONG
DIM txtWork AS STRING

RANDOMIZE TIMER

img = _NEWIMAGE(screenW, screenH, 32)
SCREEN img

_TITLE "QB64PE dynamic nested TYPE arrays - leak visual test - ESC exits"

blobCount = startCount
REDIM blob(1 TO blobCount) AS BlobData

FOR i = LBOUND(blob) TO UBOUND(blob)
    blob(i).x = 40 + RND * (screenW - 80)
    blob(i).y = 120 + RND * (screenH - 160)
    blob(i).vx = -2.2 + RND * 4.4
    blob(i).vy = -2.2 + RND * 4.4
    blob(i).radius = 3 + RND * 5
    blob(i).seed = i * 97

    loHist = LBOUND(blob(i).hx)
    hiHist = UBOUND(blob(i).hx)

    FOR histIdx = loHist TO hiHist
        blob(i).hx(histIdx) = blob(i).x
        blob(i).hy(histIdx) = blob(i).y
    NEXT histIdx

    loVal = LBOUND(blob(i).value)
    hiVal = UBOUND(blob(i).value)

    FOR valIdx = loVal TO hiVal
        blob(i).value(valIdx) = i * 1000 + valIdx
    NEXT valIdx

    loTxt = LBOUND(blob(i).txtSlot)
    hiTxt = UBOUND(blob(i).txtSlot)

    FOR txtIdx = loTxt TO hiTxt
        blob(i).txtSlot(txtIdx) = "START " + LTRIM$(STR$(i))
    NEXT txtIdx
NEXT i

DO
    frameNo = frameNo + 1
    _LIMIT 60

    keyPress = INKEY$
    IF keyPress = CHR$(27) THEN EXIT DO

    IF frameNo MOD 90 = 0 THEN
        oldCount = blobCount

        histCap = 8 + INT(RND * 64)
        valueCap = 4 + INT(RND * 96)
        txtCap = 1 + INT(RND * 16)

        targetCount = 20 + INT(RND * 260)

        REDIM _RETAIN blob(1 TO targetCount) AS BlobData

        blobCount = targetCount
        parentResizeCount = parentResizeCount + 1

        FOR i = LBOUND(blob) TO UBOUND(blob)
            IF blob(i).radius <= 0 THEN
                blob(i).x = 40 + RND * (screenW - 80)
                blob(i).y = 120 + RND * (screenH - 160)
                blob(i).vx = -2.2 + RND * 4.4
                blob(i).vy = -2.2 + RND * 4.4
                blob(i).radius = 3 + RND * 5
                blob(i).seed = i * 97 + frameNo

                loHist = LBOUND(blob(i).hx)
                hiHist = UBOUND(blob(i).hx)

                FOR histIdx = loHist TO hiHist
                    blob(i).hx(histIdx) = blob(i).x
                    blob(i).hy(histIdx) = blob(i).y
                NEXT histIdx

                loVal = LBOUND(blob(i).value)
                hiVal = UBOUND(blob(i).value)

                FOR valIdx = loVal TO hiVal
                    blob(i).value(valIdx) = i * 1000 + valIdx
                NEXT valIdx

                loTxt = LBOUND(blob(i).txtSlot)
                hiTxt = UBOUND(blob(i).txtSlot)

                FOR txtIdx = loTxt TO hiTxt
                    blob(i).txtSlot(txtIdx) = "NEW " + LTRIM$(STR$(i))
                NEXT txtIdx
            END IF
        NEXT i
    END IF

    IF frameNo MOD 7 = 0 AND blobCount > 0 THEN
        pick = LBOUND(blob) + INT(RND * (UBOUND(blob) - LBOUND(blob) + 1))

        newHistCap = 4 + INT(RND * 80)
        newValueCap = 2 + INT(RND * 128)
        newTxtCap = 1 + INT(RND * 20)

        REDIM _RETAIN blob(pick).hx(1 TO newHistCap)
        REDIM _RETAIN blob(pick).hy(1 TO newHistCap)
        REDIM _RETAIN blob(pick).value(1 TO newValueCap)
        REDIM _RETAIN blob(pick).txtSlot(1 TO newTxtCap)

        memberResizeCount = memberResizeCount + 4

        loHist = LBOUND(blob(pick).hx)
        hiHist = UBOUND(blob(pick).hx)

        FOR histIdx = loHist TO hiHist
            blob(pick).hx(histIdx) = blob(pick).x
            blob(pick).hy(histIdx) = blob(pick).y
        NEXT histIdx

        loTxt = LBOUND(blob(pick).txtSlot)
        hiTxt = UBOUND(blob(pick).txtSlot)

        FOR txtIdx = loTxt TO hiTxt
            blob(pick).txtSlot(txtIdx) = "RZ " + LTRIM$(STR$(pick))
        NEXT txtIdx
    END IF

    CLS

    payloadBytes = 0

    FOR i = LBOUND(blob) TO UBOUND(blob)
        blob(i).x = blob(i).x + blob(i).vx
        blob(i).y = blob(i).y + blob(i).vy

        IF blob(i).x < 20 THEN blob(i).vx = ABS(blob(i).vx)
        IF blob(i).x > screenW - 20 THEN blob(i).vx = -ABS(blob(i).vx)
        IF blob(i).y < 110 THEN blob(i).vy = ABS(blob(i).vy)
        IF blob(i).y > screenH - 20 THEN blob(i).vy = -ABS(blob(i).vy)

        loHist = LBOUND(blob(i).hx)
        hiHist = UBOUND(blob(i).hx)

        FOR histIdx = hiHist TO loHist + 1 STEP -1
            blob(i).hx(histIdx) = blob(i).hx(histIdx - 1)
            blob(i).hy(histIdx) = blob(i).hy(histIdx - 1)
        NEXT histIdx

        blob(i).hx(loHist) = blob(i).x
        blob(i).hy(loHist) = blob(i).y

        span = hiHist - loHist + 1
        IF span < 1 THEN span = 1

        FOR histIdx = loHist TO hiHist - 1
            shade = 30 + ((histIdx - loHist) * 160) \ span
            LINE (blob(i).hx(histIdx), blob(i).hy(histIdx))-(blob(i).hx(histIdx + 1), blob(i).hy(histIdx + 1)), _RGB32(shade, shade, 180)
        NEXT histIdx

        CIRCLE (blob(i).x, blob(i).y), blob(i).radius, _RGB32(255, 220, 80)

        loVal = LBOUND(blob(i).value)
        hiVal = UBOUND(blob(i).value)

        IF hiVal >= loVal THEN
            valIdx = loVal + ((frameNo + i) MOD (hiVal - loVal + 1))
            blob(i).value(valIdx) = frameNo + i * 100000
        END IF

        loTxt = LBOUND(blob(i).txtSlot)
        hiTxt = UBOUND(blob(i).txtSlot)

        IF hiTxt >= loTxt THEN
            txtIdx = loTxt + ((frameNo + i) MOD (hiTxt - loTxt + 1))
            blob(i).txtSlot(txtIdx) = "B" + LTRIM$(STR$(i)) + " F" + LTRIM$(STR$(frameNo))
        END IF

        payloadBytes = payloadBytes + (UBOUND(blob(i).hx) - LBOUND(blob(i).hx) + 1) * 4
        payloadBytes = payloadBytes + (UBOUND(blob(i).hy) - LBOUND(blob(i).hy) + 1) * 4
        payloadBytes = payloadBytes + (UBOUND(blob(i).value) - LBOUND(blob(i).value) + 1) * 4
        payloadBytes = payloadBytes + (UBOUND(blob(i).txtSlot) - LBOUND(blob(i).txtSlot) + 1) * 16
    NEXT i

    payloadKB = payloadBytes / 1024

    LINE (0, 0)-(screenW, 96), _RGB32(0, 0, 0), BF
    LINE (0, 96)-(screenW, 96), _RGB32(80, 80, 80)

    COLOR _RGB32(230, 230, 230)

    info = "frame=" + LTRIM$(STR$(frameNo))
    info = info + "   parent L/U=" + LTRIM$(STR$(LBOUND(blob))) + "/" + LTRIM$(STR$(UBOUND(blob)))
    info = info + "   blobs=" + LTRIM$(STR$(blobCount))
    info = info + "   parent REDIMs=" + LTRIM$(STR$(parentResizeCount))
    info = info + "   member REDIMs=" + LTRIM$(STR$(memberResizeCount))
    _PRINTSTRING (12, 12), info

    info = "TYPE runtime caps for next parent REDIM: histCap=" + LTRIM$(STR$(histCap))
    info = info + " valueCap=" + LTRIM$(STR$(valueCap))
    info = info + " txtCap=" + LTRIM$(STR$(txtCap))
    info = info + "   dynamic payload estimate=" + LTRIM$(STR$(INT(payloadKB))) + " KB"
    _PRINTSTRING (12, 34), info

    watchIdx = 1
    IF watchIdx < LBOUND(blob) THEN watchIdx = LBOUND(blob)
    IF watchIdx > UBOUND(blob) THEN watchIdx = UBOUND(blob)

    info = "watch blob(" + LTRIM$(STR$(watchIdx)) + ")"
    info = info + " hx=" + LTRIM$(STR$(LBOUND(blob(watchIdx).hx))) + ".." + LTRIM$(STR$(UBOUND(blob(watchIdx).hx)))
    info = info + " value=" + LTRIM$(STR$(LBOUND(blob(watchIdx).value))) + ".." + LTRIM$(STR$(UBOUND(blob(watchIdx).value)))
    info = info + " txtSlot=" + LTRIM$(STR$(LBOUND(blob(watchIdx).txtSlot))) + ".." + LTRIM$(STR$(UBOUND(blob(watchIdx).txtSlot)))
    _PRINTSTRING (12, 56), info

    txtWork = "ESC = end. The test on purpose grinds parent REDIM + member REDIM _RETAIN round and round."
    _PRINTSTRING (12, 78), txtWork

    _DISPLAY
LOOP


SCREEN 0
SYSTEM

