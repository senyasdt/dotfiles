#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true

SendMode "Input"
SetKeyDelay 30, 30

; ============================================================
; Creative Macropad Profile — Universal Candidate
;
; Target firmware architecture:
;   layer 9  -> ZBrush base
;   layer 10 -> Blender base
;   layer 11 -> Fusion 360 base
;   layer 12 -> Clip Studio Paint base
;   layer 13 -> quick tools / brushes (MO(13))
;   layer 14 -> advanced workflow (TD(4): tap F21, hold MO(14))
;   layer 15 -> global service layer (TG(15))
;
; Important hardware nuance:
;   base layers 9-12 preserve physical Ctrl / Shift / Space / Alt keys
;   in firmware, because AHK handles those poorly for direct remapping.
;   Shared F-layers 13-15 are normalized and resolved via AHK.
;   layer 0 may switch into app bases directly:
;     TD(0) hold -> TO(12)
;     A+B -> TO(9), A+C -> TO(10), A+D -> TO(11)
;
; Base layer key families available to AHK:
;   F16..F13, F17, F24..F21, >+F16, >+F15, >+F13
;
; Shared layer families:
;   layer 13 -> >^F16..F13, >^F20..F17, >^F24..F21
;   layer 14 -> <^F16..F14, <^F20..F18, <^F24..F22, <+F16..F13
;   layer 15 -> <!F16..F13, <!F20..F17, <!F24..F21, <+F24..F21
;   service toggle combo -> F13 + F16 => TG(15)
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

