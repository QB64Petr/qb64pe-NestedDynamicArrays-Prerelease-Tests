' DynField_OpenGL_Maze_Stress_v7.bas
' Requires Petr's QB64PE branch with _StaticField / _DynamicField support.
' Purpose: OpenGL stress/demo program for static nested arrays + descriptor-backed dynamic member arrays in TYPE.
'
' Controls:
'   W/S         move forward/back
'   A/D         rotate
'   Q/E         strafe
'   R           rebuild the whole world with a different seed (ordinary REDIM cleanup/init test)
'   T           grow one sector with REDIM _RETAIN on nested dynamic fields
'   F           toggle fog
'   ESC         quit
'
'   V3 fix: the software HUD layer in V1/V2 used CLS, which can cover the whole _GLRENDER layer
'           with opaque black on some QB64PE/OpenGL setups.  V3 renders GL in front and moves diagnostics
'           to the window title, so the software layer cannot hide the 3D scene.
'   V4 fix: movement basis is now derived from the same yaw convention used by the camera.
'           W/S follows the visible view direction, Q/E strafes perpendicular to it.
'   V5 add: two-level world, stair walking, room objects/furniture and object collision.
'   V7 add: view-dependent face shading for boxes and permitted downward drops from upper floors.
'   V7 add: outdoor yard, fence, sky, clouds, trees, cars and object-part composition stress.

' Notes:
'   The program intentionally avoids _MEM, PUT/GET and texture loading.  Those are separate unsafe/legacy areas.
'   This file is meant as a source-level regression/showcase for the descriptor ownership path.
'   If this file is black, run GL_BlackScreen_SmokeTest.bas from the same zip first.

OPTION _EXPLICIT

CONST PI_OVER_180 = .0174532925199433!
CONST GRID_W = 14
CONST GRID_H = 14
CONST CELL_SIZE = 3.2!
CONST WALL_H = 2.1!
CONST LEVEL_H = 3.0!
CONST EYE_H = 1.08!
CONST PLAYER_BODY_H = 1.65!
CONST MAX_STEP_UP = .42!
CONST GRAVITY_STEP = .032!
CONST MAX_FALL_SPEED = .46!
CONST PLAYER_RADIUS = .28!
CONST MOVE_STEP = .095!
CONST TURN_STEP = 2.2!
CONST HIT_TRACE_MAX = 7
CONST OUT_MIN_X = -36!
CONST OUT_MAX_X = 36!
CONST OUT_MIN_Z = -36!
CONST OUT_MAX_Z = 39!
CONST OUT_YARD_Y = 0!
CONST FENCE_H = 1.35!

TYPE Vec2Pack
    xy(1) _STATICFIELD AS SINGLE
END TYPE

TYPE Vec3Pack
    xyz(2) _STATICFIELD AS SINGLE
END TYPE

TYPE ColorPack
    rgba(3) _STATICFIELD AS SINGLE
END TYPE

TYPE WallQuad
    corner(3) _STATICFIELD AS Vec3Pack
    uv(3) _STATICFIELD AS Vec2Pack
    tint AS ColorPack
    normal(2) _STATICFIELD AS SINGLE
    flags AS LONG
    labelText AS STRING
END TYPE

TYPE LampNode
    anchor(2) _STATICFIELD AS SINGLE
    tint AS ColorPack
    pulse(3) _STATICFIELD AS SINGLE
    labelText AS STRING
END TYPE

TYPE DecalNode
    anchor(2) _STATICFIELD AS SINGLE
    sizeBox(2) _STATICFIELD AS SINGLE
    tint AS ColorPack
    labelText AS STRING
END TYPE

TYPE PropNode
    center(2) _STATICFIELD AS SINGLE
    sizeBox(2) _STATICFIELD AS SINGLE
    tint AS ColorPack
    kindValue AS LONG
    solid AS _BYTE
    labelText AS STRING
END TYPE

TYPE RoomNode
    boundsMin(2) _STATICFIELD AS SINGLE
    boundsMax(2) _STATICFIELD AS SINGLE
    floorY AS SINGLE
    props(0) _DYNAMICFIELD AS PropNode
    labels(0) _DYNAMICFIELD AS STRING
    nameText AS STRING
END TYPE

TYPE StairNode
    zoneMin(2) _STATICFIELD AS SINGLE
    zoneMax(2) _STATICFIELD AS SINGLE
    lowY AS SINGLE
    highY AS SINGLE
    axisValue AS LONG
    stepCount AS LONG
    tint AS ColorPack
    labelText AS STRING
END TYPE

TYPE ObjectPart
    center(2) _STATICFIELD AS SINGLE
    sizeBox(2) _STATICFIELD AS SINGLE
    tint AS ColorPack
    partKind AS LONG
    solid AS _BYTE
    labelText AS STRING
END TYPE

TYPE SceneObject
    anchor(2) _STATICFIELD AS SINGLE
    boundsMin(2) _STATICFIELD AS SINGLE
    boundsMax(2) _STATICFIELD AS SINGLE
    objectKind AS LONG
    solid AS _BYTE
    parts(0) _DYNAMICFIELD AS ObjectPart
    tags(0) _DYNAMICFIELD AS STRING
    nameText AS STRING
END TYPE

TYPE CloudNode
    anchor(2) _STATICFIELD AS SINGLE
    drift(2) _STATICFIELD AS SINGLE
    puffs(0) _DYNAMICFIELD AS ObjectPart
    labels(0) _DYNAMICFIELD AS STRING
    nameText AS STRING
END TYPE

TYPE HitInfo
    active AS _BYTE
    anchor(2) _STATICFIELD AS SINGLE
    normal(2) _STATICFIELD AS SINGLE
    sectorSlot AS LONG
    wallSlot AS LONG
    ageFrame AS LONG
END TYPE

TYPE SectorNode
    cell(1) _STATICFIELD AS LONG
    center(2) _STATICFIELD AS SINGLE
    floorY AS SINGLE
    sectorFlags AS LONG
    floorTint AS ColorPack
    boundsMin(2) _STATICFIELD AS SINGLE
    boundsMax(2) _STATICFIELD AS SINGLE
    walls(0) _DYNAMICFIELD AS WallQuad
    lamps(0) _DYNAMICFIELD AS LampNode
    decals(0) _DYNAMICFIELD AS DecalNode
    notes(0) _DYNAMICFIELD AS STRING
    nameText AS STRING
END TYPE

TYPE AuditRow
    marker AS LONG
    valuePack(3) _STATICFIELD AS SINGLE
    labelText AS STRING
END TYPE

TYPE WorldModel
    gridSize(1) _STATICFIELD AS LONG
    worldTint AS ColorPack
    sectors(0) _DYNAMICFIELD AS SectorNode
    rooms(0) _DYNAMICFIELD AS RoomNode
    stairs(0) _DYNAMICFIELD AS StairNode
    objects(0) _DYNAMICFIELD AS SceneObject
    clouds(0) _DYNAMICFIELD AS CloudNode
    messages(0) _DYNAMICFIELD AS STRING
    auditRows(0) _DYNAMICFIELD AS AuditRow
    lastHits(HIT_TRACE_MAX) _STATICFIELD AS HitInfo
END TYPE

REDIM SHARED demo(0 TO 0) AS WorldModel
DIM SHARED glReady AS _BYTE
DIM SHARED exitSignal AS _BYTE
DIM SHARED fogEnabled AS _BYTE
DIM SHARED worldSeed AS LONG
DIM SHARED playerX AS SINGLE
DIM SHARED playerY AS SINGLE
DIM SHARED playerGroundY AS SINGLE
DIM SHARED playerZ AS SINGLE
DIM SHARED playerYaw AS SINGLE
DIM SHARED playerPitch AS SINGLE
DIM SHARED playerVelY AS SINGLE
DIM SHARED playerAirborne AS _BYTE
DIM SHARED fogColor(0 TO 3) AS SINGLE
DIM SHARED worldReady AS _BYTE
DIM SHARED titleTick AS LONG

' Put GL last/on top.  The previous versions used _GLRENDER, _SOFTWARE plus CLS for the HUD,
' and that can produce a perfectly black software layer over a valid GL scene.
_DISPLAYORDER _SOFTWARE , _GLRENDER
_TITLE "_DynamicField OpenGL indoor/outdoor stress test V7"
SCREEN _NEWIMAGE(_DESKTOPWIDTH, _DESKTOPHEIGHT, 32)
_CLEARCOLOR _RGB32(0, 0, 0)
_MOUSEHIDE

fogColor(0) = .33!
fogColor(1) = .37!
fogColor(2) = .40!
fogColor(3) = 1!

fogEnabled = 0
worldSeed = 17
playerGroundY = 0!
playerY = EYE_H
playerYaw = 135!
playerPitch = 12!

BuildWorld worldSeed
PlacePlayerAtStart
worldReady = -1
UpdateWindowTitle

DO
    DIM keyCode AS LONG
    keyCode = _KEYHIT
    SELECT CASE keyCode
        CASE 27
            exitSignal = -1
        CASE 70, 102
            fogEnabled = NOT fogEnabled
        CASE 82, 114
            worldSeed = worldSeed + 19
            worldReady = 0
            BuildWorld worldSeed
            PlacePlayerAtStart
            worldReady = -1
            UpdateWindowTitle
        CASE 84, 116
            StressRetainPulse
            UpdateWindowTitle
    END SELECT

    HandleMotion
    UpdateVerticalMotion
    AgeHitStack
    titleTick = titleTick + 1
    IF titleTick > 20 THEN
        titleTick = 0
        UpdateWindowTitle
    END IF

    IF _EXIT THEN exitSignal = -1
    IF exitSignal THEN EXIT DO
    _LIMIT 60
LOOP

_MOUSESHOW
END

SUB HandleMotion
    DIM moveForward AS SINGLE
    DIM moveSide AS SINGLE
    DIM nextX AS SINGLE
    DIM nextZ AS SINGLE
    DIM fwdX AS SINGLE
    DIM fwdZ AS SINGLE
    DIM sideX AS SINGLE
    DIM sideZ AS SINGLE

    IF _KEYDOWN(ASC("A")) THEN playerYaw = playerYaw + TURN_STEP
    IF _KEYDOWN(ASC("D")) THEN playerYaw = playerYaw - TURN_STEP

    IF _KEYDOWN(ASC("W")) THEN moveForward = moveForward + MOVE_STEP
    IF _KEYDOWN(ASC("S")) THEN moveForward = moveForward - MOVE_STEP
    IF _KEYDOWN(ASC("E")) THEN moveSide = moveSide + MOVE_STEP
    IF _KEYDOWN(ASC("Q")) THEN moveSide = moveSide - MOVE_STEP

    IF _KEYDOWN(ASC("a")) THEN playerYaw = playerYaw + TURN_STEP
    IF _KEYDOWN(ASC("d")) THEN playerYaw = playerYaw - TURN_STEP

    IF _KEYDOWN(ASC("w")) THEN moveForward = moveForward + MOVE_STEP
    IF _KEYDOWN(ASC("s")) THEN moveForward = moveForward - MOVE_STEP
    IF _KEYDOWN(ASC("e")) THEN moveSide = moveSide + MOVE_STEP
    IF _KEYDOWN(ASC("q")) THEN moveSide = moveSide - MOVE_STEP

    MoveBasis playerYaw, fwdX, fwdZ, sideX, sideZ
    nextX = playerX + fwdX * moveForward + sideX * moveSide
    nextZ = playerZ + fwdZ * moveForward + sideZ * moveSide

    IF moveForward <> 0! OR moveSide <> 0! THEN TryMove nextX, nextZ
END SUB

SUB MoveBasis (yawValue AS SINGLE, fwdX AS SINGLE, fwdZ AS SINGLE, sideX AS SINGLE, sideZ AS SINGLE)
    DIM yawRad AS SINGLE

    yawRad = yawValue * PI_OVER_180

    ' Must match RenderGLScene camera transform:
    '   _glRotatef 360! - playerYaw, 0!, 1!, 0!
    ' At yaw 0, the camera looks toward -Z.  Positive yaw looks toward -X.
    fwdX = -SIN(yawRad)
    fwdZ = -COS(yawRad)
    sideX = COS(yawRad)
    sideZ = -SIN(yawRad)
END SUB

SUB PlacePlayerAtStart
    playerX = -((GRID_W * CELL_SIZE) / 2!) + CELL_SIZE * 1.5!
    playerZ = -((GRID_H * CELL_SIZE) / 2!) + CELL_SIZE * 1.5!
    GroundHeight playerX, playerZ, playerGroundY
    playerY = playerGroundY + EYE_H
    playerVelY = 0!
    playerAirborne = 0
END SUB

SUB UpdateVerticalMotion
    DIM targetEyeY AS SINGLE

    targetEyeY = playerGroundY + EYE_H

    IF playerY > targetEyeY + .01! OR playerAirborne THEN
        playerAirborne = -1
        playerVelY = playerVelY - GRAVITY_STEP
        IF playerVelY < -MAX_FALL_SPEED THEN playerVelY = -MAX_FALL_SPEED
        playerY = playerY + playerVelY
        IF playerY <= targetEyeY THEN
            playerY = targetEyeY
            playerVelY = 0!
            playerAirborne = 0
        END IF
    ELSE
        playerY = targetEyeY
        playerVelY = 0!
        playerAirborne = 0
    END IF
END SUB

