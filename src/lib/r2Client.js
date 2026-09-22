// src/lib/r2Client.js
import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const R2_ACCOUNT_ID = import.meta.env.VITE_R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = import.meta.env.VITE_R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = import.meta.env.VITE_R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = import.meta.env.VITE_R2_BUCKET_NAME;
const R2_PUBLIC_URL = import.meta.env.VITE_R2_PUBLIC_URL;

if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY || !R2_BUCKET_NAME) {
  console.warn('R2 environment variables not fully configured. Upload to R2 will not work.');
}

export const r2Client = new S3Client({
  region: 'auto',
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
});

export const r2Bucket = R2_BUCKET_NAME;
export const r2PublicUrl = R2_PUBLIC_URL;

export async function getPresignedUploadUrl(key, contentType, expiresIn = 3600) {
  if (!r2Client || !r2Bucket) {
    throw new Error('R2 client not configured');
  }

  const command = new PutObjectCommand({
    Bucket: r2Bucket,
    Key: key,
    ContentType: contentType,
  });

  const signedUrl = await getSignedUrl(r2Client, command, { expiresIn });
  return signedUrl;
}

export async function getPresignedDeleteUrl(key, expiresIn = 3600) {
  if (!r2Client || !r2Bucket) {
    throw new Error('R2 client not configured');
  }

  const command = new DeleteObjectCommand({
    Bucket: r2Bucket,
    Key: key,
  });

  const signedUrl = await getSignedUrl(r2Client, command, { expiresIn });
  return signedUrl;
}

export function getPublicUrl(key) {
  if (!r2PublicUrl) {
    throw new Error('R2 public URL not configured');
  }
  return `${r2PublicUrl}/${key}`;
}

export function generateUploadKey(userId, fileName, folder = 'uploads') {
  const timestamp = Date.now();
  const sanitizedFileName = fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
  return `${folder}/${userId}/${timestamp}_${sanitizedFileName}`;
}