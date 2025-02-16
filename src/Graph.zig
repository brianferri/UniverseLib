const std = @import("std");
const stat = @import("./stat.zig").stat;
const testing = std.testing;

fn Node(comptime K: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const FakeSet = std.AutoHashMap(K, void);

        data: T,
        adjacency_set: FakeSet,
        incidency_set: FakeSet,

        pub fn init(allocator: std.mem.Allocator, data: T) Self {
            return .{
                .data = data,
                .adjacency_set = FakeSet.init(allocator),
                .incidency_set = FakeSet.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.adjacency_set.deinit();
            self.incidency_set.deinit();
            self.* = undefined;
        }

        pub fn pointsTo(self: *Self, vertex: K) bool {
            return self.adjacency_set.contains(vertex);
        }

        pub fn pointedBy(self: *Self, vertex: K) bool {
            return self.incidency_set.contains(vertex);
        }

        pub fn addAdjEdge(self: *Self, vertex: K) !void {
            if (self.pointsTo(vertex)) return;
            try self.adjacency_set.put(vertex, {});
        }

        pub fn removeAdjEdge(self: *Self, vertex: K) !void {
            _ = self.adjacency_set.remove(vertex);
        }

        pub fn addIncEdge(self: *Self, vertex: K) !void {
            if (self.pointsTo(vertex)) return;
            try self.incidency_set.put(vertex, {});
        }

        pub fn removeIncEdge(self: *Self, vertex: K) !void {
            _ = self.incidency_set.remove(vertex);
        }
    };
}

pub fn Graph(comptime K: type, comptime T: type) type {
    return struct {
        const Vertex = Node(K, T);
        const Vertices = std.AutoHashMap(K, *Vertex);
        const Self = @This();
        allocator: std.mem.Allocator,

        vertices: Vertices,
        next_vertex_index: K,

        pub fn init(allocator: std.mem.Allocator, initial_index: K) Self {
            return .{
                .allocator = allocator,
                .vertices = Vertices.init(allocator),
                .next_vertex_index = initial_index,
            };
        }

        pub fn deinit(self: *Self) void {
            var vertex_iterator = self.vertices.valueIterator();

            while (vertex_iterator.next()) |vertex| {
                vertex.*.deinit();
                self.allocator.destroy(vertex.*);
            }

            self.vertices.deinit();
            self.* = undefined;
        }

        pub fn addVertex(self: *Self, data: T) !K {
            const node = try self.allocator.create(Vertex);
            node.* = Vertex.init(self.allocator, data);

            try self.vertices.put(self.next_vertex_index, node);
            self.next_vertex_index += 1;
            return self.next_vertex_index - 1;
        }

        pub fn getVertex(self: *Self, index: K) ?*Vertex {
            return self.vertices.get(index);
        }

        pub fn getVertexData(self: *Self, index: K) ?T {
            return if (self.getVertex(index)) |v| v.*.data else null;
        }

        pub fn removeVertex(self: *Self, index: K) bool {
            if (self.getVertex(index)) |vertex| {
                var vertex_iterator = self.vertices.iterator();
                while (vertex_iterator.next()) |entry| {
                    try self.removeEdge(entry.key_ptr.*, index);
                }

                vertex.deinit();
                self.allocator.destroy(vertex);

                return self.vertices.remove(index);
            }

            return false;
        }

        /// Is directional
        ///
        /// Only checks if vertex `v1` is "pointing" to vertex `v2`
        pub fn hasEdge(self: *Self, v1: K, v2: K) bool {
            if (self.getVertex(v1)) |v| {
                return v.pointsTo(v2);
            }

            return false;
        }

        pub fn addEdge(self: *Self, v1: K, v2: K) !void {
            if (self.vertices.get(v1)) |v| {
                try v.addAdjEdge(v2);
            }

            if (self.vertices.get(v2)) |v| {
                try v.addIncEdge(v1);
            }
        }

        pub fn removeEdge(self: *Self, v1: K, v2: K) !void {
            if (self.vertices.get(v1)) |v| {
                try v.removeAdjEdge(v2);
            }

            if (self.vertices.get(v2)) |v| {
                try v.removeIncEdge(v1);
            }
        }

        pub fn setVertex(self: *Self, index: K, data: T) !void {
            try self.vertices.put(index, data);
        }
    };
}

test "graph initialization" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();
}

test "add vertex" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(123);

    try testing.expect(graph.getVertexData(index) == 123);
}

test "add and remove vertex" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index = try graph.addVertex(123);

    try testing.expect(graph.getVertexData(index) == 123);
    try testing.expect(graph.removeVertex(index) == true);
    try testing.expect(graph.getVertexData(index) == null);
}

