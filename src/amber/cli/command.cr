abstract class Command < Cli::Command
  def puts(msg)
    Amber::CLI.logger.info msg, Class.name, :light_cyan
  end
end
