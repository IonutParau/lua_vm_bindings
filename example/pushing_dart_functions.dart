import 'package:lua_vm_bindings/lua_vm_bindings.dart';

void main() {
  LuaState.loadLibLua(linux: 'dlls/liblua54.so', windows: 'dlls/liblua54.dll', macos: 'dlls/liblua52.dylib');
  final ls = LuaState();

  ls.openLibs();

  ls.pushDartFunction((ls) {
    print("Called by Lua!");

    return 0;
  });
  ls.setGlobal("FuncFromDart");

  ls.loadStr('FuncFromDart()');

  ls.call(0, 0);

  ls.destroy();
}
