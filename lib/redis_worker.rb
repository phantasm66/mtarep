require 'redis'
require 'error_logger'

module RedisWorker

  include ErrorLogger

  def redis_connection(redis_host)
    count = 0

    begin
      connection = Redis.new(:host => redis_host)
      connection.ping
    rescue => error
      count += 1
      sleep 1
      retry unless count > 5

      log_error("Connection error with: #{redis_host}")
      log_error("Error returned: #{error}")
      exit
    end

    return connection
  end

  def redis_clean_acks(redis_host, hash, ip)
    redis = redis_connection(redis_host)

    acks = redis.keys('ack-*')
    acked = acks.clone

    return if acks.empty?

    acks.each do |ack|
      array = ack.split('-')[1..2]
      next unless array[1] == ip

      hash.each_pair do |k, v|
        issues = v.split(',')
        issues.each do |issue|
          acked.delete(ack) if issue =~ /#{array[0]}/
        end
      end
    end

    acked.each {|x| redis.del(x) if x.split('-')[2] == ip}
  end
end
