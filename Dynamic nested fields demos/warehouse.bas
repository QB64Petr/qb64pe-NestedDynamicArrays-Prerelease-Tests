OPTION _EXPLICIT
OPTION BASE 0

' ------------------------------------------------------------
' Nested dynamic field graphical editor demo:
'
' Warehouse -> Products -> Batches -> Serial numbers
'
' This demo shows a realistic use case for nested _DynamicField
' member arrays. Every warehouse has its own product list, every
' product has its own batch list, and every batch has its own
' serial number list.
'
' The data can be browsed and edited in memory. Nothing is saved
' to disk. This keeps the demo focused on nested dynamic fields,
' not on file I/O.
' ------------------------------------------------------------

TYPE SerialInfo
    serialName AS STRING
END TYPE

TYPE BatchInfo
    batchCode AS STRING
    unitCount AS LONG
    serialCount AS LONG

    ' Dynamic embedded array:
    ' each batch can have a different number of serial numbers.
    serials(0) _DYNAMICFIELD AS SerialInfo
END TYPE

TYPE ProductInfo
    productName AS STRING
    productCode AS STRING

    ' Static embedded array:
    ' every product has the same two fixed warehouse tags.
    fixedTag(1 TO 2) _STATICFIELD AS STRING * 18

    batchCount AS LONG

    ' Dynamic embedded array:
    ' each product can have a different number of batches.
    batches(0) _DYNAMICFIELD AS BatchInfo
END TYPE

TYPE WarehouseInfo
    warehouseName AS STRING
    cityName AS STRING
    productCount AS LONG

    ' Dynamic embedded array:
    ' each warehouse can have a different number of products.
    products(0) _DYNAMICFIELD AS ProductInfo
END TYPE


DIM screenHandle AS LONG
DIM selectedRow AS LONG
DIM topRow AS LONG
DIM totalRows AS LONG
DIM visibleRows AS LONG
DIM editField AS LONG
DIM editMode AS LONG
DIM quitFlag AS LONG
DIM keyText AS STRING
DIM prefixCode AS LONG
DIM extCode AS LONG

REDIM warehouse(0 TO 1) AS WarehouseInfo

screenHandle = _NEWIMAGE(1200, 760, 32)
SCREEN screenHandle
_TITLE "QB64PE Nested Dynamic Field Demo - Editable Warehouse"
_PRINTMODE _KEEPBACKGROUND

BuildDemoData warehouse()

selectedRow = 0
topRow = 0
visibleRows = 18
editField = 3
editMode = 0
quitFlag = 0

DO
    CountSerialRows warehouse(), totalRows

    IF totalRows < 1 THEN
        selectedRow = 0
        topRow = 0
    ELSE
        IF selectedRow < 0 THEN selectedRow = 0
        IF selectedRow > totalRows - 1 THEN selectedRow = totalRows - 1

        IF topRow > selectedRow THEN topRow = selectedRow
        IF selectedRow >= topRow + visibleRows THEN topRow = selectedRow - visibleRows + 1
        IF topRow < 0 THEN topRow = 0
        IF topRow > totalRows - visibleRows THEN topRow = totalRows - visibleRows
        IF topRow < 0 THEN topRow = 0
    END IF

    DrawWarehouseEditor warehouse(), selectedRow, topRow, visibleRows, editField, editMode
    _DISPLAY
    _LIMIT 60

    keyText = INKEY$

    IF keyText <> "" THEN
        IF editMode <> 0 THEN
            IF keyText = CHR$(27) THEN
                editMode = 0
            ELSEIF keyText = CHR$(13) THEN
                editMode = 0
            ELSEIF keyText = CHR$(9) THEN
                editField = editField + 1
                IF editField > 3 THEN editField = 1
            ELSE
                ApplyEditKey warehouse(), selectedRow, editField, keyText
            END IF
        ELSE
            IF keyText = CHR$(27) THEN
                quitFlag = 1
            ELSEIF keyText = CHR$(13) THEN
                editMode = 1
            ELSEIF keyText = CHR$(9) THEN
                editField = editField + 1
                IF editField > 3 THEN editField = 1
            ELSEIF LEN(keyText) = 2 THEN
                prefixCode = ASC(keyText)

                IF prefixCode = 0 OR prefixCode = 224 THEN
                    extCode = ASC(RIGHT$(keyText, 1))

                    SELECT CASE extCode
                        CASE 72
                            selectedRow = selectedRow - 1
                        CASE 80
                            selectedRow = selectedRow + 1
                        CASE 73
                            selectedRow = selectedRow - visibleRows
                        CASE 81
                            selectedRow = selectedRow + visibleRows
                        CASE 71
                            selectedRow = 0
                        CASE 79
                            selectedRow = totalRows - 1
                    END SELECT
                END IF
            END IF
        END IF
    END IF
