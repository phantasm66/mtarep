require 'logger'

module ErrorLogger
  def log_error(message)
    logger = Logger.new(ENV['ERROR_LOG'])
    logger.error(message)
  end
end
