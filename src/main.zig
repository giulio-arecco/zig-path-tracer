const std = @import("std");

const img_height= 64;
const img_width = 48;
const img_size = img_height * img_width;

pub fn main(init: std.process.Init) !void {
    var buffer: [img_size]u8 = undefined;

    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Writing correctly to stdout!\n", .{});
    try stdout.flush();
}
