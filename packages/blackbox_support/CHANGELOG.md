## 0.0.9
- Bump `blackbox` constraint to `^0.10.0`.

## 0.0.8
- Bump `blackbox` constraint to `^0.9.0`.

## 0.0.7
- Update dependency: blackbox ^0.8.0

## 0.0.6
- Update dependency: blackbox ^0.7.0

## 0.0.5
- Update dependency: blackbox ^0.4.0
- Remove sync lateinit reaction tests (Box.lateinit removed)

## 0.0.4
- Fix infinite microtask loop when Reaction reads a lateinit box before graph initialization

## 0.0.3
- Fix Reaction.onRead() crash on lateinit boxes: defer subscription and schedule rebuild

## 0.0.2
- Update dependency: blackbox ^0.2.0

## 0.0.1
- Initial release with shared reaction runtime for Blackbox UI adapters.