test "add edge between two vertices" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));
}

test "add and remove an edge" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    const index2 = try graph.addVertex(456);

    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try graph.removeEdge(index1, index2);
    try testing.expect(!graph.hasEdge(index1, index2));
}

test "add vertexes and edges, remove vertex, test for edges" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertexData(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertexData(index2) == 456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try testing.expect(!graph.hasEdge(index2, index1));
    try graph.addEdge(index2, index1);
    try testing.expect(graph.hasEdge(index2, index1));

    try testing.expect(graph.removeVertex(index1));
    try testing.expect(graph.getVertexData(index1) == null);
    try testing.expect(!graph.hasEdge(index1, index2));
    try testing.expect(!graph.hasEdge(index2, index1));
}

test "getting neighbors" {
    var graph = Graph(usize, u32).init(testing.allocator, 0);
    defer graph.deinit();

    const index1 = try graph.addVertex(123);
    try testing.expect(graph.getVertexData(index1) == 123);
    const index2 = try graph.addVertex(456);
    try testing.expect(graph.getVertexData(index2) == 456);

    try testing.expect(!graph.hasEdge(index1, index2));
    try graph.addEdge(index1, index2);
    try testing.expect(graph.hasEdge(index1, index2));

    try testing.expect(graph.getVertex(index1).?.pointsTo(index2));
    try testing.expect(!graph.getVertex(index2).?.pointsTo(index1));

    try testing.expect(graph.getVertex(index2).?.pointedBy(index1));
    try testing.expect(!graph.getVertex(index1).?.pointedBy(index2));
}

pub fn main() !void {
    const time = std.time;
    const Timer = time.Timer;

    var graph = Graph(usize, usize).init(std.heap.page_allocator, 0);
    defer graph.deinit();

    var file = try std.fs.cwd().createFile("out.csv", .{});
    defer file.close();

    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    // var outer_timer = try Timer.start();
    var timer = try Timer.start();
    for (0..1_000_000) |i| {
        // timer = try Timer.start();
        _ = try graph.addVertex(i);
        // std.debug.print("Adding index1: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });

        // timer = try Timer.start();
        _ = try graph.addVertex(456);
        // std.debug.print("Adding index2: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });

        var vertices1 = graph.vertices.keyIterator();

        timer = try Timer.start();
        while (vertices1.next()) |vertex1| {
            // if (graph.getNeighbors(vertex1.*).?.count() >= 5) continue;
            var vertices2 = graph.vertices.keyIterator();
            while (vertices2.next()) |vertex2| {
                // if (graph.getNeighbors(vertex2.*).?.count() >= 5) continue;
                if (vertex1 == vertex2) continue;

                // timer = try Timer.start();
                // const v1n = graph.getNeighbors(vertex1.*);
                // const v2n = graph.getNeighbors(vertex2.*);
                // std.debug.print("Getting Neighbors: {d:.3}ms\n", .{
                //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
                // });

                // std.debug.print("Vertex {d} Neighbors: {d}\n", .{ vertex1.*, v1n.?.count() });
                // std.debug.print("Vertex {d} Neighbors: {d}\n", .{ vertex2.*, v2n.?.count() });

                // timer = try Timer.start();
                try graph.addEdge(vertex1.*, vertex2.*);
                try graph.addEdge(vertex2.*, vertex1.*);
                // std.debug.print("Adding edge: {d:.3}ms\n", .{
                //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
                // });
            }
        }
        const iter_time = timer.read();
        // std.debug.print("Adding edges between all vertices: {d:.3}ms\n", .{
        //     @as(f64, @floatFromInt(iter_time)) / time.ns_per_ms,
        // });
        var buf: [1000]u8 = undefined;
        const stats = try stat(&buf);
        var edges: u64 = 0;

        var vertices = graph.vertices.valueIterator();
        while (vertices.next()) |v| {
            edges += v.*.adjacency_set.count();
        }

        _ = try file.write(try std.fmt.allocPrint(std.heap.page_allocator, "{d},{d},{d},{d},{d}\n", .{ i, graph.vertices.count(), edges, iter_time, stats.rss }));

        // timer = try Timer.start();
        // std.debug.print("{d} vertices\n", .{graph.vertices.count()});
        // std.debug.print("Counting vertices: {d:.3}ms\n\n", .{
        //     @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms,
        // });
    }
    // std.debug.print("Time to complete tasks: {d:.3}ms\n", .{
    //     @as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms,
    // });
}
