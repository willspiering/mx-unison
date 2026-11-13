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
console.log('Pointer model checks passed')