SUB BuildWorld (seedValue AS LONG)
    DIM gx AS LONG
    DIM gy AS LONG
    DIM sectorSlot AS LONG
    DIM totalSectors AS LONG
    DIM minX AS SINGLE
    DIM maxX AS SINGLE
    DIM minZ AS SINGLE
    DIM maxZ AS SINGLE
    DIM wallCount AS LONG
    DIM wallSlot AS LONG
    DIM lampCount AS LONG
    DIM lampSlot AS LONG
    DIM decalCount AS LONG
    DIM decalSlot AS LONG
    DIM noteCount AS LONG
    DIM noteSlot AS LONG
    DIM auditSlot AS LONG
    DIM spanX AS SINGLE
    DIM spanZ AS SINGLE
    DIM floorLevel AS SINGLE
    DIM westWall AS _BYTE
    DIM eastWall AS _BYTE
    DIM northWall AS _BYTE
    DIM southWall AS _BYTE
    DIM extraWall AS _BYTE

    ' This ordinary REDIM is intentional: it exercises cleanup and reinitialisation of the direct owner.
    REDIM demo(0 TO 0) AS WorldModel

    demo(0).gridSize(0) = GRID_W
    demo(0).gridSize(1) = GRID_H
    demo(0).worldTint.rgba(0) = .72!
    demo(0).worldTint.rgba(1) = .78!
    demo(0).worldTint.rgba(2) = .88!
    demo(0).worldTint.rgba(3) = 1!

    totalSectors = GRID_W * GRID_H
    REDIM demo(0).sectors(0 TO totalSectors - 1) AS SECTORNODE
    REDIM demo(0).stairs(0 TO 0) AS STAIRNODE
    REDIM demo(0).messages(0 TO 8) AS STRING
    REDIM demo(0).auditRows(0 TO 11) AS AUDITROW

    SetStair demo(0).stairs(0), -6.05!, -5.55!, 4.05!, 2.55!, 0!, LEVEL_H, 12, "main stair"

    demo(0).messages(0) = "OpenGL + _StaticField + _DynamicField nested ownership demo"
    demo(0).messages(1) = "V7 adds outdoor yard, sky, fence, clouds, trees, cars and colour chaos."
    demo(0).messages(2) = "R rebuilds the whole direct-owner world with ordinary REDIM."
    demo(0).messages(3) = "T grows nested walls/notes/lamps/room props/object parts/cloud puffs with REDIM _RETAIN."
    demo(0).messages(4) = "Collision scans descriptor-backed wall arrays, room props and outdoor object parts."
    demo(0).messages(5) = "Objects are composed from dynamic part arrays to simulate a small OOP scene graph."
    demo(0).messages(6) = "The south gate opens to the fenced outside yard."
    demo(0).messages(7) = "No _MEM, no PUT/GET: this targets safe array semantics."
    demo(0).messages(8) = "Future asset loader direction: OBJ first, glTF later."

    FOR auditSlot = 0 TO UBOUND(demo(0).auditRows)
        demo(0).auditRows(auditSlot).marker = auditSlot + seedValue * 100
        demo(0).auditRows(auditSlot).valuePack(0) = auditSlot * .25!
        demo(0).auditRows(auditSlot).valuePack(1) = seedValue
        demo(0).auditRows(auditSlot).valuePack(2) = GRID_W
        demo(0).auditRows(auditSlot).valuePack(3) = GRID_H
        demo(0).auditRows(auditSlot).labelText = "audit-row-" + LTRIM$(STR$(auditSlot))
    NEXT auditSlot

    FOR gy = 0 TO GRID_H - 1
        FOR gx = 0 TO GRID_W - 1
            sectorSlot = gy * GRID_W + gx
            minX = (gx - GRID_W / 2!) * CELL_SIZE
            maxX = minX + CELL_SIZE
            minZ = (gy - GRID_H / 2!) * CELL_SIZE
            maxZ = minZ + CELL_SIZE
            CellFloorY gx, gy, floorLevel

            demo(0).sectors(sectorSlot).cell(0) = gx
            demo(0).sectors(sectorSlot).cell(1) = gy
            demo(0).sectors(sectorSlot).center(0) = (minX + maxX) * .5!
            demo(0).sectors(sectorSlot).center(1) = floorLevel
            demo(0).sectors(sectorSlot).center(2) = (minZ + maxZ) * .5!
            demo(0).sectors(sectorSlot).floorY = floorLevel
            demo(0).sectors(sectorSlot).sectorFlags = 0
            IF floorLevel > 0! THEN demo(0).sectors(sectorSlot).sectorFlags = demo(0).sectors(sectorSlot).sectorFlags OR 2
            demo(0).sectors(sectorSlot).boundsMin(0) = minX
            demo(0).sectors(sectorSlot).boundsMin(1) = floorLevel
            demo(0).sectors(sectorSlot).boundsMin(2) = minZ
            demo(0).sectors(sectorSlot).boundsMax(0) = maxX
            demo(0).sectors(sectorSlot).boundsMax(1) = floorLevel + WALL_H
            demo(0).sectors(sectorSlot).boundsMax(2) = maxZ
            demo(0).sectors(sectorSlot).nameText = "sector " + LTRIM$(STR$(gx)) + ":" + LTRIM$(STR$(gy))

            demo(0).sectors(sectorSlot).floorTint.rgba(0) = .18! + ((gx MOD 3) * .035!) + floorLevel * .035!
            demo(0).sectors(sectorSlot).floorTint.rgba(1) = .20! + ((gy MOD 4) * .028!) + floorLevel * .025!
            demo(0).sectors(sectorSlot).floorTint.rgba(2) = .24! + (((gx + gy) MOD 5) * .022!) + floorLevel * .015!
            demo(0).sectors(sectorSlot).floorTint.rgba(3) = 1!

            westWall = 0: eastWall = 0: northWall = 0: southWall = 0: extraWall = 0
            IF gx = 0 THEN westWall = -1
            IF gx = GRID_W - 1 THEN eastWall = -1
            IF gy = 0 THEN northWall = -1
            IF gy = GRID_H - 1 THEN southWall = -1
            IF gy = GRID_H - 1 AND gx >= 3 AND gx <= 5 THEN southWall = 0

            ' Interior splitters only.  The main level transition is blocked by height-difference physics,
            ' except inside the stair volume.  This keeps the test explorable instead of making a random prison.
            IF ((gx * 23 + gy * 29 + seedValue) MOD 6) = 0 THEN extraWall = -1
            IF gx <= 2 AND gy <= 2 THEN extraWall = 0
            IF gx >= 5 AND gx <= 8 AND gy >= 5 AND gy <= 8 THEN extraWall = 0

            wallCount = 0
            IF westWall THEN wallCount = wallCount + 1
            IF eastWall THEN wallCount = wallCount + 1
            IF northWall THEN wallCount = wallCount + 1
            IF southWall THEN wallCount = wallCount + 1
            IF extraWall THEN wallCount = wallCount + 1
            IF wallCount = 0 THEN wallCount = 1

            REDIM demo(0).sectors(sectorSlot).walls(0 TO wallCount - 1) AS WALLQUAD
            wallSlot = 0

            IF westWall THEN
                SetWallQuad demo(0).sectors(sectorSlot).walls(wallSlot), minX, minZ, minX, maxZ, floorLevel, floorLevel + WALL_H, .40!, .60!, .85!, "west"
                wallSlot = wallSlot + 1
            END IF
            IF eastWall THEN
                SetWallQuad demo(0).sectors(sectorSlot).walls(wallSlot), maxX, maxZ, maxX, minZ, floorLevel, floorLevel + WALL_H, .85!, .48!, .38!, "east"
                wallSlot = wallSlot + 1
            END IF
            IF northWall THEN
                SetWallQuad demo(0).sectors(sectorSlot).walls(wallSlot), maxX, minZ, minX, minZ, floorLevel, floorLevel + WALL_H, .55!, .72!, .48!, "north"
                wallSlot = wallSlot + 1
            END IF
            IF southWall THEN
                SetWallQuad demo(0).sectors(sectorSlot).walls(wallSlot), minX, maxZ, maxX, maxZ, floorLevel, floorLevel + WALL_H, .78!, .64!, .36!, "south"
                wallSlot = wallSlot + 1
            END IF
            IF extraWall THEN
                spanX = minX + CELL_SIZE * .24!
                spanZ = minZ + CELL_SIZE * .50!
                SetWallQuad demo(0).sectors(sectorSlot).walls(wallSlot), spanX, spanZ, spanX + CELL_SIZE * .52!, spanZ, floorLevel, floorLevel + WALL_H * .85!, .75!, .35!, .80!, "splitter"
                wallSlot = wallSlot + 1
            END IF
            IF wallSlot = 0 THEN
                demo(0).sectors(sectorSlot).walls(0).flags = 0
                demo(0).sectors(sectorSlot).walls(0).labelText = "empty-wall-placeholder"
            END IF

            noteCount = 1 + ((gx + gy + seedValue) MOD 3)
            REDIM demo(0).sectors(sectorSlot).notes(0 TO noteCount - 1) AS STRING
            FOR noteSlot = 0 TO noteCount - 1
                demo(0).sectors(sectorSlot).notes(noteSlot) = demo(0).sectors(sectorSlot).nameText + " note " + LTRIM$(STR$(noteSlot))
            NEXT noteSlot

            lampCount = 1 + ((gx * 3 + gy + seedValue) MOD 2)
            REDIM demo(0).sectors(sectorSlot).lamps(0 TO lampCount - 1) AS LAMPNODE
            FOR lampSlot = 0 TO lampCount - 1
                demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(0) = minX + CELL_SIZE * (.35! + lampSlot * .25!)
                demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(1) = floorLevel + WALL_H - .25!
                demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(2) = minZ + CELL_SIZE * (.35! + ((gx + gy + lampSlot) MOD 2) * .30!)
                demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(0) = .9!
                demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(1) = .65! + .1! * (lampSlot MOD 2)
                demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(2) = .25!
                demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(3) = 1!
                demo(0).sectors(sectorSlot).lamps(lampSlot).pulse(0) = lampSlot
                demo(0).sectors(sectorSlot).lamps(lampSlot).pulse(1) = gx
                demo(0).sectors(sectorSlot).lamps(lampSlot).pulse(2) = gy
                demo(0).sectors(sectorSlot).lamps(lampSlot).pulse(3) = seedValue
                demo(0).sectors(sectorSlot).lamps(lampSlot).labelText = "lamp " + LTRIM$(STR$(lampSlot))
            NEXT lampSlot

            decalCount = (gx + gy + seedValue) MOD 4
            IF decalCount = 0 THEN decalCount = 1
            REDIM demo(0).sectors(sectorSlot).decals(0 TO decalCount - 1) AS DECALNODE
            FOR decalSlot = 0 TO decalCount - 1
                demo(0).sectors(sectorSlot).decals(decalSlot).anchor(0) = minX + CELL_SIZE * (.2! + .18! * decalSlot)
                demo(0).sectors(sectorSlot).decals(decalSlot).anchor(1) = floorLevel + .012!
                demo(0).sectors(sectorSlot).decals(decalSlot).anchor(2) = minZ + CELL_SIZE * (.75! - .13! * decalSlot)
                demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(0) = .20! + .03! * decalSlot
                demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(1) = .01!
                demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(2) = .20! + .02! * ((gx + gy) MOD 3)
                demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(0) = .25! + .07! * decalSlot
                demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(1) = .35!
                demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(2) = .60!
                demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(3) = .75!
                demo(0).sectors(sectorSlot).decals(decalSlot).labelText = "floor-decal"
            NEXT decalSlot
        NEXT gx
    NEXT gy

    BuildRooms seedValue
    BuildOutdoor seedValue
END SUB

SUB SetWallQuad (w AS WallQuad, x1 AS SINGLE, z1 AS SINGLE, x2 AS SINGLE, z2 AS SINGLE, lowY AS SINGLE, highY AS SINGLE, cr AS SINGLE, cg AS SINGLE, cb AS SINGLE, labelIn AS STRING)
    DIM dx AS SINGLE
    DIM dz AS SINGLE
    DIM invMag AS SINGLE

    w.corner(0).xyz(0) = x1: w.corner(0).xyz(1) = lowY: w.corner(0).xyz(2) = z1
    w.corner(1).xyz(0) = x2: w.corner(1).xyz(1) = lowY: w.corner(1).xyz(2) = z2
    w.corner(2).xyz(0) = x2: w.corner(2).xyz(1) = highY: w.corner(2).xyz(2) = z2
    w.corner(3).xyz(0) = x1: w.corner(3).xyz(1) = highY: w.corner(3).xyz(2) = z1

    w.uv(0).xy(0) = 0!: w.uv(0).xy(1) = 0!
    w.uv(1).xy(0) = 1!: w.uv(1).xy(1) = 0!
    w.uv(2).xy(0) = 1!: w.uv(2).xy(1) = 1!
    w.uv(3).xy(0) = 0!: w.uv(3).xy(1) = 1!

    dx = x2 - x1
    dz = z2 - z1
    invMag = SQR(dx * dx + dz * dz)
    IF invMag <> 0! THEN invMag = 1! / invMag
    w.normal(0) = -dz * invMag
    w.normal(1) = 0!
    w.normal(2) = dx * invMag

    w.tint.rgba(0) = cr
    w.tint.rgba(1) = cg
    w.tint.rgba(2) = cb
    w.tint.rgba(3) = 1!
    w.flags = 1
    w.labelText = labelIn
END SUB

SUB SetStair (st AS StairNode, minX AS SINGLE, minZ AS SINGLE, maxX AS SINGLE, maxZ AS SINGLE, lowY AS SINGLE, highY AS SINGLE, stepsValue AS LONG, labelIn AS STRING)
    st.zoneMin(0) = minX
    st.zoneMin(1) = lowY
    st.zoneMin(2) = minZ
    st.zoneMax(0) = maxX
    st.zoneMax(1) = highY
    st.zoneMax(2) = maxZ
    st.lowY = lowY
    st.highY = highY
    st.axisValue = 0
    st.stepCount = stepsValue
    st.tint.rgba(0) = .55!
    st.tint.rgba(1) = .47!
    st.tint.rgba(2) = .38!
    st.tint.rgba(3) = 1!
    st.labelText = labelIn
END SUB

SUB WalkFloorY (gx AS LONG, gy AS LONG, floorLevel AS SINGLE)
    DIM modelFloor AS SINGLE

    CellFloorY gx, gy, modelFloor
    floorLevel = modelFloor

    ' Geometry may contain an upper floor at LEVEL_H, but the player can also walk
    ' underneath it when currently on the lower level.
    IF modelFloor = LEVEL_H THEN
        IF playerGroundY >= LEVEL_H - MAX_STEP_UP - .05! THEN
            floorLevel = LEVEL_H
        ELSE
            floorLevel = 0!
        END IF
    END IF