LOOP UNTIL quitFlag <> 0

ERASE warehouse


' ============================================================
' Demo data
' ============================================================

SUB BuildDemoData (w() AS WarehouseInfo)

    w(0).warehouseName = "North Hub"
    w(0).cityName = "Prague"
    w(0).productCount = 3

    REDIM w(0).products(0 TO w(0).productCount - 1)

    w(0).products(0).productName = "Industrial Motor"
    w(0).products(0).productCode = "MTR-100"
    w(0).products(0).fixedTag(1) = "Heavy"
    w(0).products(0).fixedTag(2) = "Electric"
    w(0).products(0).batchCount = 2

    REDIM w(0).products(0).batches(0 TO w(0).products(0).batchCount - 1)

    w(0).products(0).batches(0).batchCode = "B-A100"
    w(0).products(0).batches(0).unitCount = 4
    w(0).products(0).batches(0).serialCount = 4
    REDIM w(0).products(0).batches(0).serials(0 TO w(0).products(0).batches(0).serialCount - 1)
    w(0).products(0).batches(0).serials(0).serialName = "SN-A100-01"
    w(0).products(0).batches(0).serials(1).serialName = "SN-A100-02"
    w(0).products(0).batches(0).serials(2).serialName = "SN-A100-03"
    w(0).products(0).batches(0).serials(3).serialName = "SN-A100-04"

    w(0).products(0).batches(1).batchCode = "B-A220"
    w(0).products(0).batches(1).unitCount = 2
    w(0).products(0).batches(1).serialCount = 2
    REDIM w(0).products(0).batches(1).serials(0 TO w(0).products(0).batches(1).serialCount - 1)
    w(0).products(0).batches(1).serials(0).serialName = "SN-A220-01"
    w(0).products(0).batches(1).serials(1).serialName = "SN-A220-02"

    w(0).products(1).productName = "Control Panel"
    w(0).products(1).productCode = "CTL-900"
    w(0).products(1).fixedTag(1) = "Sensitive"
    w(0).products(1).fixedTag(2) = "Indoor"
    w(0).products(1).batchCount = 1

    REDIM w(0).products(1).batches(0 TO w(0).products(1).batchCount - 1)

    w(0).products(1).batches(0).batchCode = "B-C900"
    w(0).products(1).batches(0).unitCount = 3
    w(0).products(1).batches(0).serialCount = 3
    REDIM w(0).products(1).batches(0).serials(0 TO w(0).products(1).batches(0).serialCount - 1)
    w(0).products(1).batches(0).serials(0).serialName = "SN-C900-11"
    w(0).products(1).batches(0).serials(1).serialName = "SN-C900-12"
    w(0).products(1).batches(0).serials(2).serialName = "SN-C900-13"

    w(0).products(2).productName = "Sensor Module"
    w(0).products(2).productCode = "SNS-40"
    w(0).products(2).fixedTag(1) = "Small"
    w(0).products(2).fixedTag(2) = "Fragile"
    w(0).products(2).batchCount = 3

    REDIM w(0).products(2).batches(0 TO w(0).products(2).batchCount - 1)

    w(0).products(2).batches(0).batchCode = "B-S401"
    w(0).products(2).batches(0).unitCount = 5
    w(0).products(2).batches(0).serialCount = 5
    REDIM w(0).products(2).batches(0).serials(0 TO w(0).products(2).batches(0).serialCount - 1)
    w(0).products(2).batches(0).serials(0).serialName = "SN-S401-01"
    w(0).products(2).batches(0).serials(1).serialName = "SN-S401-02"
    w(0).products(2).batches(0).serials(2).serialName = "SN-S401-03"
    w(0).products(2).batches(0).serials(3).serialName = "SN-S401-04"
    w(0).products(2).batches(0).serials(4).serialName = "SN-S401-05"

    w(0).products(2).batches(1).batchCode = "B-S402"
    w(0).products(2).batches(1).unitCount = 2
    w(0).products(2).batches(1).serialCount = 2
    REDIM w(0).products(2).batches(1).serials(0 TO w(0).products(2).batches(1).serialCount - 1)
    w(0).products(2).batches(1).serials(0).serialName = "SN-S402-01"
    w(0).products(2).batches(1).serials(1).serialName = "SN-S402-02"

    w(0).products(2).batches(2).batchCode = "B-S499"
    w(0).products(2).batches(2).unitCount = 1
    w(0).products(2).batches(2).serialCount = 1
    REDIM w(0).products(2).batches(2).serials(0 TO w(0).products(2).batches(2).serialCount - 1)
    w(0).products(2).batches(2).serials(0).serialName = "SN-S499-99"


    w(1).warehouseName = "South Depot"
    w(1).cityName = "Brno"
    w(1).productCount = 2

    REDIM w(1).products(0 TO w(1).productCount - 1)

    w(1).products(0).productName = "Power Supply"
    w(1).products(0).productCode = "PWR-55"
    w(1).products(0).fixedTag(1) = "DC"
    w(1).products(0).fixedTag(2) = "Service"
    w(1).products(0).batchCount = 2

    REDIM w(1).products(0).batches(0 TO w(1).products(0).batchCount - 1)

    w(1).products(0).batches(0).batchCode = "B-P550"
    w(1).products(0).batches(0).unitCount = 2
    w(1).products(0).batches(0).serialCount = 2
    REDIM w(1).products(0).batches(0).serials(0 TO w(1).products(0).batches(0).serialCount - 1)
    w(1).products(0).batches(0).serials(0).serialName = "SN-P550-01"
    w(1).products(0).batches(0).serials(1).serialName = "SN-P550-02"

    w(1).products(0).batches(1).batchCode = "B-P551"
    w(1).products(0).batches(1).unitCount = 4
    w(1).products(0).batches(1).serialCount = 4
    REDIM w(1).products(0).batches(1).serials(0 TO w(1).products(0).batches(1).serialCount - 1)
    w(1).products(0).batches(1).serials(0).serialName = "SN-P551-01"
    w(1).products(0).batches(1).serials(1).serialName = "SN-P551-02"
    w(1).products(0).batches(1).serials(2).serialName = "SN-P551-03"
    w(1).products(0).batches(1).serials(3).serialName = "SN-P551-04"

    w(1).products(1).productName = "Relay Board"
    w(1).products(1).productCode = "RLY-8"
    w(1).products(1).fixedTag(1) = "Output"
    w(1).products(1).fixedTag(2) = "Testing"
    w(1).products(1).batchCount = 1

    REDIM w(1).products(1).batches(0 TO w(1).products(1).batchCount - 1)

    w(1).products(1).batches(0).batchCode = "B-R800"
    w(1).products(1).batches(0).unitCount = 6
    w(1).products(1).batches(0).serialCount = 6
    REDIM w(1).products(1).batches(0).serials(0 TO w(1).products(1).batches(0).serialCount - 1)
    w(1).products(1).batches(0).serials(0).serialName = "SN-R800-01"
    w(1).products(1).batches(0).serials(1).serialName = "SN-R800-02"
    w(1).products(1).batches(0).serials(2).serialName = "SN-R800-03"
    w(1).products(1).batches(0).serials(3).serialName = "SN-R800-04"
    w(1).products(1).batches(0).serials(4).serialName = "SN-R800-05"
    w(1).products(1).batches(0).serials(5).serialName = "SN-R800-06"

