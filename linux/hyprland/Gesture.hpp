#pragma once

enum class WheelAction { None, Show, Toggle, Hide };

struct ShiftGesture {
    bool opened = false;
    bool shiftDown = false;

    WheelAction update(bool dragging, bool shift) {
        const bool pressed = shift && !shiftDown;
        shiftDown = shift;
        if (!dragging) {
            const bool wasOpen = opened;
            opened = false;
            return wasOpen ? WheelAction::Hide : WheelAction::None;
        }
        if (!opened && shift) {
            opened = true;
            return WheelAction::Show;
        }
        return opened && pressed ? WheelAction::Toggle : WheelAction::None;
    }
};
