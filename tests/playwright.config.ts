import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 30000,
  retries: 0,
  use: {
    baseURL: process.env.DFEED_URL || 'http://localhost:8080',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'default',
      testIgnore: /.*-screenshot\.spec\.ts$/,
      use: {
        ...devices['Desktop Firefox'],
      },
    },
    {
      name: 'screenshots',
      testMatch: /.*-screenshot\.spec\.ts$/,
      use: {
        ...devices['Desktop Firefox'],
      },
    },
  ],
});
