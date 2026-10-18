// No Shell imports: the drag/Shift transitions are tested with Node as well as Python.
export class ShiftGesture {
    constructor() {
        this.opened = false;
        this.shiftDown = false;
    }

    update(dragging, shift) {
        const pressed = shift && !this.shiftDown;
        this.shiftDown = shift;
        if (!dragging) {
            const hadWheel = this.opened;
            this.opened = false;
            return hadWheel ? 'hide' : null;
        }
        if (!this.opened && shift) {
            this.opened = true;
            return 'show';
        }
        return this.opened && pressed ? 'toggle' : null;
    }
}