END SUB


' ============================================================
' Navigation and editing helpers
' ============================================================

SUB CountSerialRows (w() AS WarehouseInfo, totalRows AS LONG)
    DIM wi AS LONG
    DIM pi AS LONG
    DIM bi AS LONG

    totalRows = 0

    FOR wi = LBOUND(w) TO UBOUND(w)
        FOR pi = LBOUND(w(wi).products) TO UBOUND(w(wi).products)
            FOR bi = LBOUND(w(wi).products(pi).batches) TO UBOUND(w(wi).products(pi).batches)
                totalRows = totalRows + w(wi).products(pi).batches(bi).serialCount
            NEXT bi
        NEXT pi
    NEXT wi
END SUB


SUB MapSerialRow (w() AS WarehouseInfo, targetRow AS LONG, outWi AS LONG, outPi AS LONG, outBi AS LONG, outSi AS LONG, found AS LONG)
    DIM wi AS LONG
    DIM pi AS LONG
    DIM bi AS LONG
    DIM si AS LONG
    DIM rowIndex AS LONG

    rowIndex = 0
    found = 0

    FOR wi = LBOUND(w) TO UBOUND(w)
        FOR pi = LBOUND(w(wi).products) TO UBOUND(w(wi).products)
            FOR bi = LBOUND(w(wi).products(pi).batches) TO UBOUND(w(wi).products(pi).batches)
                FOR si = LBOUND(w(wi).products(pi).batches(bi).serials) TO UBOUND(w(wi).products(pi).batches(bi).serials)
                    IF rowIndex = targetRow THEN
                        outWi = wi
                        outPi = pi
                        outBi = bi
                        outSi = si
                        found = -1
                        EXIT SUB
                    END IF

                    rowIndex = rowIndex + 1
                NEXT si
            NEXT bi
        NEXT pi
    NEXT wi
