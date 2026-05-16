#Requires AutoHotkey v2.0
#SingleInstance Force

SendMode "Input"
SetKeyDelay 30, 30

; ============================================================
; Creative Macropad Profile — Universal
;
; Firmware architecture:
;   layer 9  -> ZBrush base
;   layer 10 -> Blender base
;   layer 11 -> Fusion 360 base
;   layer 12 -> Clip Studio Paint base
;   layer 13 -> quick tools / brushes (MO(13))
;   layer 14 -> advanced workflow logic
;   layer 15 -> global service layer (TG(15))
;
; AHK sees normalized hotkey families, not the firmware layer numbers:
;
; Base app layers (9-12):
;   F16..F13, F20..F17, F24..F21, >+F16..F13
;
; Quick layer 13:
;   >^F16..F13, >^F20..F17, >^F24..F21, >!F16..F13
;
; Advanced layer 14:
;   <^F16..F13, <^F20..F17, <^F24..F21, <+F16..F13
;
; Service layer 15:
;   <!F16..F13, <!F20..F17, <!F24..F21, <+F24..F21
;
; Note:
;   Closing layer 15 by HOLD on the layer-15 F13 position is handled
;   in firmware. AHK only handles the tap action on that position.
; ============================================================

Phys(key) {
    static keys := Map(
        "a", "{vk41sc01E}",
        "b", "{vk42sc030}",
        "c", "{vk43sc02E}",
        "d", "{vk44sc020}",
        "e", "{vk45sc012}",
        "f", "{vk46sc021}",
        "g", "{vk47sc022}",
        "h", "{vk48sc023}",
        "i", "{vk49sc017}",
        "j", "{vk4Asc024}",
        "k", "{vk4Bsc025}",
        "l", "{vk4Csc026}",
        "m", "{vk4Dsc032}",
        "n", "{vk4Esc031}",
        "o", "{vk4Fsc018}",
        "p", "{vk50sc019}",
        "q", "{vk51sc010}",
        "r", "{vk52sc013}",
        "s", "{vk53sc01F}",
        "t", "{vk54sc014}",
        "u", "{vk55sc016}",
        "v", "{vk56sc02F}",
        "w", "{vk57sc011}",
        "x", "{vk58sc02D}",
        "y", "{vk59sc015}",
        "z", "{vk5Asc02C}"
    )
    Send keys[StrLower(key)]
}

ResetMods() {
    Send "{LCtrl up}{RCtrl up}{LShift up}{RShift up}{LAlt up}{RAlt up}{Ctrl up}{Shift up}{Alt up}"
}

SendClean(keys) {
    ResetMods()
    Sleep 20
    Send keys
}

BrushZ(seq) {
    ResetMods()
    Sleep 50

    SendEvent "{b down}"
    Sleep 30
    SendEvent "{b up}"
    Sleep 120

    Loop Parse seq {
        ch := A_LoopField
        SendEvent "{" ch " down}"
        Sleep 30
        SendEvent "{" ch " up}"
        Sleep 50
    }
}

F12::KeyHistory

; ============================================================
; LAYER 15 — GLOBAL SERVICE / SYSTEM
; Sticky TG(15) layer, shared by all supported creative apps
; ============================================================

#HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush") || WinActive("ahk_exe blender.exe") || WinActive("Blender") || WinActive("ahk_exe Fusion360.exe") || WinActive("Autodesk Fusion") || WinActive("Fusion") || WinActive("ahk_exe CLIPStudioPaint.exe") || WinActive("ahk_exe CLIPStudio.exe") || WinActive("Clip Studio Paint")

<!F16::SendClean("^s")              ; Save
<!F15::SendClean("^+s")             ; Save As
<!F14::SendClean("^o")              ; Open
<!F13::SendClean("^n")              ; New (hold on this key should close L15 in firmware)

<!F20::SendClean("^z")              ; Undo
<!F19::SendClean("^+z")             ; Redo
<!F18::SendClean("^c")              ; Copy
<!F17::SendClean("^v")              ; Paste

