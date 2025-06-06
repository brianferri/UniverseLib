const std = @import("std");
const uSim = @import("usim");
const Particle = @import("ulib");
const stat = @import("./util/stat.zig").stat;
const options = @import("options");

const time = std.time;
const useStat = options.stat;

const Graph = uSim.Graph;
const ParticleGraph = Graph(usize, Particle);

const InteractionTransaction = struct {
    to: usize,
    emitted: []Particle,
    /// If the particles that interacted were consumed in the interaction and are flagged for removal from the graph
    consumed: bool,
};

fn connectNewParticle(graph: *ParticleGraph, new_id: usize, source: *ParticleGraph.Node) !void {
    var new = graph.getVertex(new_id) orelse unreachable;
    new.adjacency_set = try source.adjacency_set.clone();
    new.incidency_set = try source.incidency_set.clone();

    var adj_iter = source.adjacency_set.iterator();
    while (adj_iter.next()) |entry| {
        const adj_v = graph.getVertex(entry.key_ptr.*) orelse continue;
        try adj_v.addIncEdge(new_id);
    }

    var inc_iter = source.incidency_set.iterator();
    while (inc_iter.next()) |entry| {
        const inc_v = graph.getVertex(entry.key_ptr.*) orelse continue;
        try inc_v.addAdjEdge(new_id);
    }
}

fn processInteractions(allocator: std.mem.Allocator, graph: *ParticleGraph) !void {
    var transactions = std.AutoHashMap(usize, InteractionTransaction).init(allocator);
    defer transactions.deinit();

    // Collect interaction transactions
    var iter = graph.vertices.keyIterator();
    while (iter.next()) |from_id| {
        if (transactions.contains(from_id.*)) continue;

        const from = graph.getVertex(from_id.*) orelse continue;
        var to_it = from.adjacency_set.keyIterator();
        while (to_it.next()) |to_id| {
            if (from_id.* == to_id.* or transactions.contains(to_id.*)) continue;
            const to = graph.getVertex(to_id.*) orelse continue;

            std.debug.print(
                "\rInteracting: v1 = {d} (edges: {d}), v2 = {d} (edges: {d})\x1B[0K",
                .{ from_id.*, from.adjacency_set.count(), to_id.*, to.adjacency_set.count() },
            );

            var emitted = std.ArrayList(Particle).init(allocator);
            const consumed = try Particle.interact(&from.data, &to.data, &emitted);

            try transactions.put(from_id.*, .{
                .to = to_id.*,
                .emitted = try emitted.toOwnedSlice(),
                .consumed = consumed,
            });

            break;
        }
    }
    std.debug.print("\nTransactions to apply: {d}\n", .{transactions.count()});

    // Apply interactions to graph
    var apply_index: usize = 0;
    var tx_iter = transactions.iterator();
    while (tx_iter.next()) |entry| : (apply_index += 1) {
        const tx = entry.value_ptr.*;
        const from = entry.key_ptr.*;
        const to = tx.to;

        std.debug.print(
            "\rApplying Tx {d}: from = {d}, to = {d}, emitted = {d}, consumed = {any}\x1B[0K",
            .{ apply_index, from, to, tx.emitted.len, tx.consumed },
        );

        const source_from = graph.getVertex(from) orelse return;
        const source_to = graph.getVertex(to) orelse return;
        const vertex_count = graph.vertices.count();
        for (tx.emitted, 0..) |p, i| {
            const new_id = vertex_count + i;
            try graph.putVertex(new_id, p);
            try connectNewParticle(graph, new_id, source_from);
            try connectNewParticle(graph, new_id, source_to);
        }

        if (tx.consumed) {
            _ = graph.removeVertex(from);
            _ = graph.removeVertex(to);
        }
    }
}

fn logIteration(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    graph: *ParticleGraph,
    iter: usize,
    iter_time: f64,
) !void {
    var buf: [1000]u8 = undefined;
    var edges: usize = 0;

    var vertices = graph.vertices.valueIterator();
    while (vertices.next()) |v| {
        edges += v.*.adjacency_set.count();
    }

    if (comptime useStat) {
        const memory = try stat(&buf);
        try file.writeAll(try std.fmt.allocPrint(allocator, "{d},{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time, memory.rss,
        }));
    } else {
        try file.writeAll(try std.fmt.allocPrint(allocator, "{d},{d},{d},{d}\n", .{
            iter, graph.vertices.count(), edges, iter_time,
        }));
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var outer_timer = try time.Timer.start();

    var graph = try Particle.initializeGraph(allocator);
    defer graph.deinit();
    Particle.print(&graph);
    std.debug.print("Initialized in: {d:.3}ms\n", .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms});

    var file = try std.fs.cwd().createFile("zig-out/out.csv", .{});
    defer file.close();
    _ = try file.write("iter,vertices,num_edges,iter_time,mem\n");

    var graph_state = graph;
    var i: usize = 0;
    while (true) : (i += 1) {
        std.debug.print("Calculating iter: {d}...\n", .{i});

        var timer = try time.Timer.start();
        try processInteractions(allocator, &graph);
        const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
        try logIteration(allocator, &file, &graph, i, iter_time);

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("iter: {d} | time: {d}\n", .{ i, iter_time });
        if (std.meta.eql(graph, graph_state) and i != 0) break; //? Reached stable state
        Particle.print(&graph);

        if (graph.vertices.count() == 0) break;
        graph_state = graph;
    }

    std.debug.print("Total time: {d:.3}ms\n", .{@as(f64, @floatFromInt(outer_timer.read())) / time.ns_per_ms});
}
