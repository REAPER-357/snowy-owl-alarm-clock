/** Tailwind is built to a static CSS file so the APK works offline.
 *  The grey scale ("neutral" and "white") comes from CSS variables, so the Black / Dark / Light themes
 *  are defined in www/index.html (html[data-theme=...]) and switch instantly without a rebuild. */
const n = v => `rgb(var(--n${v}) / <alpha-value>)`;
module.exports = {
  darkMode: 'class',
  content: ['./www/index.html'],
  theme: {
    extend: {
      fontFamily: { sans: ['Inter', 'sans-serif'] },
      colors: {
        white: 'rgb(var(--white) / <alpha-value>)',
        neutral: { 50: n(50), 100: n(100), 200: n(200), 300: n(300), 400: n(400), 500: n(500), 600: n(600), 700: n(700), 800: n(800), 900: n(900), 950: n(950) }
      }
    }
  },
  plugins: []
};
