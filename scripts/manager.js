const http = require('node:http');

var request_id = 0n;
const telemetry_requests = new Map();
const cluster_nodes = Object.keys(zeek.global_vars['Cluster::nodes']).length;

// Published from other endpoints.
zeek.on('Telemetry::collection_response', (endpoint, request_id, data) => {
  console.log(`Response from ${endpoint} request_id=${request_id} ${data.length} bytes`);

  const telemetry_request = telemetry_requests.get(request_id);
  if ( telemetry_request === undefined ) {
    console.error(`Unexpected collection_response() for ${endpoint} ${request_id}`)
    return;
  }

  const responses = telemetry_request.responses;
  responses.push([endpoint, data]);

  if ( responses.length < cluster_nodes ) {
    // console.log(`More responses expected ${responses.length}/${cluster_nodes}`);
    return;
  }

  // Aggregate data.
  const all_data = responses.map(r => r[1]).join("\n");
  telemetry_request.res.writeHead(200, {'Content-Type': 'text/plain'});
  telemetry_request.res.write(all_data);
  telemetry_request.res.end("\n");

  // Cleanup
  clearTimeout(telemetry_request.timeout);
  telemetry_requests.delete(request_id);
  console.log(`Deleted ${request_id}.. pending requests ${telemetry_requests.size}` ,telemetry_requests);

});

// Cheap metrics server
const server = http.createServer((req, res) => {
  ++request_id;
  console.log(`Request: ${req.method} ${req.url} ${request_id}`);

  // Prepare the request...
  const telemetry_request = {
    request_id: request_id,
    res: res,
    responses: [],
  };

  // TODO: Make timeout conifgurable...
  telemetry_request.timeout = setTimeout(() => {
    const my_request_id = request_id;
    // XXX: This should send whatever we have so far.
    const this_telemetry_request = telemetry_requests.get(request_id);
    console.log("timeout");
    this_telemetry_request.res.writeHead(500, {'Content-Type': 'text/plain'});
    this_telemetry_request.res.end("timeout");
    telemetry_requests.delete(my_request_id);
  }, 1000);

  telemetry_requests.set(request_id, telemetry_request);

  // Check if we can publish from JavaScript? For now trampoline it.
  zeek.event('Telemetry::metrics_request', [request_id]);
}).listen(19911);
