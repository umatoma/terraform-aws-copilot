const process = require('process');
const express = require('express');

const app = express();
const port = 80;
const wrap = (fn) => (...args) => fn(...args).catch(args[2]);

app.get('/', (req, res) => {
  res.send('Hello World!');
});
app.get('/request', wrap(async (req, res) => {
  res.json({ message: 'HELLO Backend Service' });
}));
app.use((err, req, res, next) => {
  if (err) {
    res.status(500);
    res.send(err.toString());
  } else {
    res.send('OK');
  }
});
app.listen(port, () => {
  console.log(`Example app listening at http://localhost:${port}`);
});
process.on('SIGINT', () => {
  process.exit(0);
});
