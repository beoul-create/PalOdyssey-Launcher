const path = require('path');

module.exports = {
  apps: [
    {
      name: 'palodyssey-bot',
      script: path.join(__dirname, 'PalLauncher', 'bin', 'Debug', 'net8.0-windows', 'PalLauncher.exe'),
      args: '--daemon',
      interpreter: 'none',
      cwd: __dirname,
      autorestart: true,
      watch: false,
      max_memory_restart: '600M',
      env: {
        NODE_ENV: 'production',
        PALODYSSEY_MODE: 'daemon'
      },
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      error_file: path.join(__dirname, 'logs', 'bot-error.log'),
      out_file: path.join(__dirname, 'logs', 'bot-out.log'),
      merge_logs: true
    }
  ]
};
