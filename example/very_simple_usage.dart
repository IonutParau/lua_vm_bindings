import 'package:lua_vm_bindings/lua_vm_bindings.dart';

int testFunc(LuaState ls) {
  print(ls.toStr(-1));
  ls.pushString("Returned from Dart!");
  return 1;
}

void main() {
  LuaState.loadLibLua(linux: 'dlls/liblua54.so', windows: 'dlls/liblua54.dll', macos: 'dlls/liblua52.dylib');
  final ls = LuaState();
  ls.openLibs();

  ls.loadStr('''print(({...})[1])''');
  ls.pushString("Hello, World!");
  ls.call(1, 0);

  ls.destroy();
}
