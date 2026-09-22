// src/routes/api/upload/r2/+server.js
import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { json } from '@sveltejs/kit';

const R2_ACCOUNT_ID = import.meta.env.VITE_R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = import.meta.env.VITE_R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = import.meta.env.VITE_R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = import.meta.env.VITE_R2_BUCKET_NAME;

if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY || !R2_BUCKET_NAME) {
  console.error('R2 environment variables not configured');
}

const r2Client = new S3Client({
  region: 'auto',
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
});

function generateKey(userId, fileName, folder) {
  const timestamp = Date.now();
  const sanitizedFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
  return `${folder}/${userId}/${timestamp}_${sanitizedFileName}`;
}

export async function POST({ request, locals }) {
  const session = await locals.getSession();
  
  if (!session?.user) {
    return json({ error: 'No autorizado' }, { status: 401 });
  }

  try {
    const { fileName, contentType, folder = 'uploads', action = 'upload' } = await request.json();

    if (!fileName || !contentType) {
      return json({ error: 'fileName y contentType son requeridos' }, { status: 400 });
    }

    const userId = session.user.id;
    const key = generateKey(userId, fileName, folder);

    if (action === 'delete') {
      const command = new DeleteObjectCommand({
        Bucket: R2_BUCKET_NAME,
        Key: key,
      });

      const signedUrl = await getSignedUrl(r2Client, command, { expiresIn: 3600 });
      return json({ signedUrl, key, action: 'delete' });
    }

    const command = new PutObjectCommand({
      Bucket: R2_BUCKET_NAME,
      Key: key,
      ContentType: contentType,
    });

    const signedUrl = await getSignedUrl(r2Client, command, { expiresIn: 3600 });

    return json({ signedUrl, key, action: 'upload' });
  } catch (error) {
    console.error('R2 presigned URL error:', error);
    return json({ error: 'Error generando URL prefirmada' }, { status: 500 });
  }
}