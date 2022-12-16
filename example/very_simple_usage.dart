import 'dart:ffi';

import 'package:lua_vm_bindings/lua_vm_bindings.dart';

int panicHandler(Pointer p) {
  final ls = LuaState(pointer: p);
  print("Something bad happened. There are also ${ls.top} elements on the stack");
  return 0;
}

int testFunc(LuaState ls) {
  print(ls.toStr(-1));
  ls.pushString("Returned from Dart!");
  return 1;
}

void main() {
  LuaState.loadLibLua(linux: 'dlls/liblua54.so');
  final ls = LuaState();
  ls.openLibs();

  ls.pushDartFunction(testFunc);
  ls.pushString("Argument from Dart!");
  ls.call(1, 1);
  print(ls.toStr(-1));
  ls.pop();

  ls.destroy();
}
