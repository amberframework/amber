require "./helpers"

module Sentry
  class ProcessRunner
    Log = ::Log.for("watch")

    property processes = Hash(String, Array(Process)).new
    property process_name : String
    FILE_TIMESTAMPS = Hash(String, Int64).new

    def initialize(
      @process_name : String,
      @build_commands = Hash(String, String).new,  # { "task1" => [ ... ], "task2" => [ ... ] }
      @run_commands = Hash(String, String).new,    # { "task1" => [ ... ], "task2" => [ ... ] }
      @includes = Hash(String, Array(String)).new, # { "task1" => [ ... ], "task2" => [ ... ] }
      @excludes = Hash(String, Array(String)).new  # { "task1" => [ ... ], "task2" => [ ... ] }
    )
      @app_running = false
    end

    def run
      scan_files(no_actions: true)
      start_processes

      loop do
        scan_files
        check_processes
        sleep 1
      end
    end

    private def scan_files(no_actions = false)
      # build a list of all files, with their associated tasks
      all_files = Hash(String, Array(String)).new # { "file" => [ "task1", "task2" ]}
      changed_files = Array(String).new

      @includes.each do |task, includes|
        excluded_files = Array(String).new
        if (excludes = @excludes[task]?)
          excludes.each { |glob| excluded_files += Dir.glob(glob) }
        end
        includes.each do |glob|
          Dir.glob(glob).each do |f|
            next if excluded_files.includes?(f)
            all_files[f] ||= Array(String).new
            all_files[f] << task
          end
        end
      end

      all_files.each do |file, tasks|
        timestamp = get_timestamp(file)
        if FILE_TIMESTAMPS[file]? != timestamp
          FILE_TIMESTAMPS[file] = timestamp
          unless no_actions
            log :scan, "File changed: #{file.colorize(:light_gray)} (will notify: #{tasks.join(", ")})"
            changed_files << file
          end
        end
      end

      return if no_actions || changed_files.empty?

      tasks_to_run = Hash(String, Int32).new
      changed_files.each do |file|
        all_files[file].each do |task|
          tasks_to_run[task] ||= 0
          tasks_to_run[task] += 1
        end
      end

      tasks_to_run.each do |task, changed_file_count|
        log task, "#{changed_file_count} file(s) changed."
        start_processes(task)
      end
    end

    # restart dead processes (currently limited to run task)
    private def check_processes
      @processes.each do |task, procs|
        # clean up process list and restart if terminated
        if procs.any?
          procs.reject!(&.terminated?)

          if procs.empty?
            # restarting currently limited to run task (server process), otherwise just notify
            if task == "run"
              log task, "All processes died. Trying to restart..."
              start_processes(task, skip_build: true)
            else
              log task, "Exited"
            end
          end
        end
      end
    end

    private def stop_processes(task_to_stop = :all)
      @processes.each do |task, procs|
        next unless task_to_stop == :all || task_to_stop.to_s == task

        if task == "run"
          log task, "Terminating app #{project_name}..."
        else
          log task, "Terminating process..."
        end
        procs.each do |process|
          {% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
            process.signal(:term) unless process.terminated?
          {% else %}
            process.kill unless process.terminated?
          {% end %}
        end
        procs.clear
      end
    end

    private def start_processes(task_to_start = :all, skip_build = false)
      if task_to_start == :all || task_to_start == "run"
        # handle run task first, exit immediately if it fails
        if (build_command_run = @build_commands["run"]) && (run_command_run = @run_commands["run"])
          ok_to_run = false
          if skip_build
            ok_to_run = true
          else
            log :run, "Building..."
            time = Time.monotonic
            build_result = Amber::CLI::Helpers.run(build_command_run)
            exit 1 unless build_result.is_a? Process::Status
            if build_result.success?
              log :run, "Compiled in #{(Time.monotonic - time)}"
              stop_processes("run") if @app_running
              ok_to_run = true
            elsif !@app_running # first run
              log :run, "Compile time errors detected, exiting...", :red
              exit 1
            end
          end

          if ok_to_run
            start_process(run_command_run)
            @app_running = true
          end
        else
          log :run, "Build or run commands missing for run task, exiting...", :red
          exit 1
        end
      end

      run_commands(skip_build, task_to_start)
    end

    private def start_process(run_command_run)
      process = Amber::CLI::Helpers.run(run_command_run, wait: false, shell: false)
      if process.is_a? Process
        @processes["run"] ||= Array(Process).new
        @processes["run"] << process
      elsif process.is_a? Exception
        log :run, "Could not run (#{process.message}), exiting...", :red
        log :run, "Please check your watch config and try again.", :red
        exit 1
      end
    end

    private def run_commands(skip_build, task_to_start)
      @run_commands.each do |task, run_command|
        next if task == "run" # already handled
        next unless task_to_start == :all || task_to_start.to_s == task

        if (build_command = @build_commands[task]?) && !skip_build
          log task, "Building..."
          build_result = Amber::CLI::Helpers.run(build_command)
          next unless build_result.is_a? Process::Status

          if build_result.success?
            Amber::CLI::Helpers.run(build_command)
          else
            log task, "Build step failed."
            next # don't continue to run command step
          end
        end

        log task, "Starting..."
        process = Amber::CLI::Helpers.run(run_command, wait: false, shell: true)
        if process.is_a? Process
          @processes[task] ||= Array(Process).new
          @processes[task] << process
        end
      end
    end

    private def get_timestamp(file : String)
      File.info(file).modification_time.to_unix
    end

    private def project_name
      process_name.capitalize.colorize(:white)
    end

    private def log(task, msg, color = :light_gray)
      Log.for(task.to_s).info { msg.colorize(color) }
    end
  end
end
