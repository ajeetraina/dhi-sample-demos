const http = require("http");
const mimeTypes = require("mime-types");

const server = http.createServer((req, res) => {
  const contentType = mimeTypes.lookup('html') || 'text/plain';
  res.writeHead(200, { "Content-Type": contentType });
  res.end("Hello from Docker Hardened Node.js!\nUsing mime-types package!\n");
});

server.listen(3000, "0.0.0.0", () => {
  console.log("Server running on port 3000");
});