END SUB


SUB ApplyEditKey (w() AS WarehouseInfo, selectedRow AS LONG, editField AS LONG, keyText AS STRING)
    DIM wi AS LONG
    DIM pi AS LONG
    DIM bi AS LONG
    DIM si AS LONG
    DIM found AS LONG
    DIM editedText AS STRING

    MapSerialRow w(), selectedRow, wi, pi, bi, si, found
    IF found = 0 THEN EXIT SUB

    SELECT CASE editField
        CASE 1
            editedText = w(wi).products(pi).productName
            EditStringValue editedText, keyText, 48
            w(wi).products(pi).productName = editedText

        CASE 2
            editedText = w(wi).products(pi).batches(bi).batchCode
            EditStringValue editedText, keyText, 32
            w(wi).products(pi).batches(bi).batchCode = editedText

        CASE 3
            editedText = w(wi).products(pi).batches(bi).serials(si).serialName
            EditStringValue editedText, keyText, 48
            w(wi).products(pi).batches(bi).serials(si).serialName = editedText
    END SELECT
END SUB


SUB EditStringValue (fieldText AS STRING, keyText AS STRING, maxChars AS LONG)
    DIM charCode AS LONG

    IF keyText = CHR$(8) THEN
        IF LEN(fieldText) > 0 THEN fieldText = LEFT$(fieldText, LEN(fieldText) - 1)
        EXIT SUB
    END IF

    IF LEN(keyText) <> 1 THEN EXIT SUB

    charCode = ASC(keyText)

    IF charCode >= 32 AND charCode <= 255 THEN
        IF LEN(fieldText) < maxChars THEN fieldText = fieldText + keyText
    END IF
