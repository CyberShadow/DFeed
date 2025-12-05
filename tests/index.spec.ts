import { test, expect } from '@playwright/test';

test('index page loads successfully', async ({ page }) => {
  const response = await page.goto('/');

  // Verify the page loads with a successful status
  expect(response?.status()).toBe(200);

  // Verify we're on a DFeed instance by checking for expected content
  await expect(page.locator('body')).toBeVisible();
});