CspSend(keys) {
    Critical 50
    ResetMods()
    Sleep 35
    SendEvent keys
    Sleep 35
    ResetMods()
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
; LAYER 15 — APP SERVICE / SYSTEM
; Sticky TG(15) layer with per-app service routing.
; ============================================================

#HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush")

<!F16::SendClean("^s")              ; Save
<!F15::SendClean("^+s")             ; Save As
<!F14::SendClean("^o")              ; Open
<!F13::SendClean("^n")              ; New

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

#HotIf WinActive("ahk_exe blender.exe") || WinActive("Blender")

<!F16::SendClean("^s")              ; Save
<!F15::SendClean("^+s")             ; Save As
<!F14::SendClean("^o")              ; Open
<!F13::SendClean("^n")              ; New

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

#HotIf WinActive("ahk_exe Fusion360.exe") || WinActive("Autodesk Fusion") || WinActive("Fusion")

<!F16::SendClean("^s")              ; Save
<!F15::SendClean("^+s")             ; Save As
<!F14::SendClean("^o")              ; Open
<!F13::SendClean("^n")              ; New

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

#HotIf WinActive("ahk_exe CLIPStudioPaint.exe") || WinActive("ahk_exe CLIPStudio.exe") || WinActive("Clip Studio Paint")

<!F16::CspSend("^s")                ; Save
<!F15::CspSend("^+s")               ; Save As
<!F14::CspSend("^o")                ; Open
<!F13::CspSend("^n")                ; New

<!F20::CspSend("^c")                ; Copy
<!F19::CspSend("^v")                ; Paste
<!F18::CspSend("#+s")               ; Screenshot Snip
<!F17::CspSend("#e")                ; Explorer

<!F24::CspSend("{Volume_Down}")     ; Volume Down
<!F23::CspSend("{Volume_Up}")       ; Volume Up
<!F22::CspSend("{Media_Play_Pause}") ; Media Play Pause
<!F21::CspSend("{Volume_Mute}")     ; Volume Mute

<+F24::CspSend("{Volume_Down}")     ; Lower Encoder Left
<+F23::CspSend("{Volume_Up}")       ; Lower Encoder Right
<+F22::CspSend("^-")                ; Upper Encoder Left / Zoom Out
<+F21::CspSend("^=")                ; Upper Encoder Right / Zoom In

#HotIf

; ============================================================
; ZBRUSH
; Base layer 9, quick layer 13, advanced layer 14
; ============================================================

#HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush")

; BASE LAYER 9 — ZBRUSH
F16::SendClean("^n")                ; Clear Tool
F15::Phys("t")                      ; Edit
F14::Phys("x")                      ; Symmetry
F13::SendClean("{Esc}")             ; Esc

F17::SendClean("^{F5}")             ; Solo

F24::Phys("q")                      ; Draw Mode
F23::Phys("w")                      ; Move
F22::Phys("b")                      ; Brush Palette
F21::SendClean("^z")                ; Undo

>+F16::SendClean("^+z")             ; Redo
>+F15::SendClean("+f")              ; PolyFrame
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

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^!c")             ; Clear Mask
<^F15::SendClean("^!b")             ; Blur Mask
<^F14::SendClean("^!s")             ; Sharpen Mask

<^F20::SendClean("^+i")             ; Invert Visibility
<^F19::SendClean("^!h")             ; HidePt
<^F18::SendClean("^!x")             ; Delete Hidden

<^F24::SendClean("^d")              ; Divide
<^F23::SendClean("+d")              ; Lower Subdivision
<^F22::SendClean("d")               ; Higher Subdivision

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

; BASE LAYER 10 — BLENDER
F16::SendClean("g")                 ; Grab Move
F15::SendClean("r")                 ; Rotate
F14::SendClean("s")                 ; Scale
F13::SendClean("{Esc}")             ; Cancel

F17::SendClean("{Tab}")             ; Edit Mode Toggle

F24::SendClean("1")                 ; Vertex Select
F23::SendClean("2")                 ; Edge Select
F22::SendClean("3")                 ; Face Select
F21::SendClean("^z")                ; Undo

>+F16::SendClean("{F3}")            ; Search
>+F15::SendClean("{NumpadDot}")     ; Frame Selected
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

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^c")              ; Copy
<^F15::SendClean("^v")              ; Paste
<^F14::SendClean("^x")              ; Cut

<^F20::SendClean("^+z")             ; Redo
<^F19::SendClean("!a")              ; Apply Menu
<^F18::SendClean("!m")              ; Merge By Distance

<^F24::SendClean("^a")              ; Select All
<^F23::SendClean("^i")              ; Invert Selection
<^F22::SendClean("^j")              ; Join

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

; BASE LAYER 11 — FUSION
F16::SendClean("q")                 ; Press Pull
F15::SendClean("m")                 ; Move Copy
F14::SendClean("f")                 ; Fillet
F13::SendClean("{Esc}")             ; Cancel

F17::SendClean("d")                 ; Dimension

F24::SendClean("p")                 ; Project
F23::SendClean("s")                 ; Sketch Palette
F22::SendClean("i")                 ; Inspect
F21::SendClean("^z")                ; Undo

>+F16::SendClean("l")               ; Line
>+F15::SendClean("a")               ; Arc
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

; LAYER 14 — ADVANCED WORKFLOW
<^F16::SendClean("^z")              ; Undo
<^F15::SendClean("^y")              ; Redo
<^F14::SendClean("^c")              ; Copy

<^F20::SendClean("^x")              ; Cut
<^F19::SendClean("^a")              ; Select All
<^F18::SendClean("^f")              ; Find

<^F24::SendClean("^s")              ; Save
<^F23::SendClean("^o")              ; Open
<^F22::SendClean("^n")              ; New Design

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

; BASE LAYER 12 — CLIP STUDIO
; Physical Space / Alt stay in firmware for pan and eyedropper behavior.
F16::CspSend("{Esc}")               ; Esc
F15::CspSend("h")                   ; Flip Canvas
F14::CspSend("^t")                  ; Transform
F13::CspSend("m")                   ; Marquee

F17::CspSend("g")                   ; Fill

F24::CspSend("b")                   ; Brush
F23::CspSend("e")                   ; Eraser
F22::CspSend("^z")                  ; Undo
F21::CspSend("l")                   ; Lasso

>+F16::CspSend("o")                 ; Move
>+F13::CspSend("^!r")               ; Reset Rotation (assign in CSP)

+PgDn::CspSend("[")                 ; Brush Size -
+PgUp::CspSend("]")                 ; Brush Size +
[::CspSend("^![")                   ; Rotate Canvas Left (assign in CSP)
]::CspSend("^!]")                   ; Rotate Canvas Right (assign in CSP)

; LAYER 13 — QUICK BRUSHES / SUBTOOLS
; These use dedicated custom shortcuts so the helper can show exact subtool names.
; Assign the same combos once in Clip Studio shortcut settings.
>^F16::CspSend("^!1")               ; G-Pen
>^F15::CspSend("^!2")               ; Pencil
>^F14::CspSend("^!3")               ; Textured Pen
>^F13::CspSend("^!4")               ; Soft Brush

>^F20::CspSend("^!5")               ; Watercolor
>^F19::CspSend("^!6")               ; Blend
>^F18::CspSend("^!7")               ; Smudge
>^F17::CspSend("^!8")               ; Airbrush

>^F24::CspSend("^!9")               ; Texture Brush
>^F23::CspSend("^!0")               ; Decoration Brush
>^F22::CspSend("^!-")               ; Favorite Brush 1
>^F21::CspSend("^!=")               ; Favorite Brush 2

; LAYER 14 — ADVANCED WORKFLOW
<^F16::CspSend("^+n")               ; New Raster Layer
<^F15::CspSend("^j")                ; Duplicate Layer
<^F14::CspSend("^e")                ; Merge Down

<^F20::CspSend("^+i")               ; Invert Selection
<^F19::CspSend("^d")                ; Deselect
<^F18::CspSend("^!l")               ; Liquify (assign in CSP)

<^F24::CspSend("^!g")               ; Clip To Layer Below
<^F23::CspSend("/")                 ; Lock Transparent Pixels
<^F22::CspSend("q")                 ; Quick Mask

<+F16::CspSend("^!r")               ; Reference Layer (assign in CSP)
<+F15::CspSend("^!s")               ; Symmetry Ruler (assign in CSP)
<+F14::CspSend("^!a")               ; Toggle Anti-Aliasing (assign in CSP)
<+F13::CspSend("^!m")               ; Temporary Transparent Color (assign in CSP)

<+F20::CspSend("^![")               ; Brush Hardness -
<+F19::CspSend("^!]")               ; Brush Hardness +
<+F18::CspSend("^![")               ; Canvas Rotate Left
<+F17::CspSend("^!]")               ; Canvas Rotate Right

#HotIf