END SUB


' ============================================================
' Drawing
' ============================================================

SUB DrawWarehouseEditor (w() AS WarehouseInfo, selectedRow AS LONG, topRow AS LONG, visibleRows AS LONG, editField AS LONG, editMode AS LONG)
    DIM bgCol AS _UNSIGNED LONG
    DIM headerCol AS _UNSIGNED LONG
    DIM panelCol AS _UNSIGNED LONG
    DIM cardCol AS _UNSIGNED LONG
    DIM rowCol AS _UNSIGNED LONG
    DIM selectedCol AS _UNSIGNED LONG
    DIM borderCol AS _UNSIGNED LONG
    DIM accentCol AS _UNSIGNED LONG
    DIM textCol AS _UNSIGNED LONG
    DIM dimCol AS _UNSIGNED LONG
    DIM editCol AS _UNSIGNED LONG

    bgCol = _RGB32(18, 24, 36)
    headerCol = _RGB32(29, 38, 56)
    panelCol = _RGB32(34, 45, 66)
    cardCol = _RGB32(42, 55, 78)
    rowCol = _RGB32(48, 62, 88)
    selectedCol = _RGB32(65, 88, 126)
    borderCol = _RGB32(92, 116, 156)
    accentCol = _RGB32(90, 180, 255)
    textCol = _RGB32(235, 240, 250)
    dimCol = _RGB32(178, 190, 210)
    editCol = _RGB32(255, 224, 120)

    CLS , bgCol

    LINE (0, 0)-(1199, 72), headerCol, BF
    LINE (0, 72)-(1199, 72), accentCol

    PrintFit 24, 16, "QB64PE Nested Dynamic Field Demo - Editable Warehouse", 72, textCol
    PrintFit 24, 42, "Browse and edit runtime data stored in nested _DynamicField arrays. No file saving is used.", 105, dimCol

    DrawListPanel w(), selectedRow, topRow, visibleRows, 24, 96, 700, 565, panelCol, rowCol, selectedCol, borderCol, accentCol, textCol, dimCol
    DrawDetailPanel w(), selectedRow, editField, editMode, 748, 96, 428, 565, cardCol, borderCol, accentCol, textCol, dimCol, editCol

    LINE (24, 690)-(1176, 735), _RGB32(30, 40, 58), BF
    LINE (24, 690)-(1176, 735), borderCol, B

    IF editMode = 0 THEN
        PrintFit 42, 704, "Keys: Up/Down select   PageUp/PageDown scroll   Home/End jump   Tab choose field   Enter edit   Esc quit", 138, dimCol
    ELSE
        PrintFit 42, 704, "EDIT MODE: type text   Backspace delete   Tab choose field   Enter or Esc leave edit mode", 138, editCol
    END IF
END SUB