END SUB


SUB CellFloorY (gx AS LONG, gy AS LONG, floorLevel AS SINGLE)
    floorLevel = 0!
    IF gx >= 8 THEN floorLevel = LEVEL_H
    IF gx >= 5 AND gx <= 7 AND gy >= 5 AND gy <= 8 THEN floorLevel = 0!
END SUB

SUB GroundHeight (x0 AS SINGLE, z0 AS SINGLE, groundY AS SINGLE)
    DIM stairSlot AS LONG
    DIM stairRatio AS SINGLE
    DIM stairBand AS LONG
    DIM stairLen AS SINGLE
    DIM gx AS LONG
    DIM gy AS LONG
    DIM rawGX AS SINGLE
    DIM rawGZ AS SINGLE

    groundY = 0!

    FOR stairSlot = 0 TO UBOUND(demo(0).stairs)
        IF x0 >= demo(0).stairs(stairSlot).zoneMin(0) AND x0 <= demo(0).stairs(stairSlot).zoneMax(0) THEN
            IF z0 >= demo(0).stairs(stairSlot).zoneMin(2) AND z0 <= demo(0).stairs(stairSlot).zoneMax(2) THEN
                stairLen = demo(0).stairs(stairSlot).zoneMax(0) - demo(0).stairs(stairSlot).zoneMin(0)
                IF stairLen < .001! THEN stairLen = .001!
                stairRatio = (x0 - demo(0).stairs(stairSlot).zoneMin(0)) / stairLen
                IF stairRatio < 0! THEN stairRatio = 0!
                IF stairRatio > 1! THEN stairRatio = 1!
                stairBand = INT(stairRatio * demo(0).stairs(stairSlot).stepCount)
                IF stairBand < 0 THEN stairBand = 0
                IF stairBand > demo(0).stairs(stairSlot).stepCount THEN stairBand = demo(0).stairs(stairSlot).stepCount
                groundY = demo(0).stairs(stairSlot).lowY + (demo(0).stairs(stairSlot).highY - demo(0).stairs(stairSlot).lowY) * (stairBand / demo(0).stairs(stairSlot).stepCount)
                EXIT SUB
            END IF
        END IF
    NEXT stairSlot

    rawGX = x0 / CELL_SIZE + GRID_W / 2!
    rawGZ = z0 / CELL_SIZE + GRID_H / 2!

    IF rawGX < 0! OR rawGX >= GRID_W OR rawGZ < 0! OR rawGZ >= GRID_H THEN
        groundY = OUT_YARD_Y
        EXIT SUB
    END IF

    gx = INT(rawGX)
    gy = INT(rawGZ)
    IF gx < 0 THEN gx = 0
    IF gx > GRID_W - 1 THEN gx = GRID_W - 1
    IF gy < 0 THEN gy = 0
    IF gy > GRID_H - 1 THEN gy = GRID_H - 1
    'CellFloorY gx, gy, groundY
    WalkFloorY gx, gy, groundY
END SUB

SUB BuildRooms (seedValue AS LONG)
    REDIM demo(0).rooms(0 TO 5) AS ROOMNODE
    SetRoom 0, -20!, -20!, -8!, -10!, 0!, 4 + (seedValue MOD 3), "lower storage"
    SetRoom 1, -19!, -8!, -3!, 6!, 0!, 6 + ((seedValue + 1) MOD 3), "lower empty hall"
    SetRoom 2, -20!, 8!, -7!, 20!, 0!, 5 + ((seedValue + 2) MOD 3), "lower cabinet room"
    SetRoom 3, 4!, -19!, 19!, -6!, LEVEL_H, 6 + ((seedValue + 3) MOD 3), "upper gallery"
    SetRoom 4, 5!, -3!, 20!, 9!, LEVEL_H, 7 + ((seedValue + 4) MOD 3), "upper table room"
    SetRoom 5, 7!, 11!, 20!, 20!, LEVEL_H, 4 + ((seedValue + 5) MOD 3), "upper archive"
END SUB

SUB SetRoom (roomSlot AS LONG, minX AS SINGLE, minZ AS SINGLE, maxX AS SINGLE, maxZ AS SINGLE, floorLevel AS SINGLE, propCount AS LONG, labelIn AS STRING)
    DIM propSlot AS LONG
    DIM propX AS SINGLE
    DIM propZ AS SINGLE
    DIM spanX AS SINGLE
    DIM spanZ AS SINGLE
    DIM diceA AS LONG
    DIM diceB AS LONG
    DIM kindValue AS LONG
    DIM sizeX AS SINGLE
    DIM sizeY AS SINGLE
    DIM sizeZ AS SINGLE
    DIM roomPad AS SINGLE

    demo(0).rooms(roomSlot).boundsMin(0) = minX
    demo(0).rooms(roomSlot).boundsMin(1) = floorLevel
    demo(0).rooms(roomSlot).boundsMin(2) = minZ
    demo(0).rooms(roomSlot).boundsMax(0) = maxX
    demo(0).rooms(roomSlot).boundsMax(1) = floorLevel + WALL_H
    demo(0).rooms(roomSlot).boundsMax(2) = maxZ
    demo(0).rooms(roomSlot).floorY = floorLevel
    demo(0).rooms(roomSlot).nameText = labelIn

    REDIM demo(0).rooms(roomSlot).labels(0 TO 2) AS STRING
    demo(0).rooms(roomSlot).labels(0) = labelIn
    demo(0).rooms(roomSlot).labels(1) = "dynamic room labels"
    demo(0).rooms(roomSlot).labels(2) = "props are descriptor-owned"

    IF propCount < 1 THEN propCount = 1
    REDIM demo(0).rooms(roomSlot).props(0 TO propCount - 1) AS PROPNODE

    spanX = maxX - minX
    spanZ = maxZ - minZ
    roomPad = 1.25!

    FOR propSlot = 0 TO propCount - 1
        diceA = (propSlot * 37 + roomSlot * 19 + worldSeed * 11) MOD 100
        diceB = (propSlot * 23 + roomSlot * 41 + worldSeed * 7) MOD 100
        propX = minX + roomPad + (spanX - roomPad * 2!) * (diceA / 100!)
        propZ = minZ + roomPad + (spanZ - roomPad * 2!) * (diceB / 100!)

        ' Keep a clear pocket around the initial spawn.  Otherwise the demo can start inside a cabinet.
        IF roomSlot = 0 AND propX < -14! AND propZ < -14! THEN propX = propX + 4!

        kindValue = (propSlot + roomSlot + worldSeed) MOD 4
        SELECT CASE kindValue
            CASE 0
                sizeX = .62!: sizeY = .34!: sizeZ = .48!
            CASE 1
                sizeX = .42!: sizeY = .95!: sizeZ = .34!
            CASE 2
                sizeX = .34!: sizeY = .34!: sizeZ = .34!
            CASE ELSE
                sizeX = .85!: sizeY = .28!: sizeZ = .22!
        END SELECT

        SetProp demo(0).rooms(roomSlot).props(propSlot), propX, floorLevel + sizeY, propZ, sizeX, sizeY, sizeZ, kindValue, "prop " + LTRIM$(STR$(propSlot))
    NEXT propSlot
END SUB

SUB SetProp (p AS PropNode, x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, sx AS SINGLE, sy AS SINGLE, sz AS SINGLE, kindValue AS LONG, labelIn AS STRING)
    p.center(0) = x0
    p.center(1) = y0
    p.center(2) = z0
    p.sizeBox(0) = sx
    p.sizeBox(1) = sy
    p.sizeBox(2) = sz
    p.kindValue = kindValue
    p.solid = -1
    SELECT CASE kindValue
        CASE 0
            p.tint.rgba(0) = .55!: p.tint.rgba(1) = .34!: p.tint.rgba(2) = .18!
        CASE 1
            p.tint.rgba(0) = .35!: p.tint.rgba(1) = .44!: p.tint.rgba(2) = .52!
        CASE 2
            p.tint.rgba(0) = .65!: p.tint.rgba(1) = .55!: p.tint.rgba(2) = .35!
        CASE ELSE
            p.tint.rgba(0) = .45!: p.tint.rgba(1) = .25!: p.tint.rgba(2) = .60!
    END SELECT
    p.tint.rgba(3) = 1!
    p.labelText = labelIn
END SUB

SUB StressRetainPulse
    DIM sectorSlot AS LONG
    DIM roomSlot AS LONG
    DIM oldWallTop AS LONG
    DIM oldNoteTop AS LONG
    DIM oldLampTop AS LONG
    DIM oldPropTop AS LONG
    DIM oldLabelTop AS LONG
    DIM x0 AS SINGLE
    DIM z0 AS SINGLE
    DIM floorLevel AS SINGLE

    sectorSlot = ((worldSeed * 7) + 31) MOD (GRID_W * GRID_H)
    floorLevel = demo(0).sectors(sectorSlot).floorY

    oldWallTop = UBOUND(demo(0).sectors(sectorSlot).walls)
    REDIM _RETAIN demo(0).sectors(sectorSlot).walls(0 TO oldWallTop + 1) AS WALLQUAD
    x0 = demo(0).sectors(sectorSlot).center(0) - .55!
    z0 = demo(0).sectors(sectorSlot).center(2) + .55!
    SetWallQuad demo(0).sectors(sectorSlot).walls(oldWallTop + 1), x0, z0, x0 + 1.1!, z0, floorLevel, floorLevel + WALL_H * .72!, .95!, .15!, .15!, "retain-added-wall"

    oldNoteTop = UBOUND(demo(0).sectors(sectorSlot).notes)
    REDIM _RETAIN demo(0).sectors(sectorSlot).notes(0 TO oldNoteTop + 1) AS STRING
    demo(0).sectors(sectorSlot).notes(oldNoteTop + 1) = "retain note seed " + LTRIM$(STR$(worldSeed))

    oldLampTop = UBOUND(demo(0).sectors(sectorSlot).lamps)
    REDIM _RETAIN demo(0).sectors(sectorSlot).lamps(0 TO oldLampTop + 1) AS LAMPNODE
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).anchor(0) = demo(0).sectors(sectorSlot).center(0)
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).anchor(1) = floorLevel + WALL_H + .12!
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).anchor(2) = demo(0).sectors(sectorSlot).center(2)
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).tint.rgba(0) = 1!
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).tint.rgba(1) = .1!
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).tint.rgba(2) = .1!
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).tint.rgba(3) = 1!
    demo(0).sectors(sectorSlot).lamps(oldLampTop + 1).labelText = "retain lamp"

    roomSlot = (worldSeed * 5 + 3) MOD (UBOUND(demo(0).rooms) + 1)
    oldPropTop = UBOUND(demo(0).rooms(roomSlot).props)
    REDIM _RETAIN demo(0).rooms(roomSlot).props(0 TO oldPropTop + 1) AS PROPNODE
    x0 = demo(0).rooms(roomSlot).boundsMin(0) + 1.4! + ((oldPropTop + worldSeed) MOD 5) * .7!
    z0 = demo(0).rooms(roomSlot).boundsMin(2) + 1.4! + ((oldPropTop + worldSeed * 2) MOD 5) * .7!
    SetProp demo(0).rooms(roomSlot).props(oldPropTop + 1), x0, demo(0).rooms(roomSlot).floorY + .42!, z0, .42!, .42!, .42!, 2, "retain crate"

    oldLabelTop = UBOUND(demo(0).rooms(roomSlot).labels)
    REDIM _RETAIN demo(0).rooms(roomSlot).labels(0 TO oldLabelTop + 1) AS STRING
    demo(0).rooms(roomSlot).labels(oldLabelTop + 1) = "retain room label " + LTRIM$(STR$(worldSeed))

    DIM objectSlot AS LONG
    DIM oldPartTop AS LONG
    DIM cloudSlot AS LONG
    DIM oldPuffTop AS LONG

    IF UBOUND(demo(0).objects) >= 0 THEN
        objectSlot = (worldSeed * 11 + 7) MOD (UBOUND(demo(0).objects) + 1)
        oldPartTop = UBOUND(demo(0).objects(objectSlot).parts)
        REDIM _RETAIN demo(0).objects(objectSlot).parts(0 TO oldPartTop + 2) AS OBJECTPART
        SetObjectPart objectSlot, oldPartTop + 1, demo(0).objects(objectSlot).anchor(0) + .18!, demo(0).objects(objectSlot).anchor(1) + 1.1!, demo(0).objects(objectSlot).anchor(2) + .18!, .16!, .16!, .16!, .95!, .25!, .95!, 1, 0, "retain sparkle A"
        SetObjectPart objectSlot, oldPartTop + 2, demo(0).objects(objectSlot).anchor(0) - .18!, demo(0).objects(objectSlot).anchor(1) + 1.35!, demo(0).objects(objectSlot).anchor(2) - .18!, .12!, .24!, .12!, .20!, .95!, .95!, 2, 0, "retain sparkle B"
    END IF

    IF UBOUND(demo(0).clouds) >= 0 THEN
        cloudSlot = (worldSeed * 3 + 2) MOD (UBOUND(demo(0).clouds) + 1)
        oldPuffTop = UBOUND(demo(0).clouds(cloudSlot).puffs)
        REDIM _RETAIN demo(0).clouds(cloudSlot).puffs(0 TO oldPuffTop + 1) AS OBJECTPART
        SetCloudPuff cloudSlot, oldPuffTop + 1, demo(0).clouds(cloudSlot).anchor(0) + ((oldPuffTop MOD 4) - 1) * .85!, demo(0).clouds(cloudSlot).anchor(1) + .15!, demo(0).clouds(cloudSlot).anchor(2) + ((oldPuffTop MOD 5) - 2) * .55!, .70!, .22!, .42!, .88!, .92!, 1!
    END IF

    worldSeed = worldSeed + 1
