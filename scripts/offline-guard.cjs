// Preload de los checks offline. Falla antes de abrir un secreto o un socket.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const net = require('node:net');
const { syncBuiltinESMExports } = require('node:module');

function assertReadable(file) {
	const name = String(file).replace(/\\/g, '/');
	if (/(^|\/)(\.env(?:[./]|$)|\.env[^/]*$|\.(?:aws|ssh|vercel)(?:\/|$)|\.npmrc$|\.pgpass$|credentials(?:[./]|$)|secrets?(?:[./]|$))/i.test(name)) {
		throw new Error('OFFLINE: lectura de secretos bloqueada.');
	}
}

for (const method of ['readFileSync', 'readFile', 'openSync', 'open', 'createReadStream']) {
	const original = fs[method];
	fs[method] = function (file, ...args) {
		assertReadable(file);
		return original.call(this, file, ...args);
	};
}
for (const method of ['readFile', 'open']) {
	const original = fsp[method];
	fsp[method] = function (file, ...args) {
		assertReadable(file);
		return original.call(this, file, ...args);
	};
}

net.Socket.prototype.connect = function () {
	throw new Error('OFFLINE: conexiones de red bloqueadas.');
};
globalThis.fetch = async function () {
	throw new Error('OFFLINE: fetch bloqueado; usa dobles de prueba.');
};
syncBuiltinESMExports();
