# zeek-js-metrics

Prototype for request-response metrics in a Zeek cluster.


Upon an HTTP request to the manager do:

  * raise Telemetry::metrics_request() event
  * Manager broadcasts `Telemetry::collection_request()` event to all nodes
  * Manager now waits for `Telemetry::collection_response()`s from all nodes
  * Once all responses are received, manager replies to pending HTTP request

  * TODO: Timeout: Just return what was received so far, unify.

TODO:

  * String memory leak :-/
  * MALLOC_CONF and supervisor not working right? :-/
