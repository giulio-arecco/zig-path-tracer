//! This file implements compile-time duck-typing utilities by leveraging Zig's comptime reflection.

/// Since Zig doesn't have formal interfaces, this function enforces that dynamic generic types
/// (`anytype`) implement the required methods at compile time, triggering a compile error if they don't.
///
/// Failures trigger a compile error, preventing invalid interface implementations.
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
