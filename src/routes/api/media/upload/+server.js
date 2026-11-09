// POST /api/media/upload
//
// ENDPOINT RETIRADO.
//
// La galeria usa upload-intent + upload-commit. Avatar/portada usan la via
// de compatibilidad /api/upload/r2, tambien con staging y validacion completa.
//
// Este endpoint anterior no hacia nada de eso: aceptaba cualquier tipo de
// contenido y cualquier tamano, y dejaba que el CLIENTE eligiera el bucket
// (`es_privado`). Con eso se podia subir al bucket publico un archivo que
// el navegador interpretara como HTML o SVG (contenido activo servido desde
// el dominio de la app). Ademas generaba claves con otro formato
// (`<userId>/<uuid>`) que no encaja con el que reconoce el resto del codigo.
//
// Ninguna parte de la aplicacion lo usa (verificado: no hay referencias en
// `src/`). Se responde 410 Gone para que quede claro a donde va el codigo
// nuevo, en lugar de dejar vivo un camino mas debil que el bueno.
import { json } from '@sveltejs/kit';

export async function POST() {
	return json(
		{
			error:
				'Este endpoint esta retirado. Usa /api/media/upload-intent y /api/media/upload-commit para fotografias.'
		},
		{ status: 410 }
	);
}
