# encoding: utf-8
require 'error_logger'

module Collector
  module ProviderBlocks
    include ErrorLogger

    def current_blocks(options={})
      blocks_hash = {}
      ssh_options = '-o StrictHostKeyChecking=no'

      prov_patterns = options[:provider_block_patterns].values.join('|')
      shortname = options[:shortname].split('.')[0]

      if options[:mta].match('powermta')
        remote_cmd = "egrep '(#{prov_patterns}).*,#{shortname},.*' #{options[:maillog]}"
      else
        remote_cmd = "tail -500000 #{options[:maillog]} | egrep '(#{prov_patterns})'"
      end

      loglines = %x{ssh -i #{options[:ssh_key]} #{ssh_options} #{options[:ssh_user]}@#{options[:mta]} "#{remote_cmd}"}
      loglines = loglines.split("\n").reverse

      options[:provider_block_patterns].each_pair do |provider, pattern|
        matched = loglines.find {|x| x.match(/#{pattern}/)}

        next if matched.nil?

        unless options[:mta].match('powermta')
          datetime_array = matched.split[0..2]
          time_array = datetime_array[2].split(':')
          epoch_time = Time.local(Time.now.strftime("%Y"), datetime_array[0], datetime_array[1], time_array[0], time_array[1], time_array[2])

          next if Time.now.to_i - epoch_time.to_i > 7200
        end

        blocks_hash[provider] = matched.to_s.strip
      end

      blocks_hash = 'no blocks' if blocks_hash.empty?
      return blocks_hash
    end
  end
end
