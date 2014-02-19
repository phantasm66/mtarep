#!/usr/bin/env ruby
# encoding: utf-8

$:.unshift File.expand_path('lib')
$:.unshift File.expand_path('lib/collector')

require 'runner'
require 'yaml'

include Collector::Runner

config = YAML.load_file('config/mtarep.yml')
ENV['ERROR_LOG'] = config['error_log']

run_collector({ :active_pid => Process.pid,
                :command => File.expand_path($0),
                :rbls => config['rbls'],
                :mta_map => config['mta_map'],
                :snds_key => config['snds_key'],
                :provider_block_strings => config['provider_block_strings'],
                :ssh_user => config['ssh_user'],
                :ssh_key => config['ssh_key'],
                :maillog => config['maillog_path'],
                :redis_host => config['redis_host'],
                :removal_links => config['removal_links'] })
