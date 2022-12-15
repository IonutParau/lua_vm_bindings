import 'dart:ffi';

import 'package:lua_vm_bindings/lua_vm_bindings.dart';

int panicHandler(Pointer p) {
  final ls = LuaState(pointer: p);
  print("Something bad happened. There are also ${ls.top} elements on the stack");
  return 0;
}

void main() {
  LuaState.loadLibLua(linux: 'external_libs/liblua54.so');
  final ls = LuaState();
  ls.openLibs();
  print("We have ${ls.top} elements on the stack!");
  ls.atPanic(LuaNativeFunctionPointer.fromFunction<LuaNativeFunction>(panicHandler, 1));
  ls.pushString("This is an error message");
  ls.error();
  print(ls.statePtr);
  ls.destroy();
}