END SUB


SUB BuildOutdoor (seedValue AS LONG)
    DIM objectSlot AS LONG
    DIM fenceIndex AS LONG
    DIM treeSlot AS LONG
    DIM carSlot AS LONG
    DIM chaosSlot AS LONG
    DIM x0 AS SINGLE
    DIM z0 AS SINGLE
    DIM sideValue AS LONG
    DIM totalObjects AS LONG

    totalObjects = 76
    REDIM demo(0).objects(0 TO totalObjects - 1) AS SCENEOBJECT
    objectSlot = 0

    ' Fence around the yard.  It is deliberately built as many little descriptor-owned objects,
    ' not as one monolithic mesh, so collision/rendering walks many nested arrays.
    FOR fenceIndex = 0 TO 9
        x0 = OUT_MIN_X + 3.6! + fenceIndex * 7.0!
        BuildFenceSegment objectSlot, x0, OUT_MIN_Z, 0
        objectSlot = objectSlot + 1
        BuildFenceSegment objectSlot, x0, OUT_MAX_Z, 0
        objectSlot = objectSlot + 1
    NEXT fenceIndex
    FOR fenceIndex = 0 TO 9
        z0 = OUT_MIN_Z + 3.8! + fenceIndex * 7.2!
        BuildFenceSegment objectSlot, OUT_MIN_X, z0, 1
        objectSlot = objectSlot + 1
        BuildFenceSegment objectSlot, OUT_MAX_X, z0, 1
        objectSlot = objectSlot + 1
    NEXT fenceIndex

    FOR treeSlot = 0 TO 9
        x0 = OUT_MIN_X + 5! + ((treeSlot * 13 + seedValue * 3) MOD 60)
        z0 = OUT_MIN_Z + 8! + ((treeSlot * 17 + seedValue * 5) MOD 62)
        IF x0 > -24! AND x0 < 24! AND z0 > -24! AND z0 < 24! THEN z0 = OUT_MAX_Z - 6! - treeSlot
        BuildTree objectSlot, x0, z0, treeSlot
        objectSlot = objectSlot + 1
    NEXT treeSlot

    FOR carSlot = 0 TO 3
        x0 = -27! + carSlot * 5.6!
        z0 = OUT_MAX_Z - 10! - ((carSlot + seedValue) MOD 3) * 2.3!
        BuildCar objectSlot, x0, z0, carSlot
        objectSlot = objectSlot + 1
    NEXT carSlot

    FOR chaosSlot = 0 TO 5
        x0 = 12! + ((chaosSlot * 7 + seedValue) MOD 17)
        z0 = 24! + ((chaosSlot * 11 + seedValue * 2) MOD 10)
        BuildColorTower objectSlot, x0, z0, chaosSlot
        objectSlot = objectSlot + 1
    NEXT chaosSlot

    FOR chaosSlot = 0 TO 7
        x0 = OUT_MIN_X + 8! + ((chaosSlot * 9 + seedValue * 4) MOD 20)
        z0 = 22! + ((chaosSlot * 5 + seedValue * 3) MOD 15)
        sideValue = chaosSlot MOD 3
        IF sideValue = 0 THEN
            BuildCratePile objectSlot, x0, z0, chaosSlot
        ELSEIF sideValue = 1 THEN
            BuildOutdoorTable objectSlot, x0, z0, chaosSlot
        ELSE
            BuildSignPost objectSlot, x0, z0, chaosSlot
        END IF
        objectSlot = objectSlot + 1
    NEXT chaosSlot

    ' Fill any reserved slots with harmless colour posts so there are no uninitialised owner elements.
    DO WHILE objectSlot <= UBOUND(demo(0).objects)
        BuildColorTower objectSlot, OUT_MIN_X + 4! + objectSlot, OUT_MIN_Z + 6! + (objectSlot MOD 5), objectSlot
        objectSlot = objectSlot + 1
    LOOP

    BuildClouds seedValue
END SUB

SUB InitSceneObject (objectSlot AS LONG, x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, kindValue AS LONG, solidFlag AS _BYTE, labelIn AS STRING)
    demo(0).objects(objectSlot).anchor(0) = x0
    demo(0).objects(objectSlot).anchor(1) = y0
    demo(0).objects(objectSlot).anchor(2) = z0
    demo(0).objects(objectSlot).boundsMin(0) = x0
    demo(0).objects(objectSlot).boundsMin(1) = y0
    demo(0).objects(objectSlot).boundsMin(2) = z0
    demo(0).objects(objectSlot).boundsMax(0) = x0
    demo(0).objects(objectSlot).boundsMax(1) = y0
    demo(0).objects(objectSlot).boundsMax(2) = z0
    demo(0).objects(objectSlot).objectKind = kindValue
    demo(0).objects(objectSlot).solid = solidFlag
    demo(0).objects(objectSlot).nameText = labelIn
    REDIM demo(0).objects(objectSlot).tags(0 TO 2) AS STRING
    demo(0).objects(objectSlot).tags(0) = labelIn
    demo(0).objects(objectSlot).tags(1) = "scene-object owns dynamic parts"
    demo(0).objects(objectSlot).tags(2) = "procedural object graph node"
END SUB

SUB SetObjectPart (objectSlot AS LONG, partSlot AS LONG, x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, sx AS SINGLE, sy AS SINGLE, sz AS SINGLE, cr AS SINGLE, cg AS SINGLE, cb AS SINGLE, kindValue AS LONG, solidFlag AS _BYTE, labelIn AS STRING)
    demo(0).objects(objectSlot).parts(partSlot).center(0) = x0
    demo(0).objects(objectSlot).parts(partSlot).center(1) = y0
    demo(0).objects(objectSlot).parts(partSlot).center(2) = z0
    demo(0).objects(objectSlot).parts(partSlot).sizeBox(0) = sx
    demo(0).objects(objectSlot).parts(partSlot).sizeBox(1) = sy
    demo(0).objects(objectSlot).parts(partSlot).sizeBox(2) = sz
    demo(0).objects(objectSlot).parts(partSlot).tint.rgba(0) = cr
    demo(0).objects(objectSlot).parts(partSlot).tint.rgba(1) = cg
    demo(0).objects(objectSlot).parts(partSlot).tint.rgba(2) = cb
    demo(0).objects(objectSlot).parts(partSlot).tint.rgba(3) = 1!
    demo(0).objects(objectSlot).parts(partSlot).partKind = kindValue
    demo(0).objects(objectSlot).parts(partSlot).solid = solidFlag
    demo(0).objects(objectSlot).parts(partSlot).labelText = labelIn
    ExpandObjectBounds objectSlot, x0 - sx, y0 - sy, z0 - sz, x0 + sx, y0 + sy, z0 + sz
END SUB

SUB ExpandObjectBounds (objectSlot AS LONG, minX AS SINGLE, minY AS SINGLE, minZ AS SINGLE, maxX AS SINGLE, maxY AS SINGLE, maxZ AS SINGLE)
    IF minX < demo(0).objects(objectSlot).boundsMin(0) THEN demo(0).objects(objectSlot).boundsMin(0) = minX
    IF minY < demo(0).objects(objectSlot).boundsMin(1) THEN demo(0).objects(objectSlot).boundsMin(1) = minY
    IF minZ < demo(0).objects(objectSlot).boundsMin(2) THEN demo(0).objects(objectSlot).boundsMin(2) = minZ
    IF maxX > demo(0).objects(objectSlot).boundsMax(0) THEN demo(0).objects(objectSlot).boundsMax(0) = maxX
    IF maxY > demo(0).objects(objectSlot).boundsMax(1) THEN demo(0).objects(objectSlot).boundsMax(1) = maxY
    IF maxZ > demo(0).objects(objectSlot).boundsMax(2) THEN demo(0).objects(objectSlot).boundsMax(2) = maxZ
END SUB

SUB BuildFenceSegment (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, axisValue AS LONG)
    DIM sx AS SINGLE
    DIM sz AS SINGLE
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 10, -1, "yard fence"
    REDIM demo(0).objects(objectSlot).parts(0 TO 4) AS OBJECTPART
    IF axisValue = 0 THEN
        sx = 3.25!: sz = .08!
        SetObjectPart objectSlot, 0, x0 - sx, OUT_YARD_Y + FENCE_H * .5!, z0, .12!, FENCE_H * .5!, .12!, .35!, .23!, .12!, 1, -1, "left post"
        SetObjectPart objectSlot, 1, x0 + sx, OUT_YARD_Y + FENCE_H * .5!, z0, .12!, FENCE_H * .5!, .12!, .35!, .23!, .12!, 1, -1, "right post"
        SetObjectPart objectSlot, 2, x0, OUT_YARD_Y + .42!, z0, sx, .075!, sz, .50!, .34!, .17!, 1, -1, "low rail"
        SetObjectPart objectSlot, 3, x0, OUT_YARD_Y + .92!, z0, sx, .075!, sz, .50!, .34!, .17!, 1, -1, "high rail"
        SetObjectPart objectSlot, 4, x0, OUT_YARD_Y + 1.46!, z0, sx * .92!, .035!, .06!, .90!, .80!, .35!, 1, 0, "sun strip"
    ELSE
        sx = .08!: sz = 3.35!
        SetObjectPart objectSlot, 0, x0, OUT_YARD_Y + FENCE_H * .5!, z0 - sz, .12!, FENCE_H * .5!, .12!, .35!, .23!, .12!, 1, -1, "front post"
        SetObjectPart objectSlot, 1, x0, OUT_YARD_Y + FENCE_H * .5!, z0 + sz, .12!, FENCE_H * .5!, .12!, .35!, .23!, .12!, 1, -1, "back post"
        SetObjectPart objectSlot, 2, x0, OUT_YARD_Y + .42!, z0, sx, .075!, sz, .50!, .34!, .17!, 1, -1, "low rail"
        SetObjectPart objectSlot, 3, x0, OUT_YARD_Y + .92!, z0, sx, .075!, sz, .50!, .34!, .17!, 1, -1, "high rail"
        SetObjectPart objectSlot, 4, x0, OUT_YARD_Y + 1.46!, z0, .06!, .035!, sz * .92!, .90!, .80!, .35!, 1, 0, "sun strip"
    END IF
END SUB

SUB BuildTree (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, treeIndex AS LONG)
    DIM partSlot AS LONG
    DIM angleStep AS SINGLE
    DIM px AS SINGLE
    DIM pz AS SINGLE
    DIM shadeBase AS SINGLE
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 20, -1, "tree object"
    REDIM demo(0).objects(objectSlot).parts(0 TO 13) AS OBJECTPART
    SetObjectPart objectSlot, 0, x0, OUT_YARD_Y + .72!, z0, .18!, .72!, .18!, .38!, .21!, .08!, 1, -1, "trunk"
    SetObjectPart objectSlot, 1, x0, OUT_YARD_Y + 1.42!, z0, .25!, .32!, .25!, .42!, .25!, .10!, 1, -1, "thick trunk"
    FOR partSlot = 2 TO 10
        angleStep = (partSlot * 41 + treeIndex * 13) * PI_OVER_180
        px = x0 + SIN(angleStep) * (.38! + (partSlot MOD 3) * .16!)
        pz = z0 + COS(angleStep) * (.38! + (partSlot MOD 4) * .11!)
        shadeBase = .30! + (partSlot MOD 4) * .08!
        SetObjectPart objectSlot, partSlot, px, OUT_YARD_Y + 2.0! + (partSlot MOD 3) * .18!, pz, .46!, .34!, .46!, .10!, shadeBase + .22!, .12!, 1, 0, "leaf cube"
    NEXT partSlot
    SetObjectPart objectSlot, 11, x0 - .42!, OUT_YARD_Y + .08!, z0, .42!, .05!, .08!, .30!, .16!, .05!, 1, 0, "root A"
    SetObjectPart objectSlot, 12, x0 + .42!, OUT_YARD_Y + .08!, z0, .42!, .05!, .08!, .30!, .16!, .05!, 1, 0, "root B"
    SetObjectPart objectSlot, 13, x0, OUT_YARD_Y + .08!, z0 + .42!, .08!, .05!, .42!, .30!, .16!, .05!, 1, 0, "root C"
END SUB

SUB BuildCar (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, carIndex AS LONG)
    DIM cr AS SINGLE
    DIM cg AS SINGLE
    DIM cb AS SINGLE
    cr = .18! + (carIndex MOD 3) * .28!
    cg = .25! + ((carIndex + 1) MOD 3) * .18!
    cb = .35! + ((carIndex + 2) MOD 3) * .16!
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 30, -1, "boxy car"
    REDIM demo(0).objects(objectSlot).parts(0 TO 11) AS OBJECTPART
    SetObjectPart objectSlot, 0, x0, OUT_YARD_Y + .42!, z0, 1.15!, .32!, .55!, cr, cg, cb, 1, -1, "car body"
    SetObjectPart objectSlot, 1, x0 - .12!, OUT_YARD_Y + .86!, z0, .55!, .28!, .42!, cr * .78!, cg * .78!, cb * .95!, 1, -1, "car cabin"
    SetObjectPart objectSlot, 2, x0 - .78!, OUT_YARD_Y + .20!, z0 - .58!, .20!, .20!, .08!, .03!, .03!, .035!, 1, -1, "wheel"
    SetObjectPart objectSlot, 3, x0 + .78!, OUT_YARD_Y + .20!, z0 - .58!, .20!, .20!, .08!, .03!, .03!, .035!, 1, -1, "wheel"
    SetObjectPart objectSlot, 4, x0 - .78!, OUT_YARD_Y + .20!, z0 + .58!, .20!, .20!, .08!, .03!, .03!, .035!, 1, -1, "wheel"
    SetObjectPart objectSlot, 5, x0 + .78!, OUT_YARD_Y + .20!, z0 + .58!, .20!, .20!, .08!, .03!, .03!, .035!, 1, -1, "wheel"
    SetObjectPart objectSlot, 6, x0 - 1.18!, OUT_YARD_Y + .46!, z0 - .25!, .05!, .08!, .12!, 1!, .92!, .35!, 1, 0, "left lamp"
    SetObjectPart objectSlot, 7, x0 - 1.18!, OUT_YARD_Y + .46!, z0 + .25!, .05!, .08!, .12!, 1!, .92!, .35!, 1, 0, "right lamp"
    SetObjectPart objectSlot, 8, x0 + 1.18!, OUT_YARD_Y + .45!, z0 - .30!, .05!, .07!, .10!, 1!, .10!, .08!, 1, 0, "tail lamp"
    SetObjectPart objectSlot, 9, x0 + 1.18!, OUT_YARD_Y + .45!, z0 + .30!, .05!, .07!, .10!, 1!, .10!, .08!, 1, 0, "tail lamp"
    SetObjectPart objectSlot, 10, x0 - .12!, OUT_YARD_Y + 1.16!, z0, .32!, .04!, .28!, .88!, .95!, 1!, 1, 0, "roof shine"
    SetObjectPart objectSlot, 11, x0, OUT_YARD_Y + .78!, z0 - .46!, .62!, .05!, .035!, .70!, .90!, 1!, 1, 0, "window strip"
