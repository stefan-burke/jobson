const baseConfig = require('./webpack.config');

module.exports = Object.assign({}, baseConfig, {
	mode: 'production',
	devtool: 'source-map',
});
