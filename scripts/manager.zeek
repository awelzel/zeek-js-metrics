# Event invoked from JavaScript upon a metrics request
module Telemetry;

const _topics = vector(Cluster::logger_topic, Cluster::proxy_topic, Cluster::worker_topic);

# XXX: Remove this.
redef JavaScript::initial_heap_size_in_bytes = 8 * 1024 * 1024;
redef JavaScript::maximum_heap_size_in_bytes = 24 * 1024 * 1024;

event Telemetry::metrics_request(request_id: count) {
  # Broker::publish(Cluster::manager_topic, Telemetry::request_collection, Cluster::manager_topic);
  for ( _, topic in _topics )
    Broker::publish(topic, Telemetry::collection_request, Cluster::manager_topic, request_id);

  # Handle the local part.
  local data = do_collection_request();
  event Telemetry::collection_response(Cluster::node, request_id, data);
}

# Self-test
@if ( T )
global rid = 0;
event self_test()
  {
  event Telemetry::metrics_request(rid);
  schedule 0.05sec { self_test() };
  }

event zeek_init()
  {
  event self_test();
  }

event Telemetry::collection_response(endpoint: string, request_id: count, data: string) {
  print "ZEEK: Telemetry::collection_response", endpoint;
}
@endif

@load ./manager.js