SUB DrawListPanel (w() AS WarehouseInfo, selectedRow AS LONG, topRow AS LONG, visibleRows AS LONG, x AS LONG, y AS LONG, panelW AS LONG, panelH AS LONG, panelCol AS _UNSIGNED LONG, rowCol AS _UNSIGNED LONG, selectedCol AS _UNSIGNED LONG, borderCol AS _UNSIGNED LONG, accentCol AS _UNSIGNED LONG, textCol AS _UNSIGNED LONG, dimCol AS _UNSIGNED LONG)
    DIM rowIndex AS LONG
    DIM drawIndex AS LONG
    DIM rowY AS LONG
    DIM wi AS LONG
    DIM pi AS LONG
    DIM bi AS LONG
    DIM si AS LONG
    DIM found AS LONG
    DIM rowText AS STRING
    DIM totalRows AS LONG

    CountSerialRows w(), totalRows

    LINE (x, y)-(x + panelW, y + panelH), panelCol, BF
    LINE (x, y)-(x + panelW, y + panelH), borderCol, B

    PrintFit x + 16, y + 14, "Serial number list", 60, textCol
    PrintFit x + 500, y + 14, "Rows: " + LTRIM$(STR$(totalRows)), 24, dimCol

    LINE (x + 14, y + 42)-(x + panelW - 14, y + 42), accentCol

    FOR drawIndex = 0 TO visibleRows - 1
        rowIndex = topRow + drawIndex
        rowY = y + 54 + drawIndex * 28

        IF rowIndex >= totalRows THEN
            LINE (x + 12, rowY)-(x + panelW - 12, rowY + 23), _RGB32(39, 50, 70), BF
        ELSE
            MapSerialRow w(), rowIndex, wi, pi, bi, si, found

            IF found <> 0 THEN
                IF rowIndex = selectedRow THEN
                    LINE (x + 12, rowY)-(x + panelW - 12, rowY + 23), selectedCol, BF
                    LINE (x + 12, rowY)-(x + panelW - 12, rowY + 23), accentCol, B
                ELSE
                    LINE (x + 12, rowY)-(x + panelW - 12, rowY + 23), rowCol, BF
                END IF

                rowText = LTRIM$(STR$(rowIndex + 1)) + ". " + _
                          RTRIM$(w(wi).warehouseName) + " / " + _
                          RTRIM$(w(wi).products(pi).productCode) + " / " + _
                          RTRIM$(w(wi).products(pi).batches(bi).batchCode) + " / " + _
                          RTRIM$(w(wi).products(pi).batches(bi).serials(si).serialName)

                PrintFit x + 22, rowY + 5, rowText, 82, textCol
            END IF
        END IF
    NEXT drawIndex

    PrintFit x + 16, y + panelH + 8, "The list is generated from Warehouse.products().batches().serials().", 80, dimCol
END SUB


SUB DrawDetailPanel (w() AS WarehouseInfo, selectedRow AS LONG, editField AS LONG, editMode AS LONG, x AS LONG, y AS LONG, panelW AS LONG, panelH AS LONG, cardCol AS _UNSIGNED LONG, borderCol AS _UNSIGNED LONG, accentCol AS _UNSIGNED LONG, textCol AS _UNSIGNED LONG, dimCol AS _UNSIGNED LONG, editCol AS _UNSIGNED LONG)
    DIM wi AS LONG
    DIM pi AS LONG
    DIM bi AS LONG
    DIM si AS LONG
    DIM found AS LONG
    DIM statusText AS STRING

    LINE (x, y)-(x + panelW, y + panelH), cardCol, BF
    LINE (x, y)-(x + panelW, y + panelH), borderCol, B

    PrintFit x + 16, y + 14, "Selected record", 45, textCol
    LINE (x + 14, y + 42)-(x + panelW - 14, y + 42), accentCol

    MapSerialRow w(), selectedRow, wi, pi, bi, si, found

    IF found = 0 THEN
        PrintFit x + 16, y + 64, "No selected record.", 45, dimCol
        EXIT SUB
    END IF

    PrintFit x + 16, y + 62, "Warehouse:", 18, dimCol
    PrintFit x + 140, y + 62, RTRIM$(w(wi).warehouseName), 32, textCol

    PrintFit x + 16, y + 88, "City:", 18, dimCol
    PrintFit x + 140, y + 88, RTRIM$(w(wi).cityName), 32, textCol

    PrintFit x + 16, y + 124, "Product code:", 18, dimCol
    PrintFit x + 140, y + 124, RTRIM$(w(wi).products(pi).productCode), 32, textCol

    DrawEditBox x + 16, y + 154, panelW - 32, 44, "Product name", w(wi).products(pi).productName, editField, 1, editMode, textCol, dimCol, borderCol, accentCol, editCol

    PrintFit x + 16, y + 214, "Static tags:", 18, dimCol
    PrintFit x + 140, y + 214, RTRIM$(w(wi).products(pi).fixedTag(1)) + ", " + RTRIM$(w(wi).products(pi).fixedTag(2)), 32, textCol

    DrawEditBox x + 16, y + 252, panelW - 32, 44, "Batch code", w(wi).products(pi).batches(bi).batchCode, editField, 2, editMode, textCol, dimCol, borderCol, accentCol, editCol

    PrintFit x + 16, y + 312, "Batch units:", 18, dimCol
    PrintFit x + 140, y + 312, LTRIM$(STR$(w(wi).products(pi).batches(bi).unitCount)), 32, textCol

    PrintFit x + 16, y + 338, "Serial count:", 18, dimCol
    PrintFit x + 140, y + 338, LTRIM$(STR$(w(wi).products(pi).batches(bi).serialCount)), 32, textCol

    DrawEditBox x + 16, y + 376, panelW - 32, 44, "Serial number", w(wi).products(pi).batches(bi).serials(si).serialName, editField, 3, editMode, textCol, dimCol, borderCol, accentCol, editCol

    LINE (x + 16, y + 448)-(x + panelW - 16, y + 520), _RGB32(32, 43, 62), BF
    LINE (x + 16, y + 448)-(x + panelW - 16, y + 520), borderCol, B

    PrintFit x + 28, y + 462, "Memory model:", 45, textCol
    PrintFit x + 28, y + 486, "products(), batches(), and serials() are separate", 48, dimCol
    PrintFit x + 28, y + 506, "descriptor-backed nested dynamic member arrays.", 48, dimCol

    IF editMode = 0 THEN
        statusText = "View mode"
    ELSE
        statusText = "Editing selected field"
    END IF

    PrintFit x + 16, y + panelH - 28, statusText, 45, editCol
