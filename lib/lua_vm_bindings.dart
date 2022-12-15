import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The type of a C function in Lua.
typedef LuaCFunction = int Function(Pointer);

/// The type for a native C function in Lua.
typedef LuaNativeFunction = Int32 Function(Pointer);

/// The type for a native C function pointer in Lua.
typedef LuaNativeFunctionPointer = Pointer<NativeFunction<LuaNativeFunction>>;

late DynamicLibrary _libLua;

/// Container for the types of errors Lua can have
enum LuaThreadStatus {
  ok,
  yield,
  runtimeError,
  syntaxError,
  memoryError,
  error,
}

/// Container for a Lua type.
enum LuaType {
  nil,
  boolean,
  lightuserdata,
  number,
  string,
  table,
  function,
  userdata,
  thread,
  none,
}

/// Container for a LuaState from the Lua DLL.
class LuaState {
  DynamicLibrary? dll;

  static void loadLibLua({String? windows, String? linux, String? macos}) {
    _libLua = DynamicLibrary.open(Platform.isLinux ? linux! : (Platform.isWindows ? windows! : macos!));
  }

  LuaState({
    this.dll,
    Pointer? pointer,
  }) {
    dll ??= _libLua;
    if (pointer != null) {
      statePtr = pointer;
    }
    _init(pointer == null);
  }

  /// The pointer to the lua_State.
  late Pointer statePtr;

  void Function(Pointer)? _destroyer;

  void _init(bool allocState) {
    if (allocState) {
      final newState = dll!.lookupFunction<Pointer Function(), Pointer Function()>("luaL_newstate");
      statePtr = newState();
    }
  }

  /// Erase a lua_State pointer.
  void destroy() {
    _destroyer ??= dll!.lookupFunction<Void Function(Pointer), void Function(Pointer)>('lua_close');

    _destroyer!(statePtr);
  }

  void Function(Pointer ls)? _openLibsFn;

  void openLibs() {
    _openLibsFn ??= dll!.lookupFunction<Void Function(Pointer), void Function(Pointer)>('luaL_openlibs');

    _openLibsFn!(statePtr);
  }

  void Function(Pointer)? _errorFn;

  /// Raises a Lua error, using the value on the top of the stack as the error object.
  void error() {
    _errorFn ??= dll!.lookupFunction<Int Function(Pointer), int Function(Pointer)>('lua_error');

    _errorFn!(statePtr);
  }

  Pointer Function(Pointer, Pointer)? _atPanicFn;

  /// Sets the panic handler of this LuaState and returns the old one. Takes in a C Function Pointer.
  Pointer atPanic(Pointer cFunc) {
    _atPanicFn ??= dll!.lookupFunction<Pointer Function(Pointer, Pointer), Pointer Function(Pointer, Pointer)>('lua_atpanic');

    return _atPanicFn!(statePtr, cFunc);
  }

  void Function(Pointer, int, int)? _callFn;

  /// Binding to `lua_call`. `args` is amount of arguments to pop and call it with, calls the value just before the arguments, pops the called value, and then pushes `returns` amount of returned values.
  void call(int args, int returns) {
    _callFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int), void Function(Pointer, int, int)>('lua_call');

    _callFn!(statePtr, args, returns);
  }

  void Function(Pointer, int)? _settopfn;
  int Function(Pointer)? _gettopfn;

  set top(int newTop) {
    _settopfn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_settop');

    _settopfn!(statePtr, newTop);
  }

  int get top {
    _gettopfn ??= dll!.lookupFunction<Int Function(Pointer), int Function(Pointer)>('lua_settop');

    return _gettopfn!(statePtr);
  }

  /// Pop from the Lua stack [n] elements.
  void pop(int n) {
    top -= n;
  }

  void Function(Pointer, int)? _removeFn;

  /// Removes element at [i].
  void remove(int i) {
    _removeFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_remove');

    _removeFn!(statePtr, i % top);
  }

  void Function(Pointer, bool)? _pushBfn;

  /// Push onto the stack a new boolean.
  void pushBoolean(bool boolean) {
    _pushBfn ??= dll!.lookupFunction<Void Function(Pointer, Bool), void Function(Pointer, bool)>('lua_pushboolean');

    _pushBfn!(statePtr, boolean);
  }

  void Function(Pointer, Pointer)? _pushCFn;

  /// Pushes a C function onto the stack, preferrably converted from a Dart function.
  void pushCFunction(LuaNativeFunctionPointer fn) {
    _pushCFn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer)>('lua_pushcfunction');

    _pushCFn!(statePtr, fn);
  }

  void Function(Pointer, Pointer<Utf8>)? _pushLStrfn;

  /// Pushes a string as a null-terminated UTF8 array onto the stack. It is recommended you only use ASCII characters though.
  void pushString(String str) {
    _pushLStrfn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer<Utf8>)>('lua_pushstring');

    _pushLStrfn!(statePtr, str.toNativeUtf8());
  }

  void Function(Pointer, int)? _pushIntfn;

  /// Pushes an integer of value [n] onto the stack.
  void pushInteger(int n) {
    _pushIntfn ??= dll!.lookupFunction<Void Function(Pointer, Int64), void Function(Pointer, int)>('lua_pushinteger');

    _pushIntfn!(statePtr, n);
  }

  void Function(Pointer)? _pushNilfn;

  /// Pushes nil onto the stack
  void pushNil() {
    _pushNilfn ??= dll!.lookupFunction<Void Function(Pointer), void Function(Pointer)>('lua_pushnil');

    _pushNilfn!(statePtr);
  }

  void Function(Pointer, double)? _pushNumfn;

  /// Pushes a number onto the stack.
  void pushNumber(double n) {
    _pushNumfn ??= dll!.lookupFunction<Void Function(Pointer, Double), void Function(Pointer, double)>('lua_pushnumber');

    _pushNumfn!(statePtr, n);
  }
}
