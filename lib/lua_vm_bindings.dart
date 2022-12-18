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
  fileError,
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
      return fn.call(LuaState(pointer: state));
    }
  } catch (e) {
    print('Calling a Dart function from Lua raised Dart error: $e');
  }

  return 0;
}

int _luaCleanupDartFuncBinding(Pointer state) {
  final ls = LuaState(pointer: state);
  if (!ls.getMetatable(-1)) return 0;
  ls.getField(-1, "dart_fn");
  final i = ls.toInteger(-1);
  _luaPushedDartFuncs.remove(i);
  ls.pop(1);
  return 0;
}

/// Container for a LuaState from the Lua DLL.
class LuaState {
  DynamicLibrary? dll;

  /// Loads the global DLL to use as a fallback if none is specified in the [LuaState] constructor.
  static void loadLibLua({String? windows, String? linux, String? macos}) {
    _libLua = toLibLua(windows: windows, linux: linux, macos: macos);
  }

  /// Returns the Lua DLL to be used.
  static DynamicLibrary toLibLua({String? windows, String? linux, String? macos}) {
    return DynamicLibrary.open(Platform.isLinux ? linux! : (Platform.isWindows ? windows! : macos!));
  }

  LuaState({
    this.dll,
    Pointer? pointer,
  }) {
    if (pointer != null) {
      statePtr = pointer;
    }
    dll ??= _libLua;
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

  /// Destroy this [LuaState]. After this is called, never use this [LuaState] ever again.
  void destroy() {
    collect();

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

  int Function(Pointer, Pointer<Utf8>, Pointer<Utf8>)? _loadFileXFn;
  int Function(Pointer, Pointer<Utf8>)? _loadStringFn;

  LuaThreadStatus loadFile(String fileName) {
    return loadFileX(fileName, null);
  }

  LuaThreadStatus loadFileX(String fileName, String? mode) {
    _loadFileXFn ??= dll!.lookupFunction<Int Function(Pointer, Pointer, Pointer), int Function(Pointer, Pointer<Utf8>, Pointer<Utf8>)>('luaL_loadfilex');

    final ptr = mode == null ? nullptr : mode.toNativeUtf8();
    final fnptr = fileName.toNativeUtf8();
    final r = LuaThreadStatus.values[_loadFileXFn!(statePtr, fnptr, ptr)];
    if (ptr.address != nullptr.address) malloc.free(ptr);
    malloc.free(fnptr);

    return r;
  }

  LuaThreadStatus loadStr(String str) {
    _loadStringFn ??= dll!.lookupFunction<Int Function(Pointer, Pointer), int Function(Pointer, Pointer<Utf8>)>('luaL_loadstring');

    final strPtr = str.toNativeUtf8();
    final r = LuaThreadStatus.values[_loadStringFn!(statePtr, strPtr)];
    malloc.free(strPtr);
    return r;
  }

  int Function(Pointer, Pointer<Utf8>)? _newMetatableFn;

  /// Pushes a new metatable and makes it associated with [name] in the registry.
  void newMetatable(String name) {
    _newMetatableFn ??= dll!.lookupFunction<Int Function(Pointer, Pointer), int Function(Pointer, Pointer<Utf8>)>('luaL_newmetatable');

    final nameptr = name.toNativeUtf8();
    _newMetatableFn!(statePtr, nameptr);
    malloc.free(nameptr);
  }

  bool Function(Pointer, int)? _getMetatableFn;

  /// If the value at [i] has a metatable, pushes the metatable and returns true.
  /// Otherwise, pushes nothing and returns false.
  bool getMetatable(int i) {
    _getMetatableFn ??= dll!.lookupFunction<Bool Function(Pointer, Int), bool Function(Pointer, int)>('lua_getmetatable');

    return _getMetatableFn!(statePtr, i);
  }

  void Function(Pointer, int)? _setMetatableFn;

  /// Pops the top value and sets [i]'s metatable to it.
  void setMetatable(int i) {
    _setMetatableFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_setmetatable');

    _setMetatableFn!(statePtr, i);
  }

  /// Sets the value at [i]'s metatable to the value at [meta].
  void setMetatableAs(int i, int meta) {
    final v = i % (top + 1);
    final meta = i % (top + 1);

    pushNil();
    copy(meta, top);
    setMetatable(v);
  }

  void Function(Pointer, int)? _settopfn;
  int Function(Pointer)? _gettopfn;

  set top(int newTop) {
    _settopfn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_settop');

    _settopfn!(statePtr, newTop);
  }

  int get top {
    _gettopfn ??= dll!.lookupFunction<Int Function(Pointer), int Function(Pointer)>('lua_gettop');

    return _gettopfn!(statePtr);
  }

  /// Pop from the Lua stack [n] elements.
  void pop([int n = 1]) {
    top -= n;
  }

  /// Removes element at [i].
  void remove(int i) {
    rotate(i, -1);
    pop(1);
  }

  void Function(Pointer, int, int)? _rotateFn;

  /// Rotates the stack elements between the valid index [idx] and the top of the stack [n] times.
  void rotate(int idx, int n) {
    _rotateFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int), void Function(Pointer, int, int)>('lua_rotate');

    _rotateFn!(statePtr, idx, n);
  }

  void Function(Pointer, int)? _replaceFn;

  /// Moves the top element into [i], without shifting any element (therefore replacing the value at [i]). Also pops that top element!
  void replace(int i) {
    _replaceFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_replace');

    _replaceFn!(statePtr, i % (top + 1));
  }

  void Function(Pointer, int, int)? _copyFn;

  /// Copies [from] to [to]
  void copy(int from, int to) {
    _copyFn ??= dll!.lookupFunction<Void Function(Pointer, Int, Int), void Function(Pointer, int, int)>('lua_copy');

    _copyFn!(statePtr, from % (top + 1), to % (top + 1));
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
    final t = table % (top + 1);
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
    final t = table % (top + 1);
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

  /// Pushes a C function onto the stack, preferrably converted from a Dart function.
  void pushCFunction(LuaNativeFunctionPointer fn) {
    pushCClosure(fn, 0);
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

    // (+1)
    newMetatable("${fn.hashCode}-dart-func-bindings");

    // (+2)
    pushString("dart_fn");
    pushInteger(fn.hashCode);

    // (-2)
    setTable(-3);

    // (+2)
    pushString("__gc");
    pushCFunction(LuaNativeFunctionPointer.fromFunction<LuaNativeFunction>(_luaCleanupDartFuncBinding, 0));

    // (-2)
    setTable(-3);

    // (0)
    setMetatable(-2);
  }

  int Function(Pointer, int)? _gcFn;

  void collect() {
    _gcFn ??= dll!.lookupFunction<Int Function(Pointer, Int), int Function(Pointer, int)>('lua_gc');

    _gcFn!(statePtr, 2);
  }

  void Function(Pointer, Pointer<Utf8>)? _pushLStrfn;

  /// Pushes a string as a null-terminated UTF8 array onto the stack. It is recommended you only use ASCII characters though.
  void pushString(String str) {
    _pushLStrfn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer<Utf8>)>('lua_pushstring');

    final strptr = str.toNativeUtf8();
    _pushLStrfn!(statePtr, strptr);
    malloc.free(strptr);
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

  /// Creates a new empty table and pushes it onto the stack
  void newTable() {
    createTable(0, 0);
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

  void Function(Pointer, int)? _getTableFn;

  /// Pushes onto the stack `t[k]`, where `t` is the value at [table], and `k` is the value at [top]
  void getTable(int table) {
    _getTableFn ??= dll!.lookupFunction<Void Function(Pointer, Int), void Function(Pointer, int)>('lua_gettable');

    _getTableFn!(statePtr, table);
  }

  /// A helper method.
  /// Equivalent to `t[k] = v`, where t is the value at [table], k is the value at [key] and v is the value at [val]
  void setTableKV(int table, int key, int val) {
    final t = table % (top + 1);
    final k = key % (top + 1);
    final v = val % (top + 1);

    pushNil();
    pushNil();
    copy(k, top - 1);
    copy(v, top);
    setTable(t);
  }

  void setField(int table, String field, int val) {
    final t = table % (top + 1);
    final v = val % (top + 1);
    pushString(field);

    setTableKV(t, top, v);
    remove(top);
  }

  /// A helper method.
  /// Pushes `t[k]`, where t is the value at [table] and k is the value at [key].
  void getTableK(int table, int key) {
    final t = table % (top + 1);
    final k = key % (top + 1);

    pushNil();
    copy(k, top);
    getTable(t);
  }

  void getField(int table, String field) {
    final t = table % (top + 1);
    pushString(field);

    getTableK(t, top);
  }

  void Function(Pointer, Pointer<Utf8>)? _setGlobFn;

  /// Pops the top value and sets it as a global.
  void setGlobal(String name) {
    _setGlobFn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer<Utf8>)>('lua_setglobal');

    final nameptr = name.toNativeUtf8();
    _setGlobFn!(statePtr, nameptr);
    malloc.free(nameptr);
  }

  void Function(Pointer, Pointer<Utf8>)? _getGlobFn;

  /// Pushes the global called [name].
  void getGlobal(String name) {
    _getGlobFn ??= dll!.lookupFunction<Void Function(Pointer, Pointer), void Function(Pointer, Pointer<Utf8>)>('lua_getglobal');

    final nameptr = name.toNativeUtf8();
    _getGlobFn!(statePtr, nameptr);
    malloc.free(nameptr);
  }

  int Function(Pointer, int)? _typeFn;

  /// Returns the type of the value at [i]
  LuaType type(int i) {
    _typeFn ??= dll!.lookupFunction<Int Function(Pointer, Int), int Function(Pointer, int)>('lua_type');

    var t = _typeFn!(statePtr, i);

    if (t == -1) {
      return LuaType.none;
    } else {
      return LuaType.values[t];
    }
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

  /// Helper function that takes a map of values and makes a new table with those contents (to the best of its abilitied, not all values are serializable)
  /// Supports both [LuaDartFunction]s and [LuaNativeFunctionPointer].
  void pushLib(Map<String, dynamic> lib, [LuaDartFunctionReleaser? releaser]) {
    createTable(lib.length, lib.length);
    lib.forEach((key, value) {
      pushString(key);

      if (value is LuaDartFunction) {
        releaser?.bind(value);
        pushDartFunction(value);
      } else if (value is String) {
        pushString(value);
      } else if (value is Map<String, dynamic>) {
        pushLib(value);
      } else if (value is LuaNativeFunctionPointer) {
        pushCFunction(value);
      } else if (value is int) {
        pushInteger(value);
      } else if (value is double) {
        pushNumber(value);
      } else if (value is bool) {
        pushBoolean(value);
      } else if (value == null) {
        pushNil();
      }

      setTable(-3);
    });
  }

  /// Like [pushLib], but it also sets it to a global [name].
  /// If [markAsLoaded] is `true`, it will also set `package.loaded[modname]` to that value.
  void makeLib(String name, Map<String, dynamic> lib, {bool markAsLoaded = true, LuaDartFunctionReleaser? releaser}) {
    pushLib(lib, releaser);

    // Make global
    setGlobal(name);

    if (markAsLoaded) {
      // Hello reader, the numbers in paramtheses mean how many elements are added
      // on the stack, in order to keep track of operations.

      // Get package (+1)
      getGlobal('package');

      // Get `loaded` (+1)
      pushString('loaded');
      getTable(top - 1);

      // Set field (0)
      pushString(name);
      getGlobal(name);
      setTable(top - 2);

      pop(2);
    }
  }

  /// Checks if the value at [i] is a string.
  bool isStr(int i) {
    return type(i) == LuaType.string;
  }

  /// Checks if the value at [i] is a number.
  bool isNumber(int i) {
    return type(i) == LuaType.number;
  }

  /// Checks if the value at [i] is a boolean.
  bool isBoolean(int i) {
    return type(i) == LuaType.boolean;
  }

  /// Checks if the value at [i] is a function.
  bool isFunction(int i) {
    return type(i) == LuaType.function;
  }

  /// Checks if the value at [i] is a table.
  bool isTable(int i) {
    return type(i) == LuaType.table;
  }

  /// Checks if the value at [i] is a nil or none.
  bool isNilOrNone(int i) {
    return type(i) == LuaType.nil || type(i) == LuaType.none;
  }

  /// Checks if the value at [i] is a table.
  bool isThread(int i) {
    return type(i) == LuaType.thread;
  }
}

class LuaDartFunctionReleaser {
  final _fns = <LuaDartFunction>[];

  void bind(LuaDartFunction fn) {
    _fns.add(fn);
  }

  void release() {
    for (var fn in _fns) {
      _luaPushedDartFuncs.remove(fn.hashCode);
    }
    _fns.clear();
  }
}
