// SVGO config for protodot/graphviz diagrams served from GitHub Pages.
// Conservative: keep viewBox (its removal breaks diagram scaling) and do not
// touch the <a xlink:href> links / text protodot emits.
export default {
  multipass: true,
  plugins: [
    {
      name: 'preset-default',
      params: {
        overrides: {
          removeViewBox: false,
        },
      },
    },
  ],
};