END SUB

SUB BuildColorTower (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, towerIndex AS LONG)
    DIM partSlot AS LONG
    DIM cr AS SINGLE
    DIM cg AS SINGLE
    DIM cb AS SINGLE
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 40, -1, "colour tower"
    REDIM demo(0).objects(objectSlot).parts(0 TO 15) AS OBJECTPART
    FOR partSlot = 0 TO 15
        cr = ((partSlot * 31 + towerIndex * 17) MOD 100) / 100!
        cg = ((partSlot * 47 + towerIndex * 19) MOD 100) / 100!
        cb = ((partSlot * 59 + towerIndex * 23) MOD 100) / 100!
        IF cr < .18! THEN cr = cr + .28!
        IF cg < .18! THEN cg = cg + .28!
        IF cb < .18! THEN cb = cb + .28!
        SetObjectPart objectSlot, partSlot, x0 + ((partSlot MOD 2) - .5!) * .28!, OUT_YARD_Y + .18! + partSlot * .19!, z0 + (((partSlot \ 2) MOD 2) - .5!) * .28!, .22!, .18!, .22!, cr, cg, cb, 1, -1, "rainbow brick"
    NEXT partSlot
END SUB

SUB BuildCratePile (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, pileIndex AS LONG)
    DIM partSlot AS LONG
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 50, -1, "crate pile"
    REDIM demo(0).objects(objectSlot).parts(0 TO 8) AS OBJECTPART
    FOR partSlot = 0 TO 8
        SetObjectPart objectSlot, partSlot, x0 + ((partSlot MOD 3) - 1) * .55!, OUT_YARD_Y + .25! + (partSlot \ 3) * .42!, z0 + (((partSlot + pileIndex) MOD 2) - .5!) * .45!, .24!, .24!, .24!, .58!, .39! + (partSlot MOD 3) * .05!, .20!, 1, -1, "outdoor crate"
    NEXT partSlot
END SUB

SUB BuildOutdoorTable (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, tableIndex AS LONG)
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 60, -1, "outdoor table"
    REDIM demo(0).objects(objectSlot).parts(0 TO 8) AS OBJECTPART
    SetObjectPart objectSlot, 0, x0, OUT_YARD_Y + .64!, z0, .95!, .08!, .45!, .42!, .24!, .11!, 1, -1, "table top"
    SetObjectPart objectSlot, 1, x0 - .72!, OUT_YARD_Y + .34!, z0 - .28!, .07!, .34!, .07!, .30!, .17!, .08!, 1, -1, "leg"
    SetObjectPart objectSlot, 2, x0 + .72!, OUT_YARD_Y + .34!, z0 - .28!, .07!, .34!, .07!, .30!, .17!, .08!, 1, -1, "leg"
    SetObjectPart objectSlot, 3, x0 - .72!, OUT_YARD_Y + .34!, z0 + .28!, .07!, .34!, .07!, .30!, .17!, .08!, 1, -1, "leg"
    SetObjectPart objectSlot, 4, x0 + .72!, OUT_YARD_Y + .34!, z0 + .28!, .07!, .34!, .07!, .30!, .17!, .08!, 1, -1, "leg"
    SetObjectPart objectSlot, 5, x0 - 1.22!, OUT_YARD_Y + .36!, z0, .30!, .18!, .35!, .20!, .35!, .70!, 1, -1, "chair A"
    SetObjectPart objectSlot, 6, x0 + 1.22!, OUT_YARD_Y + .36!, z0, .30!, .18!, .35!, .70!, .30!, .20!, 1, -1, "chair B"
    SetObjectPart objectSlot, 7, x0, OUT_YARD_Y + .86!, z0, .16!, .16!, .16!, .95!, .18!, .12!, 2, 0, "fruit pyramid"
    SetObjectPart objectSlot, 8, x0 + .42!, OUT_YARD_Y + .80!, z0 - .12!, .10!, .10!, .10!, .15!, .95!, .45!, 1, 0, "green cup"
END SUB

SUB BuildSignPost (objectSlot AS LONG, x0 AS SINGLE, z0 AS SINGLE, signIndex AS LONG)
    InitSceneObject objectSlot, x0, OUT_YARD_Y, z0, 70, -1, "colour sign"
    REDIM demo(0).objects(objectSlot).parts(0 TO 5) AS OBJECTPART
    SetObjectPart objectSlot, 0, x0, OUT_YARD_Y + .75!, z0, .08!, .75!, .08!, .40!, .25!, .10!, 1, -1, "sign post"
    SetObjectPart objectSlot, 1, x0, OUT_YARD_Y + 1.42!, z0, .70!, .28!, .06!, .90!, .20!, .30!, 1, -1, "red board"
    SetObjectPart objectSlot, 2, x0 - .38!, OUT_YARD_Y + 1.44!, z0 - .07!, .08!, .18!, .025!, .20!, .95!, .95!, 1, 0, "letter block"
    SetObjectPart objectSlot, 3, x0, OUT_YARD_Y + 1.44!, z0 - .07!, .08!, .18!, .025!, .95!, .95!, .20!, 1, 0, "letter block"
    SetObjectPart objectSlot, 4, x0 + .38!, OUT_YARD_Y + 1.44!, z0 - .07!, .08!, .18!, .025!, .20!, .95!, .20!, 1, 0, "letter block"
    SetObjectPart objectSlot, 5, x0, OUT_YARD_Y + 1.83!, z0, .20!, .20!, .20!, .95!, .75!, .10!, 2, 0, "top icon"
END SUB

SUB BuildClouds (seedValue AS LONG)
    DIM cloudSlot AS LONG
    DIM puffSlot AS LONG
    DIM x0 AS SINGLE
    DIM z0 AS SINGLE
    REDIM demo(0).clouds(0 TO 7) AS CLOUDNODE
    FOR cloudSlot = 0 TO UBOUND(demo(0).clouds)
        x0 = OUT_MIN_X + 8! + ((cloudSlot * 13 + seedValue * 5) MOD 58)
        z0 = OUT_MIN_Z + 10! + ((cloudSlot * 19 + seedValue * 7) MOD 62)
        demo(0).clouds(cloudSlot).anchor(0) = x0
        demo(0).clouds(cloudSlot).anchor(1) = 9.5! + (cloudSlot MOD 4) * .65!
        demo(0).clouds(cloudSlot).anchor(2) = z0
        demo(0).clouds(cloudSlot).drift(0) = .02! + cloudSlot * .004!
        demo(0).clouds(cloudSlot).drift(1) = 0!
        demo(0).clouds(cloudSlot).drift(2) = .01! + (cloudSlot MOD 3) * .003!
        demo(0).clouds(cloudSlot).nameText = "cloud " + LTRIM$(STR$(cloudSlot))
        REDIM demo(0).clouds(cloudSlot).labels(0 TO 1) AS STRING
        demo(0).clouds(cloudSlot).labels(0) = "dynamic cloud labels"
        demo(0).clouds(cloudSlot).labels(1) = "puffs are dynamic object parts"
        REDIM demo(0).clouds(cloudSlot).puffs(0 TO 5 +(cloudSlot MOD 3)) AS OBJECTPART
        FOR puffSlot = 0 TO UBOUND(demo(0).clouds(cloudSlot).puffs)
            SetCloudPuff cloudSlot, puffSlot, x0 + (puffSlot - 3) * .72!, demo(0).clouds(cloudSlot).anchor(1) + ((puffSlot MOD 2) * .22!), z0 + ((puffSlot MOD 4) - 1.5!) * .48!, .62! + (puffSlot MOD 3) * .14!, .22!, .36! + (puffSlot MOD 2) * .10!, .86!, .90!, .96!
        NEXT puffSlot
    NEXT cloudSlot
END SUB

SUB SetCloudPuff (cloudSlot AS LONG, puffSlot AS LONG, x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, sx AS SINGLE, sy AS SINGLE, sz AS SINGLE, cr AS SINGLE, cg AS SINGLE, cb AS SINGLE)
    demo(0).clouds(cloudSlot).puffs(puffSlot).center(0) = x0
    demo(0).clouds(cloudSlot).puffs(puffSlot).center(1) = y0
    demo(0).clouds(cloudSlot).puffs(puffSlot).center(2) = z0
    demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(0) = sx
    demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(1) = sy
    demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(2) = sz
    demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(0) = cr
    demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(1) = cg
    demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(2) = cb
    demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(3) = .64!
    demo(0).clouds(cloudSlot).puffs(puffSlot).partKind = 1
    demo(0).clouds(cloudSlot).puffs(puffSlot).solid = 0
    demo(0).clouds(cloudSlot).puffs(puffSlot).labelText = "cloud puff"
END SUB

SUB TryMove (candidateX AS SINGLE, candidateZ AS SINGLE)
    DIM blocked AS _BYTE
    DIM hitSector AS LONG
    DIM hitWall AS LONG
    DIM hitX AS SINGLE
    DIM hitZ AS SINGLE
    DIM hitNx AS SINGLE
    DIM hitNz AS SINGLE
    DIM candidateGround AS SINGLE

    GroundHeight candidateX, candidateZ, candidateGround

    ' Upward movement is step-limited.  Downward movement is allowed so the player can drop from
    ' the upper floor where no wall blocks the edge.  The vertical motion then falls toward the
    ' new ground height instead of snapping upward/downward like a chess piece.
    IF candidateGround - playerGroundY > MAX_STEP_UP THEN
        PushHit -900, -1, candidateX, candidateZ, 0!, 0!
        EXIT SUB
    END IF

    CheckWallCollision candidateX, candidateZ, candidateGround, blocked, hitSector, hitWall, hitX, hitZ, hitNx, hitNz
    IF blocked = 0 THEN CheckPropCollision candidateX, candidateZ, candidateGround, blocked, hitSector, hitWall, hitX, hitZ, hitNx, hitNz
    IF blocked = 0 THEN CheckObjectCollision candidateX, candidateZ, candidateGround, blocked, hitSector, hitWall, hitX, hitZ, hitNx, hitNz

    IF blocked THEN
        PushHit hitSector, hitWall, hitX, hitZ, hitNx, hitNz
    ELSE
        playerX = candidateX
        playerZ = candidateZ
        IF candidateGround < playerGroundY - .04! THEN
            playerGroundY = candidateGround
            playerAirborne = -1
            IF playerVelY > 0! THEN playerVelY = 0!
        ELSE
            playerGroundY = candidateGround
            playerY = playerGroundY + EYE_H
            playerVelY = 0!
            playerAirborne = 0
        END IF
    END IF
END SUB

SUB CheckWallCollision (candidateX AS SINGLE, candidateZ AS SINGLE, candidateGround AS SINGLE, blocked AS _BYTE, hitSector AS LONG, hitWall AS LONG, hitX AS SINGLE, hitZ AS SINGLE, hitNx AS SINGLE, hitNz AS SINGLE)
    DIM sectorSlot AS LONG
    DIM wallSlot AS LONG
    DIM x1 AS SINGLE
    DIM z1 AS SINGLE
    DIM x2 AS SINGLE
    DIM z2 AS SINGLE
    DIM lowY AS SINGLE
    DIM highY AS SINGLE
    DIM dx AS SINGLE
    DIM dz AS SINGLE
    DIM segSq AS SINGLE
    DIM proj AS SINGLE
    DIM nearX AS SINGLE
    DIM nearZ AS SINGLE
    DIM dpx AS SINGLE
    DIM dpz AS SINGLE
    DIM distSq AS SINGLE
    DIM bestDistSq AS SINGLE

    blocked = 0
    bestDistSq = 9999999!
    hitSector = -1
    hitWall = -1

    FOR sectorSlot = 0 TO UBOUND(demo(0).sectors)
        FOR wallSlot = 0 TO UBOUND(demo(0).sectors(sectorSlot).walls)
            IF demo(0).sectors(sectorSlot).walls(wallSlot).flags <> 0 THEN
                lowY = demo(0).sectors(sectorSlot).walls(wallSlot).corner(0).xyz(1)
                highY = demo(0).sectors(sectorSlot).walls(wallSlot).corner(2).xyz(1)
                IF candidateGround + PLAYER_BODY_H >= lowY AND candidateGround <= highY THEN
                    x1 = demo(0).sectors(sectorSlot).walls(wallSlot).corner(0).xyz(0)
                    z1 = demo(0).sectors(sectorSlot).walls(wallSlot).corner(0).xyz(2)
                    x2 = demo(0).sectors(sectorSlot).walls(wallSlot).corner(1).xyz(0)
                    z2 = demo(0).sectors(sectorSlot).walls(wallSlot).corner(1).xyz(2)
                    dx = x2 - x1
                    dz = z2 - z1
                    segSq = dx * dx + dz * dz
                    IF segSq > .00001! THEN
                        proj = ((candidateX - x1) * dx + (candidateZ - z1) * dz) / segSq
                        IF proj < 0! THEN proj = 0!
                        IF proj > 1! THEN proj = 1!
                        nearX = x1 + proj * dx
                        nearZ = z1 + proj * dz
                        dpx = candidateX - nearX
                        dpz = candidateZ - nearZ
                        distSq = dpx * dpx + dpz * dpz
                        IF distSq < PLAYER_RADIUS * PLAYER_RADIUS THEN
                            IF distSq < bestDistSq THEN
                                bestDistSq = distSq
                                blocked = -1
                                hitSector = sectorSlot
                                hitWall = wallSlot
                                hitX = nearX
                                hitZ = nearZ
                                hitNx = demo(0).sectors(sectorSlot).walls(wallSlot).normal(0)
                                hitNz = demo(0).sectors(sectorSlot).walls(wallSlot).normal(2)
                            END IF
                        END IF
                    END IF
                END IF
            END IF
        NEXT wallSlot
    NEXT sectorSlot
