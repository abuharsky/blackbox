# blackbox_jaspr_example

An example Jaspr app for `blackbox` and `blackbox_codegen`.

It mirrors the Flutter example with two demos:

- sync + async counter chain
- account + auth + profile flow

## Generate code

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Run in the browser

Compile the client app:

```bash
dart compile js lib/main.dart -o web/main.dart.js
```

Then serve the `web/` folder with any static file server.

## Persistence

The example uses `LocalStorageStore` from `blackbox_jaspr` for persistent boxes.
