/** Attrappe für expo-location. Fordert nichts an und liefert nichts. */
export const Accuracy = { Balanced: 3, High: 4, BestForNavigation: 5 } as const;
export type LocationAccuracy = number;
export type LocationObject = {
  coords: { latitude: number; longitude: number; heading: number | null; speed: number | null; accuracy: number | null };
  timestamp: number;
};
export const requestForegroundPermissionsAsync = async () => ({ status: 'granted' as const });
export const requestBackgroundPermissionsAsync = async () => ({ status: 'granted' as const });
export const getForegroundPermissionsAsync = async () => ({ status: 'granted' as const });
export const startLocationUpdatesAsync = async () => {};
export const stopLocationUpdatesAsync = async () => {};
export const hasStartedLocationUpdatesAsync = async () => false;
