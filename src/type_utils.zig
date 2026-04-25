pub fn assertAnytypeHasDecls(val: anytype, comptime expected_decls: []const []const u8 ) void {
    const T = @TypeOf(val);
    const ActualType = switch (@typeInfo(T)) {
        .pointer => |ptr_info| ptr_info.child,
        else => T
    };

    inline for(expected_decls) |decl| {
        if (!@hasDecl(ActualType, decl)) @compileError("Type '" ++ @typeName(ActualType) ++ "' does not contain the required declaration '" ++ decl ++ "'.");
    }
}
