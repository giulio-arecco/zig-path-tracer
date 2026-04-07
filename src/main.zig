const std = @import("std");
const powi = std.math.powi;

const img_height= 64;
const img_width = 48;

const circle_radius = 5;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try print_circle(io, img_height, img_width, circle_radius);
}

fn print_circle(io: std.Io, comptime out_height: u16, comptime out_width: u16, radius: u16) !void {
    const out_size_with_nl = out_height * out_width + out_height;
    const half_out_height = @as(isize, out_height / 2);
    const half_out_width = @as(isize, out_width / 2);
    const int_rad = @as(isize, radius);
    const rad_2 = int_rad * int_rad;


    var out_buffer: [out_size_with_nl]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const stdout = &stdout_writer.interface;

    for(0..out_height) |i| {
        const y= @as(isize, @intCast(i)) - half_out_height; // y is in range [-half_out_height, half_out_height)
        const y_2 = y * y;

        for (0..out_width) |j| {
            const x= @as(isize, @intCast(j)) - half_out_width; // x is in range [-half_out_width, half_out_width)
            const x_2 = x * x;


            if (x_2 + y_2 > rad_2) {
                try stdout.writeByte('x');
            }
            else {
                try stdout.writeByte('.');
            }
        }

        try stdout.writeByte('\n');
    }

    try stdout.flush();
}

fn greet_user(io: std.Io) !void {
    var in_buffer: [128]u8 = undefined;
    var out_buffer: [128]u8 = undefined;

    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const stdout = &stdout_writer.interface;

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    const stdin = &stdin_reader.interface;

    try stdout.writeAll("Insert your name here: ");
    try stdout.flush();

    const input = try stdin.takeDelimiterExclusive('\n');
    const name = std.mem.trimEnd(u8, input, &std.ascii.whitespace);

    try stdout.print("Hi {s}!\n", .{name});
    try stdout.flush();
}
