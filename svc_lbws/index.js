const process = require('process');
const express = require('express');
const axios = require('axios');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const { SERVICE_DISCOVERY_ENDPOINT, SNS_TOPIC_ARNS } = process.env;
const app = express();
const port = 80;
const wrap = (fn) => (...args) => fn(...args).catch(args[2]);
const client = new SNSClient({ region: 'ap-northeast-1' });

app.get('/', (req, res) => {
  res.send('Hello World!');
});
app.get('/request', wrap(async (req, res) => {
  const bsUrl = `http://bs.${SERVICE_DISCOVERY_ENDPOINT}`;
  const response = await axios.get(`${bsUrl}/request`);
  res.json(response.data);
}));
app.get('/publish', wrap(async (req, res) => {
  const out = await client.send(new PublishCommand({
    Message: 'HELLO',
    TopicArn: JSON.parse(SNS_TOPIC_ARNS).hello,
  }));
  res.json({ MessageId: out.MessageId });
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
