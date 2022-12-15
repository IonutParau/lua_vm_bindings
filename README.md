# Lua VM Bindings

A simple set of basic bindings for Lua.
These bindings are written purely in Dart, and use `dart:ffi` to communicate directly to liblua.

# Initializing the state

```dart
// Specify the path to library. Used by all LuaStates.
LuaState.loadLibLua(windows: 'path/to/dll', macos: 'path/to/dylib', linux: 'path/to/so');

final luaState = LuaState();
```

# Cleaning up the state

```dart
// Frees up the memory allocated by Lua.
// Only call this once when the lua VM itself is no longer needed, not when the binding is no longer needed!
luaState.destroy();
```

# Using Functions

Due to the restrictions on converting Dart functions to C function pointers, you need to convert the functions over yourself.

```dart
int returnTrue(Pointer p) {
  final ls = LuaState(pointer: p);

  ls.pushBoolean(true);

  return 1;
}

void main() {
  LuaState.loadLibLua(/* paths here */);

  final luaState = LuaState();

  // Push the function.
  luaState.pushCFunction(LuaNativeFunctionPointer.fromFunction(returnTrue));

  // At the end
  luaState.destroy();
}

```

# Running examples

First clone this repository:

```sh
git clone https://github.com/IonutParau/lua_vm_bindings 'lua_vm_bindings'
```

Then cd into the newly-made directory and run an example like so:

```dart
dart run example/<example>.dart
```
