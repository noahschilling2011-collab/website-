/** Attrappe für @react-native-async-storage/async-storage: eine Map. */
const speicher = new Map<string, string>();
export default {
  getItem: async (k: string) => speicher.get(k) ?? null,
  setItem: async (k: string, v: string) => { speicher.set(k, v); },
  removeItem: async (k: string) => { speicher.delete(k); },
  clear: async () => { speicher.clear(); },
};
