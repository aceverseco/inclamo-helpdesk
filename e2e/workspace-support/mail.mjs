// Minimal SMTP sink for synthetic tests; never forwards messages.
import net from 'node:net';
import http from 'node:http';
const messages = [];
net.createServer(socket => {
  socket.write('220 synthetic-mail ESMTP\r\n');
  let buffer = '', data = false, body = '', recipient = '';
  socket.on('data', chunk => {
    buffer += chunk;
    if (buffer.length + body.length > 2_000_000) return socket.destroy();
    while (buffer.includes('\r\n')) {
      const offset = buffer.indexOf('\r\n');
      const line = buffer.slice(0, offset); buffer = buffer.slice(offset + 2);
      if (data) {
        if (line === '.') {
          messages.push({ recipient, body, received_at: new Date().toISOString() });
          if (messages.length > 100) messages.shift();
          body = ''; data = false; socket.write('250 stored\r\n');
        } else body += `${line.replace(/^\.\./, '.')}\r\n`;
      } else if (/^(EHLO|HELO)/i.test(line)) socket.write('250 synthetic-mail\r\n');
      else if (/^RCPT TO:/i.test(line)) { recipient = line.slice(8).trim(); socket.write('250 ok\r\n'); }
      else if (/^DATA$/i.test(line)) { data = true; socket.write('354 end with dot\r\n'); }
      else if (/^QUIT$/i.test(line)) socket.end('221 bye\r\n');
      else socket.write('250 ok\r\n');
    }
  });
}).listen(1025, '0.0.0.0');
http.createServer((request, response) => {
  response.setHeader('Content-Type', 'application/json');
  if (request.method === 'DELETE') messages.length = 0;
  response.end(JSON.stringify(messages));
}).listen(8025, '0.0.0.0');