END SUB

SUB CheckPropCollision (candidateX AS SINGLE, candidateZ AS SINGLE, candidateGround AS SINGLE, blocked AS _BYTE, hitSector AS LONG, hitWall AS LONG, hitX AS SINGLE, hitZ AS SINGLE, hitNx AS SINGLE, hitNz AS SINGLE)
    DIM roomSlot AS LONG
    DIM propSlot AS LONG
    DIM minX AS SINGLE
    DIM maxX AS SINGLE
    DIM minZ AS SINGLE
    DIM maxZ AS SINGLE
    DIM minY AS SINGLE
    DIM maxY AS SINGLE
    DIM bestGap AS SINGLE
    DIM gapX1 AS SINGLE
    DIM gapX2 AS SINGLE
    DIM gapZ1 AS SINGLE
    DIM gapZ2 AS SINGLE

    blocked = 0

    FOR roomSlot = 0 TO UBOUND(demo(0).rooms)
        FOR propSlot = 0 TO UBOUND(demo(0).rooms(roomSlot).props)
            IF demo(0).rooms(roomSlot).props(propSlot).solid THEN
                minX = demo(0).rooms(roomSlot).props(propSlot).center(0) - demo(0).rooms(roomSlot).props(propSlot).sizeBox(0) - PLAYER_RADIUS
                maxX = demo(0).rooms(roomSlot).props(propSlot).center(0) + demo(0).rooms(roomSlot).props(propSlot).sizeBox(0) + PLAYER_RADIUS
                minZ = demo(0).rooms(roomSlot).props(propSlot).center(2) - demo(0).rooms(roomSlot).props(propSlot).sizeBox(2) - PLAYER_RADIUS
                maxZ = demo(0).rooms(roomSlot).props(propSlot).center(2) + demo(0).rooms(roomSlot).props(propSlot).sizeBox(2) + PLAYER_RADIUS
                minY = demo(0).rooms(roomSlot).props(propSlot).center(1) - demo(0).rooms(roomSlot).props(propSlot).sizeBox(1)
                maxY = demo(0).rooms(roomSlot).props(propSlot).center(1) + demo(0).rooms(roomSlot).props(propSlot).sizeBox(1)
                IF candidateGround + PLAYER_BODY_H >= minY AND candidateGround <= maxY THEN
                    IF candidateX >= minX AND candidateX <= maxX AND candidateZ >= minZ AND candidateZ <= maxZ THEN
                        blocked = -1
                        hitSector = -200 - roomSlot
                        hitWall = propSlot
                        hitX = demo(0).rooms(roomSlot).props(propSlot).center(0)
                        hitZ = demo(0).rooms(roomSlot).props(propSlot).center(2)
                        gapX1 = ABS(candidateX - minX)
                        gapX2 = ABS(maxX - candidateX)
                        gapZ1 = ABS(candidateZ - minZ)
                        gapZ2 = ABS(maxZ - candidateZ)
                        bestGap = gapX1
                        hitNx = -1!: hitNz = 0!
                        IF gapX2 < bestGap THEN bestGap = gapX2: hitNx = 1!: hitNz = 0!
                        IF gapZ1 < bestGap THEN bestGap = gapZ1: hitNx = 0!: hitNz = -1!
                        IF gapZ2 < bestGap THEN hitNx = 0!: hitNz = 1!
                        EXIT SUB
                    END IF
                END IF
            END IF
        NEXT propSlot
    NEXT roomSlot
END SUB


SUB CheckObjectCollision (candidateX AS SINGLE, candidateZ AS SINGLE, candidateGround AS SINGLE, blocked AS _BYTE, hitSector AS LONG, hitWall AS LONG, hitX AS SINGLE, hitZ AS SINGLE, hitNx AS SINGLE, hitNz AS SINGLE)
    DIM objectSlot AS LONG
    DIM partSlot AS LONG
    DIM minX AS SINGLE
    DIM maxX AS SINGLE
    DIM minZ AS SINGLE
    DIM maxZ AS SINGLE
    DIM minY AS SINGLE
    DIM maxY AS SINGLE
    DIM bestGap AS SINGLE
    DIM gapX1 AS SINGLE
    DIM gapX2 AS SINGLE
    DIM gapZ1 AS SINGLE
    DIM gapZ2 AS SINGLE

    blocked = 0

    FOR objectSlot = 0 TO UBOUND(demo(0).objects)
        IF demo(0).objects(objectSlot).solid THEN
            IF candidateX >= demo(0).objects(objectSlot).boundsMin(0) - PLAYER_RADIUS AND candidateX <= demo(0).objects(objectSlot).boundsMax(0) + PLAYER_RADIUS THEN
                IF candidateZ >= demo(0).objects(objectSlot).boundsMin(2) - PLAYER_RADIUS AND candidateZ <= demo(0).objects(objectSlot).boundsMax(2) + PLAYER_RADIUS THEN
                    FOR partSlot = 0 TO UBOUND(demo(0).objects(objectSlot).parts)
                        IF demo(0).objects(objectSlot).parts(partSlot).solid THEN
                            minX = demo(0).objects(objectSlot).parts(partSlot).center(0) - demo(0).objects(objectSlot).parts(partSlot).sizeBox(0) - PLAYER_RADIUS
                            maxX = demo(0).objects(objectSlot).parts(partSlot).center(0) + demo(0).objects(objectSlot).parts(partSlot).sizeBox(0) + PLAYER_RADIUS
                            minZ = demo(0).objects(objectSlot).parts(partSlot).center(2) - demo(0).objects(objectSlot).parts(partSlot).sizeBox(2) - PLAYER_RADIUS
                            maxZ = demo(0).objects(objectSlot).parts(partSlot).center(2) + demo(0).objects(objectSlot).parts(partSlot).sizeBox(2) + PLAYER_RADIUS
                            minY = demo(0).objects(objectSlot).parts(partSlot).center(1) - demo(0).objects(objectSlot).parts(partSlot).sizeBox(1)
                            maxY = demo(0).objects(objectSlot).parts(partSlot).center(1) + demo(0).objects(objectSlot).parts(partSlot).sizeBox(1)
                            IF candidateGround + PLAYER_BODY_H >= minY AND candidateGround <= maxY THEN
                                IF candidateX >= minX AND candidateX <= maxX AND candidateZ >= minZ AND candidateZ <= maxZ THEN
                                    blocked = -1
                                    hitSector = -500 - objectSlot
                                    hitWall = partSlot
                                    hitX = demo(0).objects(objectSlot).parts(partSlot).center(0)
                                    hitZ = demo(0).objects(objectSlot).parts(partSlot).center(2)
                                    gapX1 = ABS(candidateX - minX)
                                    gapX2 = ABS(maxX - candidateX)
                                    gapZ1 = ABS(candidateZ - minZ)
                                    gapZ2 = ABS(maxZ - candidateZ)
                                    bestGap = gapX1
                                    hitNx = -1!: hitNz = 0!
                                    IF gapX2 < bestGap THEN bestGap = gapX2: hitNx = 1!: hitNz = 0!
                                    IF gapZ1 < bestGap THEN bestGap = gapZ1: hitNx = 0!: hitNz = -1!
                                    IF gapZ2 < bestGap THEN hitNx = 0!: hitNz = 1!
                                    EXIT SUB
                                END IF
                            END IF
                        END IF
                    NEXT partSlot
                END IF
            END IF
        END IF
    NEXT objectSlot
END SUB

SUB PushHit (sectorSlot AS LONG, wallSlot AS LONG, hitX AS SINGLE, hitZ AS SINGLE, hitNx AS SINGLE, hitNz AS SINGLE)
    DIM traceSlot AS LONG
    FOR traceSlot = HIT_TRACE_MAX TO 1 STEP -1
        demo(0).lastHits(traceSlot) = demo(0).lastHits(traceSlot - 1)
    NEXT traceSlot
    demo(0).lastHits(0).active = -1
    demo(0).lastHits(0).anchor(0) = hitX
    demo(0).lastHits(0).anchor(1) = .08!
    demo(0).lastHits(0).anchor(2) = hitZ
    demo(0).lastHits(0).normal(0) = hitNx
    demo(0).lastHits(0).normal(1) = 0!
    demo(0).lastHits(0).normal(2) = hitNz
    demo(0).lastHits(0).sectorSlot = sectorSlot
    demo(0).lastHits(0).wallSlot = wallSlot
    demo(0).lastHits(0).ageFrame = 0
END SUB

SUB AgeHitStack
    DIM traceSlot AS LONG
    FOR traceSlot = 0 TO HIT_TRACE_MAX
        IF demo(0).lastHits(traceSlot).active THEN
            demo(0).lastHits(traceSlot).ageFrame = demo(0).lastHits(traceSlot).ageFrame + 1
            IF demo(0).lastHits(traceSlot).ageFrame > 90 THEN demo(0).lastHits(traceSlot).active = 0
        END IF
    NEXT traceSlot
END SUB

SUB UpdateWindowTitle
    DIM infoText AS STRING
    infoText = "_DynamicField OpenGL maze V7 | indoor/outdoor object graph | W/S Q/E A/D R T F ESC"
    infoText = infoText + " | seed=" + LTRIM$(STR$(worldSeed))
    infoText = infoText + " | X=" + LTRIM$(STR$(INT(playerX * 100!) / 100!))
    infoText = infoText + " Z=" + LTRIM$(STR$(INT(playerZ * 100!) / 100!))
    infoText = infoText + " ground=" + LTRIM$(STR$(INT(playerGroundY * 100!) / 100!))
    infoText = infoText + " eye=" + LTRIM$(STR$(INT(playerY * 100!) / 100!))
    IF playerAirborne THEN infoText = infoText + " | falling"
    IF demo(0).lastHits(0).active THEN
        infoText = infoText + " | hit sector " + LTRIM$(STR$(demo(0).lastHits(0).sectorSlot)) + " wall " + LTRIM$(STR$(demo(0).lastHits(0).wallSlot))
    ELSE
        infoText = infoText + " | hit none"
    END IF
    _TITLE infoText
END SUB

SUB _GL
    IF glReady = 0 THEN InitGL
    IF worldReady = 0 THEN
        RenderSmokeScene
    ELSE
        RenderGLScene
    END IF
END SUB

SUB InitGL
    _GLVIEWPORT 0, 0, _WIDTH, _HEIGHT
    _GLCLEARCOLOR .06!, .075!, .10!, 1!
    _GLCLEARDEPTH 1!
    _GLDEPTHFUNC _GL_LESS
    _GLENABLE _GL_DEPTH_TEST
    _GLSHADEMODEL _GL_SMOOTH
    _GLDISABLE _GL_TEXTURE_2D
    _GLDISABLE _GL_LIGHTING
    _GLDISABLE _GL_CULL_FACE
    _GLBLENDFUNC _GL_SRC_ALPHA, _GL_ONE_MINUS_SRC_ALPHA
    _GLENABLE _GL_BLEND
    _GLFOGFV _GL_FOG_COLOR, _OFFSET(fogColor())
    _GLFOGF _GL_FOG_START, 7!
    _GLFOGF _GL_FOG_END, 36!
    _GLHINT _GL_FOG_HINT, _GL_NICEST
    glReady = -1
END SUB

SUB RenderSmokeScene
    _GLVIEWPORT 0, 0, _WIDTH, _HEIGHT
    _GLCLEARCOLOR .06!, .075!, .10!, 1!
    _GLCLEAR _GL_COLOR_BUFFER_BIT OR _GL_DEPTH_BUFFER_BIT
    _GLMATRIXMODE _GL_PROJECTION
    _GLLOADIDENTITY
    _GLUPERSPECTIVE 62!, _WIDTH / _HEIGHT, .08!, 90!
    _GLMATRIXMODE _GL_MODELVIEW
    _GLLOADIDENTITY
    DrawEyeSpaceBeacon
END SUB


