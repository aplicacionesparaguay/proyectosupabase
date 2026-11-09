// Compatibilidad para avatar/portada. Todas las subidas pasan por intents
// privados, decodificacion completa, eliminacion EXIF y un destino servidor.
// La galeria usa exclusivamente /api/media/upload-intent + upload-commit.
export { profileImageUpload as POST } from '$lib/server/profileImages';