END SUB


SUB DrawEditBox (x AS LONG, y AS LONG, boxW AS LONG, boxH AS LONG, labelText AS STRING, valueText AS STRING, editField AS LONG, thisField AS LONG, editMode AS LONG, textCol AS _UNSIGNED LONG, dimCol AS _UNSIGNED LONG, borderCol AS _UNSIGNED LONG, accentCol AS _UNSIGNED LONG, editCol AS _UNSIGNED LONG)
    DIM boxCol AS _UNSIGNED LONG
    DIM frameCol AS _UNSIGNED LONG
    DIM shownText AS STRING

    boxCol = _RGB32(30, 40, 58)
    frameCol = borderCol

    IF editField = thisField THEN
        IF editMode <> 0 THEN
            frameCol = editCol
        ELSE
            frameCol = accentCol
        END IF
    END IF

    LINE (x, y)-(x + boxW, y + boxH), boxCol, BF
    LINE (x, y)-(x + boxW, y + boxH), frameCol, B

    PrintFit x + 10, y + 6, labelText, 28, dimCol

    IF editField = thisField AND editMode <> 0 THEN
        ' Show spaces while editing, so the user can see them.
        shownText = VisibleSpaces$(valueText) + "_"
    ELSE
        shownText = valueText
    END IF

    PrintFit x + 10, y + 24, shownText, 48, textCol
END SUB


SUB PrintFit (x AS LONG, y AS LONG, sourceText AS STRING, maxChars AS LONG, textCol AS _UNSIGNED LONG)
    DIM shownText AS STRING

    shownText = sourceText

    IF maxChars > 3 THEN
        IF LEN(shownText) > maxChars THEN
            shownText = LEFT$(shownText, maxChars - 3) + "..."
        END IF
    END IF

    COLOR textCol
    _PRINTSTRING (x, y), shownText
END SUB

FUNCTION VisibleSpaces$ (sourceText AS STRING)
    DIM i AS LONG
    DIM resultText AS STRING
    DIM ch AS STRING

    resultText = ""

    FOR i = 1 TO LEN(sourceText)
        ch = MID$(sourceText, i, 1)

        IF ch = " " THEN
            resultText = resultText + CHR$(32)
        ELSE
            resultText = resultText + ch
        END IF
    NEXT i

    VisibleSpaces$ = resultText
END FUNCTION

