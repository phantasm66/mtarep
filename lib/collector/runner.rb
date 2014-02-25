# encoding: utf-8
require 'hosts'
require 'rbls'
require 'snds'
require 'brightmail'
require 'dns_worker'
require 'securerandom'
require 'error_logger'
require 'redis_worker'
require 'provider_blocks'

module Collector
  module Runner

    include DnsWorker
    include ErrorLogger
    include RedisWorker
    include Collector::Hosts
    include Collector::ProviderBlocks
    include Collector::Rbls
    include Collector::Snds
    include Collector::Brightmail

    def pid_cleanup(active_pid, command)
      pid = nil

      Dir.glob("/proc/*/cmdline").each do |ps|
        begin
          if IO.read(ps).match(command)
            pid = ps.split('/')[2].to_i

            if pid == active_pid
              pid = nil
              next
            end
          end
        rescue Errno::ENOENT
          next
        end
      end

      Process.kill('KILL', pid) unless pid.nil?
    end

    def run_collector(options={})
      pid_cleanup(options[:active_pid], options[:command])

      snds_data = snds_data(options[:snds_key])
      redis = redis_connection(options[:redis_host])

      mta_map(options[:mta_map]).each do |mta_data|
        snds = []

        score = score_lookup(mta_data[:ip])
        rbls = rbl_listings(mta_data[:ip], options[:rbls])

        snds_data.each_pair do |ip_address, data|
          next unless ip_address == mta_data[:ip]
          snds = data
          break
        end

        snds.empty? ? snds = ['no data', 'no data'] : snds

        blocks = current_blocks({ :mta => mta_data[:alias],
                                  :provider_block_strings => options[:provider_block_strings],
                                  :ssh_user => options[:ssh_user],
                                  :ssh_key => options[:ssh_key],
                                  :maillog => options[:maillog] })

        if blocks.empty?
          blocks = 'no blocks'
        elsif blocks.key?('error')
          blocks = blocks['error']
        else
          blocks_array = []

          blocks.each_pair do |provider, log|
            id = SecureRandom.hex(13)
            redis.hmset(id, mta_data[:alias], log)

            blocks_array << "#{provider}:#{id}"
          end

          blocks = blocks_array.join(',')
        end

        fields = {
          :hostname => mta_data[:fqdn],
          :senderscore => score,
          :sndscolor => snds[0],
          :sndstraps => snds[1],
          :brightmail => brightmail_reputation(mta_data[:ip]),
          :provblocks => blocks,
          :listings => rbls[mta_data[:ip]]
        }

        begin
          redis.del(mta_data[:ip])

          new_redis_data = fields.to_a.flatten
          new_redis_data.each {|data| redis.rpush(mta_data[:ip], data)}

          redis_clean_acks(options[:redis_host], fields, mta_data[:ip])
        rescue => error
          log_error('Problem encountered during a redis operation')
          log_error("Redis server returned: #{error}")
        end
      end

      # now update rbl & removal link lists in redis!

      begin
        redis.del('rbls')
        options[:rbls].each {|rbl| redis.rpush('rbls', rbl)}

        redis.del('removal_links')
        redis.mapped_hmset('removal_links', options[:removal_links])
      rescue => error
        log_error('Problem encountered during a redis operation')
        log_error("Redis server returned: #{error}")
      end
    end
  end
end
