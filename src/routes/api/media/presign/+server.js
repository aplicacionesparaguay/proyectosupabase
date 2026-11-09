import { json } from '@sveltejs/kit';

// No firmar claves elegibles desde filas legacy editables por el navegador.
// Las galerias actuales reciben URLs tras comprobar estado y propietario.
export function POST() {
	return json({ error: 'Usa /api/media/owner o /api/media/public.' }, { status: 410 });
}
