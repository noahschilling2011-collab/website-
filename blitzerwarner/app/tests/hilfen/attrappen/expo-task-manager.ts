/**
 * Attrappe für expo-task-manager.
 *
 * defineTask() merkt sich den Handler, statt ihn zu registrieren. Damit läuft
 * der Import von location/task.ts durch — und der steht in index.ts auf
 * oberster Ebene, also im Startpfad der App.
 */
export const aufgaben = new Map<string, unknown>();
export const defineTask = (name: string, handler: unknown): void => { aufgaben.set(name, handler); };
export const isTaskRegisteredAsync = async () => false;
export const unregisterTaskAsync = async () => {};
