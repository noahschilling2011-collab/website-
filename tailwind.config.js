/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Ruhiges, dunkles Werkzeug-Theme
        bg: '#0f1115',
        surface: '#171a21',
        border: '#262b36',
        muted: '#8b93a7',
        accent: '#4f7cff',
      },
    },
  },
  plugins: [],
}
