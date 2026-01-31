// src/lib/r2Client.js
import { S3Client } from '@aws-sdk/client-s3';

// Configuración de Cloudflare R2
const R2_ACCOUNT_ID = import.meta.env.VITE_R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = import.meta.env.VITE_R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = import.meta.env.VITE_R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = import.meta.env.VITE_R2_BUCKET_NAME;
const R2_PUBLIC_URL = import.meta.env.VITE_R2_PUBLIC_URL; // URL pública del bucket

// Validar variables de entorno
if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY || !R2_BUCKET_NAME) {
  throw new Error(
    'Missing Cloudflare R2 environment variables. Make sure VITE_R2_ACCOUNT_ID, VITE_R2_ACCESS_KEY_ID, VITE_R2_SECRET_ACCESS_KEY, and VITE_R2_BUCKET_NAME are set.'
  );
}

// Crear cliente S3 compatible con R2
export const r2Client = new S3Client({
  region: 'auto', // R2 usa 'auto' como región
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
});

export { R2_BUCKET_NAME, R2_PUBLIC_URL };

// Función helper para generar URLs públicas
export function getPublicUrl(key) {
  if (!R2_PUBLIC_URL) {
    throw new Error('VITE_R2_PUBLIC_URL is not set. Cannot generate public URLs.');
  }
  return `${R2_PUBLIC_URL}/${key}`;
}