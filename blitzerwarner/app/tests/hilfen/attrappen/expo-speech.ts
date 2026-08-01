/** Attrappe für expo-speech. Merkt sich, was gesagt worden wäre. */
export const gesprochen: string[] = [];
export const speak = (text: string): void => { gesprochen.push(text); };
export const stop = async (): Promise<void> => {};
export const isSpeakingAsync = async (): Promise<boolean> => false;
