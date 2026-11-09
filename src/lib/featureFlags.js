/**
 * Interruptores de funcionalidad.
 *
 * La base de datos tiene las tablas del nucleo del producto (profiles,
 * user_photos, user_banners, media) pero todavia no las de la capa social
 * (follows, notifications, media_likes, media_comments, media_subscriptions,
 * messages). Consultarlas produce un 404 por peticion en la consola.
 *
 * En vez de crear tablas vacias o de silenciar los errores a mano, cada
 * funcionalidad depende de su interruptor. Cuando esta en `false`:
 *
 *   · no se lanza ninguna consulta, asi que no hay error en consola;
 *   · el elemento visual que dependia de ella no se renderiza.
 *
 * Activar una funcionalidad cuando su tabla exista es cambiar un `false` por
 * `true` en este archivo. No hace falta tocar ningun componente.
 *
 * Prioridad actual del producto: subida, visualizacion y eliminacion de fotos
 * y videos. La capa social queda fuera de alcance hasta que su esquema este
 * definido.
 */

/**
 * @typedef {Object} SocialFeatures
 * @property {boolean} follows       tabla `follows`
 * @property {boolean} notifications tabla `notifications`
 * @property {boolean} likes          tabla `media_likes`
 * @property {boolean} comments       tabla `media_comments`
 * @property {boolean} subscriptions  tabla `media_subscriptions` y `suscripciones`
 * @property {boolean} messages       tabla `messages`
 */

/** @type {SocialFeatures} */
export const SOCIAL = Object.freeze({
	follows: false,
	notifications: false,
	likes: false,
	comments: false,
	subscriptions: false,
	messages: false
});
