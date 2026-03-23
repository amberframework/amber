# Crystal Concurrency Guide

Crystal provides cooperative concurrency through fibers and channels. This model is essential for understanding Amber's WebSocket handling, background jobs, and I/O-driven request processing.

## Concurrency vs Parallelism

Crystal currently provides **concurrency** (multiple tasks making progress by interleaving) but not true parallelism (multiple tasks executing simultaneously). A Crystal program runs on a single OS thread by default, except for the garbage collector. Experimental multi-thread parallelism exists but is not yet stable.

## Fibers

Fibers are lightweight, cooperative execution units managed by the Crystal runtime. They are similar to goroutines or coroutines.

### Key Properties

- **Lightweight**: Start with ~4KB stack, can grow up to 8MB
- **Cooperative**: Must explicitly yield control (at I/O, sleep, channel ops)
- **Millions possible**: On 64-bit systems, you can spawn millions of fibers
- **No preemption**: A CPU-bound fiber will block all others until it yields

### Spawning Fibers

```crystal
# Spawn with a block
spawn do
  puts "Running in a fiber"
end

# Spawn with a method call (copies arguments to avoid closure issues)
spawn puts("Hello")

# Named fiber for debugging
spawn(name: "worker") do
  loop do
    process_next_job
  end
end
```

### Fiber Scheduling

Fibers don't execute immediately. The runtime scheduler maintains a queue:

```crystal
spawn do
  puts "This runs second"
end
puts "This runs first"
Fiber.yield  # Yields to the spawned fiber
```

**When fibers yield control:**
- `Fiber.yield` -- Voluntary yield
- `sleep` -- Timer-based yield
- I/O operations (socket read/write, file I/O)
- Channel `send`/`receive` when blocked
- Any operation that enters the event loop

### The Event Loop

The event loop is a special fiber that manages async I/O. When a fiber performs I/O that would block, it registers with the event loop and yields. The event loop resumes the fiber when the I/O is ready.

```crystal
spawn do
  server = TCPServer.new("0.0.0.0", 8080)
  loop do
    # accept yields until a connection arrives
    socket = server.accept
    # Spawn a new fiber per connection
    spawn handle_client(socket)
  end
end
```

### Keeping the Program Alive

The main fiber exiting kills all other fibers. Common patterns:

```crystal
# Sleep forever -- keeps the main fiber alive
sleep

# Sleep for a duration
sleep 10.seconds

# Wait for specific completion via channel
done = Channel(Nil).new
spawn do
  do_work
  done.send(nil)
end
done.receive  # Blocks until work is done
```

## Channels

Channels are typed communication pipes between fibers. They follow CSP (Communicating Sequential Processes) principles -- communicate by sharing messages, not by sharing memory.

### Unbuffered Channels

An unbuffered channel blocks the sender until a receiver is ready, and vice versa:

```crystal
ch = Channel(String).new

spawn do
  ch.send("Hello from fiber")
end

message = ch.receive  # Blocks until send happens
puts message  # => "Hello from fiber"
```

### Buffered Channels

Buffered channels allow sends without blocking until the buffer is full:

```crystal
ch = Channel(Int32).new(capacity: 10)

# Can send up to 10 values without blocking
10.times { |i| ch.send(i) }

# 11th send would block until a receive frees space
```

### Channel Operations

```crystal
ch = Channel(String).new

# Blocking receive
value = ch.receive

# Non-blocking receive (returns nil if nothing available)
value = ch.receive?

# Send
ch.send("data")

# Close a channel
ch.close

# Check if closed
ch.closed?
```

### Fan-Out / Fan-In Patterns

**Fan-out:** Multiple fibers reading from one channel:

```crystal
work = Channel(Job).new(100)

# Multiple workers
5.times do |i|
  spawn(name: "worker-#{i}") do
    while job = work.receive?
      process(job)
    end
  end
end
```

**Fan-in:** Multiple fibers writing to one channel:

```crystal
results = Channel(Result).new

sources.each do |source|
  spawn do
    data = fetch(source)
    results.send(data)
  end
end

sources.size.times do
  result = results.receive
  handle(result)
end
```

### Select

`select` waits on multiple channel operations:

```crystal
ch1 = Channel(Int32).new
ch2 = Channel(String).new

select
when value = ch1.receive
  puts "Got int: #{value}"
when value = ch2.receive
  puts "Got string: #{value}"
end
```

Non-blocking select with `else`:

```crystal
select
when value = ch.receive
  process(value)
else
  # No value available, do something else
end
```

Timeout pattern:

```crystal
timeout = Channel(Nil).new
spawn do
  sleep 5.seconds
  timeout.send(nil)
end

select
when value = data_channel.receive
  process(value)
when timeout.receive
  puts "Timed out waiting for data"
end
```

## Concurrency Patterns in Amber

### WebSocket Fiber Model

Each WebSocket connection runs in its own fiber. Messages are processed sequentially within a connection but concurrently across connections:

```crystal
# Simplified Amber WebSocket handling
spawn do
  loop do
    message = socket.receive
    channel.handle_message(message)
    # Fiber yields during socket.receive (I/O wait)
  end
end
```

### Background Jobs and Work-Stealing

Amber's job system uses fibers with a work-stealing pattern. Idle web instances can pick up queued jobs:

```crystal
# Jobs are enqueued to an adapter
MyJob.new(user_id: 42).enqueue

# Workers (fibers) pull jobs from the queue
spawn(name: "job-worker") do
  loop do
    if job = queue.dequeue?
      job.perform
    else
      sleep 1.second  # Yield and retry
    end
  end
end
```

### Request Processing

Each HTTP request is handled in a fiber. The pipeline of middleware pipes runs sequentially within the fiber, but different requests run concurrently:

```crystal
# Simplified request handling
spawn do
  context = accept_request
  pipeline.call(context)  # Runs pipes, controller, renders response
  # Fiber yields at I/O points (reading body, writing response)
end
```

## Best Practices

1. **Never block a fiber with CPU-intensive work** without yielding. Use `Fiber.yield` in long loops.

2. **Use channels for communication**, not shared mutable state. While single-threaded mode makes shared state safe today, channels future-proof your code for parallelism.

3. **Handle channel closure**: `receive?` returns nil on closed channels. Always check in loops.

4. **Name your fibers** for debugging: `spawn(name: "description") { ... }`

5. **Keep fiber stacks small**: Avoid deep recursion or large stack allocations in fibers.

6. **Use buffered channels** when producers and consumers run at different rates.

7. **Always ensure the main fiber stays alive** if you need spawned fibers to complete. Use `sleep`, channels, or `Fiber.yield`.
