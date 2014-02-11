require 'hosts'
require 'rbls'
require 'snds'
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

      mta_map(options[:mta_map]).each_pair do |ip, mta|
        snds = []

        score = dns_lookup(ip, 'score.senderscore.com')
        rbls = rbl_listings(ip, options[:rbls])
        mta_shortname = mta.split('.')[0]

        snds_data.each_pair do |ip_address, data|
          next unless ip_address == ip
          snds = data
          break
        end

        snds.empty? ? snds = ['no data', 'no data'] : snds

        blocks = current_blocks({ :mta => mta,
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
            redis.hmset(id, mta_shortname, log)

            blocks_array << "#{provider}:#{id}"
          end

          blocks = blocks_array.join(',')
        end

        fields = {
          :hostname => mta,
          :senderscore => score,
          :sndscolor => snds[0],
          :sndstraps => snds[1],
          :provblocks => blocks,
          :listings => rbls[ip]
        }

        begin
          redis.del(ip)

          new_redis_data = fields.to_a.flatten
          new_redis_data.each {|data| redis.rpush(ip, data)}

          redis_clean_acks(options[:redis_host], fields, ip)
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
