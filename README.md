MTAREP
================================
Collect and report on your mail servers' reputation, deliverability and rbl statistics.

Requirements
------------
    Thin
    Sinatra
    Redis Server
    Redis RubyGem
    Net/SSH RubyGem
    Postfix MTA

Overview
--------
The following data is collected and displayed for each postfix MTA you report on using mtarep:

    ReturnPath's Sender Score
    Microsoft's SNDS (Smart Network Data Services)
    Postfix Maillog SMTP Rejection Blocks
    RBL/DNSBL Listings

All the data is collected and inserted into a redis data store whenever the collector completes a run. The collector (collector.rb) can be scheduled via cron. The sinatra webapp (app.rb) handles generating the HTML and retrieving the data from redis.

Web Interface
-------------
![Alt text](screenshots/mtarep-webui-example.png?raw=true)

When a provider block or rbl cell contains a listing, it becomes clickable. For provider blocks, when you click a block link a modal appears containing the most recent smtp rejection message from your server's maillog (location and access are configurable in the mtarep-conf.yml file), as well details about the listing and a direct link to that provider's block removal form or instructions. The same scenario occurs for rbl listings as well minus the maillog info, because mtarep queries rbl lists directly over dns (you can customize the list of rbls queried in the mtarep-conf.yml file as well).

Each issue's modal contains an acknowledgement button that can be clicked once you begin working an mtarep reported issue. When the acknowledgement button is clicked, a unique key is inserted back into redis that holds all the details about the listing, the date and time it was acknowledged, and by which http authenticated username. Once acknowledged, the modal no longer displays an acknowledgement button, but instead displays the date, time and username that acknowledged the issue. This prevents multiple users working the same issue unknowingly.

Each column header in the web interface allows for rows sorting (eg: sort by rbl listings, microsoft SNDS filtering or trap hits, hostname, etc..)

Graphing
--------
![Alt text](screenshots/mtarep-graphs-example.png?raw=true)

The included graphing will require you to configure a few things outside the scope of mtarep.

