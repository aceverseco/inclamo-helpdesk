// Stands in for the incoming webhook of the operator's chat in the install's
// test mode: keeps what was posted, so a test can read which alarm arrived.
//   POST   /           an alarm, as the scripts send it: {"text": "..."}
//   GET    /requests   everything posted so far
//   DELETE /requests   forget it
// Inside the stack it also carries the name of Chatwoot's hub and counts what
// connects to port 443, so a test can see that nothing calls the hub:
//   GET    /hub        {"connections": n}
//   DELETE /hub        forget them
import { createServer } from 'node:http';
import { createServer as createListener } from 'node:net';

const requests = [];
let hubConnections = 0;

createListener(socket => {
  hubConnections += 1;
  socket.on('error', () => {});
  socket.end();
}).listen(443, '0.0.0.0');

createServer((request, response) => {
  const answer = (status, body) => {
    response.writeHead(status, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(body));
  };
  if (request.url === '/requests' && request.method === 'GET') return answer(200, requests);
  if (request.url === '/requests' && request.method === 'DELETE') {
    requests.length = 0;
    return answer(200, []);
  }
  if (request.url === '/hub' && request.method === 'GET') return answer(200, { connections: hubConnections });
  if (request.url === '/hub' && request.method === 'DELETE') {
    hubConnections = 0;
    return answer(200, { connections: 0 });
  }
  if (request.method !== 'POST') return answer(404, { error: 'not found' });
  let raw = '';
  request.on('data', chunk => { raw += chunk; });
  request.on('end', () => {
    let body;
    try { body = JSON.parse(raw); } catch { return answer(400, { error: 'the alarm is not JSON' }); }
    requests.push({ at: new Date().toISOString(), body });
    answer(200, { ok: true });
  });
}).listen(Number(process.env.PORT || 9099), '0.0.0.0');
