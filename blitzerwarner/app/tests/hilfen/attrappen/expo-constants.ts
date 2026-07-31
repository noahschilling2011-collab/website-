/**
 * Attrappe für expo-constants.
 *
 * expoConfig.extra spiegelt, was app.config.js im Entwicklungsbuild setzt —
 * der Datenschutz-Screen liest daraus, ob die Internet-Berechtigung entzogen
 * ist.
 */
export default { expoConfig: { extra: { internetEntzogen: false } } };
