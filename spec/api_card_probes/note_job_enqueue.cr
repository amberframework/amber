require "./probe_support"

job = APICardProbeJob.new(42_i64)
typeof(job.enqueue(queue: "import-data", delay: 5.minutes)).should eq(Amber::Jobs::JobEnvelope)
