const process = require('process');
const { SQSClient, ReceiveMessageCommand, DeleteMessageCommand } = require('@aws-sdk/client-sqs');
const client = new SQSClient({ region: 'ap-northeast-1' });

(async () => {
  console.log('Queue URL', process.env.QUEUE_URI);
  while (true) {
    try {
      const out = await client.send(new ReceiveMessageCommand({
        QueueUrl: process.env.QUEUE_URI,
        WaitTimeSeconds: 10,
      }))
      if (out.Messages === undefined || out.Messages.length === 0) {
        console.log('No Message...');
        continue;
      }
      for (const message of out.Messages) {
        console.log('Message', message.Body);
      }
      await client.send(new DeleteMessageCommand({
        QueueUrl: queueUrl,
        ReceiptHandle: out.Messages[0].ReceiptHandle,
      }))
    } catch (err) {
      console.error(err);
    }
  }
})();

process.on('SIGINT', () => {
  process.exit(0)
});