SUB RenderGLScene
    DIM sectorSlot AS LONG
    DIM wallSlot AS LONG
    DIM lampSlot AS LONG
    DIM decalSlot AS LONG
    DIM stairSlot AS LONG
    DIM roomSlot AS LONG
    DIM propSlot AS LONG
    DIM objectSlot AS LONG
    DIM cloudSlot AS LONG
    DIM traceSlot AS LONG

    _GLVIEWPORT 0, 0, _WIDTH, _HEIGHT
    _GLCLEARCOLOR .06!, .075!, .10!, 1!
    _GLDISABLE _GL_TEXTURE_2D
    _GLDISABLE _GL_LIGHTING
    _GLCLEAR _GL_COLOR_BUFFER_BIT OR _GL_DEPTH_BUFFER_BIT

    _GLMATRIXMODE _GL_PROJECTION
    _GLLOADIDENTITY
    _GLUPERSPECTIVE 62!, _WIDTH / _HEIGHT, .08!, 90!
    _GLMATRIXMODE _GL_MODELVIEW
    _GLLOADIDENTITY

    DrawEyeSpaceBeacon

    _GLMATRIXMODE _GL_MODELVIEW
    _GLLOADIDENTITY

    IF fogEnabled THEN
        _GLENABLE _GL_FOG
    ELSE
        _GLDISABLE _GL_FOG
    END IF

    _GLROTATEF playerPitch, 1!, 0!, 0!
    _GLROTATEF 360! - playerYaw, 0!, 1!, 0!
    _GLTRANSLATEF -playerX, -playerY, -playerZ

    DrawSky
    DrawOutdoorGround

    FOR cloudSlot = 0 TO UBOUND(demo(0).clouds)
        DrawCloud cloudSlot
    NEXT cloudSlot

    DrawWorldOriginMarker
    DrawMoveProbe
    DrawWorldFloor

    FOR stairSlot = 0 TO UBOUND(demo(0).stairs)
        DrawStair stairSlot
    NEXT stairSlot

    FOR roomSlot = 0 TO UBOUND(demo(0).rooms)
        DrawRoomOutline roomSlot
        FOR propSlot = 0 TO UBOUND(demo(0).rooms(roomSlot).props)
            DrawProp roomSlot, propSlot
        NEXT propSlot
    NEXT roomSlot

    FOR objectSlot = 0 TO UBOUND(demo(0).objects)
        DrawSceneObject objectSlot
    NEXT objectSlot

    FOR sectorSlot = 0 TO UBOUND(demo(0).sectors)
        FOR decalSlot = 0 TO UBOUND(demo(0).sectors(sectorSlot).decals)
            DrawDecal sectorSlot, decalSlot
        NEXT decalSlot
    NEXT sectorSlot

    FOR sectorSlot = 0 TO UBOUND(demo(0).sectors)
        FOR wallSlot = 0 TO UBOUND(demo(0).sectors(sectorSlot).walls)
            DrawWall sectorSlot, wallSlot
        NEXT wallSlot
    NEXT sectorSlot

    FOR sectorSlot = 0 TO UBOUND(demo(0).sectors)
        FOR lampSlot = 0 TO UBOUND(demo(0).sectors(sectorSlot).lamps)
            DrawLamp sectorSlot, lampSlot
        NEXT lampSlot
    NEXT sectorSlot

    FOR traceSlot = 0 TO HIT_TRACE_MAX
        IF demo(0).lastHits(traceSlot).active THEN DrawHitMarker traceSlot
    NEXT traceSlot
END SUB

SUB DrawEyeSpaceBeacon
    ' Camera-space sanity marker.  If this triangle is visible, the GL viewport/projection path is alive.
    ' It deliberately does not read any _DynamicField data and is drawn before the world transform.
    _GLDISABLE _GL_DEPTH_TEST
    _GLDISABLE _GL_FOG
    _GLBEGIN _GL_TRIANGLES
    _GLCOLOR4F 1!, .10!, .10!, 1!: _GLVERTEX3F -.24!, -.18!, -1.05!
    _GLCOLOR4F .10!, 1!, .10!, 1!: _GLVERTEX3F .24!, -.18!, -1.05!
    _GLCOLOR4F 1!, .90!, .10!, 1!: _GLVERTEX3F 0!, .25!, -1.05!
    _GLEND
    _GLENABLE _GL_DEPTH_TEST
END SUB


SUB DrawSky
    DIM farSpan AS SINGLE
    farSpan = 88!
    _GLDISABLE _GL_DEPTH_TEST
    _GLDISABLE _GL_FOG
    _GLBEGIN _GL_QUADS
    _GLCOLOR4F .08!, .16!, .42!, 1!: _GLVERTEX3F playerX - farSpan, 24!, playerZ - farSpan
    _GLCOLOR4F .10!, .22!, .58!, 1!: _GLVERTEX3F playerX + farSpan, 24!, playerZ - farSpan
    _GLCOLOR4F .38!, .66!, .95!, 1!: _GLVERTEX3F playerX + farSpan, 6!, playerZ - farSpan
    _GLCOLOR4F .42!, .72!, 1!, 1!: _GLVERTEX3F playerX - farSpan, 6!, playerZ - farSpan

    _GLCOLOR4F .10!, .20!, .50!, 1!: _GLVERTEX3F playerX + farSpan, 24!, playerZ - farSpan
    _GLCOLOR4F .10!, .22!, .56!, 1!: _GLVERTEX3F playerX + farSpan, 24!, playerZ + farSpan
    _GLCOLOR4F .46!, .74!, 1!, 1!: _GLVERTEX3F playerX + farSpan, 6!, playerZ + farSpan
    _GLCOLOR4F .42!, .72!, 1!, 1!: _GLVERTEX3F playerX + farSpan, 6!, playerZ - farSpan

    _GLCOLOR4F .10!, .22!, .56!, 1!: _GLVERTEX3F playerX + farSpan, 24!, playerZ + farSpan
    _GLCOLOR4F .08!, .16!, .42!, 1!: _GLVERTEX3F playerX - farSpan, 24!, playerZ + farSpan
    _GLCOLOR4F .42!, .72!, 1!, 1!: _GLVERTEX3F playerX - farSpan, 6!, playerZ + farSpan
    _GLCOLOR4F .46!, .74!, 1!, 1!: _GLVERTEX3F playerX + farSpan, 6!, playerZ + farSpan

    _GLCOLOR4F .08!, .16!, .42!, 1!: _GLVERTEX3F playerX - farSpan, 24!, playerZ + farSpan
    _GLCOLOR4F .08!, .16!, .42!, 1!: _GLVERTEX3F playerX - farSpan, 24!, playerZ - farSpan
    _GLCOLOR4F .42!, .72!, 1!, 1!: _GLVERTEX3F playerX - farSpan, 6!, playerZ - farSpan
    _GLCOLOR4F .42!, .72!, 1!, 1!: _GLVERTEX3F playerX - farSpan, 6!, playerZ + farSpan
    _GLEND
    _GLENABLE _GL_DEPTH_TEST
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawOutdoorGround
    DIM stripeSlot AS LONG
    DIM x0 AS SINGLE
    DIM z0 AS SINGLE
    DIM flowerX AS SINGLE
    DIM flowerZ AS SINGLE

    _GLCOLOR4F .10!, .34!, .13!, 1!
    _GLBEGIN _GL_QUADS
    _GLVERTEX3F OUT_MIN_X, OUT_YARD_Y - .035!, OUT_MIN_Z
    _GLVERTEX3F OUT_MAX_X, OUT_YARD_Y - .035!, OUT_MIN_Z
    _GLVERTEX3F OUT_MAX_X, OUT_YARD_Y - .035!, OUT_MAX_Z
    _GLVERTEX3F OUT_MIN_X, OUT_YARD_Y - .035!, OUT_MAX_Z
    _GLEND

    ' Bright path out of the building gate.
    _GLCOLOR4F .52!, .43!, .28!, 1!
    _GLBEGIN _GL_QUADS
    _GLVERTEX3F -12!, OUT_YARD_Y - .025!, 21.8!
    _GLVERTEX3F -3!, OUT_YARD_Y - .025!, 21.8!
    _GLVERTEX3F -1!, OUT_YARD_Y - .025!, OUT_MAX_Z - 2!
    _GLVERTEX3F -14!, OUT_YARD_Y - .025!, OUT_MAX_Z - 2!
    _GLEND

    FOR stripeSlot = 0 TO 17
        x0 = OUT_MIN_X + 3! + stripeSlot * 3.8!
        _GLCOLOR4F .08! + (stripeSlot MOD 3) * .04!, .40! + (stripeSlot MOD 4) * .03!, .12!, .55!
        _GLBEGIN _GL_QUADS
        _GLVERTEX3F x0, OUT_YARD_Y - .022!, OUT_MIN_Z + 1!
        _GLVERTEX3F x0 + 1.4!, OUT_YARD_Y - .022!, OUT_MIN_Z + 1!
        _GLVERTEX3F x0 + 2.6!, OUT_YARD_Y - .022!, OUT_MAX_Z - 1!
        _GLVERTEX3F x0 + 1.2!, OUT_YARD_Y - .022!, OUT_MAX_Z - 1!
        _GLEND
    NEXT stripeSlot

    _GLDISABLE _GL_FOG
    FOR stripeSlot = 0 TO 35
        flowerX = OUT_MIN_X + 4! + ((stripeSlot * 17 + worldSeed * 3) MOD 64)
        flowerZ = OUT_MIN_Z + 4! + ((stripeSlot * 23 + worldSeed * 5) MOD 67)
        IF flowerX < -23! OR flowerX > 23! OR flowerZ < -23! OR flowerZ > 23! THEN
            _GLCOLOR4F .85!, .20! + (stripeSlot MOD 5) * .12!, .25! + (stripeSlot MOD 4) * .15!, 1!
            DrawSmallPyramid flowerX, OUT_YARD_Y + .08!, flowerZ, .055!
        END IF
    NEXT stripeSlot
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawSceneObject (objectSlot AS LONG)
    DIM partSlot AS LONG
    FOR partSlot = 0 TO UBOUND(demo(0).objects(objectSlot).parts)
        DrawObjectPart objectSlot, partSlot
    NEXT partSlot
END SUB

SUB DrawObjectPart (objectSlot AS LONG, partSlot AS LONG)
    DIM x0 AS SINGLE
    DIM y0 AS SINGLE
    DIM z0 AS SINGLE
    DIM sx AS SINGLE
    DIM sy AS SINGLE
    DIM sz AS SINGLE
    DIM cr AS SINGLE
    DIM cg AS SINGLE
    DIM cb AS SINGLE
    x0 = demo(0).objects(objectSlot).parts(partSlot).center(0)
    y0 = demo(0).objects(objectSlot).parts(partSlot).center(1)
    z0 = demo(0).objects(objectSlot).parts(partSlot).center(2)
    sx = demo(0).objects(objectSlot).parts(partSlot).sizeBox(0)
    sy = demo(0).objects(objectSlot).parts(partSlot).sizeBox(1)
    sz = demo(0).objects(objectSlot).parts(partSlot).sizeBox(2)
    cr = demo(0).objects(objectSlot).parts(partSlot).tint.rgba(0)
    cg = demo(0).objects(objectSlot).parts(partSlot).tint.rgba(1)
    cb = demo(0).objects(objectSlot).parts(partSlot).tint.rgba(2)
    IF demo(0).objects(objectSlot).parts(partSlot).partKind = 2 THEN
        _GLCOLOR4F cr, cg, cb, .96!
        DrawSmallPyramid x0, y0, z0, sx
    ELSE
        DrawBoxLit x0, y0, z0, sx, sy, sz, cr, cg, cb, .96!
    END IF
END SUB

SUB DrawCloud (cloudSlot AS LONG)
    DIM puffSlot AS LONG
    DIM x0 AS SINGLE
    DIM y0 AS SINGLE
    DIM z0 AS SINGLE
    DIM sx AS SINGLE
    DIM sy AS SINGLE
    DIM sz AS SINGLE
    _GLDISABLE _GL_FOG
    FOR puffSlot = 0 TO UBOUND(demo(0).clouds(cloudSlot).puffs)
        x0 = demo(0).clouds(cloudSlot).puffs(puffSlot).center(0)
        y0 = demo(0).clouds(cloudSlot).puffs(puffSlot).center(1)
        z0 = demo(0).clouds(cloudSlot).puffs(puffSlot).center(2)
        sx = demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(0)
        sy = demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(1)
        sz = demo(0).clouds(cloudSlot).puffs(puffSlot).sizeBox(2)
        DrawBoxLit x0, y0, z0, sx, sy, sz, demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(0), demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(1), demo(0).clouds(cloudSlot).puffs(puffSlot).tint.rgba(2), .52!
    NEXT puffSlot
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawWorldOriginMarker
    ' Large fixed marker around the world origin.  This also does not depend on descriptor data.
    _GLDISABLE _GL_FOG
    _GLLINEWIDTH 3!
    _GLBEGIN _GL_LINES
    _GLCOLOR4F 1!, .15!, .15!, 1!: _GLVERTEX3F -1.5!, .08!, 0!: _GLVERTEX3F 1.5!, .08!, 0!
    _GLCOLOR4F .15!, 1!, .15!, 1!: _GLVERTEX3F 0!, .08!, -1.5!: _GLVERTEX3F 0!, .08!, 1.5!
    _GLCOLOR4F .2!, .55!, 1!, 1!: _GLVERTEX3F 0!, .08!, 0!: _GLVERTEX3F 0!, 2.5!, 0!
    _GLEND
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawMoveProbe
exit sub
    DIM fwdX AS SINGLE
    DIM fwdZ AS SINGLE
    DIM sideX AS SINGLE
    DIM sideZ AS SINGLE

    MoveBasis playerYaw, fwdX, fwdZ, sideX, sideZ

    _GLDISABLE _GL_FOG
    _GLCOLOR3F .2!, 1!, .25!
    DrawSmallPyramid playerX + fwdX * 2.4!, playerGroundY + 1.05!, playerZ + fwdZ * 2.4!, .18!
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawWorldFloor
    DIM sectorSlot AS LONG
    DIM minX AS SINGLE
    DIM maxX AS SINGLE
    DIM minZ AS SINGLE
    DIM maxZ AS SINGLE
    DIM floorLevel AS SINGLE

    FOR sectorSlot = 0 TO UBOUND(demo(0).sectors)
        minX = demo(0).sectors(sectorSlot).boundsMin(0)
        maxX = demo(0).sectors(sectorSlot).boundsMax(0)
        minZ = demo(0).sectors(sectorSlot).boundsMin(2)
        maxZ = demo(0).sectors(sectorSlot).boundsMax(2)
        floorLevel = demo(0).sectors(sectorSlot).floorY
        _GLCOLOR4F demo(0).sectors(sectorSlot).floorTint.rgba(0), demo(0).sectors(sectorSlot).floorTint.rgba(1), demo(0).sectors(sectorSlot).floorTint.rgba(2), 1!
        _GLBEGIN _GL_QUADS
        _GLVERTEX3F minX, floorLevel, minZ
        _GLVERTEX3F maxX, floorLevel, minZ
        _GLVERTEX3F maxX, floorLevel, maxZ
        _GLVERTEX3F minX, floorLevel, maxZ
        _GLEND
    NEXT sectorSlot