Sent, bounced, expired and feedback loop count graphs can be easily configured for the domains of your choosing via the 'graph_domains' list array section in the included mtarep-conf.yml configuration file. The graphing is provided by the [HighCharts JS API](http://www.highcharts.com/products/highcharts). The individual bar graphs can be removed from view to allow more granular detail on the remaining bar graphs. This is particularly helpful if your sent total bar graph obfuscates the shit out of the bounce, fbl or expired graphs (deliverability hint: you want this to happen!).

The graph data is calculated from midnight on the current day and continues to be calculated until 11:59pm on that same day. The data used to calculate the sent, bounced, fbl and expired bar graphs is not *collected* by mtarep. However, bar graphs will be calculated and rendered by mtarep if the appropriate data exists in the same redis db used by mtarep.

The mtarep graphing web interface will search redis for keys in the format of:

    20140208:expired
    20140208:fbl
    20140208:bounced
    20140208:sent

*Where 20140208 is the current date*

These keys contain an incrementing total for each unique domain that has been sent, bounced, expired or feedback-loop received.

The exact redis operation is HINCRBY (http://redis.io/commands/hincrby).

Using the redis rubygem, you could do something like this to increment a counter for each bounced email to gmail.com:
```ruby
key = [Time.now.strftime("%Y%m%d")]
key << 'bounced'
@redis.hincrby(key.join(':'), 'gmail.com', 1)
```

This would update the increment counter on the 'gmail.com' field for redis key '20140208:bounced' by 1 for each bounced 'gmail.com' message that is processed by this code. This could be easily accomplished by creating a custom redis output plugin with [Logstash](https://github.com/logstash/logstash) to filter and ship this data directly from your postfix mail logs.

Configuration
-------------
Please adjust and remove the '.example' appendage from the included example configs to config.ru, mtarep-thin.yml and mtarep-conf.yml accordingly.
All configuration of mtarep is managed from the app's main YAML configuration file (mtarep-conf.yml).

Individual mtarep-conf.yml configuration settings:

**error_log**
---
The absolute path to your main mtarep error log file. All directories in the path must already exist. If the error log file does not exist, it will be created.

**redis_server**
---
The DNS resolvable hostname of your redis server. Your redis server will be accessed over the default port of 6379 and the primary 'db0' database. Currently non standard ports and redis databases are not supported.

**snds_key**
---
Your organization's microsoft 'smart network data services' (SNDS) data access key. If you do not use microsoft's SNDS, you should signup here: https://postmaster.live.com/snds/.

**maillog_path**
---
The absolute path to your current postfix mail log file on each postfix MTA that you are using mtarep to report major provider rejections/blocks for. Currently only postfix log formats are supported.

**ssh_key**
---
The absolute path to the ssh key file you want to access your remote postfix MTAs with. The ssh key you provide here must have permissions to the remote 'maillog_path' you specified above, and for the 'ssh_user' you specify below.

**ssh_user**
---
The ssh username associated with the 'ssh_key' you specified above.

**http_auth_file**
---
The absolute path to your mtarep app's http authentication file. This is used for authentcating login access credentials (username/password) to the mtarep web interface.

The format of this file must be:
```
'username:{SHA}ME2JP/+546KPSPZQxQirw0qkUsQRyYWM='
```
Currently only a SHA1 base64 digest is supported (Digest::SHA1.base64digest('password')).

**mta_map**
---
This setting can contain either a YAML array collection or a YAML hash collection.

A YAML array collection is used when you want mtarep to use the same fqdn/hostname to lookup public fqdn/hostname/ip reputation data as well as the fqdn/hostname to ssh to for mail log parsing (ESP and ISP (provider) SMTP rejection log entries). Do not use this type of map if you ssh to your MTAs using a different fqdn/hostname or host alias from it's public mail fqdn/hostname.

The YAML hash collection support for this configuration setting should be used if you ssh to your MTAs using an internal hostname or alias that is different from the host's public fqdn hostname.

For example, if you have an MTA with a public HELO hostname of mta1.mydomain.com and you also access the MTA with ssh using that same hostname, then you want to use a YAML array collection here. If you have an MTA with a public HELO hostname of mta1.mydomain.com but you ssh to the MTA using the shortname 'mta1', then you want to use a YAML hash collection here (mta1: 'mta1.mydomain.com', etc..).

**graph_domains** (optional)
---
The domains that you want mtarep to render sent, bounced, feedback-loop and expired message counts for.

**rbls**
---
A YAML array collection of RBL/DNSBL's you want mtarep to check your MTA public IP addresses against. The format of these must be the RBL hostnames that are queried for listings (eg: bl.spamcop.net)

**provider_block_strings**
---
A YAML hash collection of external email provider names (the key) and a string (the value) that indicates a provider is blocking your MTA. These key/values are used by mtarep to search your remote MTA mail logs using the other related configuration settings you specified elsewhere in the main mtarep-conf.yml configuration file.

**removal_links**
---
A YAML hash collection of external email provider names and rbl lists (the key) and a corresponding URL (the value) to that provider or rbl's listing info and/or removal form.

**assistance_links** (optional)
---
A YAML hash collection of any custom documentation you maintain that outlines steps your organization has for resolving a specific mtarep reported issue. These links are used in the modal of a clicked issue in mtarep.

Install
-------
- Clone this repo
- Create & customize the rackup (config.ru), thin (mtarep-thin.yml) and mtarep (mtarep-conf.yml) files using the included example files
- Start your 'thin' web server with your newly customized mtarep-thin.yml file
- Schedule the mtarep/collector.rb to run every 15 minutes via cron or other scheduling process (see below for details)
- Browse to a http://hostname:port combination that resolves to what you specified in the mtarep-thin.yml configuration file

You should adjust the scheduling interval for mtarep/collector.rb according to the size of your data, number of MTAs, size of maillogs, etc. Just keep in mind the time it will take each collector run to complete. Mtarep will safely terminate any currently running collector process it detects before it's run begins so there's no overlap in jobs.
