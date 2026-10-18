import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';

const source = await readFile(new URL('../gnome/shiftdrop@local.shiftdrop/gesture.js', import.meta.url), 'utf8');
const {ShiftGesture} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('GNOME drag: first Shift shows, repeated Shift switches, release hides', () => {
    const gesture = new ShiftGesture();
    assert.equal(gesture.update(false, false), null);
    assert.equal(gesture.update(true, false), null);
    assert.equal(gesture.update(true, true), 'show');
    for (let i = 0; i < 20; i++) assert.equal(gesture.update(true, true), null);
    assert.equal(gesture.update(true, false), null);
    assert.equal(gesture.update(true, true), 'toggle');
    assert.equal(gesture.update(true, false), null);
    assert.equal(gesture.update(true, true), 'toggle');
    assert.equal(gesture.update(false, false), 'hide');
    assert.equal(gesture.update(false, false), null);
});

test('Shift held before a file drag still opens the wheel', () => {
    const gesture = new ShiftGesture();
    assert.equal(gesture.update(false, true), null);
    assert.equal(gesture.update(true, true), 'show');
    assert.equal(gesture.update(false, true), 'hide');
});
