require 'net/ssh'
require 'timeout'
require 'error_logger'

module Collector
  module ProviderBlocks

    include ErrorLogger

    def current_blocks(options={})
      blocks_hash = {}
      loglines = ''

      fgrep = "export LC_ALL=C && fgrep"
      all_bounced = "#{fgrep} status=bounced #{options[:maillog]} | tail -5000"
      comcast_error = "#{fgrep} #{options[:provider_block_strings]['comcast']} #{options[:maillog]} | tail -10"

      count = 0

      begin
        Net::SSH.start(options[:mta], options[:ssh_user], :paranoid => false, :keys => [options[:ssh_key]]) do |ssh|
          Timeout.timeout(240) do
            ssh.exec!(all_bounced) do |channel, stream, data|
              loglines << data if stream == :stdout
            end
          end

          Timeout.timeout(240) do
            # because comcast is so fucking special!
            ssh.exec!(comcast_error) do |channel, stream, data|
              loglines << data if stream == :stdout
            end
          end
        end
      rescue => error
        count += 1
        retry unless count > 2

        log_error('Problem encountered during ssh and remote maillog parsing')
        log_error("Error returned: #{error}")
      end

      loglines = loglines.split("\n").reverse

      options[:provider_block_strings].each_pair do |provider, string|
        options[:mta].match(/-2$/) ? pattern = '-2' : pattern = '[a-z]'
        matched = loglines.find {|x| x.match(/#{pattern}\/(smtp|error).*#{string}/)}

        next if matched.nil?

        datetime_array = matched.split[0..2]
        time_array = datetime_array[2].split(':')

        epoch_time = Time.local(Time.now.strftime("%Y"),
                                datetime_array[0],
                                datetime_array[1],
                                time_array[0],
                                time_array[1],
                                time_array[2])

        now = Time.now.to_i
        timestamp = epoch_time.to_i
        timediff = now - timestamp

        unless timediff > 7200
          blocks_hash[provider] = matched.to_s.strip
        end
      end

      return blocks_hash
    end
  end
end
