module.exports = {
  apps: [{
    name: 'cv-builder',
    script: 'server.js',
    cwd: __dirname,
    env: { NODE_ENV: 'production' },
    max_memory_restart: '200M'
  }]
};
