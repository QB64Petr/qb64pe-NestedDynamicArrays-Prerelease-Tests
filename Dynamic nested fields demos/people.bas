OPTION _EXPLICIT
OPTION BASE 0

' Demo:
'   PersonInfo -> dynamic array of ChildInfo
'   ChildInfo  -> dynamic array of FriendInfo
'
' The important point is memory efficiency:
'   - each person can have a different number of children
'   - each child can have a different number of friends
'   - only the descriptor is stored inline for _DynamicField arrays
'   - the actual dynamic member array payload is allocated per owner element
'
' _StaticField is used only for data that has the same fixed bounds
' for every owner element.

TYPE FriendInfo
    ' Variable-length string stored by the FriendInfo element.
    friendName AS STRING
END TYPE

TYPE ChildInfo
    childName AS STRING
    age AS INTEGER

    ' Static embedded array:
    ' Every child always has exactly two note slots.
    ' This is stored inline because the bounds are fixed for every child.
    fixedNote(1 TO 2) _STATICFIELD AS STRING

    friendCount AS LONG

    ' Dynamic embedded array:
    ' Each child can have a different number of friends.
    ' The ChildInfo element stores only a descriptor for this array.
    friends(0) _DYNAMICFIELD AS FriendInfo
END TYPE

TYPE PersonInfo
    personName AS STRING
    age AS INTEGER

    ' Static embedded array:
    ' Every person always has exactly two contact slots.
    ' This is suitable for _StaticField because the size is the same
    ' for every PersonInfo element.
    fixedContact(1 TO 2) _STATICFIELD AS STRING * 24

    childCount AS LONG

    ' Dynamic embedded array:
    ' Each person can have a different number of children.
    ' The PersonInfo element stores only a descriptor for this array.
    children(0) _DYNAMICFIELD AS ChildInfo
END TYPE


DIM personIndex AS LONG
DIM childIndex AS LONG
DIM friendIndex AS LONG

' The parent array itself is dynamic here.
' This is the usual way to create an array of UDTs that contain
' descriptor-backed _DynamicField member arrays.
REDIM people(0 TO 2) AS PersonInfo



' Person 0: Alice has 2 children.
people(0).personName = "Alice"
people(0).age = 34
people(0).fixedContact(1) = "phone"
people(0).fixedContact(2) = "email"

people(0).childCount = 2

' Resize only Alice's children array.
' Other PersonInfo elements keep their own independent children arrays.
REDIM people(0).children(0 TO people(0).childCount - 1)

people(0).children(0).childName = "Emma"
people(0).children(0).age = 8
people(0).children(0).fixedNote(1) = "school"
people(0).children(0).fixedNote(2) = "music"
people(0).children(0).friendCount = 3

' Resize only Emma's friends array.
REDIM people(0).children(0).friends(0 TO people(0).children(0).friendCount - 1)
people(0).children(0).friends(0).friendName = "Sofia"
people(0).children(0).friends(1).friendName = "Nina"
people(0).children(0).friends(2).friendName = "Laura"

people(0).children(1).childName = "Adam"
people(0).children(1).age = 5
people(0).children(1).fixedNote(1) = "kindergarten"
people(0).children(1).fixedNote(2) = "football"
people(0).children(1).friendCount = 1

' Adam has only one friend, so only one FriendInfo element is allocated.
REDIM people(0).children(1).friends(0 TO people(0).children(1).friendCount - 1)
people(0).children(1).friends(0).friendName = "Oliver"



' Person 1: Boris has 1 child.

people(1).personName = "Boris"
people(1).age = 41
people(1).fixedContact(1) = "phone"
people(1).fixedContact(2) = "work"

people(1).childCount = 1

' Boris has a different number of children than Alice.
REDIM people(1).children(0 TO people(1).childCount - 1)

