// Test-only transport fault injector. The upstream is fixed to the synthetic
// central container and the network has no route to production.
import http from 'node:http';
let fault = null;
let requests = 0;
http.createServer(async (request, response) => {
  let body = ''; for await (const chunk of request) body += chunk;
  if (request.method === 'POST') fault = JSON.parse(body || 'null');
  if (request.method === 'DELETE') fault = null;
  response.setHeader('Content-Type', 'application/json');
  response.end(JSON.stringify({ fault, requests }));
}).listen(8081, '0.0.0.0');
http.createServer((request, response) => {
  requests += 1;
  const matched = fault && request.url.includes(fault.path || '/');
  if (matched && fault.mode === 'unavailable') {
    if (!fault.persistent) fault = null;
    response.writeHead(503); response.end('synthetic outage'); request.resume(); return;
  }
  const drop = matched && fault.mode === 'lost_ack';
  if (drop) fault = null;
  const upstream = http.request({ hostname: 'central', port: 3000, path: request.url, method: request.method, headers: { ...request.headers, host: 'central:3000' } }, result => {
    if (drop) { result.resume(); result.on('end', () => response.destroy()); return; }
    response.writeHead(result.statusCode, result.headers); result.pipe(response);
  });
  upstream.on('error', () => { response.writeHead(503); response.end('synthetic upstream unavailable'); });
  request.pipe(upstream);
}).listen(8080, '0.0.0.0');
