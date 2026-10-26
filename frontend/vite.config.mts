import typescript from '@rollup/plugin-typescript'
import vue from '@vitejs/plugin-vue'
import { readFileSync, writeFileSync } from 'fs'
import * as path from 'path'
import ViteFonts from 'unplugin-fonts/vite'
import { defineConfig } from 'vite'
import cssInjectedByJsPlugin from 'vite-plugin-css-injected-by-js'
import dts from 'vite-plugin-dts'
import vuetify, { transformAssetUrls } from 'vite-plugin-vuetify'

/**
 * Strip the font preload tags that unplugin-fonts injects into dist/index.html.
 *
 * The Material Design Icons font ships as eot/ttf/woff/woff2 and unplugin-fonts
 * preloads every one of them, which triggers the console errors
 * "link rel=preload has an unsupported `type` value" (eot) and
 * "preloaded ... but not used within a few seconds" (the other formats), plus
 * ~2 MB of useless font traffic per page load. The @font-face rules only use
 * woff2, so the preloads are dropped and the browser fetches what it needs.
 */
function stripFontPreloads() {
  return {
    name: 'strip-font-preloads',
    apply: 'build' as const,
    closeBundle() {
      const htmlPath = path.resolve(__dirname, 'dist/index.html')
      const html = readFileSync(htmlPath, 'utf-8')
      const cleaned = html.replace(/\s*<link\b[^>]*rel="preload"[^>]*as="font"[^>]*>/gi, '')
      if (cleaned !== html) {
        writeFileSync(htmlPath, cleaned)
        // eslint-disable-next-line no-console
        console.log('strip-font-preloads: removed font preloads from dist/index.html')
      }
    }
  }
}

// https://vitejs.dev/config/
export default defineConfig({
  define: {
    __APP_VERSION__: JSON.stringify(`reev-frontend@${process.env.REEV_VERSION}`)
  },
  plugins: [
    vue({
      template: { transformAssetUrls }
    }),
    dts({
      insertTypesEntry: true
    }),
    cssInjectedByJsPlugin(),
    // https://github.com/vuetifyjs/vuetify-loader/tree/next/packages/vite-plugin
    vuetify({
      autoImport: true,
      styles: {
        configFile: 'src/styles/settings.scss'
      }
    }),
    ViteFonts({
      google: {
        families: [
          {
            name: 'Roboto',
            styles: 'wght@100;300;400;500;700;900'
          }
        ]
      }
    }),
    stripFontPreloads()
  ],
  resolve: {
    alias: {
      '@bihealth/reev-frontend-lib': path.resolve(__dirname, 'src/ext/reev-frontend-lib/src'),
      '@': path.resolve(__dirname, 'src')
    }
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: false,
        secure: false
      },
      '/internal': {
        target: 'http://localhost:8080',
        changeOrigin: false,
        secure: false
      },
      '/favicon.ico': {
        target: 'http://localhost:8080',
        changeOrigin: false,
        secure: false
      }
    }
  },
  build: {
    chunkSizeWarningLimit: 5000,
    rollupOptions: {
      plugins: [
        typescript({
          exclude: ['**/*.spec.ts', '**/*.stories.ts', '**/fixture.*.json']
        })
      ]
    }
  }
})
