// The project website (ADR 0011): a landing page of its own, and Starlight for the docs.
import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';

const repo = 'https://github.com/mikheil-gigauri/dryfit';

export default defineConfig({
  site: 'https://mikheil-gigauri.github.io',
  base: '/dryfit',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'dryfit',
      description:
        'Test unreleased npm libraries inside real consumer apps, installed the way they will be released.',
      favicon: '/favicon.svg?v=2',
      logo: { light: './src/assets/mark-light.svg', dark: './src/assets/mark-dark.svg' },
      social: [{ icon: 'github', label: 'GitHub', href: repo }],
      editLink: { baseUrl: `${repo}/edit/main/apps/site/` },
      components: { PageTitle: './src/components/PageTitle.astro' },
      expressiveCode: {
        styleOverrides: {
          borderRadius: '6px',
          borderColor: 'var(--dl-grid)',
          codeFontFamily: 'var(--sl-font-mono)',
          uiFontFamily: 'var(--sl-font)',
          frames: { shadowColor: 'transparent', frameBoxShadowCssValue: 'none' },
        },
      },
      customCss: [
        '@fontsource-variable/bricolage-grotesque/standard.css',
        '@fontsource-variable/martian-mono',
        './src/styles/theme.css',
      ],
      sidebar: [
        {
          label: 'Guides',
          items: [
            { label: 'Getting started', link: '/guides/getting-started/' },
            { label: 'Build and publish settings', link: '/guides/libraries/' },
            { label: 'How it works', link: '/guides/how-it-works/' },
            { label: 'Package managers', link: '/guides/package-managers/' },
            { label: 'Frameworks and caches', link: '/guides/frameworks/' },
            { label: 'Menu bar app', link: '/guides/menu-bar/' },
            { label: 'The commit guard', link: '/guides/commit-guard/' },
            { label: 'Coding agents', link: '/guides/agents/' },
            { label: 'Troubleshooting', link: '/guides/troubleshooting/' },
            { label: 'Compared with npm link and yalc', link: '/guides/comparison/' },
          ],
        },
        { label: 'Reference', items: [{ label: 'CLI', link: '/reference/cli/' }] },
      ],
    }),
  ],
});
