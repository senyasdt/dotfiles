#Requires AutoHotkey v2.0
#SingleInstance Force

SendMode "Input"
SetKeyDelay 30, 30

; ============================================================
; ZBrush Macropad Profile
; Работает только когда активно окно ZBrush
; ============================================================

#HotIf WinActive("ahk_exe ZBrush.exe") || WinActive("ZBrush")


; ============================================================
; HELPERS
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
    SetScrollLockState false
}

BrushZ(seq) {
    ; Отпускаем все модификаторы, потому что слои Vial используют Ctrl/Alt/Shift
    Send "{LCtrl up}{RCtrl up}{LShift up}{RShift up}{LAlt up}{RAlt up}{Ctrl up}{Shift up}{Alt up}"
    Sleep 50

    ; Отправляем B отдельно
    SendEvent "{b down}"
    Sleep 30
    SendEvent "{b up}"

    ; Даём ZBrush время открыть палитру кистей
    Sleep 120

    ; Отправляем остальные буквы по одной
    Loop Parse seq {
        ch := A_LoopField
        SendEvent "{" ch " down}"
        Sleep 30
        SendEvent "{" ch " up}"
        Sleep 50
    }
}

Brush(seq) {
    ; Для выбора кистей через B + буква + буква.
    ; Перед отправкой отпускаем модификаторы, потому что слои Vial
    ; используют Ctrl/Alt/Shift-комбинации.
    Send "{Ctrl up}{Shift up}{Alt up}"
    Sleep 30
    Send seq
}

Tap(keys) {
    Send "{Ctrl up}{Shift up}{Alt up}"
    Sleep 20
    Send keys
}

HoldKey(key) {
    Send "{" key " down}"
}

ReleaseKey(key) {
    Send "{" key " up}"
}

F12::KeyHistory
; ============================================================
; LAYER 1 — ОСНОВНАЯ РАБОТА
; Plain F13–F24 + RShift F13–F15
; ============================================================

; Верхний ряд
F16::Send "^n"          ; Clear tool
F15::Phys("t")         ; Edit
F14::Phys("x")           ; Symmetry
F13::Send "{Esc}"           ; Esc

F17::Send "^{F5}"          ; Solo

; Третий ряд — режимы / вид
F24::Phys("q")           ; Draw mode
F23::Phys("w")           ; Move
F22::Phys("b")           ; All Brushes
F21::Send "^z"            ; Undo

; Нижний ряд
>+F15::Send "f"         ; Frame / Fit
>+F14::Send "p"         ; Perspective
>+F13::{                ; DynaMesh
    KeyWait "F13"
    ResetMods()
    Sleep 20
    Send "^{F11}"
    Sleep 20
    ResetMods()
}

; Энкодеры Layer 1
PgDn::Send "["          ; Brush Size -
PgUp::Send "]"          ; Brush Size +

>+PgDn::Send "{NumpadSub}" ; Zoom out
>+PgUp::Send "{NumpadAdd}" ; Zoom in


; ============================================================
; LAYER 2 — КИСТИ
; RCtrl+F13–F24 + RAlt+F13–F16
; ============================================================

; Основные sculpt brushes
>^F16::BrushZ("st")     ; Standard
>^F15::BrushZ("cb")     ; ClayBuildup
>^F14::BrushZ("ds")     ; DamStandard
>^F13::BrushZ("mv")     ; Move

>^F20::BrushZ("in")     ; Inflate
>^F19::BrushZ("pi")     ; Pinch
>^F18::BrushZ("cl")     ; Clay
>^F17::BrushZ("mt")     ; Move Topological

>^F24::BrushZ("td")     ; TrimDynamic
>^F23::BrushZ("hp")     ; hPolish
>^F22::BrushZ("sk")     ; SnakeHook
>^F21::BrushZ("ma")     ; MaskPen / Mask brush

; Нижний ряд слоя кистей
>!F16::BrushZ("cr")     ; Crease / если отличается — поменяешь
>!F15::BrushZ("mo")     ; Morph / запас
>!F14::BrushZ("si")     ; Smooth stronger / запас
>!F13::BrushZ("zb")     ; ZModeler / запас

; Энкодеры Layer 2
>!F20::Send "["         ; Brush Size -
>!F19::Send "]"         ; Brush Size +
>!F18::Send "s"         ; Draw Size popup
>!F17::Send "u"         ; Z Intensity popup


; ============================================================
; LAYER 3 — УТИЛИТЫ / МАСКИ / ПОЛИГРУППЫ
; LCtrl+F13–F24 + LShift+F13–F16
; ============================================================

; Маски
<^F16::Send "^!c"       ; Clear Mask — назначить в ZBrush
<^F15::Send "^!b"       ; Blur Mask — назначить в ZBrush
<^F14::Send "^!s"       ; Sharpen Mask — назначить в ZBrush
<^F13::Send "^w"        ; Group Masked / Polygroup

; Visibility / selection
<^F20::Send "^+i"       ; Invert visibility / если назначишь
<^F19::Send "^!h"       ; HidePt / кастом
<^F18::Send "^!x"       ; Delete Hidden / кастом
<^F17::Send "^+a"       ; Show all / кастом

; Geometry
<^F24::Send "^d"        ; Divide
<^F23::Send "+d"        ; Lower Subdivision
<^F22::Send "d"         ; Higher Subdivision / Dynamic Subdiv
<^F21::Send "^!d"       ; Dynamesh — назначить в ZBrush

; Нижний ряд утилит
<+F16::Send "!s"        ; Solo
<+F15::Send "+f"        ; PolyFrame
<+F14::Send "^!m"       ; Mirror And Weld — назначить
<+F13::Send "^!r"       ; ZRemesher — назначить

; Энкодеры Layer 3
<+F20::Send "+d"        ; Lower Subdivision
<+F19::Send "d"         ; Higher Subdivision
<+F18::Send "^z"        ; Undo
<+F17::Send "^+z"       ; Redo


; ============================================================
; LAYER 4 — СИСТЕМНЫЙ / PROJECT
; LAlt+F13–F24 + LShift+F21–F24 + RShift+F21–F24
; ============================================================

; Файл / проект
<!F16::Send "^s"        ; Save
<!F15::Send "^+s"       ; Save As
<!F14::Send "^o"        ; Open
<!F13::Send "^n"        ; New

; UI / окно
<!F20::Send "{Tab}"     ; Hide/Show UI
<!F19::Send "f"         ; Frame
<!F18::Send "p"         ; Perspective
<!F17::Send "{Esc}"     ; Cancel / close menu

; Системные
<!F24::Send "#+s"       ; Win+Shift+S screenshot
<!F23::Send "!{Tab}"    ; Alt+Tab
<!F22::Send "{PrintScreen}"
<!F21::Send "{Esc}"

; Нижний ряд Layer 4
<+F24::Send "{Volume_Down}"
<+F23::Send "{Volume_Up}"
<+F22::Send "{Volume_Mute}"
<+F21::Send "{Media_Play_Pause}"

; Энкодеры Layer 4
>+F24::Send "{Volume_Down}"
>+F23::Send "{Volume_Up}"
>+F22::Send "{WheelDown}"
>+F21::Send "{WheelUp}"


#HotIf
