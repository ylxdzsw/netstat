require('speedtest-net')()
  .on('data', data => console.log(JSON.stringify(data)))
  .on('error', err => console.log(err))