<!F24::SendClean("#+s")             ; Screenshot Snip
<!F23::SendClean("!{Tab}")          ; App Switch
<!F22::SendClean("{PrintScreen}")   ; Print Screen
<!F21::SendClean("{Esc}")           ; Cancel

<+F24::SendClean("{Volume_Down}")   ; Volume Down
<+F23::SendClean("{Volume_Up}")     ; Volume Up
<+F22::SendClean("{Volume_Mute}")   ; Volume Mute
<+F21::SendClean("{Media_Play_Pause}") ; Media Play Pause

#HotIf

; ============================================================
; ZBRUSH
; Base layer 9, quick layer 13, advanced layer 14
; ============================================================

#HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush")

; BASE — ZBRUSH
F16::SendClean("^n")                ; Clear Tool
F15::Phys("t")                      ; Edit
F14::Phys("x")                      ; Symmetry
F13::SendClean("{Esc}")             ; Esc

F20::SendClean("[")                 ; Brush Size -
F19::SendClean("]")                 ; Brush Size +
F18::SendClean("s")                 ; Draw Size Popup
F17::SendClean("^{F5}")             ; Solo

F24::Phys("q")                      ; Draw Mode
F23::Phys("w")                      ; Move
F22::Phys("b")                      ; Brush Palette
F21::SendClean("^z")                ; Undo

>+F16::SendClean("^+z")             ; Redo
>+F15::SendClean("+f")              ; PolyFrame
>+F14::SendClean("f")               ; Frame / Fit
>+F13::{
    KeyWait "F13"
    ResetMods()
    Sleep 20
    Send "^{F11}"
    Sleep 20
    ResetMods()
}                                   ; DynaMesh

PgDn::SendClean("[")                ; Brush Size -
PgUp::SendClean("]")                ; Brush Size +
>+PgDn::SendClean("{NumpadSub}")    ; Zoom Out
>+PgUp::SendClean("{NumpadAdd}")    ; Zoom In

; LAYER 13 — QUICK BRUSHES / TOOLS
>^F16::BrushZ("st")                 ; Standard
>^F15::BrushZ("cb")                 ; ClayBuildup
>^F14::BrushZ("ds")                 ; DamStandard
>^F13::BrushZ("mv")                 ; Move

>^F20::BrushZ("in")                 ; Inflate
>^F19::BrushZ("pi")                 ; Pinch
>^F18::BrushZ("cl")                 ; Clay
>^F17::BrushZ("mt")                 ; Move Topological

>^F24::BrushZ("td")                 ; TrimDynamic
>^F23::BrushZ("hp")                 ; hPolish
>^F22::BrushZ("sk")                 ; SnakeHook
>^F21::BrushZ("ma")                 ; Mask Brush

>!F16::BrushZ("cr")                 ; Crease
>!F15::BrushZ("mo")                 ; Morph
>!F14::BrushZ("si")                 ; Smooth Stronger
>!F13::BrushZ("zb")                 ; ZModeler

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^!c")             ; Clear Mask
<^F15::SendClean("^!b")             ; Blur Mask
<^F14::SendClean("^!s")             ; Sharpen Mask
<^F13::SendClean("^w")              ; Group Masked

<^F20::SendClean("^+i")             ; Invert Visibility
<^F19::SendClean("^!h")             ; HidePt
<^F18::SendClean("^!x")             ; Delete Hidden
<^F17::SendClean("^+a")             ; Show All

<^F24::SendClean("^d")              ; Divide
<^F23::SendClean("+d")              ; Lower Subdivision
<^F22::SendClean("d")               ; Higher Subdivision
<^F21::SendClean("^!d")             ; DynaMesh Action

<+F16::SendClean("!s")              ; Solo
<+F15::SendClean("+f")              ; PolyFrame
<+F14::SendClean("^!m")             ; Mirror And Weld
<+F13::SendClean("^!r")             ; ZRemesher

#HotIf

; ============================================================
; BLENDER
; Base layer 10, quick layer 13, advanced layer 14
; ============================================================

#HotIf WinActive("ahk_exe blender.exe") || WinActive("Blender")

; BASE — BLENDER
F16::SendClean("g")                 ; Grab Move
F15::SendClean("r")                 ; Rotate
F14::SendClean("s")                 ; Scale
F13::SendClean("{Esc}")             ; Cancel

