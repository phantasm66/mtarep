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

All the data is collected and inserted into a redis data store whenever the collector completes a run. The collector (collector.rb) can be scheduled via cron. The sinatra webapp (app.rb) handles generating the HTML and retrieving the data from redis. Sent, bounced, expired and feedback loop count graphs can be easily configured for the domains of your choosing from within the main app.rb 'domains' word array. The graphing is provided by the [HighCharts JS API](http://www.highcharts.com/products/highcharts).

Please adjust the included config.ru, mtarep-thin.yml and mtarep-conf.yml config files accordingly. The mta_map array config line in mtarep-conf.yml can take a single fqdn that resolves to multiple A records (ie: a group of MTA IP addresses) or you can just list out your MTA public fqdns in the mta_map YAML list array.

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

