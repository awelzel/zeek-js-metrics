const http = require('node:http');

let global_request_id = 0n;
const telemetry_requests = new Map();
const telemetry_timeout_ms = 500;
const cluster_nodes = new Set(Object.keys(zeek.global_vars['Cluster::nodes']));

// Send out whatever was collected for this telemetry_request and cleanup.
function sendResponse(telemetry_request) {
  // Check which nodes failed to respond and log a warning...
  const nodes = new Set(telemetry_request.responses.map((r) => r[0]));
  if (nodes.size !== cluster_nodes.size) {
    cluster_nodes.forEach((n) => {
      if (!nodes.has(n)) console.warn(`Node ${n} failed to respond to request ${telemetry_request.request_id}`);
    });
  }

  // Aggregate the data. TODO: Help text
  const all_data = telemetry_request.responses.map((r) => r[1]).join('\n');
  telemetry_request.res.writeHead(200, { 'Content-Type': 'text/plain' });
  telemetry_request.res.write(all_data);
  telemetry_request.res.end('\n');

  // Clean the map.
  telemetry_requests.delete(telemetry_request.request_id);
}

// Collect telemetry responses from other nodes.
zeek.on('Telemetry::collection_response', (endpoint, request_id, data) => {
  const telemetry_request = telemetry_requests.get(request_id);
  if (telemetry_request === undefined) {
    console.warn(`Unexpected collection_response() for ${endpoint} ${request_id}`);
    return;
  }

  telemetry_request.responses.push([endpoint, data]);

  // Are we waiting for more?
  if (telemetry_request.responses.length < cluster_nodes.size) return;

  sendResponse(telemetry_request);

  clearTimeout(telemetry_request.timeout);
});

// Cheap metrics server
const server = http.createServer((req, res) => {
  if (req.url !== '/metrics') {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Try /metrics...\n');
    return;
  }

  global_request_id += 1n;

  const telemetry_request = {
    request_id: global_request_id,
    res,
    responses: [],
  };

  telemetry_request.timeout = setTimeout(() => {
    sendResponse(telemetry_request);
  }, telemetry_timeout_ms);

  telemetry_requests.set(telemetry_request.request_id, telemetry_request);

  zeek.invoke('Telemetry::metrics_request_trampoline', [telemetry_request.request_id]);
});

server.listen(19911);
