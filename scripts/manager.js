const http = require('node:http');

let global_request_id = 0n;
const telemetry_requests = new Map();
const telemetry_timeout_ms = 1000;
const cluster_nodes = new Set(Object.keys(zeek.global_vars['Cluster::nodes']));

class MetricsInfo {
  constructor() {
    this.type_text = undefined;
    this.help_text = undefined;
    this.data = [];
  }

  hasText() {
    return this.type_text !== undefined && this.help_text !== undefined;
  }
}

// A currently pending telemetry request
class TelemetryRequest {
  constructor(request_id, res) {
    this.request_id = request_id;
    this.res = res;
    this.endpoints = new Set();
    this.metrics = new Map();
    this.timeout = undefined;
  }

  getMetricInfo(name) {
    let minfo = this.metrics.get(name);
    if (minfo === undefined) {
      minfo = new MetricsInfo();
      this.metrics.set(name, minfo);
    }
    return minfo;
  }

  // Parse the string data produced by the Zeek script. Could
  // also consider doing something more efficient, but this should
  // work...
  //
  // Currently this is Prometheus format directly with
  // HELP and TEXT lines assumed to be consistent.
  parseMetrics(data) {
    data.split('\n').forEach((l) => {
      if (l[0] === '#') {
        const parts = l.split(' ', 3);
        const what = parts[1];
        const name = parts[2];
        const minfo = this.getMetricInfo(name);

        if (minfo.hasText()) return;

        if (what === 'HELP') minfo.help_text = l;
        else if (what === 'TYPE') minfo.type_text = l;
        else console.warn(`Ignoring invalid comment line ${l}`);
        return;
      }

      let idx = l.indexOf('{');
      if (idx <= 0) idx = l.indexOf(' ');

      const name = l.slice(0, idx);
      const minfo = this.getMetricInfo(name);
      minfo.data.push(l);
    });
  }

  sendResponse() {
    if (this.endpoints.size !== cluster_nodes.size) {
      cluster_nodes.forEach((n) => {
        if (!this.endpoints.has(n)) {
          console.warn(`Node ${n} failed to respond to request ${this.request_id}`);
        }
      });
    }

    this.res.writeHead(200, { 'Content-Type': 'text/plain' });
    this.metrics.forEach((minfo) => {
      this.res.write(`${minfo.help_text}\n`);
      this.res.write(`${minfo.type_text}\n`);
      // Could sort if wanted to...
      this.res.write(minfo.data.join('\n'));
      this.res.write('\n');
    });

    this.res.end();

    // Remove this request from the map of pending requests.
    telemetry_requests.delete(this.request_id);
  }

  receiveCollectionResponse(endpoint, data) {
    this.endpoints.add(endpoint);
    this.parseMetrics(data);

    // Are we waiting for more?
    if (this.endpoints.size < cluster_nodes.size) return;

    this.sendResponse();
    clearTimeout(this.timeout);
  }
}

// Collect telemetry responses from other nodes.
zeek.on('Telemetry::collection_response', (endpoint, request_id, data) => {
  const telemetry_request = telemetry_requests.get(request_id);
  if (telemetry_request === undefined) {
    console.warn(`Unexpected collection_response() for ${endpoint} ${request_id}`);
    return;
  }

  // Handle received data...
  telemetry_request.receiveCollectionResponse(endpoint, data);
});

// Cheap metrics server
const server = http.createServer((req, res) => {
  if (req.url !== '/metrics') {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Try /metrics...\n');
    return;
  }

  global_request_id += 1n;

  const telemetry_request = new TelemetryRequest(global_request_id, res);
  telemetry_request.timeout = setTimeout(() => {
    telemetry_request.sendResponse(telemetry_request);
  }, telemetry_timeout_ms);

  telemetry_requests.set(telemetry_request.request_id, telemetry_request);

  zeek.invoke('Telemetry::metrics_request_trampoline', [telemetry_request.request_id]);
});

server.listen(19911);
