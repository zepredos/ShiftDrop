import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {ShiftGesture} from './gesture.js';

const BUS = 'io.github.shiftdrop.ShiftDrop';
const PATH = '/io/github/shiftdrop/ShiftDrop';
const INTERFACE = BUS;

export default class ShiftDropExtension extends Extension {
    enable() {
        this._gesture = new ShiftGesture();
        this._enabled = true;
        this._timer = 0;
        this._hideTimer = 0;
        this._selection = global.display.get_selection();
        this._cancellable = new Gio.Cancellable();
        this._position = null;
        this._positionedWindow = null;
        this._indicator = new PanelMenu.Button(0.0, 'ShiftDrop');
        this._indicator.add_child(new St.Icon({icon_name: 'view-refresh-symbolic', style_class: 'system-status-icon'}));
        const open = new PopupMenu.PopupMenuItem('Open ShiftDrop');
        open.connect('activate', () => this._call('Open', null));
        this._indicator.menu.addMenuItem(open);
        this._pause = new PopupMenu.PopupSwitchMenuItem('Pause drag + Shift', false);
        this._indicator.menu.addMenuItem(this._pause);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
        this._ownerSignal = this._selection.connect('owner-changed', (_selection, type, owner) => {
            if (type !== Meta.SelectionType.SELECTION_DND)
                return;
            this._dragging = Boolean(owner);
            if (this._dragging && !this._timer) {
                this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 35, () => this._tick());
            } else if (!this._dragging) {
                this._tick();
            }
        });
    }

    _tick() {
        if (!this._enabled)
            return GLib.SOURCE_REMOVE;
        const [x, y, modifiers] = global.get_pointer();
        const types = this._selection.get_mimetypes(Meta.SelectionType.SELECTION_DND) ?? [];
        const dragging = Boolean(this._dragging && (modifiers & Clutter.ModifierType.BUTTON1_MASK) && types.includes('text/uri-list'));
        const action = this._gesture.update(dragging && !this._pause.state,
            Boolean(modifiers & Clutter.ModifierType.SHIFT_MASK));
        if (action === 'show') {
            if (this._hideTimer) {
                GLib.Source.remove(this._hideTimer);
                this._hideTimer = 0;
            }
            this._position = {x, y};
            this._positionedWindow = null;
            this._call('ShowWheel', new GLib.Variant('(iib)', [x, y, false]));
        } else if (action === 'toggle') {
            this._call('ToggleWheel', null);
        } else if (action === 'hide' && !this._hideTimer) {
            this._position = null;
            // Give Qt time to accept the copy drop before hiding its destination.
            this._hideTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 180, () => {
                this._hideTimer = 0;
                this._call('HideWheel', null);
                return GLib.SOURCE_REMOVE;
            });
        }
        if (this._position)
            this._positionWheel();
        if (!this._dragging) {
            if (this._timer)
                GLib.Source.remove(this._timer);
            this._timer = 0;
            return GLib.SOURCE_REMOVE;
        }
        return GLib.SOURCE_CONTINUE;
    }

    _positionWheel() {
        // Wayland clients cannot place themselves globally. Only move our wheel.
        for (const actor of global.get_window_actors()) {
            const window = actor.get_meta_window();
            if (window.get_title() !== 'ShiftDrop Wheel' ||
                ![window.get_wm_class(), window.get_gtk_application_id()].includes(BUS))
                continue;
            const id = window.get_stable_sequence();
            if (this._positionedWindow === id)
                return;
            const monitor = Main.layoutManager.monitors.find(m =>
                this._position.x >= m.x && this._position.x < m.x + m.width &&
                this._position.y >= m.y && this._position.y < m.y + m.height);
            if (!monitor)
                return;
            const x = Math.round(Math.max(monitor.x, Math.min(this._position.x - 190, monitor.x + monitor.width - 380)));
            const y = Math.round(Math.max(monitor.y + 30, Math.min(this._position.y - 190, monitor.y + monitor.height - 380)));
            window.move_frame(false, x, y);
            this._positionedWindow = id;
            return;
        }
    }

    _call(method, parameters) {
        Gio.DBus.session.call(BUS, PATH, INTERFACE, method, parameters, null,
            Gio.DBusCallFlags.NONE, 5000, this._cancellable, (connection, result) => {
                try {
                    connection.call_finish(result);
                } catch (error) {
                    if (this._enabled && !error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED)) {
                        console.warn(`ShiftDrop ${method}: ${error.message}`);
                        if (method === 'ShowWheel' || method === 'Open')
                            Main.notify('ShiftDrop', 'Install the ShiftDrop desktop app first, then try again.');
                    }
                }
            });
    }

    disable() {
        this._enabled = false;
        this._cancellable.cancel();
        if (this._timer)
            GLib.Source.remove(this._timer);
        if (this._hideTimer)
            GLib.Source.remove(this._hideTimer);
        this._selection.disconnect(this._ownerSignal);
        Gio.DBus.session.call(BUS, PATH, INTERFACE, 'HideWheel', null, null,
            Gio.DBusCallFlags.NO_AUTO_START, 1000, null, (connection, result) => {
                try { connection.call_finish(result); } catch { /* App may already be closed. */ }
            });
        this._indicator.destroy();
        this._selection = this._indicator = this._pause = this._gesture = this._cancellable = null;
        this._position = this._positionedWindow = null;
        this._timer = this._hideTimer = this._ownerSignal = 0;
    }
}
