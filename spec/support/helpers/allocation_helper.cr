module AllocationHelper
  # Returns the bytes the garbage collector handed out while the block ran.
  # Parameter-limit specs use it to prove a hostile request is rejected
  # without allocating in proportion to a number written in the request.
  def bytes_allocated_by(&) : UInt64
    before = GC.stats.total_bytes
    yield
    GC.stats.total_bytes - before
  end
end
