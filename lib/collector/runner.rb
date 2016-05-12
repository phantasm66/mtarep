# encoding: utf-8
require 'hosts'
require 'rbls'
require 'influxdb'
require 'snds'
require 'logger'
require 'brightmail'
require 'dns_worker'
require 'securerandom'
require 'error_logger'
require 'redis_worker'
require 'provider_blocks'
require 'auto_submission'

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
    include Collector::AutoSubmission

    def pid_cleanup(active_pid, command)
      pid = nil
      log = Logger.new('/var/log/bsd/mtarep_collector_runs.log')

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

      unless pid.nil?
        log.info("[INFO] found previously running collector... killing pid: #{pid} to avoid collisions")
        Process.kill('KILL', pid)
      end
    end

    def run_collector(options={})
      log = Logger.new('/var/log/bsd/mtarep_collector_runs.log')
      log.info("[INFO] starting new mtarep collector run")

      pid_cleanup(options[:active_pid], options[:command])

      snds_data = snds_data(options[:snds_key])
      redis = redis_connection(options[:redis_server])

      influxdb_timestamp = Time.now.to_i

      auto_submissions = {}

      mta_map(options[:mta_map]).each do |mta_data|
        snds = []

        log.info("[INFO] looking up ReturnPath SenderScore for ip #{mta_data[:ip]}")
        score = score_lookup(mta_data[:ip])
        log.info("[INFO] ReturnPath SenderScore for ip #{mta_data[:ip]} is: #{score}")

        log.info("[INFO] checking if ip #{mta_data[:ip]} is listed on any well known rbls")
        rbls = rbl_listings(mta_data[:ip], options[:rbls])

        if rbls[mta_data[:ip]] == 'unlisted'
          log.info("[INFO] ip #{mta_data[:ip]} is not listed on any well known rbls")
        else
          log.info("[INFO] ip #{mta_data[:ip]} is currently listed on the following rbls: #{rbls[mta_data[:ip]]}")
        end

        log.info("[INFO] retreiving any available microsoft SNDS data for ip #{mta_data[:ip]}")
        snds_data.each_pair do |ip_address, data|
          next unless ip_address == mta_data[:ip]
          snds = data
          log.info("[INFO] found the following microsoft SNDS data for ip #{mta_data[:ip]}: #{snds}")
          break
        end

        snds.empty? ? snds = ['no data', 'no data'] : snds

        log.info("[INFO] checking ISP/ESP blocks for ip #{mta_data[:ip]}")
        provider_blocks = current_blocks({ :mta => mta_data[:ssh_host],
                                  :provider_block_patterns => options[:provider_block_patterns],
                                  :ssh_user => options[:ssh_user],
                                  :ssh_key => options[:ssh_key],
                                  :maillog => mta_data[:maillog_path],
                                  :shortname => mta_data[:shortname] })

        if provider_blocks == 'no blocks'
          log.info("[INFO] no ISP/ESP blocks found for ip #{mta_data[:ip]}")
        else
          log.info("[INFO] found the following ISP/ESP blocks for ip #{mta_data[:ip]}: #{provider_blocks}")
        end

        auto_submission_provider_blocks = provider_blocks

        if provider_blocks.class == Hash
          blocks_array = []
          provider_blocks.each_pair do |provider, log|
            log = log.gsub(/(<|>)/, '')
            id = SecureRandom.hex(13)
            redis.hmset(id, mta_data[:shortname], log)

            blocks_array << "#{provider}:#{id}"
          end

          provider_blocks = blocks_array.join(',')
        end

        fields = {
          :hostname => mta_data[:fqdn],
          :dns => dns_match?(mta_data[:ip], mta_data[:fqdn]),
          :senderscore => score,
          :sndscolor => snds[0],
          :sndstraps => snds[1],
          :brightmail => brightmail_reputation(mta_data[:ip]),
          :provblocks => provider_blocks,
          :listings => rbls[mta_data[:ip]]
        }

        # dump fields per mta (audit trail of listings)
        log = Logger.new('/var/log/bsd/mtarep_collector_runs.log')
        log.info("[INFO] PRE-OVERWRITE ACKS: #{redis.keys('ack-*').join(', ')}")
        log.info("[INFO] COLLECTOR OVERWRITE DATA: #{fields.to_json}")

        #
        # push data to redis
        #
        begin
          redis.del(mta_data[:ip])

          new_redis_data = fields.to_a.flatten
          new_redis_data.each {|data| redis.rpush(mta_data[:ip], data)}

          redis_clean_acks(options[:redis_server], fields, mta_data[:ip])

        rescue Redis::CannotConnectError, Redis::ConnectionError, Redis::TimeoutError => error
          log_error('Problem encountered during a redis operation')
          log_error("Redis server returned: #{error}")
        end

        log.info("[INFO] POST-OVERWRITE ACKS: #{redis.keys('ack-*').join(', ')}")

        #
        # send data to influxdb
        #
        influxdb = InfluxDB::Client.new(
          'mtarep',
          :host => 'influxdb.bsdinternal.com',
          :port => 443,
          :username => 'mtarep',
          :password => 'mt4r3p',
          :use_ssl => true,
          :retry => 5
        )

        # convert sndscolor to an integer metric
        case fields[:sndscolor]
          when 'no data' then sndscolor_level = 0
          when 'green' then sndscolor_level = 0
          when 'yellow' then sndscolor_level = 50
          when 'red' then sndscolor_level = 100
        end

        # convert brightmail to an integer metric
        case fields[:brightmail]
          when 'error' then brightmail_level = 0
          when 'good' then brightmail_level = 0
          when 'neutral' then brightmail_level = 0
          when 'bad' then brightmail_level = 100
        end

        # convert provblocks to an integer metric
        case fields[:provblocks]
          when 'error' then provblocks_count = 0
          when 'no blocks' then provblocks_count = 0
          else provblocks_count = fields[:provblocks].split(',').count
        end

        # convert listings to an integer metric
        case fields[:listings]
          when 'error' then rbl_listings_count = 0
          when 'unlisted' then rbl_listings_count = 0
          else rbl_listings_count = fields[:listings].split(',').count
        end

        begin
          influxdb.write_point("mtarep.raw.#{fields[:hostname].split('.')[0]}",
            :senderscore => fields[:senderscore].to_i,
            :sndscolor => sndscolor_level,
            :sndstraps => fields[:sndstraps].to_i,
            :brightmail => brightmail_level,
            :provblocks => provblocks_count,
            :listings => rbl_listings_count,
            :time => influxdb_timestamp
          )
        rescue InfluxDB::Error, InfluxDB::AuthenticationError, InfluxDB::ConnectionError => error
          log_error('Problem encountered during inserts to influxdb.bsdinternal.com:mtarep.mtarep')
          log_error("Error: #{error}")
        end

        auto_submissions[mta_data[:ip]] = {
          :provider_blocks => auto_submission_provider_blocks,
          :rbl_blocks => fields[:listings]
        }
      end

      auto_submissions[:basic_submission_fields] = options[:basic_submission_fields]
      auto_submissions[:block_urls] = options[:removal_links]

      # auto submit removals
      run_removals(auto_submissions, redis)

      begin
        redis.del('rbls')
        # update rbl list
        options[:rbls].each {|rbl| redis.rpush('rbls', rbl)}

        redis.del('removal_links')
        redis.mapped_hmset('removal_links', options[:removal_links])
      rescue => error
        log_error('Problem encountered during a redis operation')
        log_error("Redis server returned: #{error}")
      end

      log.info("[INFO] finished mtarep collector run")
    end
  end
end
