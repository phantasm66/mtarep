# encoding: utf-8
require 'logger'
require 'error_logger'
require 'dns_worker'
require 'rubygems/dependency_installer'

#
# Individual removal methods must be named the same as the block name
# (as defined in mtarep.yml), replacing dots (.) w/ an underscore
#

%w{ watir-webdriver mail }.each do |gem|
  unless Gem::Specification::find_all_by_name(gem).any?
    Gem::DependencyInstaller.new.install(gem)
    Gem.clear_paths
  end

  require gem
end

Selenium::WebDriver::PhantomJS.path = '/home/mtarep/current/phantomjs'

module Collector
  module AutoSubmission
    include DnsWorker
    include ErrorLogger

    def create_ack(redis, ack)
      redis.set(ack, "mtarep #{Time.now.to_s.split[0..1].join(' ')}")
    end

    def send_email(options={})
      if options[:email_request]
        message_body = <<-END.gsub(/^\s+/, '')
          Greetings,
          <br>
          <br>
          I would like to request a delisting of #{options[:ip]} from the #{options[:provider]} blacklist.
          <br>
          <br>
          <strong>SMTP rejection response:</strong>
          <br>
          <br>
          <font color="#000000" face="courier new, monospace">#{options[:smtp_log]}</font>
          <br>
          <br>
          Please let me know if you need any additional info to expedite the delisting
          <br>
          <br>
          <font color="#000000" face="Georgia"><strong>Josiah Webb</strong></font>
          <font color="#666666" face="Georgia"><strong>Platform Engineer</strong></font>
          <font color="#999999" face="Georgia"><strong>Blue State Digital</strong></font>
          <br>
          <br>
          <font color="#000000" face="Georgia">Blue State Digital</font>
          <br>
          <font color="#000000" face="Georgia">711 Atlantic Ave, Suite 102</font>
          <br>
          <font color="#000000" face="Georgia">Boston, MA 02111</font>
        END
      end

      if options[:spamcop]
        message_body = <<-END.gsub(/^\s+/, '')
          #{options[:message]}
          <br>
          <br>
          <strong>Provider:</strong> #{options[:provider]}
          <br>
          <strong>IP(s):</strong> #{options[:ips].join(', ')}
          <br>
          <strong>URL:</strong> #{options[:url]}
          <br>
          <br>
        END
      end

      if options[:failure]
        message_body = <<-END.gsub(/^\s+/, '')
          #{options[:message]}
          <br>
          <br>
          <strong>Provider:</strong> #{options[:provider]}
          <br>
          <strong>IP(s):</strong> #{options[:ips].join(', ')}
          <br>
          <strong>URL:</strong> #{options[:url]}
          <br>
          <strong>Error:</strong> #{options[:error]}
          <br>
          <strong>Removal page text at time of error:</strong>
          <br>
          #{options[:body].force_encoding("ASCII-8BIT")}
          <br>
        END
      end

      count = 0

      begin
        Mail.deliver do
          from     options[:from]
          to       options[:to]
          cc       'platform@bluestatedigital.com'
          subject  options[:subject]

          html_part do
            content_type         'text/html'
            content_disposition  'inline'
            body                 message_body
          end
        end
      rescue Net::SMTPUnknownError, Net::SMTPServerBusy, Net::SMTPError, Net::SMTPFatalError => error
        count += 1
        sleep 1
        retry unless count > 3

        puts "Problem sending mtarep autosubmission email (provider: #{options[:provider]} - error: #{error})"
        log_error("[ERROR] Problem sending mtarep autosubmission email (provider: #{options[:provider]} - error: #{error})")

        return :failure
      end
    end

    def comcast(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      ip_fields = %w{
        rbl_ip1
        rbl_ip2
        rbl_ip3
        rbl_ip4
        rbl_ip5
      }

      blocked_ips = ips.each_slice(5).to_a
      blocked_ips.map! {|ip_array| Hash[ip_fields.zip(ip_array)]}
      blocked_ips = blocked_ips.each {|hash| hash.delete_if {|k,v| v.to_s.strip == '' }}

      blocked_ips.each do |fields_hash|
        begin
          # load removal page
          phantom.goto(url)
          phantom.button(:value => 'Submit').wait_until_present(10)

          # form population and submission
          phantom.text_field(:name => 'FName').set basic_submission_fields['removal_fname']
          phantom.text_field(:name => 'LName').set basic_submission_fields['removal_lname']
          phantom.text_field(:name => 'Email').set basic_submission_fields['removal_email']
          phantom.text_field(:name => 'Phoned').set basic_submission_fields['removal_phone']
          phantom.text_field(:name => 'Phone').set basic_submission_fields['removal_phone']
          phantom.text_field(:name => 'rbl_domain').set basic_submission_fields['removal_domain']
          phantom.textarea(:name => 'comments').set smtp_log
          phantom.select_list(:name => 'rbl_iam').select 'Email Administrator of the blocked mail server'
          phantom.checkbox(:name => 'rbl_actions_4').set

          fields_hash.each_pair {|field, ip| phantom.text_field(:name => field).set ip}

          phantom.button(:value => 'Submit').click
          phantom.button(:value => 'Submit').wait_while_present(10)

          # wait for confirmation
          Watir::Wait.until(10) {phantom.text.include?('Thank you for your submission')}

          # create acks in redis
          fields_hash.each_pair {|field, ip| create_ack(redis, "ack-#{provider}-#{ip}")}
        rescue Watir::Wait::TimeoutError => error
          options = {
            :from => 'mtarep@bluestatedigital.com',
            :to => 'platform@bluestatedigital.com',
            :subject => "Failed #{provider} removal request autosubmission",
            :message => "A failure occurred while mtarep auto submitted a removal request",
            :provider => provider,
            :ips => fields_hash.values.join(', '),
            :url => url,
            :failure => true,
            :error => error,
            :body => phantom.text
          }

          send_email(options)
        end
      end

      phantom.close
    end

    def bl_score_senderscore_com(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      ips.each do |ip|
        begin
          # load removal page
          phantom.goto(url)
          phantom.button(:id => 'remove_btn').wait_until_present(10)

          # form population and submission
          phantom.text_field(:id => 'ssbl_lookup').set ip

          phantom.button(:id => 'remove_btn').click

          # wait for confirmation
          Watir::Wait.until(10) {phantom.text.include?("#{ip} has been submitted for removal")}

          # create ack in redis
          create_ack(redis, "ack-#{provider}-#{ip}")
        rescue Watir::Wait::TimeoutError => error
          options = {
            :from => 'mtarep@bluestatedigital.com',
            :to => 'platform@bluestatedigital.com',
            :subject => "Failed #{provider} removal request autosubmission",
            :message => "A failure occurred while mtarep auto submitted a removal request",
            :provider => provider,
            :ips => ip,
            :url => url,
            :failure => true,
            :error => error,
            :body => phantom.text
          }

          send_email(options)
        end
      end

      phantom.close
    end

    def bl_spamcop_net(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')

      unless ips.empty?
        ips.each {|ip| create_ack(redis, "ack-#{provider}-#{ip}")}

        options = {
          :from => 'mtarep@bluestatedigital.com',
          :to => 'platform@bluestatedigital.com',
          :subject => 'Spamcop ip blocks have been automatically acknowledged',
          :message => 'The following blocks have been acked in mtarep and should expire in 2 to 24 hours:',
          :provider => provider,
          :ips => ips.join(', '),
          :url => url,
          :spamcop => true
        }

        send_email(options)
      end
    end

    def cidr_bl_mcafee_com(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')

      unless ips.empty?
        ips.each do |ip|
          options = {
            :from => 'platform@bluestatedigital.com',
            :to => 'ts-feedback@mcafee.com',
            :subject => 'False Positive/ Delisting Request',
            :provider => provider,
            :ip => ip,
            :smtp_log => smtp_log,
            :email_request => true
          }

          send_status = send_email(options)

          unless send_status == :failure
            create_ack(redis, "ack-#{provider}-#{ip}")
          end
        end
      end
    end

    def earthlink(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')

      unless ips.empty?
        ips.each do |ip|
          options = {
            :from => 'platform@bluestatedigital.com',
            :to => 'blockedbyearthlink@abuse.earthlink.net',
            :subject => "Blocked #{ip}",
            :provider => provider,
            :ip => ip,
            :smtp_log => smtp_log,
            :email_request => true
          }

          send_status = send_email(options)

          unless send_status == :failure
            create_ack(redis, "ack-#{provider}-#{ip}")
          end
        end
      end
    end

    def maps(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      ips.each do |ip|
        begin
          # load removal page
          phantom.goto(url)
          phantom.link(:id => 'IPLookupBtn').wait_until_present(10)

          expected_href = "/reputations/block/#{ip}/QIL"

          # form population and submission
          phantom.text_field(:id => 'ReputationIp').set ip

          # submit and wait for removal link
          phantom.link(:id => 'IPLookupBtn').click
          phantom.link(:href => expected_href).wait_until_present(10)

          # click removal link
          phantom.link(:href => expected_href).click
          phantom.link(:href => expected_href).wait_while_present(10)

          # wait for confirmation
          Watir::Wait.until(10) {phantom.html.include?('QILExemptionResult removed')}

          # create ack in redis
          create_ack(redis, "ack-#{provider}-#{ip}")
        rescue Watir::Wait::TimeoutError => error
          options = {
            :from => 'mtarep@bluestatedigital.com',
            :to => 'platform@bluestatedigital.com',
            :subject => "Failed #{provider} removal request autosubmission",
            :message => "A failure occurred while mtarep auto submitted a removal request",
            :provider => provider,
            :ips => ip,
            :url => url,
            :failure => true,
            :error => error,
            :body => phantom.text
          }

          send_email(options)
        end

        sleep 3
      end

      phantom.close
    end

    def united(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      begin
        # load removal page
        phantom.goto(url)
        phantom.button(:type => 'submit').wait_until_present(10)

        # form population and submission
        phantom.text_field(:name => 'organisation').set 'Blue State Digital'
        phantom.text_field(:name => 'name').set "#{basic_submission_fields['removal_fname']} #{basic_submission_fields['removal_lname']}"
        phantom.text_field(:name => 'email').set basic_submission_fields['removal_email']
        phantom.text_field(:name => 'email_unsubscribe').set 'bounce@bounce.bluestatedigital.com'
        phantom.input(:name => 'txtDate').send_keys Time.now.strftime("%m/%d/%Y")
        phantom.textarea(:name => 'description').set 'bulk email sender'
        phantom.textarea(:name => 'mail_del_failure').set smtp_log
        phantom.textarea(:name => 'ipaddresses').set ips.join(' ')

        phantom.button(:type => 'submit').click
        phantom.button(:type => 'submit').wait_while_present(10)

        # wait for confirmation
        Watir::Wait.until(10) {phantom.text.include?('Thank You')}

        # create acks in redis
        ips.each {|ip| create_ack(redis, "ack-#{provider}-#{ip}")}
      rescue Watir::Wait::TimeoutError => error
        options = {
          :from => 'mtarep@bluestatedigital.com',
          :to => 'platform@bluestatedigital.com',
          :subject => "Failed #{provider} removal request autosubmission",
          :message => "A failure occurred while mtarep auto submitted a removal request",
          :provider => provider,
          :ips => ips.join(', '),
          :url => url,
          :failure => true,
          :error => error,
          :body => phantom.text
        }

        send_email(options)
      end

      phantom.close
    end

    def verizon(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      begin
        # load removal page
        phantom.goto(url)
        phantom.button(:value => 'Submit').wait_until_present(10)

        # form population and submission
        phantom.text_field(:name => 'firstName').set basic_submission_fields['removal_fname']
        phantom.text_field(:name => 'lastName').set basic_submission_fields['removal_lname']
        phantom.text_field(:name => 'companyName').set 'Blue State Digital'
        phantom.text_field(:name => 'emailAddress').set basic_submission_fields['removal_email']
        phantom.text_field(:name => 'emailAddressConfirmation').set basic_submission_fields['removal_email']
        phantom.text_field(:name => 'phoneNumber').set basic_submission_fields['removal_phone']
        phantom.textarea(:name => 'domains').set basic_submission_fields['removal_domain']
        phantom.textarea(:name => 'smtpServers').set ips.join(',')
        phantom.radio(:name => 'spfRecords', :value => 'Yes').set

        phantom.button(:value => 'Submit').click
        phantom.button(:value => 'Submit').wait_while_present(10)

        # wait for confirmation
        Watir::Wait.until(10) {phantom.text.include?('Whitelist Request Form Confirmation')}

        # create acks in redis
        ips.each {|ip| create_ack(redis, "ack-#{provider}-#{ip}")}
      rescue Watir::Wait::TimeoutError => error
        options = {
          :from => 'mtarep@bluestatedigital.com',
          :to => 'platform@bluestatedigital.com',
          :subject => "Failed #{provider} removal request autosubmission",
          :message => "A failure occurred while mtarep auto submitted a removal request",
          :provider => provider,
          :ips => ips.join(', '),
          :url => url,
          :failure => true,
          :error => error,
          :body => phantom.text
        }

        send_email(options)
      end

      phantom.close
    end

    def cox(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      ips.each do |ip|
        begin
          # load removal page
          phantom.goto(url)
          phantom.button(:value => 'Submit').wait_until_present(10)

          # form population and submission
          phantom.text_field(:name => 'FirstName').set basic_submission_fields['removal_fname']
          phantom.text_field(:name => 'LastName').set basic_submission_fields['removal_lname']
          phantom.text_field(:name => 'from').set basic_submission_fields['removal_email']
          phantom.text_field(:name => 'Phone').set basic_submission_fields['removal_phone']
          phantom.text_field(:name => 'DomainName').set basic_submission_fields['removal_domain']
          phantom.text_field(:name => 'RangeOfMailServers').set ip
          phantom.textarea(:name => 'problem').set smtp_log
          phantom.textarea(:name => 'resolveSteps').set smtp_log
          phantom.select_list(:name => 'problemCategory').select 'My IP is being blocked'

          phantom.button(:value => 'Submit').click
          phantom.button(:value => 'Submit').wait_while_present(10)

          # wait for confirmation
          Watir::Wait.until(10) {phantom.text.include?('unblock request has been submitted')}

          # create acks in redis
          ips.each {|ip| create_ack(redis, "ack-#{provider}-#{ip}")}
        rescue Watir::Wait::TimeoutError => error
          options = {
            :from => 'mtarep@bluestatedigital.com',
            :to => 'platform@bluestatedigital.com',
            :subject => "Failed #{provider} removal request autosubmission",
            :message => "A failure occurred while mtarep auto submitted a removal request",
            :provider => provider,
            :ips => ip,
            :url => url,
            :failure => true,
            :error => error,
            :body => phantom.text
          }

          send_email(options)
        end
      end

      phantom.close
    end

    def gmail(ips=[], url, smtp_log, basic_submission_fields, redis)
      provider = __method__.to_s.gsub('_', '.')
      phantom = Watir::Browser.new(:phantomjs, :args => ['--ignore-ssl-errors=yes', '--ssl-protocol=tlsv1'])

      # install netcat if needed
      %x{rpm -q nc > /dev/null}
      %x{yum install -y --quiet nc} unless $?.exitstatus == 0

      # install dig if needed
      %x{rpm -q bind-utils > /dev/null}
      %x{yum install -y --quiet bind-utils} unless $?.exitstatus == 0

      # install ping if needed
      %x{rpm -q iputils > /dev/null}
      %x{yum install -y --quiet iputils} unless $?.exitstatus == 0

      log_file = '/tmp/smtp_log'
      rcpt_address = smtp_log.split.select {|x| x.match('to=<')}[0].split(/[<>]/)[1]
      mxs = %x{dig mx gmail.com +short}.split("\n").map {|x| x.split[1]}
      telnet_results = %x{echo 'HELO test.bluestatedigital.com' | nc #{mxs[0]} 25}
      telnet_results = "Connected to #{mxs[0]}\n" + telnet_results
      ping_results = %x{ping -c 1 #{mxs[0]}}

      # dump smtp_log to a temp file for uploading
      File.open(log_file, "w") {|file| file.puts smtp_log}

      begin
        # load removal page
        phantom.goto(url)
        phantom.divs(:class => /submit-button/).wait_until_present(10)

        # form population and submission
        phantom.text_field(:name => 'contact_email').set basic_submission_fields['removal_email']
        phantom.text_field(:name => 'affected_domain').set basic_submission_fields['removal_domain']
        phantom.select_list(:name => 'users_in_domain').select '500-999'
        phantom.text_field(:name => 'affected_users').set rcpt_address
        phantom.text_field(:name => 'brief_summary').set 'Google is rejecting emails from our domain/ips'
        phantom.file_field(:name => 'Filedata').set log_file
        phantom.form(:action => /upload_id/).wait_until_present(10)
        phantom.textarea(:name => 'smtp').set log_file
        phantom.textarea(:name => 'firewall').set 'none'
        phantom.textarea(:name => 'dns_lookup').set mxs.join("\n")
        phantom.textarea(:name => 'telenet_lookup').set telnet_results
        phantom.textarea(:name => 'ping_lookup').set ping_results
        phantom.textarea(:name => 'additional_body').set 'none'

        phantom.divs(:class => /submit-button/).click
        phantom.divs(:class => /submit-button/).wait_while_present(10)

        # wait for confirmation
        Watir::Wait.until(10) {phantom.text.include?('Thank you for your report')}

        # create acks in redis
        ips.each {|ip| create_ack(redis, "ack-#{provider}-#{ip}")}
      rescue Watir::Wait::TimeoutError => error
        options = {
          :from => 'mtarep@bluestatedigital.com',
          :to => 'platform@bluestatedigital.com',
          :subject => "Failed #{provider} removal request autosubmission",
          :message => "A failure occurred while mtarep auto submitted a removal request",
          :provider => provider,
          :ips => ips.join(', '),
          :url => url,
          :failure => true,
          :error => error,
          :body => phantom.text
        }

        send_email(options)
      end

      phantom.close
    end

    #
    # NOTE: don't add *anything* after this run_removals method!
    #
    def run_removals(auto_submissions, redis)
      acks = redis.keys('ack*')
      basic_submission_fields = auto_submissions.delete(:basic_submission_fields)
      block_urls = auto_submissions.delete(:block_urls)
      log = Logger.new('/var/log/bsd/mtarep_collector_runs.log')

      acks_from_auto_submissions = []
      final_submissions = []
      smtp_logs = {}

      auto_submissions.each_pair do |ip, blocks_hash|
        blocks_hash.each_pair do |block_type, blocks|
          if blocks.class == String
            next if blocks.match(/(no\sblocks|unlisted)/)
          end

          case block_type
            when :rbl_blocks
            blocks.split(',').each do |rbl|
              acks_from_auto_submissions << "ack-#{rbl}-#{ip}"
              next if acks.include?("ack-#{rbl}-#{ip}")
              final_submissions << {rbl => ip}
              smtp_logs[rbl] = nil
            end

            when :provider_blocks
            blocks.each_pair do |provider, smtp_log|
              acks_from_auto_submissions << "ack-#{provider}-#{ip}"
              next if acks.include?("ack-#{provider}-#{ip}")
              final_submissions << {provider => ip}
              smtp_logs[provider] = smtp_log
            end
          end
        end
      end

      merged_hashes = final_submissions.each_with_object({}) do |item, hash|
        k,v = item.shift
        (hash[k] ||= []) << v
      end

      final_submissions = merged_hashes.map {|k,v| {k => v}}

      # initiate removals!
      final_submissions.each do |hash|
        hash.each do |blocker, blocked_ips|
          begin
            method_name = blocker.gsub('.', '_')
            log.info("[INFO] attempting to auto-submit a removal request for #{blocker.gsub('_', '.')}")

            if method_name.match('maps')
              if smtp_logs[blocker].match('RBL')
                next
              end
            end

            send(method_name, blocked_ips, block_urls[blocker], smtp_logs[blocker], basic_submission_fields, redis)
          rescue NoMethodError => error
            log.info("[INFO] sorry... mtarep does not have an auto submitter defined for #{blocker.gsub('_', '.')}")
            log.info("[INFO] error: #{error}")
            next
          end
        end
      end

      # cleanup any orphaned redis acks
      acks_from_auto_submissions.each {|ack| acks.delete(ack)}
      acks.each {|ack| redis.del(ack)} unless acks.empty?
    end
  end
end
