#include "../hyprland/Gesture.hpp"
#include <cassert>

int main() {
    ShiftGesture gesture;
    assert(gesture.update(false, true) == WheelAction::None);
    assert(gesture.update(true, true) == WheelAction::Show);
    assert(gesture.update(true, true) == WheelAction::None);
    assert(gesture.update(true, false) == WheelAction::None);
    assert(gesture.update(true, true) == WheelAction::Toggle);
    assert(gesture.update(true, true) == WheelAction::None);
    assert(gesture.update(true, false) == WheelAction::None);
    assert(gesture.update(true, true) == WheelAction::Toggle);
    assert(gesture.update(false, false) == WheelAction::Hide);
    assert(gesture.update(false, false) == WheelAction::None);
    assert(gesture.update(true, false) == WheelAction::None);
    assert(gesture.update(true, true) == WheelAction::Show);
}
