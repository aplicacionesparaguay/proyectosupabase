/**
 * R2 no usa perfiles AWS, FIPS, ARN ni S3 Express. Fijar estos valores evita
 * que los proveedores por defecto busquen configuracion/credenciales en disco.
 * No contiene endpoints, claves ni otros datos del entorno.
 * @type {import('@aws-sdk/client-s3').S3ClientConfig}
 */
export const R2_CLIENT_OPTIONS = {
	region: 'auto',
	defaultsMode: 'standard',
	forcePathStyle: true,
	authSchemePreference: ['sigv4'],
	disableS3ExpressSessionAuth: true,
	maxAttempts: 2,
	retryMode: 'standard',
	requestChecksumCalculation: 'WHEN_REQUIRED',
	responseChecksumValidation: 'WHEN_REQUIRED',
	sigv4aSigningRegionSet: [],
	useArnRegion: false,
	useDualstackEndpoint: false,
	useFipsEndpoint: false,
	userAgentAppId: 'agua-media'
};