F20::SendClean("e")                 ; Extrude
F19::SendClean("i")                 ; Inset
F18::SendClean("^b")                ; Bevel
F17::SendClean("{Tab}")             ; Edit Mode Toggle

F24::SendClean("1")                 ; Vertex Select
F23::SendClean("2")                 ; Edge Select
F22::SendClean("3")                 ; Face Select
F21::SendClean("^z")                ; Undo

>+F16::SendClean("{F3}")            ; Search
>+F15::SendClean("{NumpadDot}")     ; Frame Selected
>+F14::SendClean("/")               ; Local View
>+F13::SendClean("x")               ; Delete Menu

; LAYER 13 — QUICK TOOLS
>^F16::SendClean("b")               ; Box Select
>^F15::SendClean("c")               ; Circle Select
>^F14::SendClean("k")               ; Knife
>^F13::SendClean("^r")              ; Loop Cut

>^F20::SendClean("f")               ; Fill
>^F19::SendClean("m")               ; Merge
>^F18::SendClean("p")               ; Separate Menu
>^F17::SendClean("u")               ; UV Menu

>^F24::SendClean("o")               ; Proportional Editing
>^F23::SendClean("h")               ; Hide Selected
>^F22::SendClean("!h")              ; Unhide All
>^F21::SendClean("z")               ; Shading Pie

>!F16::SendClean("1")               ; Front View
>!F15::SendClean("3")               ; Right View
>!F14::SendClean("7")               ; Top View
>!F13::SendClean("0")               ; Camera View

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^c")              ; Copy
<^F15::SendClean("^v")              ; Paste
<^F14::SendClean("^x")              ; Cut
<^F13::SendClean("^z")              ; Undo

<^F20::SendClean("^+z")             ; Redo
<^F19::SendClean("!a")              ; Apply Menu
<^F18::SendClean("!m")              ; Merge By Distance
<^F17::SendClean("!z")              ; Shading Pie

<^F24::SendClean("^a")              ; Select All
<^F23::SendClean("^i")              ; Invert Selection
<^F22::SendClean("^j")              ; Join
<^F21::SendClean("^l")              ; Make Links

<+F16::SendClean("t")               ; Toolbar Toggle
<+F15::SendClean(".")               ; Pivot Pie
<+F14::SendClean(",")               ; Set Origin Menu
<+F13::SendClean("/")               ; Local View

#HotIf

; ============================================================
; AUTODESK FUSION
; Base layer 11, quick layer 13, advanced layer 14
; ============================================================

#HotIf WinActive("ahk_exe Fusion360.exe") || WinActive("Autodesk Fusion") || WinActive("Fusion")

; BASE — FUSION
F16::SendClean("q")                 ; Press Pull
F15::SendClean("m")                 ; Move Copy
F14::SendClean("f")                 ; Fillet
F13::SendClean("{Esc}")             ; Cancel

F20::SendClean("e")                 ; Extrude
F19::SendClean("o")                 ; Offset
F18::SendClean("x")                 ; Trim
F17::SendClean("d")                 ; Dimension

F24::SendClean("p")                 ; Project
F23::SendClean("s")                 ; Sketch Palette
F22::SendClean("i")                 ; Inspect
F21::SendClean("^z")                ; Undo

>+F16::SendClean("l")               ; Line
>+F15::SendClean("a")               ; Arc
>+F14::SendClean("r")               ; Rectangle
>+F13::SendClean("{Enter}")         ; Confirm / Finish

; LAYER 13 — QUICK TOOLS
>^F16::SendClean("c")               ; Circle
>^F15::SendClean("o")               ; Offset
>^F14::SendClean("n")               ; Normal Constraint
>^F13::SendClean("a")               ; Arc

>^F20::SendClean("t")               ; Tangent Constraint
>^F19::SendClean("v")               ; Visibility
>^F18::SendClean("g")               ; Grid Toggle
>^F17::SendClean("u")               ; Undo View Change

