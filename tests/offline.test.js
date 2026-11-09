import { readFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { Socket } from 'node:net';
import { describe, expect, it } from 'vitest';

describe('guard del arnes offline', () => {
	it('bloquea antes de abrir un nombre de secreto incluso inexistente', async () => {
		expect(() => readFileSync('never-created/.env')).toThrow('OFFLINE');
		expect(() => readFileSync('never-created/.aws/config')).toThrow('OFFLINE');
		await expect(async () => readFile('never-created/.env.local')).rejects.toThrow('OFFLINE');
	});
	it('impide sockets y fetch antes de cualquier conexion', async () => {
		expect(() => new Socket().connect(443, 'offline.invalid')).toThrow('OFFLINE');
		await expect(fetch('https://offline.invalid')).rejects.toThrow('OFFLINE');
	});
});
