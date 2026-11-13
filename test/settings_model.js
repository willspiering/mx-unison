const assert = require('node:assert/strict')
const Model = require('../Model.js')
const remap = { keys: [
  { key: 0, label: 'Primary click', value: 80 },
  { key: '82', label: 'Middle button', value: 82 },
  { key: '999', label: 'New device control', value: 999 }
] }
const divert = { keys: [
  { key: 82, label: 'Middle button', value: 0 },
  { key: '195', label: 'Gesture button', value: 1 }
] }
const controls = Model.assignmentControls(remap, divert)
assert.deepEqual(controls.map(c => c.key), ['0', '82', '999', '195'])
assert.equal(controls[1].remap, remap.keys[1])
assert.equal(controls[1].divert, divert.keys[0])
assert.equal(controls[2].label, 'New device control')
assert.equal(controls[3].remap, null)
assert.deepEqual(Model.assignmentControls(null, null), [])
assert.equal(Model.assignmentControls(null, { keys: [{}, null, { key: '__proto__' }] }).length, 1)
const extras = [
  { name: 'pointer_speed', kind: 'range' },
  { name: 'report_rate', kind: 'choice' },
  { name: 'custom-remap', kind: 'map_choice' },
  { name: 'custom-lock', kind: 'multiple_toggle' }
]
assert.deepEqual(Model.remainingSettings({ settings: extras }, ['dpi']), extras)
console.log('Settings model checks passed')

// Pointer acceleration preferences ride along in status.json, keyed by device id.
const status = Model.parseStatus(JSON.stringify({
  ok: true, devices: [], pointer: { 'A1B2C3D4': { acceleration: 'mac' } }, pointerRuntime: { applied: ['logitech-mx-master-3s'], error: '' }
}))
assert.equal(status.hasPointer, true)
assert.equal(Model.pointerMode(status.pointer, 'A1B2C3D4'), 'mac')
assert.equal(Model.pointerMode(status.pointer, 'other'), 'system')
assert.equal(Model.pointerMode(null, 'A1B2C3D4'), 'system')
assert.equal(Model.pointerAccelerated(status.pointer, 'A1B2C3D4'), true)
assert.equal(Model.parseStatus('{"ok":true,"devices":[]}').hasPointer, false)
const patched = Model.patchPointerMode(status.pointer, 'ABC', 'mac')
assert.deepEqual(patched, { 'A1B2C3D4': { acceleration: 'mac' }, ABC: { acceleration: 'mac' } })
assert.deepEqual(Model.patchPointerMode(patched, 'A1B2C3D4', 'system'), { ABC: { acceleration: 'mac' } })
assert.deepEqual(status.pointer, { 'A1B2C3D4': { acceleration: 'mac' } }, 'patch must not mutate the snapshot')
assert.equal(Model.profileAccelerated({ name: 'Work', pointer: { acceleration: 'mac' } }), true)
assert.equal(Model.profileAccelerated({ name: 'Old' }), false)
assert.ok(Model.pointerAccelHelp().indexOf('macOS') !== -1)
// Selection: a pick made this session beats the persisted preference, so a
// keyboard saved by the popup cannot pin the settings window to itself.
assert.equal(Model.preferredDeviceId('keys', 'mouse', true), 'mouse')
assert.equal(Model.preferredDeviceId('keys', 'mouse', false), 'keys')
assert.equal(Model.preferredDeviceId('', 'mouse', false), 'mouse')
assert.equal(Model.preferredDeviceId(null, '', true), '')
assert.equal(Model.preferredDeviceId('keys', '', true), 'keys')
const pickList = [{ id: 'keys', kind: 'keyboard', online: true }, { id: 'mouse', kind: 'mouse', online: true }]
assert.equal(Model.pickDefaultDevice(pickList, Model.preferredDeviceId('keys', 'mouse', true), true).id, 'mouse')
assert.equal(Model.pickDefaultDevice(pickList, Model.preferredDeviceId('keys', 'keys', true), true).id, 'keys')
// Buttons list summary: software actions, overrides and hardware state.
const back = { key: '83', label: 'Back Button', remap: null,
  divert: { key: '83', value: 0, choices: [{ id: 0, name: 'Regular' }, { id: 1, name: 'Diverted' }, { id: 2, name: 'Mouse Gestures' }] } }
const binds = [
  { device: 'm', control: '83', app: '', mode: 'shortcut', shortcut: 'ALT+Left', gestures: {} },
  { device: 'm', control: '83', app: 'zed', mode: 'shortcut', shortcut: 'CTRL+minus', gestures: {} },
  { device: 'm', control: '83', app: 'chromium', mode: 'shortcut', shortcut: 'ALT+Left', gestures: {} },
  { device: 'm', control: '82', app: '', mode: 'gesture', shortcut: 'CTRL+t', gestures: { up: 'SUPER+Up' } }
]
const backState = Model.controlState(back, binds)
assert.equal(backState.binding.shortcut, 'ALT+Left')
assert.deepEqual(backState.overrides, ['chromium', 'zed'])
assert.equal(backState.software, true)
assert.equal(backState.gestures, true)
assert.equal(backState.remapped, '')
assert.equal(backState.diverted, '')
const left = { key: '80', label: 'Left Button', divert: null,
  remap: { key: '80', value: 81, choices: [{ id: 80, name: 'Left Click' }, { id: 81, name: 'Right Click' }] } }
const leftState = Model.controlState(left, binds)
assert.equal(leftState.binding, null)
assert.equal(leftState.software, false)
assert.equal(leftState.remapped, 'Right Click')
assert.equal(Model.controlState(Object.assign({}, left, { remap: Object.assign({}, left.remap, { value: 80 }) }), []).remapped, '')
const ruled = Object.assign({}, back, { divert: Object.assign({}, back.divert, { value: { id: 1, name: 'Diverted' } }) })
assert.equal(Model.controlState(ruled, []).diverted, 'Diverted')
assert.equal(Model.controlState(null, null).binding, null)
assert.equal(Model.stepsSummary('CTRL+c\n\nCTRL+v'), 'CTRL+c → CTRL+v')
console.log('Pointer model checks passed')
