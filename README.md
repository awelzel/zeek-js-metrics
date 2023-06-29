# zeek-js-metrics

Prototype for request-response Prometheus metrics in a Zeek cluster.


Upon an HTTP request to the manager do:

  * Invoke `Telemetry::metrics_request()`  on Zeek scripting side.
  * Manager broadcasts `Telemetry::collection_request()` event to all nodes
  * Manager now waits for `Telemetry::collection_response()`s from all nodes
  * Once all responses are received, manager replies to pending HTTP request
  * On timeout, reply with what you had.


## Results for Zeek 6.0 RC3

  * RelWithDebInfo build
  * 24 workers, 3 loggers, 1 proxy, 1 manager
  * nfamilies=4, ncounters_per_family=200


1) Base - no JS, no frameworks/telemetry/prometheus

   * worker usage: 0.5-1.5%
   * manager usage: 6-7% usage (?)


1) Base Zeek and loading of frameworks/telemetry/prometheus to enable import/export, nothing scrapes

   * worker usage: ~1-2%
   * manager usage: ~30% (!)


2) ZeekJS + the scripts here

2.1) When nothing scrapes there is no overhead

   * worker usage 0.5% - 1.5%
   * manager usage: 6-7% (?)

2.2) Scraping every second (which is high, but comparable to default export/import interval)

   * worker usage: 1.5-2.5%
   * manager usage: ~10%.

2.3) Scraping a more reasonable every 5 seconds
   * manager usage: ~7%
   * worker usage ~1%


## TODO:

  * String memory leak in ZeekJS :-/ (https://github.com/corelight/zeekjs/pull/67)
