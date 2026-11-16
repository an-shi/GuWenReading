import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'

const serif = '"Noto Serif SC", "Source Han Serif SC", "Songti SC", "SimSun", serif'
const sans = '"Noto Sans SC", "Microsoft YaHei", "PingFang SC", system-ui, sans-serif'

export default createVuetify({
  components,
  directives,
  theme: {
    defaultTheme: 'paper',
    themes: {
      paper: {
        dark: false,
        colors: {
          background: '#efe8da',
          surface: '#fbf7ef',
          'surface-variant': '#e8dfcf',
          primary: '#1c5a4c',
          'primary-darken-1': '#15473c',
          secondary: '#9a6a34',
          accent: '#b3543f',
          error: '#a53b35',
          info: '#3b6475',
          success: '#3f6b4f',
          warning: '#a4762c',
          'on-background': '#2d2a24',
          'on-surface': '#2d2a24',
          'on-primary': '#f8f2e7',
        },
        variables: {
          'border-color': '#d8ccb8',
          'border-opacity': 0.9,
        },
      },
      light: {
        dark: false,
        colors: {
          background: '#f5f6f3',
          surface: '#ffffff',
          'surface-variant': '#eceee9',
          primary: '#16584a',
          secondary: '#9a6a34',
          accent: '#b3543f',
          error: '#a53b35',
          info: '#3b6475',
          success: '#3f6b4f',
          warning: '#a4762c',
          'on-background': '#252824',
          'on-surface': '#252824',
          'on-primary': '#ffffff',
        },
      },
      dark: {
        dark: true,
        colors: {
          background: '#111815',
          surface: '#18211d',
          'surface-variant': '#22302a',
          primary: '#7fb9a8',
          secondary: '#c8a06a',
          accent: '#d18a72',
          error: '#d17872',
          info: '#7fa5b4',
          success: '#83b08f',
          warning: '#d0ab62',
          'on-background': '#e7e2d6',
          'on-surface': '#e7e2d6',
          'on-primary': '#10201b',
        },
      },
    },
  },
  defaults: {
    VBtn: { rounded: 'lg', variant: 'flat', class: 'text-none' },
    VCard: { rounded: 'xl', elevation: 0 },
    VTextField: { variant: 'outlined', density: 'comfortable', hideDetails: 'auto' },
    VTextarea: { variant: 'outlined', density: 'comfortable' },
    VSelect: { variant: 'outlined', density: 'comfortable', hideDetails: 'auto' },
    VDialog: { maxWidth: 720 },
    VChip: { rounded: 'lg' },
  },
  display: {
    mobileBreakpoint: 'md',
    thresholds: { xs: 0, sm: 600, md: 840, lg: 1140, xl: 1540 },
  },
  icons: {
    defaultSet: 'mdi',
  },
})

export { serif, sans }
