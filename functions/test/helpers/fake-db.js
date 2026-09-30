'use strict';

/**
 * Minimal in-memory RTDB double for unit-testing the backend logic without
 * the Firebase emulator. Supports:
 *   - ref(path).once('value') with orderByKey/startAt/endAt and
 *     orderByChild/equalTo
 *   - ref(path).transaction(fn)
 *   - ref().update(map) (multi-path, atomic from the caller's perspective)
 */

function setAt(root, path, value) {
  const parts = path.split('/').filter(Boolean);
  let node = root;
  for (let i = 0; i < parts.length - 1; i++) {
    if (node[parts[i]] === undefined || node[parts[i]] === null || typeof node[parts[i]] !== 'object') {
      node[parts[i]] = {};
    }
    node = node[parts[i]];
  }
  const last = parts[parts.length - 1];
  if (value === null || value === undefined) {
    delete node[last];
  } else {
    node[last] = value;
  }
}

function getAt(root, path) {
  const parts = path.split('/').filter(Boolean);
  let node = root;
  for (const part of parts) {
    if (node === null || node === undefined || typeof node !== 'object') return undefined;
    node = node[part];
  }
  return node;
}

class FakeRef {
  constructor(db, path, {
    orderByKey = false,
    startAt = null,
    endAt = null,
    equalTo = undefined,
    hasEqual = false,
    orderByChild = null,
  } = {}) {
    this.db = db;
    this.path = path;
    this._orderByKey = orderByKey;
    this._startAt = startAt;
    this._endAt = endAt;
    this._equalTo = equalTo;
    this._hasEqual = hasEqual;
    this._orderByChild = orderByChild;
  }

  child(name) {
    return new FakeRef(this.db, `${this.path}/${name}`);
  }

  orderByKey() {
    return new FakeRef(this.db, this.path, { orderByKey: true, startAt: this._startAt, endAt: this._endAt, equalTo: this._equalTo, hasEqual: this._hasEqual });
  }

  startAt(key) {
    return new FakeRef(this.db, this.path, { orderByKey: this._orderByKey, startAt: key, endAt: this._endAt, equalTo: this._equalTo, hasEqual: this._hasEqual, orderByChild: this._orderByChild });
  }

  endAt(key) {
    return new FakeRef(this.db, this.path, { orderByKey: this._orderByKey, startAt: this._startAt, endAt: key, equalTo: this._equalTo, hasEqual: this._hasEqual, orderByChild: this._orderByChild });
  }

  orderByChild(field) {
    return new FakeRef(this.db, this.path, { orderByChild: field });
  }

  equalTo(value) {
    return new FakeRef(this.db, this.path, {
      orderByKey: this._orderByKey,
      startAt: this._startAt,
      endAt: this._endAt,
      equalTo: value,
      hasEqual: true,
      orderByChild: this._orderByChild,
    });
  }

  async once() {
    let value = getAt(this.db.data, this.path);
    if (this._orderByKey && value && typeof value === 'object') {
      const filtered = {};
      for (const [key, v] of Object.entries(value)) {
        if (this._startAt !== null && key < this._startAt) continue;
        if (this._endAt !== null && key > this._endAt) continue;
        filtered[key] = v;
      }
      value = Object.keys(filtered).length > 0 ? filtered : null;
    }
    if (this._hasEqual && value && typeof value === 'object') {
      const field = this._orderByChild || 'id';
      const filtered = {};
      for (const [key, v] of Object.entries(value)) {
        if (v && typeof v === 'object' && String(v[field]) === String(this._equalTo)) {
          filtered[key] = v;
        }
      }
      value = Object.keys(filtered).length > 0 ? filtered : null;
    }
    return { val: () => (value === undefined ? null : value) };
  }

  async set(value) {
    setAt(this.db.data, this.path, value);
  }

  async update(value) {
    if (this.path === '') {
      for (const [path, v] of Object.entries(value)) setAt(this.db.data, path, v);
      return;
    }
    const current = getAt(this.db.data, this.path) || {};
    const merged = { ...current };
    for (const [key, v] of Object.entries(value)) {
      if (v === null || v === undefined) delete merged[key];
      else merged[key] = v;
    }
    setAt(this.db.data, this.path, merged);
  }

  async transaction(fn, applyLocally = false, completeOnExisting = false) {
    const current = getAt(this.db.data, this.path);
    const result = fn(current === undefined ? null : current);
    if (result === undefined) {
      return { committed: false, snapshot: { val: () => (current === undefined ? null : current) } };
    }
    setAt(this.db.data, this.path, result);
    return { committed: true, snapshot: { val: () => result } };
  }
}

class FakeDatabase {
  constructor(seed = {}) {
    this.data = JSON.parse(JSON.stringify(seed));
  }

  ref(path = '') {
    return new FakeRef(this, path);
  }
}

module.exports = { FakeDatabase, getAt, setAt };
