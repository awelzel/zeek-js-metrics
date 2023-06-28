@load base/frameworks/cluster
@load base/frameworks/telemetry

module Telemetry;

export {
  # Event invoked from JavaScript upon a metrics request
  global metrics_request: event(request_id: count);
  global metrics_request_done: event();

 # Request/response for telemetry.
  global collection_request: event(reply_topic: string, request_id: count);

 # Data is maybe already Preomtheus formatted, maybe not...
  global collection_response: event(endpoint: string, request_id: count, data: string);
}

type MetricInfo: record {
  help: string;
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
function fmt_prom_line(m: Telemetry::Metric, metric_infos: table[string, string] of MetricInfo): string {
  local prefix = gsub(m$opts$prefix, /[.-]/, "_");
  local name = gsub(m$opts$name, /[-.]/, "_");
  local labels = fmt_prom_labels(m$opts$labels, m$labels);

  if ( [prefix, name] !in metric_infos ) {
    local _type = to_lower(gsub(cat(m$opts$metric_type), /.+_/, ""));
    metric_infos[prefix, name] = MetricInfo($help=m$opts$help_text, $_type=_type);
  }

  return fmt("%s_%s%s %s", prefix, name, labels, m$value);
}

function do_collection_request(): string {
  local prom_lines: vector of string;
  local metrics = Telemetry::collect_metrics("*", "*");

  local metric_infos: table[string, string] of MetricInfo;
  for ( _, m in metrics ) {
    prom_lines += fmt_prom_line(m, metric_infos);
  }

  return join_string_vec(prom_lines, "\n");
}

event Telemetry::collection_request(reply_topic: string, request_id: count) {
  local data = do_collection_request();
  Broker::publish(reply_topic, Telemetry::collection_response, Cluster::node, request_id, data);
}


module GLOBAL;

@if ( ! Supervisor::is_supervisor() )
@if ( ! Cluster::is_enabled() || Cluster::local_node_type() == Cluster::MANAGER )
@load ./manager.zeek
@endif
@endif
