#!/usr/bin/env ruby
# encoding: utf-8

libs = File.expand_path("../**/*", __FILE__)
$:.unshift *Dir.glob(libs)

require 'runner'
require 'yaml'

include Collector::Runner

yaml_config = File.expand_path("../config/mtarep.yml", __FILE__)
config = YAML.load_file(yaml_config)

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
                :redis_server => config['redis_server'],
                :removal_links => config['removal_links'] })
