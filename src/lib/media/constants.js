export const MAX_PHOTO_BYTES = 10 * 1024 * 1024;
export const MAX_PHOTO_PIXELS = 50_000_000;
export const MAX_FILES_PER_BATCH = 10;
export const MAX_TITLE_LENGTH = 120;
export const MAX_DESCRIPTION_LENGTH = 1000;

export const ALLOWED_PHOTO_TYPES = Object.freeze(['image/jpeg', 'image/png', 'image/webp']);

export const PHOTO_EXTENSIONS = Object.freeze({
	'image/jpeg': Object.freeze(['.jpg', '.jpeg']),
	'image/png': Object.freeze(['.png']),
	'image/webp': Object.freeze(['.webp'])
});

/** @param {unknown} value */
export function isAllowedPhotoType(value) {
	return typeof value === 'string' && ALLOWED_PHOTO_TYPES.includes(value);
}

export function maxPhotoBytesLabel() {
	return `${MAX_PHOTO_BYTES / (1024 * 1024)} MB`;
}
