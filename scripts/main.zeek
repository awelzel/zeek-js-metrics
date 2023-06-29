@load base/frameworks/cluster
@load base/frameworks/telemetry

module Telemetry;

export {
  # Event sent to nodes to trigger collection. Answer expected on reply_topic.
  global collection_request: event(reply_topic: string, request_id: count);

  # Event sent as response to a collection_request().
  global collection_response: event(endpoint: string, request_id: count, data: string);

  # Simple trampoline function called from JavaScript to publish requests
  # via Broker and do local collection. Too much any and opaque involved.
  global metrics_request_trampoline: function(request_id: count);

}

type MetricInfo: record {
  help_text: string;
  _type: string;
};

function fmt_prom_labels(names: vector of string, values: vector of string): string {
  local labels = vector(fmt("endpoint=\"%s\"", Cluster::node));  # cheap
  for ( i, k in names ) {
    labels += fmt("%s=\"%s\"", gsub(k, /-/, "_"), values[i]);
  }
  return fmt("{%s}", join_string_vec(labels, ","));
}

# This will do same serialization over and over again. We could
# serialize to JSON and do it on the manager. If we could get
# a pointer to a record we could cache it based on that, maybe.
function fmt_prom_line(m: Telemetry::Metric, metric_infos: table[string] of MetricInfo): string {
  local opts = m$opts;
  local prefix = gsub(opts$prefix, /[.-]/, "_");
  local name = gsub(opts$name, /[-.]/, "_");
  local prom_name = fmt("%s_%s%s", prefix, name, opts$is_total? "_total" : "");
  local prom_labels = fmt_prom_labels(opts$labels, m$labels);

  if ( prom_name !in metric_infos ) {
    local _type = to_lower(gsub(cat(opts$metric_type), /.+_/, ""));
    metric_infos[prom_name] = MetricInfo($help_text=opts$help_text, $_type=_type);
  }

  local total_str = opts$is_total ? "_total" : "";

  return fmt("%s%s %s", prom_name, prom_labels, m$value);
}

function do_collection_request(): string {
  local prom_lines: vector of string;
  local metrics = Telemetry::collect_metrics("*", "*");

  local metric_infos: table[string] of MetricInfo;
  for ( _, m in metrics ) {
    prom_lines += fmt_prom_line(m, metric_infos);
  }

  # Suffix type and help lines.
  for ( [prom_name], info in metric_infos ) {
    prom_lines += fmt("# HELP %s %s", prom_name, info$help_text);
    prom_lines += fmt("# TYPE %s %s", prom_name, info$_type);
  }

  return join_string_vec(prom_lines, "\n");
}

event Telemetry::collection_request(reply_topic: string, request_id: count) {
  local data = do_collection_request();
  Broker::publish(reply_topic, Telemetry::collection_response, Cluster::node, request_id, data);
}


function metrics_request_trampoline(request_id: count) {
  for ( topic in Cluster::broadcast_topics )
    Broker::publish(topic, Telemetry::collection_request, Cluster::manager_topic, request_id);

  # Handle local data collection for manager.
  local data = do_collection_request();
  event Telemetry::collection_response(Cluster::node, request_id, data);
}


module GLOBAL;

@if ( ! Supervisor::is_supervisor() )
@if ( ! Cluster::is_enabled() || Cluster::local_node_type() == Cluster::MANAGER )
@load ./manager.js
@endif
@endif