people(1).children(0).childName = "Tereza"
people(1).children(0).age = 12
people(1).children(0).fixedNote(1) = "science"
people(1).children(0).fixedNote(2) = "drawing"
people(1).children(0).friendCount = 4

' Tereza has four friends.
REDIM people(1).children(0).friends(0 TO people(1).children(0).friendCount - 1)
people(1).children(0).friends(0).friendName = "Anna"
people(1).children(0).friends(1).friendName = "Eliska"
people(1).children(0).friends(2).friendName = "Marek"
people(1).children(0).friends(3).friendName = "Jan"



' Person 2: Clara has 3 children.

people(2).personName = "Clara"
people(2).age = 38
people(2).fixedContact(1) = "phone"
people(2).fixedContact(2) = "chat"

people(2).childCount = 3

' Clara has three children, again with independent storage.
REDIM people(2).children(0 TO people(2).childCount - 1)

people(2).children(0).childName = "Daniel"
people(2).children(0).age = 10
people(2).children(0).fixedNote(1) = "math"
people(2).children(0).fixedNote(2) = "chess"
people(2).children(0).friendCount = 2

REDIM people(2).children(0).friends(0 TO people(2).children(0).friendCount - 1)
people(2).children(0).friends(0).friendName = "Filip"
people(2).children(0).friends(1).friendName = "Viktor"

people(2).children(1).childName = "Lucie"
people(2).children(1).age = 7
people(2).children(1).fixedNote(1) = "dance"
people(2).children(1).fixedNote(2) = "reading"
people(2).children(1).friendCount = 1

REDIM people(2).children(1).friends(0 TO people(2).children(1).friendCount - 1)
people(2).children(1).friends(0).friendName = "Amelie"

people(2).children(2).childName = "Matej"
people(2).children(2).age = 3
people(2).children(2).fixedNote(1) = "home"
people(2).children(2).fixedNote(2) = "toys"
people(2).children(2).friendCount = 2

REDIM people(2).children(2).friends(0 TO people(2).children(2).friendCount - 1)
people(2).children(2).friends(0).friendName = "Tomas"
people(2).children(2).friends(1).friendName = "Petr"



' print the whole structure

CLS

PRINT "Nested _DynamicField / _StaticField demo"
PRINT STRING$(72, "-")

FOR personIndex = LBOUND(people) TO UBOUND(people)
    PRINT
    PRINT "Person: "; RTRIM$(people(personIndex).personName); _
          "  Age:"; people(personIndex).age; _
          "  Children:"; people(personIndex).childCount

    PRINT "  Static contact slots: "; _
          RTRIM$(people(personIndex).fixedContact(1)); ", "; _
          RTRIM$(people(personIndex).fixedContact(2))

    FOR childIndex = LBOUND(people(personIndex).children) TO UBOUND(people(personIndex).children)
        PRINT
        PRINT "    Child: "; RTRIM$(people(personIndex).children(childIndex).childName); _
              "  Age:"; people(personIndex).children(childIndex).age; _
              "  Friends:"; people(personIndex).children(childIndex).friendCount

        PRINT "      Static note slots: "; _
              RTRIM$(people(personIndex).children(childIndex).fixedNote(1)); ", "; _
              RTRIM$(people(personIndex).children(childIndex).fixedNote(2))

        PRINT "      Friends: ";

        FOR friendIndex = LBOUND(people(personIndex).children(childIndex).friends) TO _
                          UBOUND(people(personIndex).children(childIndex).friends)

            PRINT RTRIM$(people(personIndex).children(childIndex).friends(friendIndex).friendName);

            IF friendIndex < UBOUND(people(personIndex).children(childIndex).friends) THEN
                PRINT ", ";
            END IF
        NEXT friendIndex

        PRINT
        SLEEP
    NEXT childIndex
NEXT personIndex

PRINT
PRINT STRING$(72, "-")
PRINT "Done."

' Cleanup:
' ERASE releases the parent array and the descriptor-backed nested arrays.
ERASE people

