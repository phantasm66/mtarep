mtarep
================================
A ruby webapp to collect and report mail server reputations, deliverability and rbl statistics. The UI is powered by [Sinatra](https://github.com/sinatra/sinatra/) and the backend is provided by [Redis](http://redis.io/). If you follow the installation steps outlined in this README, you should be up and running within 15 minutes.

Requirements
------------
* [Thin](https://github.com/macournoyer/thin/)
* [Sinatra](https://github.com/sinatra/sinatra/)
* [Redis Server](http://redis.io/)
* [Redis Ruby Client](https://github.com/redis/redis-rb)
* [Ruby Net/SSH](https://github.com/net-ssh/net-ssh)
* [Fully Functional Postfix Mail Servers](http://www.postfix.org/)

Overview
--------
The following data is collected and displayed for each postfix MTA you report on using mtarep:

* [Return Path Sender Score](https://www.senderscore.org/)
* [Microsoft SNDS (Smart Network Data Services)](https://postmaster.live.com/snds/)
* Postfix SMTP Client Rejections (Parsed Mail Logs)
* [Cloudmark CSI](http://www.cloudmark.com/en/products/cloudmark-sender-intelligence/how-it-works)
* [Brightmail Reputation Service](http://www.symantec.com/security_response/glossary/define.jsp?letter=b&word=brightmail-reputation-service)
* RBL/DNSBL Listings

All the data is collected and inserted into a redis data store whenever the collector completes a run. The collector (collector.rb) can be scheduled via cron. The sinatra webapp (app.rb) handles generating the HTML and retrieving the data from redis.

Web Interface
-------------
![Alt text](screenshots/mtarep-webui-example.png?raw=true)

When a provider block or rbl cell contains a listing, it becomes clickable. For provider blocks, when you click a block link a modal appears containing the most recent smtp rejection message from your server's maillog (location and access are configurable in the mtarep.yml file), as well details about the listing and a direct link to that provider's block removal form or instructions. The same scenario occurs for rbl listings but without the maillog info, as mtarep queries rbls directly via a dns lookup.

![Alt text](screenshots/mtarep-modal-example.png?raw=true)

Each issue modal contains an acknowledgement button that can be clicked once you begin working an mtarep reported issue. When the acknowledgement button is clicked, a unique key is inserted back into redis that holds basic details about the issue, including a timestamp and the mtarep authenticated http username. Once acknowledged, the acknowledgement button is replaced with a timestamp and the mtarep authenticated http username that acknowledged the issue. This prevents multiple users working the same issue unknowingly.

Each column header in the web interface allows for rows sorting (eg: sort by rbl listings, microsoft SNDS filtering or trap hits, hostname, etc..)

Graphing
--------
![Alt text](screenshots/mtarep-graphs-example.png?raw=true)

To enable graphing you will need to configure a few things outside the scope of mtarep.

Sent, bounced, expired and feedback loop bar graphs can be configured for the domains of your choosing via the 'graph_domains' YAML array collection in the mtarep.yml configuration file. The graphing is provided by the [HighCharts JS API](http://www.highcharts.com/products/highcharts). Individual bar graphs can be removed from view by clicking each type of graph in the graphing legend. This allows more granular detail on specific bar graphs, which can be particularly helpful if your sent total bar graph obfuscates the shit out of the bounce, fbl or expired graphs.

Each individual bar graph is calculated from midnight on the current day and continues to be calculated until 11:59pm on that same day. The data used to calculate the sent, bounced, fbl and expired bar graphs is not *collected* by mtarep. However, bar graphs will be calculated and rendered by mtarep if the appropriate data exists in the same redis db used by mtarep.

The mtarep graphing code will search your mtarep redis backend for HINCRBY based keys in the format of:
```lua
20140208:expired
20140208:fbl
20140208:bounced
20140208:sent
```
*Where 20140208 is the current date*

These redis keys should contain an incrementing total for each unique domain that has been sent, bounced, expired or feedback-loop received. The exact redis operation is [HINCRBY](http://redis.io/commands/hincrby).

Using the [redis-rb](https://github.com/redis/redis-rb) ruby client you could do something like this:
```ruby
key = [Time.now.strftime("%Y%m%d")]
key << 'bounced'
@redis.hincrby(key.join(':'), 'gmail.com', 1)
```
The above code would increment a counter for each bounced email to 'gmail.com' under the redis key '20140208:bounced'. This could be accomplished by creating a custom redis output plugin with [Logstash](https://github.com/logstash/logstash) to filter and ship this data directly from your postfix mail logs to either a pubsub broker like [RabbitMQ](https://www.rabbitmq.com/) or perhaps even directly to your redis datastore.

Configuration
-------------
Mtarep comes with example configuration files for rackup (config.ru), thin (thin.yml) and mtarep itself (mtarep.yml). Please copy the example configs without the '.example' appendage and adjust each config according to your environment.

The individual mtarep.yml configuration file settings are as follows:

***error_log:***

   The absolute path to your main mtarep error log file. All directories in the path must already exist. If the error log file does not exist, it will be created.

***redis_server:***

   The DNS resolvable hostname of your redis server. Your redis server will be accessed over the default port of 6379 and the primary 'db0' database. Currently non standard ports and redis databases are not supported.

***snds_key:***

   Your organization's microsoft [Smart Network Data Services](https://postmaster.live.com/snds/) data access key. If you do not use microsoft SNDS, you should signup immediately. There is a wealth of info regarding your inbox placement.

***maillog_path:***

   The absolute path to your current postfix mail log file on each postfix MTA that you are using mtarep to report major provider rejections/blocks for. Currently only postfix log formats are supported.

***ssh_key:***

   The absolute path to the ssh key file (on the server running mtarep) you want to use to access your remote postfix MTA mail logs with. The ssh key you provide here must have permissions to the remote 'maillog_path' specified above, and for the 'ssh_user' you specify below.

***ssh_user:***

   The ssh username associated with the 'ssh_key' you specified above.

***http_auth_file:***

   The absolute path to your mtarep app's http authentication file. This is used for authentcating login access credentials (username/password) to the mtarep web interface.

   The format of this file must be:
   ```lua
   username:{SHA}ME2JP/+546KPSPZQxQirw0qkUsQRyYWM=
   ```
   Currently only a SHA1 base64 digest is supported (```Digest::SHA1.base64digest('password')```).

***mta_map:***

   This setting can contain either a YAML array collection or a YAML hash collection.

   A YAML array collection is used when you want mtarep to use the same fqdn/hostname to lookup public fqdn/hostname/ip reputation data as well as the fqdn/hostname to ssh to for mail log parsing (ESP and ISP (provider) SMTP rejection log entries). Do not use this type of map if you ssh to your MTAs using a different fqdn/hostname or host alias from it's public mail fqdn/hostname.

   The YAML hash collection support for this configuration setting should be used if you ssh to your MTAs using an internal hostname or alias that is different from the host's public fqdn hostname.

   For example, if you have an MTA with a public HELO hostname of mta1.mydomain.com and you also access the MTA with ssh using that same hostname, then you want to use a YAML array collection here. If you have an MTA with a public HELO hostname of mta1.mydomain.com but you ssh to the MTA using the shortname 'mta1', then you want to use a YAML hash collection here (mta1: 'mta1.mydomain.com', etc..).

***graph_domains:*** (optional)

   The domains that you want mtarep to render sent, bounced, feedback-loop and expired bat graph totals for.

***rbls:***

   A YAML array collection of RBL/DNSBL's you want mtarep to check your MTA public IP addresses against. The format of these must be the RBL hostnames that are queried for listings (eg: bl.spamcop.net)

***provider_block_strings:***

   A YAML hash collection of external email provider names (the key) and a string (the value) that indicates a provider is blocking your MTA. These key/values are used by mtarep to search your remote MTA mail logs for particular rejection text patterns. The rejection patterns for several major email providers are already included in the mtarep.yml.example file.

***removal_links:***

   A YAML hash collection of external email provider names and rbl lists (the key) and a corresponding URL (the value) to that provider or rbl's listing info and/or removal form.

***assistance_links:*** (optional)

   A YAML hash collection of any custom documentation you maintain that outlines steps your organization has for resolving a specific mtarep reported issue. These links are used in the modal of a clicked issue in mtarep.

Installation
------------
- git clone https://github.com/phantasm66/mtarep.git
- create config.ru, thin.yml and mtarep.yml configs from included example configs
- start the thin web server
- check the specified mtarep *error_log* location for any errors
- run mtarep/collector.rb manually to test your mtarep.yml (errors display on stderr)
- cron mtarep/collector.rb to run every 15 minutes (additional details below)
- go to http://hostname:port (according to your thin.yml config file)

Data Collection Schedule
------------------------
You may need to adjust your cron scheduling interval for mtarep/collector.rb according to the amount of data you want mtarep to collect, the number and size of your MTA maillogs, etc. Before you schedule the cron, it might be wise to do a manual collection run with your production mtarep.yml and time it. However, if collector runs *do* overlap, the collector will safely terminate previously running collector processes. This prevents cascading collection runs, collisions, etc.

