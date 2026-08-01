/** Attrappe für expo-av. Erzeugt keine Töne. */
export const InterruptionModeAndroid = { DoNotMix: 1, DuckOthers: 2 } as const;
export const InterruptionModeIOS = { MixWithOthers: 0, DoNotMix: 1, DuckOthers: 2 } as const;
export const Audio = {
  setAudioModeAsync: async () => {},
  Sound: {
    createAsync: async () => ({
      sound: { setOnPlaybackStatusUpdate: () => {}, unloadAsync: async () => {} },
    }),
  },
};
