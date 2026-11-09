export class LeaseLostError extends Error {
	constructor() { super('El trabajo ya no pertenece a esta lease.'); this.name = 'LeaseLostError'; }
}

/** Mantiene como maximo un heartbeat en vuelo y espera su cierre antes de completar. */
export async function runWithHeartbeat({ heartbeat, run, intervalMs }) {
	const controller = new AbortController();
	let pending;
	let lost = false;
	const tick = () => {
		if (pending || lost) return;
		pending = Promise.resolve().then(heartbeat).then((owned) => {
			if (!owned) { lost = true; controller.abort(); }
		}).catch(() => { lost = true; controller.abort(); }).finally(() => { pending = undefined; });
	};
	const timer = setInterval(tick, intervalMs);
	timer.unref?.();
	try {
		const result = await run(controller.signal);
		clearInterval(timer);
		await pending;
		if (lost) throw new LeaseLostError();
		return result;
	} finally {
		clearInterval(timer);
		await pending;
	}
}
