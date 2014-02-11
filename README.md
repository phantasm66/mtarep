MTAREP
================================
Collect and report on your mail servers' reputation, deliverability and rbl statistics.

Requirements:
-------------
    Sinatra
    Redis
    Thin

Overview:
---------
The following data is displayed for each MTA you report on using mtarep:

    ReturnPath's Sender Score
    Microsoft's SNDS (Smart Network Data Services)
    Major ESP SMTP rejection blocks
    Several widely used RBL's

All the data is collected and inserted into a redis data store whenever the collector completes a run. The collector (collector.rb) can be scheduled via cron. The sinatra webapp (app.rb) handles generating the HTML and retrieving the data from redis.

Web UI:
-------
![Alt text](screenshots/mtarep-webui-example.png?raw=true)

When a provider block or rbl cell contains a listing, it becomes clickable. For provider blocks, when you click a block link a modal appears containing the most recent smtp rejection message from your server's maillog (location and access are configurable in the mtarep-conf.yml file), as well details about the listing and a direct link to that provider's block removal form or instructions. The same scenario occurs for rbl listings as well minus the maillog info, because mtarep queries rbl lists directly over dns (you can customize the list of rbls queried in the mtarep-conf.yml file as well).

Each column header in the WebUI allows for sorting (eg: sort by rbl listings, microsoft SNDS filtering or trap hits, hostname, etc..)

Graphing:
---------
![Alt text](screenshots/mtarep-graphs-example.png?raw=true)

The included graphing will require you to configure a few things outside the scope of mtarep.

Sent, bounced, expired and feedback loop count graphs can be easily configured for the domains of your choosing via the 'graph_domains' list array section in the included mtarep-conf.yml configuration file. The graphing is provided by the [HighCharts JS API](http://www.highcharts.com/products/highcharts). The individual bar graphs can be removed from view to allow more granular detail on the remaining bar graphs. This is particularly helpful if your sent total bar graph obfuscates the shit out of the bounce, fbl or expired graphs (deliverability hint: you want this to happen!).

The graph data is calculated from midnight on the current day and continues to be calculated until 11:59pm on that same day. The data used to calculate the sent, bounced, fbl and expired bar graphs is not *collected* by mtarep. However, it will be calculated and rendered if the appropriate data exists in the same redis db used by mtarep. The web ui will automatically calculate any HINCRBY (key field increment) keys in your redis backend in the format of:

    20140208:expired"
    20140208:fbl"
    20140208:bounced"
    20140208:sent"

These keys contain incrementing totals of each unique domain that has been sent a message by your mail servers. The exact redis operation is HINCRBY (http://redis.io/commands/hincrby). 

In a single 24 hour period (midnight to 11:59pm), you will need to be shipping and storing increments of unique domain totals for sent, expired, fbl and bounced messages. Unique domain single increments can easily be inserted into redis using the HINCRBY operation and using a log shipping tool like [Logstash](https://github.com/logstash/logstash), which comes stock with a fantastic set of output formats (like redis).

Configuration:
--------------
Please adjust and remove the '.example' appendage from the included example configs to config.ru, mtarep-thin.yml and mtarep-conf.yml accordingly.
All configuration of mtarep is managed from the app's main YAML configuration file (mtarep-conf.yml).

Individual mtarep-conf.yml configuration settings:

**error_log**

    The file path to the main mtarep error log file. All directories in the path must already exist.

**redis_server**

    The DNS resolvable hostname of your redis server. Your redis server will be accessed over the default port of 6379 and the primary 'db0' database. Currently non standard ports and redis databases are not supported.

**snds_key**

    Your organization's microsoft 'smart network data services' (SNDS) data access key. If you do not use microsoft's SNDS, you should signup here: https://postmaster.live.com/snds/

**maillog_path**

    The remote file path to your current postfix mail log file on each MTA that you are using mtarep to report major provider rejections/blocks for. Currently only postfix log formats are supported.

**ssh_key**

    The file path to the ssh key you want to access your remote MTAs with. The ssh key you provide here must have permissions to the remote 'maillog_path' you specified above, and for the 'ssh_user' you specify below.

**ssh_user**

    The ssh username associated with the 'ssh_key' you specified above.

**mta_map**

    Either a list of individual public MTA hostnames that you want mtarep to report on, or a single DNS hostname that resolves to multiple A records for multiple MTAs that you want mtarep to report on.

**graph_domains** (optional)

    The domains that you want mtarep to render sent, bounced, feedback-loop and expired message counts for.

**rbls**

    The list of RBL/DNSBL's you want mtarep to check your MTA IP addresses against. The format of each of these must be the RBL/DNSBL hostnames that are queried for listings (eg: bl.spamcop.net)

**provider_block_strings**

    A key/value list of external email provider names (the key) and a string (the value) that indicates a provider is blocking your MTA. These key/values are used by mtarep to search your remote MTA mail logs using the other related configuration settings you specified elsewhere in the main mtarep-conf.yml configuration file.

**removal_links**

    A key/value list of external email provider names and rbl lists (the key) and a corresponding URL (the value) to that provider or rbl's listing info and/or removal form.

**assistance_links** (optional)

    A key/value list of custom documentation that outlines any steps your organization has for resolving a reported mtarep issue. These links are used in the modal of a clicked issue in mtarep.

Install:
--------
- Clone this repo
- Customize the 3 included configs for rackup (config.ru), thin (mtarep-thin.yml) and mtarep (mtarep-conf.yml)
- Start your 'thin' web server with the customized mtarep-thin.yml file
- Schedule the mtarep/collector.rb to run every 15 minutes via cron or other scheduling process
- Browse to a http://hostname:port combination that resolves to what you specified in the mtarep-thin.yml configuration file

You should adjust the scheduling interval for mtarep/collector.rb according to the size of your data, number of MTAs, size of maillogs, etc. Just keep in mind the time it will take each collector run to complete. Mtarep will safely terminate any currently running collector process it detects before it's run begins so there's no overlap in jobs.
