const https = require('https');

const payload = JSON.stringify({
  context: {
    client: {
      clientName: "WEB_REMIX",
      clientVersion: "1.20231214.00.00"
    }
  },
  browseId: "MPREb_CjTGS8Mw6nZ"
});

const req = https.request({
  hostname: 'music.youtube.com',
  path: '/youtubei/v1/browse?alt=json',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': payload.length
  }
}, (res) => {
  let body = '';
  res.on('data', d => body += d);
  res.on('end', () => {
    const data = JSON.parse(body);
    console.log(Object.keys(data));
    if(data.contents) console.log("Has contents!");
  });
});
req.write(payload);
req.end();
