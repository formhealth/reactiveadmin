import DefaultTheme from "vitepress/theme";
import "@fontsource-variable/ibm-plex-sans";
import "@fontsource/ibm-plex-mono/400.css";
import "@fontsource/ibm-plex-mono/500.css";
import "./site.css";
import Home from "./Home.vue";

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("Home", Home);
  },
};