END SUB

SUB DrawStair (stairSlot AS LONG)
    DIM stepSlot AS LONG
    DIM totalSteps AS LONG
    DIM stepLen AS SINGLE
    DIM centerX AS SINGLE
    DIM centerY AS SINGLE
    DIM centerZ AS SINGLE
    DIM sizeX AS SINGLE
    DIM sizeY AS SINGLE
    DIM sizeZ AS SINGLE
    DIM topY AS SINGLE

    totalSteps = demo(0).stairs(stairSlot).stepCount
    IF totalSteps < 1 THEN totalSteps = 1
    stepLen = (demo(0).stairs(stairSlot).zoneMax(0) - demo(0).stairs(stairSlot).zoneMin(0)) / totalSteps
    sizeX = stepLen * .5!
    sizeZ = (demo(0).stairs(stairSlot).zoneMax(2) - demo(0).stairs(stairSlot).zoneMin(2)) * .5!
    centerZ = (demo(0).stairs(stairSlot).zoneMin(2) + demo(0).stairs(stairSlot).zoneMax(2)) * .5!

    FOR stepSlot = 0 TO totalSteps - 1
        topY = demo(0).stairs(stairSlot).lowY + (demo(0).stairs(stairSlot).highY - demo(0).stairs(stairSlot).lowY) * ((stepSlot + 1) / totalSteps)
        sizeY = (topY - demo(0).stairs(stairSlot).lowY) * .5!
        IF sizeY < .025! THEN sizeY = .025!
        centerX = demo(0).stairs(stairSlot).zoneMin(0) + stepLen * (stepSlot + .5!)
        centerY = demo(0).stairs(stairSlot).lowY + sizeY
        DrawBoxLit centerX, centerY, centerZ, sizeX * .96!, sizeY, sizeZ * .92!, demo(0).stairs(stairSlot).tint.rgba(0) + stepSlot * .01!, demo(0).stairs(stairSlot).tint.rgba(1) + stepSlot * .006!, demo(0).stairs(stairSlot).tint.rgba(2), 1!
    NEXT stepSlot

    centerX = (demo(0).stairs(stairSlot).zoneMin(0) + demo(0).stairs(stairSlot).zoneMax(0)) * .5!
    centerY = demo(0).stairs(stairSlot).highY + .08!
    sizeX = (demo(0).stairs(stairSlot).zoneMax(0) - demo(0).stairs(stairSlot).zoneMin(0)) * .5!
    DrawBoxLit centerX, centerY, demo(0).stairs(stairSlot).zoneMin(2) - .08!, sizeX, .08!, .08!, .18!, .24!, .30!, 1!
    DrawBoxLit centerX, centerY, demo(0).stairs(stairSlot).zoneMax(2) + .08!, sizeX, .08!, .08!, .18!, .24!, .30!, 1!
END SUB

SUB DrawRoomOutline (roomSlot AS LONG)
    DIM minX AS SINGLE
    DIM maxX AS SINGLE
    DIM minZ AS SINGLE
    DIM maxZ AS SINGLE
    DIM y0 AS SINGLE
    minX = demo(0).rooms(roomSlot).boundsMin(0)
    maxX = demo(0).rooms(roomSlot).boundsMax(0)
    minZ = demo(0).rooms(roomSlot).boundsMin(2)
    maxZ = demo(0).rooms(roomSlot).boundsMax(2)
    y0 = demo(0).rooms(roomSlot).floorY + .035!
    _GLDISABLE _GL_FOG
    _GLLINEWIDTH 2!
    _GLCOLOR4F .9!, .9!, .55!, .6!
    _GLBEGIN _GL_LINE_LOOP
    _GLVERTEX3F minX, y0, minZ
    _GLVERTEX3F maxX, y0, minZ
    _GLVERTEX3F maxX, y0, maxZ
    _GLVERTEX3F minX, y0, maxZ
    _GLEND
    IF fogEnabled THEN _GLENABLE _GL_FOG
END SUB

SUB DrawProp (roomSlot AS LONG, propSlot AS LONG)
    DIM cx AS SINGLE
    DIM cy AS SINGLE
    DIM cz AS SINGLE
    DIM sx AS SINGLE
    DIM sy AS SINGLE
    DIM sz AS SINGLE
    DIM cr AS SINGLE
    DIM cg AS SINGLE
    DIM cb AS SINGLE

    cx = demo(0).rooms(roomSlot).props(propSlot).center(0)
    cy = demo(0).rooms(roomSlot).props(propSlot).center(1)
    cz = demo(0).rooms(roomSlot).props(propSlot).center(2)
    sx = demo(0).rooms(roomSlot).props(propSlot).sizeBox(0)
    sy = demo(0).rooms(roomSlot).props(propSlot).sizeBox(1)
    sz = demo(0).rooms(roomSlot).props(propSlot).sizeBox(2)
    cr = demo(0).rooms(roomSlot).props(propSlot).tint.rgba(0)
    cg = demo(0).rooms(roomSlot).props(propSlot).tint.rgba(1)
    cb = demo(0).rooms(roomSlot).props(propSlot).tint.rgba(2)
    DrawBoxLit cx, cy, cz, sx, sy, sz, cr, cg, cb, .98!
END SUB

SUB DrawWall (sectorSlot AS LONG, wallSlot AS LONG)
    DIM cornerSlot AS LONG
    IF demo(0).sectors(sectorSlot).walls(wallSlot).flags = 0 THEN EXIT SUB

    _GLCOLOR4F demo(0).sectors(sectorSlot).walls(wallSlot).tint.rgba(0), demo(0).sectors(sectorSlot).walls(wallSlot).tint.rgba(1), demo(0).sectors(sectorSlot).walls(wallSlot).tint.rgba(2), .92!
    _GLBEGIN _GL_QUADS
    _GLNORMAL3F demo(0).sectors(sectorSlot).walls(wallSlot).normal(0), demo(0).sectors(sectorSlot).walls(wallSlot).normal(1), demo(0).sectors(sectorSlot).walls(wallSlot).normal(2)
    FOR cornerSlot = 0 TO 3
        _GLVERTEX3F demo(0).sectors(sectorSlot).walls(wallSlot).corner(cornerSlot).xyz(0), demo(0).sectors(sectorSlot).walls(wallSlot).corner(cornerSlot).xyz(1), demo(0).sectors(sectorSlot).walls(wallSlot).corner(cornerSlot).xyz(2)
    NEXT cornerSlot
    _GLEND
END SUB

SUB DrawDecal (sectorSlot AS LONG, decalSlot AS LONG)
    DIM x0 AS SINGLE
    DIM x1 AS SINGLE
    DIM z0 AS SINGLE
    DIM z1 AS SINGLE
    DIM y0 AS SINGLE
    x0 = demo(0).sectors(sectorSlot).decals(decalSlot).anchor(0) - demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(0)
    x1 = demo(0).sectors(sectorSlot).decals(decalSlot).anchor(0) + demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(0)
    z0 = demo(0).sectors(sectorSlot).decals(decalSlot).anchor(2) - demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(2)
    z1 = demo(0).sectors(sectorSlot).decals(decalSlot).anchor(2) + demo(0).sectors(sectorSlot).decals(decalSlot).sizeBox(2)
    y0 = demo(0).sectors(sectorSlot).decals(decalSlot).anchor(1)
    _GLCOLOR4F demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(0), demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(1), demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(2), demo(0).sectors(sectorSlot).decals(decalSlot).tint.rgba(3)
    _GLBEGIN _GL_QUADS
    _GLVERTEX3F x0, y0, z0
    _GLVERTEX3F x1, y0, z0
    _GLVERTEX3F x1, y0, z1
    _GLVERTEX3F x0, y0, z1
    _GLEND
END SUB

SUB DrawLamp (sectorSlot AS LONG, lampSlot AS LONG)
    DIM x0 AS SINGLE
    DIM y0 AS SINGLE
    DIM z0 AS SINGLE
    x0 = demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(0)
    y0 = demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(1)
    z0 = demo(0).sectors(sectorSlot).lamps(lampSlot).anchor(2)
    _GLCOLOR4F demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(0), demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(1), demo(0).sectors(sectorSlot).lamps(lampSlot).tint.rgba(2), .95!
    DrawSmallPyramid x0, y0, z0, .10!
END SUB

SUB DrawHitMarker (traceSlot AS LONG)
    DIM x0 AS SINGLE
    DIM y0 AS SINGLE
    DIM z0 AS SINGLE
    DIM alphaValue AS SINGLE
    x0 = demo(0).lastHits(traceSlot).anchor(0)
    y0 = demo(0).lastHits(traceSlot).anchor(1)
    z0 = demo(0).lastHits(traceSlot).anchor(2)
    alphaValue = 1! - demo(0).lastHits(traceSlot).ageFrame / 90!
    IF alphaValue < .1! THEN alphaValue = .1!
    _GLCOLOR4F 1!, .05!, .03!, alphaValue
    DrawSmallPyramid x0, y0 + .12!, z0, .16!
END SUB

SUB FaceShade (faceX AS SINGLE, faceY AS SINGLE, faceZ AS SINGLE, normX AS SINGLE, normY AS SINGLE, normZ AS SINGLE, shadeValue AS SINGLE)
    DIM lightX AS SINGLE
    DIM lightY AS SINGLE
    DIM lightZ AS SINGLE
    DIM lenValue AS SINGLE
    DIM dotValue AS SINGLE

    ' OpenGL 1.1 immediate mode has no problem with per-face colours.
    ' This is a tiny CPU-side camera/head-lamp: every box face gets a shade from its normal
    ' and the vector from that face toward the player eye.  It is not a shadow system.
    lightX = playerX - faceX
    lightY = playerY - faceY
    lightZ = playerZ - faceZ
    lenValue = SQR(lightX * lightX + lightY * lightY + lightZ * lightZ)
    IF lenValue < .001! THEN lenValue = .001!
    lightX = lightX / lenValue
    lightY = lightY / lenValue
    lightZ = lightZ / lenValue

    dotValue = lightX * normX + lightY * normY + lightZ * normZ
    IF dotValue < 0! THEN dotValue = 0!
    shadeValue = .28! + dotValue * .72!
    IF normY > .5! THEN shadeValue = shadeValue + .18!
    IF normY < -.5! THEN shadeValue = shadeValue - .08!
    IF shadeValue < .18! THEN shadeValue = .18!
    IF shadeValue > 1.18! THEN shadeValue = 1.18!
END SUB

SUB BoxFaceColor (cr AS SINGLE, cg AS SINGLE, cb AS SINGLE, alphaValue AS SINGLE, shadeValue AS SINGLE)
    DIM outR AS SINGLE
    DIM outG AS SINGLE
    DIM outB AS SINGLE

    outR = cr * shadeValue
    outG = cg * shadeValue
    outB = cb * shadeValue
    IF outR > 1! THEN outR = 1!
    IF outG > 1! THEN outG = 1!
    IF outB > 1! THEN outB = 1!
    _GLCOLOR4F outR, outG, outB, alphaValue
END SUB

SUB DrawBoxLit (x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, sx AS SINGLE, sy AS SINGLE, sz AS SINGLE, cr AS SINGLE, cg AS SINGLE, cb AS SINGLE, alphaValue AS SINGLE)
    DIM shadeValue AS SINGLE

    _GLBEGIN _GL_QUADS

    ' front, +Z
    FaceShade x0, y0, z0 + sz, 0!, 0!, 1!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F 0!, 0!, 1!
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz

    ' back, -Z
    FaceShade x0, y0, z0 - sz, 0!, 0!, -1!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F 0!, 0!, -1!
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz

    ' top, +Y
    FaceShade x0, y0 + sy, z0, 0!, 1!, 0!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F 0!, 1!, 0!
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz

    ' bottom, -Y
    FaceShade x0, y0 - sy, z0, 0!, -1!, 0!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F 0!, -1!, 0!
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz

    ' high X, +X
    FaceShade x0 + sx, y0, z0, 1!, 0!, 0!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F 1!, 0!, 0!
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz

    ' low X, -X
    FaceShade x0 - sx, y0, z0, -1!, 0!, 0!, shadeValue
    BoxFaceColor cr, cg, cb, alphaValue, shadeValue
    _GLNORMAL3F -1!, 0!, 0!
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz

    _GLEND
END SUB

SUB DrawBox (x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, sx AS SINGLE, sy AS SINGLE, sz AS SINGLE)
    _GLBEGIN _GL_QUADS
    ' front
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz
    ' back
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz
    ' top
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz
    ' bottom
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz
    ' x high
    _GLVERTEX3F x0 + sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 + sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 - sz
    _GLVERTEX3F x0 + sx, y0 + sy, z0 + sz
    ' x low
    _GLVERTEX3F x0 - sx, y0 - sy, z0 - sz
    _GLVERTEX3F x0 - sx, y0 - sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 + sz
    _GLVERTEX3F x0 - sx, y0 + sy, z0 - sz
    _GLEND
END SUB

SUB DrawSmallPyramid (x0 AS SINGLE, y0 AS SINGLE, z0 AS SINGLE, s AS SINGLE)
    _GLBEGIN _GL_TRIANGLES
    _GLVERTEX3F x0, y0 + s, z0
    _GLVERTEX3F x0 - s, y0 - s, z0 - s
    _GLVERTEX3F x0 + s, y0 - s, z0 - s

    _GLVERTEX3F x0, y0 + s, z0
    _GLVERTEX3F x0 + s, y0 - s, z0 - s
    _GLVERTEX3F x0 + s, y0 - s, z0 + s

    _GLVERTEX3F x0, y0 + s, z0
    _GLVERTEX3F x0 + s, y0 - s, z0 + s
    _GLVERTEX3F x0 - s, y0 - s, z0 + s

    _GLVERTEX3F x0, y0 + s, z0
    _GLVERTEX3F x0 - s, y0 - s, z0 + s
    _GLVERTEX3F x0 - s, y0 - s, z0 - s
    _GLEND
END SUB
