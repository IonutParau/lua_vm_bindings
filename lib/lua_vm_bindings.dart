import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The type of a Dart function. This is rarely used due to `dart:ffi` limitations.
typedef LuaDartFunction = int Function(LuaState ls);

/// The type of a C function in Lua.
typedef LuaCFunction = int Function(Pointer lsPtr);

/// The type for a native C function in Lua.
typedef LuaNativeFunction = Int32 Function(Pointer lsPtr);

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

/// This stores pushed Dart Functions, as a work-around to converting Dart functions to C functions on the fly, by using Lua upvalues.
final _luaPushedDartFuncs = <int, LuaDartFunction>{};

int _luaCallCorrespondingDartFunction(Pointer state) {
  try {
    final ls = LuaState(pointer: state);
    final up = ls.toInteger(ls.upvalueIndex(1));

    final fn = _luaPushedDartFuncs[up];

    if (fn != null) {
      return fn.call(ls);
    }
  } catch (e) {
    print('Calling a Dart function from Lua raised Dart error: $e');
  }

  return 0;
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
    registryIndex = -maxStack - 1000;
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

  void Function(Pointer, int, int, int, Pointer)? _callkFn;

  /// Binding to `lua_call`. `args` is amount of arguments to pop and call it with, calls the value just before the arguments, pops the called value, and then pushes `returns` amount of returned values.
  void call(int args, int returns) {
    _callkFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int, Int, Pointer), void Function(Pointer, int, int, int, Pointer)>('lua_callk');

    _callkFn!(statePtr, args, returns, 0, nullptr);
  }

  int Function(Pointer, int, int, int, int, Pointer)? _pcallkFn;

  /// Like call, but in the case of a Lua error, it will catch the error,
  /// push it, and if [msgh] is not 0, call the value at [msgh].
  /// Also returns a [LuaThreadStatus] to specify what error happened.
  LuaThreadStatus pcall(int args, int returns, int msgh) {
    _pcallkFn ??= dll!.lookupFunction<Int Function(Pointer, Int, Int, Int, Int, Pointer), int Function(Pointer, int, int, int, int, Pointer)>('lua_pcallk');

    final i = _pcallkFn!(statePtr, args, returns, msgh, 0, nullptr);

    return LuaThreadStatus.values[i];
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
  void pop([int n = 1]) {
    top -= n;
  }

  void Function(Pointer, int)? _removeFn;

  /// Removes element at [i].
  void remove(int i) {
    _removeFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_remove');

    _removeFn!(statePtr, i % top);
  }

  void Function(Pointer, int)? _replaceFn;

  /// Moves the top element into [i], without shifting any element (therefore replacing the value at [i]). Also pops that top element!
  void replace(int i) {
    _replaceFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_replace');

    _replaceFn!(statePtr, i % top);
  }

  void Function(Pointer, int, int)? _copyFn;

  /// Copies [from] to [to]
  void copy(int from, int to) {
    _copyFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int), void Function(Pointer, int, int)>('lua_copy');

    _copyFn!(statePtr, from % top, to % top);
  }

  int Function(Pointer, int)? _nextFn;

  /// Pops the top value from the stack as the key.
  /// Pushes a key-value pair onto the stack (key is at -2 and value at -1).
  /// Returns 0 if the end of the table is reached.
  int next(int table) {
    _nextFn ??= dll!.lookupFunction<Int Function(Pointer, Int), int Function(Pointer, int)>('lua_next');

    return _nextFn!(statePtr, table);
  }

  /// Iterates every key in a table and calls fn for each.
  /// At the top is the value, and below the top is the key,
  /// and make sure at the end of the function call you leave it like that,
  /// If your function returns anything, those `DO` get popped from the stack!
  void iterC(int table, LuaCFunction fn) {
    final t = table % top;
    pushNil();

    while (next(t) != 0) {
      pop(1 + fn(statePtr));
    }
  }

  /// Iterates every key in a table and calls fn for each.
  /// At the top is the value, and below the top is the key,
  /// and make sure at the end of the function call you leave it like that,
  /// If your function returns anything, those `DO` get popped from the stack!
  void iter(int table, LuaDartFunction fn) {
    final t = table % top;
    pushNil();

    while (next(t) != 0) {
      pop(1 + fn(this));
    }
  }

  int maxStack = 1000000;
  late int registryIndex;

  /// Returns the pseudo-index that represents the [i]-th upvalue of the running function. [i] must be in the range [1,256].
  int upvalueIndex(int i) {
    return registryIndex - i;
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

  void Function(Pointer, Pointer, int)? _pushCClos;

  /// Pushes a C closure onto the stack, with top n values being upvalues, preferrably converted from a Dart function. Those upvalues are also popped.
  void pushCClosure(LuaNativeFunctionPointer fn, int n) {
    _pushCClos ??= dll!.lookupFunction<Void Function(Pointer, Pointer, Int), void Function(Pointer, Pointer, int)>('lua_pushcclosure');

    _pushCClos!(statePtr, fn, n);
  }

  /// Pushes a Dart function onto the stack by using this work-around:
  /// 1. Push [fn.hashCode] on the stack
  /// 2. Push the [_luaCallCorrespondingDartFunction] function pointer on the stack as a C closure with an upvalue being that hashcode.
  /// 3. Tell [_luaCallCorrespondingDartFunction] to call [fn] if the upvalue it has been called with is [fn.hashCode]
  void pushDartFunction(LuaDartFunction fn) {
    pushInteger(fn.hashCode);
    pushCClosure(LuaNativeFunctionPointer.fromFunction<LuaNativeFunction>(_luaCallCorrespondingDartFunction, 0), 1);
    _luaPushedDartFuncs[fn.hashCode] = fn;
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

  void Function(Pointer)? _newTableFn;

  /// Creates a new empty table and pushes it onto the stack
  void newTable() {
    _newTableFn ??= dll!.lookupFunction<Void Function(Pointer), void Function(Pointer)>('lua_newtable');

    _newTableFn!(statePtr);
  }

  void Function(Pointer, int, int)? _createTableFn;

  /// Creates a new empty table with a pre-allocated size (for performance reasons) and pushes it onto the stack.
  /// [narr] is how many elements in a sequence to prepare for,
  /// and [nrec] is how many other elements the table will have.
  void createTable(int narr, int nrec) {
    _createTableFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int), void Function(Pointer, int, int)>('lua_createtable');

    _createTableFn!(statePtr, narr, nrec);
  }

  void Function(Pointer, int)? _setTableFn;

  /// Equivalent to `t[k] = v`, where t is the value at [table], v is the value on the top of the stack, and k is the value just below the top.
  /// This pops the key and the value, and, this may trigger a metamethod.
  void setTable(int table) {
    _setTableFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_settable');

    _setTableFn!(statePtr, table);
  }

  /// A helper method.
  /// Equivalent to `t[k] = v`, where t is the value at [table], k is the value at [key] and v is the value at [val]
  void setTableKV(int table, int key, int val) {
    final t = table % top;
    final k = key % top;
    final v = val % top;

    pushNil();
    pushNil();
    copy(k, top - 1);
    copy(v, top);
    setTable(t);
  }

  void Function(Pointer, Pointer<Utf8>)? _setGlobFn;

  /// Pops the top value and sets it as a global.
  void setGlobal(String name) {
    _setGlobFn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer<Utf8>)>('lua_setglobal');

    _setGlobFn!(statePtr, name.toNativeUtf8());
  }

  bool Function(Pointer, int)? _toBoolFn;

  /// Returns the value at [i] as a boolean
  bool toBoolean(int i) {
    _toBoolFn ??= dll!.lookupFunction<Bool Function(Pointer, Int), bool Function(Pointer, int)>('lua_toboolean');

    return _toBoolFn!(statePtr, i);
  }

  LuaNativeFunctionPointer Function(Pointer, int)? _toCFn;

  /// Returns the value at [i] as a [LuaCFunction]
  LuaCFunction toCFunction(int i) {
    _toCFn ??= dll!.lookupFunction<LuaNativeFunctionPointer Function(Pointer, Int), LuaNativeFunctionPointer Function(Pointer, int)>('lua_toboolean');

    return _toCFn!(statePtr, i).asFunction<LuaCFunction>();
  }

  /// Returns the value at [i] as a [LuaDartFunction]
  LuaDartFunction toDartFunction(int i) {
    final cFn = toCFunction(i);

    return (state) {
      return cFn(state.statePtr);
    };
  }

  int Function(Pointer, int, Pointer)? _toIntXFn;

  /// Returns the value at [i] as an integer
  int toInteger(int i) {
    _toIntXFn ??= dll!.lookupFunction<Int Function(Pointer, Int, Pointer), int Function(Pointer, int, Pointer)>('lua_tointegerx');

    return _toIntXFn!(statePtr, i, nullptr);
  }

  double Function(Pointer, int, Pointer)? _toNumXFn;

  /// Returns the value at [i] as a double
  double toNumber(int i) {
    _toNumXFn ??= dll!.lookupFunction<Double Function(Pointer, Int, Pointer), double Function(Pointer, int, Pointer)>('lua_tonumberx');

    return _toNumXFn!(statePtr, i, nullptr);
  }

  Pointer<Utf8> Function(Pointer, int, Pointer<Int>)? _tolStrFn;

  /// Returns the value at [i] as a string
  String? toStr(int i) {
    _tolStrFn ??= dll!.lookupFunction<Pointer<Utf8> Function(Pointer, Int, Pointer<Int>), Pointer<Utf8> Function(Pointer, int, Pointer<Int>)>('lua_tolstring');

    final p = _tolStrFn!(statePtr, i, nullptr);

    if (p.address == nullptr.address) {
      return null;
    }

    return p.toDartString();
  }
}
