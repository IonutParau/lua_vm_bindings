import 'dart:ffi';

import 'package:lua_vm_bindings/lua_vm_bindings.dart';

int testFunc(LuaState ls) {
  print(ls.toStr(-1));
  ls.pushString("Returned from Dart!");
  return 1;
}

int customHandler(Pointer p) {
  final ls = LuaState(pointer: p);

  print(ls.toStr(-1));

  return 0;
}

void main() {
  LuaState.loadLibLua(linux: 'dlls/liblua54.so');
  final ls = LuaState();
  ls.openLibs();

  ls.loadStr('''print(({...})[1])''');
  ls.pushString("Hello, World!");
  ls.call(1, 0);

  ls.destroy();
}
