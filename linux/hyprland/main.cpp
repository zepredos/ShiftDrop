#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/protocols/core/DataDevice.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <optional>
#include <stdexcept>

#include "Gesture.hpp"

namespace {
ShiftGesture gesture;
SP<CEventLoopTimer> timer;
CHyprSignalListener openedListener;
std::optional<Vector2D> anchor;
PHLWINDOWREF positioned;

bool isWheel(PHLWINDOW window) {
    return window && window->m_class == "io.github.shiftdrop.ShiftDrop" && window->m_title == "ShiftDrop Wheel";
}

void send(const std::string& event) {
    g_pEventManager->postEvent({"shiftdrop", event});
}

void prepare(PHLWINDOW window) {
    if (!isWheel(window) || !anchor)
        return;
    using namespace Desktop::Types;
    window->m_isFloating = true;
    window->m_ruleApplicator->noFocus().set(true, PRIORITY_SET_PROP);
    window->m_ruleApplicator->noAnim().set(true, PRIORITY_SET_PROP);
    window->m_ruleApplicator->decorate().set(false, PRIORITY_SET_PROP);
    window->m_ruleApplicator->borderSize().set(0, PRIORITY_SET_PROP);
}

void placeWheel() {
    if (!anchor)
        return;
    for (const auto& window : Desktop::windowState()->windows()) {
        if (!isWheel(window) || !window->m_isMapped || positioned.lock() == window)
            continue;
        Vector2D position = *anchor - Vector2D{190, 190};
        for (const auto& monitor : State::monitorState()->monitors()) {
            const auto origin = monitor->m_position;
            const auto size = monitor->m_size;
            if (anchor->x < origin.x || anchor->x >= origin.x + size.x || anchor->y < origin.y || anchor->y >= origin.y + size.y)
                continue;
            position.x = std::clamp(position.x, origin.x, std::max(origin.x, origin.x + size.x - 380));
            position.y = std::clamp(position.y, origin.y, std::max(origin.y, origin.y + size.y - 380));
            break;
        }
        prepare(window);
        Config::Actions::floatWindow(Config::Actions::TOGGLE_ACTION_ENABLE, window);
        Config::Actions::resize({380, 380}, false, window);
        Config::Actions::move(position, false, window);
        window->finishAnimation();
        Desktop::windowState()->raise(window);
        positioned = window;
        g_pInputManager->simulateMouseMovement();
        return;
    }
}

void tick() {
    const bool dragging = PROTO::data && PROTO::data->dndActive();
    const bool shift = dragging && (g_pInputManager->getModsFromAllKBs() & HL_MODIFIER_SHIFT);
    // shortcut: 0.56.2 exposes active DND, not its MIME list; Qt rejects non-file drops.
    // Use a MIME accessor when Hyprland exposes one to plugins.
    switch (gesture.update(dragging, shift)) {
        case WheelAction::Show: {
            anchor = Pointer::mgr()->position();
            positioned.reset();
            send(std::format("show,{},{}", std::lround(anchor->x), std::lround(anchor->y)));
            break;
        }
        case WheelAction::Toggle: send("toggle"); break;
        case WheelAction::Hide:
            send("hide");
            anchor.reset();
            positioned.reset();
            break;
        case WheelAction::None: break;
    }
    placeWheel();
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string_view{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
        throw std::runtime_error("ShiftDrop: rebuild the plugin against the exact running Hyprland package.");
    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.tag != "v0.56.2" && version.tag != "0.56.2")
        throw std::runtime_error("ShiftDrop currently targets Hyprland 0.56.2.");
    openedListener = Event::bus()->m_events.window.openEarly.listen([](PHLWINDOW window) { prepare(window); });
    timer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(35), [](SP<CEventLoopTimer> self, void*) {
        tick();
        self->updateTimeout(std::chrono::milliseconds(35));
    }, nullptr);
    g_pEventLoopManager->addTimer(timer);
    return {"shiftdrop", "ShiftDrop drag + Shift wheel", "zepredos", "0.2.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (timer) {
        timer->cancel();
        g_pEventLoopManager->removeTimer(timer);
        timer.reset();
    }
    openedListener.reset();
    send("hide");
    anchor.reset();
    positioned.reset();
    gesture = {};
}
