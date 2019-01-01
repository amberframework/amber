abstract class Command < Cli::Command
  def info(msg)
    Amber::CLI.logger.info msg, Class.name, :light_cyan
  end

  def error(msg)
    Amber::CLI.logger.error msg, Class.name, :red
  end
end
