abstract class Command < Cli::Command
  Log = ::Log.for(self)

  def info(msg)
    Log.info { msg.colorize(:light_cyan) }
  end

  def error(msg)
    Log.error { msg.colorize(:light_red) }
  end
end
