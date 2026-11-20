require "json"

module RouterVsMica
  # A point estimate (a median, or a geometric mean for ratios) with its 95%
  # bootstrap interval.
  record Estimate, center : Float64, low : Float64, high : Float64 do
    include JSON::Serializable
  end

  # The result of one baseline-against-candidate comparison: absolute
  # nanoseconds per call for each side (median batch), the paired ratio
  # candidate/baseline (geometric mean over pairs, which treats a slow batch
  # on either side alike),
  # and bytes allocated per call.
  record PairedResult, label : String, candidate : String, pairs : Int32, calls_per_batch : Int32,
    baseline_ns : Estimate, candidate_ns : Estimate, ratio : Estimate,
    baseline_bytes_per_call : Float64, candidate_bytes_per_call : Float64 do
    include JSON::Serializable

    # Returns true when the ratio's interval lies wholly below 1.0.
    def candidate_faster? : Bool
      ratio.high < 1.0
    end

    # Returns true when the ratio's interval lies wholly above 1.0.
    def candidate_slower? : Bool
      ratio.low > 1.0
    end
  end

  # Times two workloads in interleaved pairs and adds pairs until the
  # paired ratio's 95% bootstrap interval lies on one side of 1.0 or is
  # narrower than 1% of the ratio.
  #
  # A workload is any value with `run : Int32` that does a fixed amount of
  # work and returns a checksum; `calls` is how many calls one `run` makes.
  module PairedMeasurement
    MIN_PAIRS       =             60
    MAX_PAIRS       =            600
    CHECK_EVERY     =             10
    BATCH_TARGET_NS =    1_000_000.0
    RESAMPLES       =          2_000
    RANDOM_SEED     = 20_261_120_u64
    WIDTH_TOLERANCE =           0.01
    WARMUP_BATCHES  =              5

    # Keeps checksums alive so the optimizer keeps every call.
    class_property checksum : Int64 = 0_i64

    def self.compare(label : String, candidate_name : String, baseline, candidate, calls : Int32) : PairedResult
      WARMUP_BATCHES.times do
        @@checksum &+= baseline.run
        @@checksum &+= candidate.run
      end
      list_of_baseline_ns = [] of Float64
      list_of_candidate_ns = [] of Float64
      list_of_log_ratios = [] of Float64
      random = Random.new(RANDOM_SEED)
      pair_index = 0
      while pair_index < MAX_PAIRS
        if pair_index.even?
          baseline_ns = time(baseline)
          candidate_ns = time(candidate)
        else
          candidate_ns = time(candidate)
          baseline_ns = time(baseline)
        end
        list_of_baseline_ns << baseline_ns / calls
        list_of_candidate_ns << candidate_ns / calls
        list_of_log_ratios << Math.log(candidate_ns / baseline_ns)
        pair_index += 1
        if pair_index >= MIN_PAIRS && pair_index % CHECK_EVERY == 0
          break if settled?(bootstrap_geometric_mean(list_of_log_ratios, random))
        end
      end
      PairedResult.new(
        label: label, candidate: candidate_name, pairs: pair_index, calls_per_batch: calls,
        baseline_ns: bootstrap_median(list_of_baseline_ns, random),
        candidate_ns: bootstrap_median(list_of_candidate_ns, random),
        ratio: bootstrap_geometric_mean(list_of_log_ratios, random),
        baseline_bytes_per_call: bytes_per_call(baseline, calls),
        candidate_bytes_per_call: bytes_per_call(candidate, calls))
    end

    # Returns how many repetitions of *single* fill one batch of about
    # `BATCH_TARGET_NS`.
    def self.repetitions_for(&single : -> Int32) : Int32
      repetitions = 1
      loop do
        started = Time.instant
        repetitions.times { @@checksum &+= single.call }
        elapsed = (Time.instant - started).total_nanoseconds
        return (repetitions * BATCH_TARGET_NS / elapsed).ceil.to_i.clamp(1, 50_000_000) if elapsed > BATCH_TARGET_NS / 10
        repetitions *= 4
      end
    end

    # Returns the geometric mean of the ratios whose logarithms are
    # *log_values*, with its interval.
    def self.bootstrap_geometric_mean(log_values : Array(Float64), random : Random) : Estimate
      estimate = bootstrap(log_values, random) { |values| values.sum / values.size }
      Estimate.new(Math.exp(estimate.center), Math.exp(estimate.low), Math.exp(estimate.high))
    end

    # Returns the median of *values*, with its interval.
    def self.bootstrap_median(values : Array(Float64), random : Random) : Estimate
      bootstrap(values, random) { |sample| median(sample) }
    end

    private def self.bootstrap(values : Array(Float64), random : Random, & : Array(Float64) -> Float64) : Estimate
      resample = Array(Float64).new(values.size, 0.0)
      list_of_statistics = Array(Float64).new(RESAMPLES) do
        values.size.times { |index| resample[index] = values.sample(random) }
        yield resample
      end
      list_of_statistics.sort!
      Estimate.new(yield(values), list_of_statistics[(RESAMPLES * 0.025).to_i], list_of_statistics[(RESAMPLES * 0.975).to_i - 1])
    end

    private def self.median(values : Array(Float64)) : Float64
      sorted = values.sort
      middle = sorted.size // 2
      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    end

    private def self.settled?(ratio : Estimate) : Bool
      ratio.low > 1.0 || ratio.high < 1.0 || (ratio.high - ratio.low) < WIDTH_TOLERANCE * ratio.center
    end

    private def self.time(workload) : Float64
      started = Time.instant
      @@checksum &+= workload.run
      (Time.instant - started).total_nanoseconds
    end

    private def self.bytes_per_call(workload, calls : Int32) : Float64
      before = GC.stats.total_bytes
      @@checksum &+= workload.run
      after = GC.stats.total_bytes
      (after - before).to_f / calls
    end
  end
end
