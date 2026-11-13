const assert = require('node:assert/strict')
const Model = require('../Model.js')

// Bluetooth mouse: host list with names; currently on channel 2.
const mouse = { id: 'mouse', kind: 'mouse', hosts: [
  { index: 0, name: 'laptop', paired: true, current: false },
  { index: 1, name: 'desktop', paired: true, current: true },
  { index: 2, name: '', paired: false, current: false }
], settings: [{ name: 'change-host', value: 0, choices: [{ id: 0, name: '1' }, { id: 1, name: '2' }, { id: 2, name: '3' }] }] }
// Receiver keyboard: no host list, names only in Solaar's change-host choices.
const keyboard = { id: 'keys', kind: 'keyboard', hosts: [], settings: [{ name: 'change-host', value: 1,
  choices: [{ id: 0, name: '1:laptop' }, { id: 1, name: '2:desktop' }, { id: 2, name: '3' }] }] }

const ch = Model.deviceChannels(keyboard)
assert.equal(ch[0].name, 'laptop')
assert.equal(ch[1].current, true)
assert.equal(ch[2].name, undefined)
// hosts[].current wins over a stale change-host value.
assert.equal(Model.deviceChannels(mouse)[1].current, true)
assert.equal(Model.deviceChannels(mouse)[0].current, undefined)

const config = { version: 1, keyboard: 'keys', follow: true, members: { keys: [0, 1, 2], mouse: [0, 1, 2] } }
const targets = Model.deskTargets(config, [mouse, keyboard])
assert.deepEqual(targets.map(t => t.label), ['laptop', 'desktop', 'Computer 3'])
assert.deepEqual(targets.map(t => t.here), [false, true, false])
assert.deepEqual(targets.map(t => t.available), [true, true, false])

// Different channel per device: target 1 is keyboard ch1 + mouse ch3.
const crossed = { version: 1, keyboard: 'keys', follow: false, members: { keys: [0, 1, 2], mouse: [2, 1, 0] } }
const t2 = Model.deskTargets(crossed, [mouse, keyboard])
assert.equal(t2[0].label, 'laptop')        // keyboard name preferred
assert.equal(t2[0].available, false)       // mouse channel 3 is unpaired
assert.equal(t2[1].here, true)

// Missing member: nothing is "here"; empty group gives no targets.
assert.equal(Model.deskTargets(config, [keyboard]).some(t => t.here), false)
assert.deepEqual(Model.deskTargets({ members: {} }, [mouse]), [])
assert.deepEqual(Model.deskTargets(null, null), [])

// Host names are device-supplied: markup is escaped.
const evil = { id: 'keys', hosts: [{ index: 0, name: '<b>x</b>', current: true }] }
assert.equal(Model.deskTargets({ keyboard: 'keys', members: { keys: [0, 1, 2] } }, [evil])[0].label, '&lt;b&gt;x&lt;/b&gt;')

// Raw names are kept alongside the escaped label for plain-text sinks.
assert.equal(Model.deskTargets({ keyboard: 'keys', members: { keys: [0, 1, 2] } }, [evil])[0].name, '<b>x</b>')
assert.equal(targets[2].name, '')

// Auto-fill: a mouse joining a keyboard-only group gets channels matched by
// host name, whatever order the mouse stores them in.
const swapped = { id: 'mouse', kind: 'mouse', hosts: [
  { index: 0, name: 'Desktop ', paired: true },
  { index: 1, name: '', paired: false },
  { index: 2, name: 'laptop', paired: true }
] }
const kbOnly = { version: 1, keyboard: 'keys', follow: false, members: { keys: [0, 1, 2] } }
assert.deepEqual(Model.matchChannels(kbOnly, [keyboard, swapped], 'mouse'), [2, 0, 1])
// The keyboard's own mapping decides which computer is which target.
const kbCrossed = { version: 1, keyboard: 'keys', follow: false, members: { keys: [1, 0, 2] } }
assert.deepEqual(Model.matchChannels(kbCrossed, [keyboard, swapped], 'mouse'), [0, 2, 1])
// Already a member: names win, unmatched targets keep the existing channel.
const member = { version: 1, keyboard: 'keys', follow: false, members: { keys: [0, 1, 2], mouse: [0, 1, 2] } }
assert.deepEqual(Model.matchChannels(member, [keyboard, swapped], 'mouse'), [2, 0, 1])
// No names anywhere: keep the current mapping, or the identity for a new device.
const bare = { id: 'bare', hosts: [] }
const bareGroup = { version: 1, keyboard: '', follow: false, members: { bare: [2, 0, 1] } }
assert.deepEqual(Model.matchChannels(bareGroup, [bare], 'bare'), [2, 0, 1])
assert.deepEqual(Model.matchChannels({ members: {} }, [bare], 'bare'), [0, 1, 2])
assert.deepEqual(Model.matchChannels(null, null, 'missing'), [0, 1, 2])
// Duplicate names never produce a repeated channel.
const dup = { id: 'dup', hosts: [{ index: 0, name: 'laptop' }, { index: 1, name: 'laptop' }, { index: 2, name: 'laptop' }] }
const dupOut = Model.matchChannels(kbOnly, [keyboard, dup], 'dup')
assert.deepEqual(dupOut.slice().sort(), [0, 1, 2])
assert.equal(dupOut[0], 0)

console.log('Desk target checks passed')
