MTAREP
================================

Collect, report and alert on various MTA reputation and rbl statistics.

Requirements:
-------------
    Sinatra
    Redis
    Thin

Reporting:
----------
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

Sent, bounced, expired and feedback loop count graphs can be easily configured for the domains of your choosing from within the main app.rb 'domains' word array. The graphing is provided by the [HighCharts JS API](http://www.highcharts.com/products/highcharts). The individual bar graphs can be removed from view to allow more granular detail on the remaining bar graphs. This is particularly helpful if your sent total bar graph obfuscates the shit out of the bounce, fbl or expired graphs (deliverability hint: you want this to happen!).

The graph data is calculated from midnight on the current day and continues to be calculated until 11:59pm on that same day. The data used to calculate the sent, bounced, fbl and expired bar graphs is *not* collected by mtarep. However, it will be calculated and rendered if the appropriate data exists in the same redis db used by mtarep. The web ui will automatically calculate any HINCRBY (key field increment) keys in your redis backend in the format of:

    20140208:expired"
    20140208:fbl"
    20140208:bounced"
    20140208:sent"

These keys contain incrementing totals of each unique domain that has been sent a message by your mail servers. The exact redis operation is HINCRBY (http://redis.io/commands/hincrby). 

In a single 24 hour period (midnight to 11:59pm), you will need to be shipping and storing increments of unique domain totals for sent, expired, fbl and bounced messages. Unique domain single increments can easily be inserted into redis using the HINCRBY operation and using a log shipping tool like [Logstash](https://github.com/logstash/logstash), which comes stock with a fantastic set of output formats (like redis).

Configuration:
--------------
Please adjust and remove the '.example' appendage from the included example configs to config.ru, mtarep-thin.yml and mtarep-conf.yml accordingly.

NOTE: The mta_map array config line in mtarep-conf.yml can take a single fqdn that resolves to multiple A records (ie: a group of MTA IP addresses) or you can just list out your MTA public fqdns in the mta_map YAML list array.

Default RBL Sources:
--------------------
    b.barracudacentral.org
    bl.mailspike.net
    bl.score.senderscore.com
    bl.spamcannibal.org
    bl.spamcop.net
    block.stopspam.org
    cbl.abuseat.org
    cidr.bl.mcafee.com
    db.wpbl.info
    dnsbl-1.uceprotect.net
    dnsbl-2.uceprotect.net
    dnsbl-3.uceprotect.net
    multi.surbl.org
    psbl.surriel.com
    ubl.unsubscore.com
    zen.spamhaus.org

