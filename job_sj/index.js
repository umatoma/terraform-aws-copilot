const process = require('process');

(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  console.log('HELLO 1');
  await sleep(500);
  console.log('HELLO 2');
  await sleep(500);
  console.log('HELLO 3');
  await sleep(500);
  console.log('HELLO 4');
  await sleep(500);
  console.log('HELLO 5');
})();

process.on('SIGINT', () => {
  process.exit(0)
});