>^F24::SendClean("h")               ; Home View
>^F23::SendClean("[")               ; Previous Tool
>^F22::SendClean("]")               ; Next Tool
>^F21::SendClean("^d")              ; Deselect

>!F16::SendClean("^c")              ; Copy
>!F15::SendClean("^v")              ; Paste
>!F14::SendClean("{Delete}")        ; Delete
>!F13::SendClean("^1")              ; Workspace 1

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^z")              ; Undo
<^F15::SendClean("^y")              ; Redo
<^F14::SendClean("^c")              ; Copy
<^F13::SendClean("^v")              ; Paste

<^F20::SendClean("^x")              ; Cut
<^F19::SendClean("^a")              ; Select All
<^F18::SendClean("^f")              ; Find
<^F17::SendClean("^g")              ; Repeat Find

<^F24::SendClean("^s")              ; Save
<^F23::SendClean("^o")              ; Open
<^F22::SendClean("^n")              ; New Design
<^F21::SendClean("{Enter}")         ; Confirm

<+F16::SendClean("+n")              ; Snaps
<+F15::SendClean("+s")              ; Sketch Toggle
<+F14::SendClean("+m")              ; Measure
<+F13::SendClean("+c")              ; Center

#HotIf

; ============================================================
; CLIP STUDIO PAINT
; Base layer 12, quick layer 13, advanced layer 14
; ============================================================

#HotIf WinActive("ahk_exe CLIPStudioPaint.exe") || WinActive("ahk_exe CLIPStudio.exe") || WinActive("Clip Studio Paint")

; BASE — CLIP STUDIO
F16::SendClean("b")                 ; Brush
F15::SendClean("e")                 ; Eraser
F14::SendClean("g")                 ; Fill
F13::SendClean("{Esc}")             ; Cancel

F20::SendClean("p")                 ; Pen
F19::SendClean("m")                 ; Marquee
F18::SendClean("i")                 ; Eyedropper
F17::SendClean("h")                 ; Hand

F24::SendClean("r")                 ; Rotate
F23::SendClean("z")                 ; Zoom
F22::SendClean("o")                 ; Object
F21::SendClean("^z")                ; Undo

>+F16::SendClean("^t")              ; Transform
>+F15::SendClean("^0")              ; Reset Zoom
>+F14::SendClean("^s")              ; Save
>+F13::SendClean("^h")              ; Flip Horizontal

; LAYER 13 — QUICK TOOLS / SCRIPTS
>^F16::SendClean("p")               ; Pen
>^F15::SendClean("o")               ; Object
>^F14::SendClean("c")               ; Decoration
>^F13::SendClean("t")               ; Text

>^F20::SendClean("[")               ; Brush Size -
>^F19::SendClean("]")               ; Brush Size +
>^F18::SendClean("-")               ; Zoom Out
>^F17::SendClean("=")               ; Zoom In

>^F24::SendClean("^t")              ; Free Transform
>^F23::SendClean("^u")              ; Hue Saturation
>^F22::SendClean("^e")              ; Merge Down
>^F21::SendClean("^d")              ; Deselect

>!F16::SendClean("^c")              ; Copy
>!F15::SendClean("^v")              ; Paste
>!F14::SendClean("^x")              ; Cut
>!F13::SendClean("{Delete}")        ; Delete

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^a")              ; Select All
<^F15::SendClean("^d")              ; Deselect
<^F14::SendClean("^+i")             ; Invert Selection
<^F13::SendClean("^+u")             ; Clear

<^F20::SendClean("^+c")             ; Copy Merged
<^F19::SendClean("^+v")             ; Paste Special
<^F18::SendClean("^+x")             ; Cut Special
<^F17::SendClean("^+t")             ; Transform

<^F24::SendClean("^l")              ; New Layer
<^F23::SendClean("^m")              ; Merge Layer
<^F22::SendClean("^r")              ; Rasterize
<^F21::SendClean("^h")              ; Flip Horizontal

<+F16::SendClean("+b")              ; Alt Brush
<+F15::SendClean("+e")              ; Alt Eraser
<+F14::SendClean("+g")              ; Alt Fill
<+F13::SendClean("+m")              ; Alt Marquee

#HotIf
